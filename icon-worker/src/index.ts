import { CATALOG_VERSION, GENERIC_KEY, ICONS } from "./icons";
import { chooseIcon, JevError, type JevOptions } from "./jev";
import type { IconLimiter, Limits } from "./limiter";

export { IconLimiter } from "./limiter";

export interface Env {
  LIMITER: DurableObjectNamespace<IconLimiter>;
  JEV_API_KEY?: string;
  JEV_MODEL: string;
  JEV_MAX_REQUEST_TOKENS: string;
  JEV_PRICE_PER_MTOK_USD: string;
  JEV_RUSSIAN_HINTS: string;
  MIN_CONFIDENCE: string;
  MONTHLY_BUDGET_USD: string;
  DAILY_BUDGET_USD: string;
  PER_INSTALL_PER_DAY: string;
  PER_IP_PER_MINUTE: string;
  GLOBAL_PER_MINUTE: string;
}

/** Test seams; production uses the real clock and network. */
export interface Deps {
  now: () => number;
  fetcher?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
}

export const MIN_NAME_LENGTH = 2;
export const MAX_NAME_LENGTH = 80;
const MAX_BODY_BYTES = 4096;
const MAX_ATTEMPTS = 2;
const INSTALL_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env, { now: Date.now });
  },
} satisfies ExportedHandler<Env>;

export async function handle(request: Request, env: Env, deps: Deps): Promise<Response> {
  const url = new URL(request.url);
  if (url.pathname === "/health" && request.method === "GET") return new Response("ok");
  if (url.pathname !== "/v1/gift-icon") return json({ error: "not_found" }, 404);
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405, { Allow: "POST" });

  const installID = request.headers.get("X-Install-ID") ?? "";
  if (!INSTALL_ID.test(installID)) return invalid();
  const name = await readName(request);
  if (name === null) return invalid();
  // Without a key or a known per-request token ceiling, spending cannot be bounded; fail closed.
  const maxRequestTokens = Number(env.JEV_MAX_REQUEST_TOKENS);
  if (!env.JEV_API_KEY || !Number.isInteger(maxRequestTokens) || maxRequestTokens <= 0) {
    return json({ error: "unavailable" }, 503);
  }

  const limiter = env.LIMITER.get(env.LIMITER.idFromName("global"));
  const pricePerToken = Number(env.JEV_PRICE_PER_MTOK_USD); // micro-dollars per token
  const minConfidence = Number(env.MIN_CONFIDENCE);
  const russianHints = env.JEV_RUSSIAN_HINTS === "true";
  const cacheKey = await sha256(`${CATALOG_VERSION}\n${env.JEV_MODEL}\n${russianHints}\n${name.toLowerCase()}`);
  // Every attempt may be billed, so each is reserved at the provider-enforced request ceiling.
  const attemptMicros = Math.ceil(maxRequestTokens * pricePerToken);

  const admission = await limiter.admit({
    cacheKey,
    installHash: await sha256(`install\n${installID.toLowerCase()}`),
    ipHash: await sha256(`ip\n${request.headers.get("CF-Connecting-IP") ?? "unknown"}`),
    now: deps.now(),
    limits: limits(env),
    reservationMicros: attemptMicros * MAX_ATTEMPTS,
  });

  switch (admission.kind) {
    case "cached":
      return iconResponse(admission.key, admission.confidence, minConfidence);
    case "rate_limited":
      return json({ error: "rate_limited" }, 429, { "Retry-After": String(admission.retryAfterSeconds) });
    case "budget_exhausted":
      return json({ error: "budget_exhausted" }, 503);
  }

  const options: JevOptions = {
    apiKey: env.JEV_API_KEY,
    model: env.JEV_MODEL,
    russianHints,
    attemptTimeoutMs: 3_000,
    maxAttempts: MAX_ATTEMPTS,
    fetcher: deps.fetcher,
    sleep: deps.sleep,
  };
  const started = deps.now();
  try {
    const { answer, unknownUsageAttempts } = await chooseIcon(name, options);
    const key = answer.key === GENERIC_KEY ? null : answer.key;
    await limiter.settle({
      reservationId: admission.reservationId,
      costMicros: Math.ceil(answer.inputTokens * pricePerToken) + unknownUsageAttempts * attemptMicros,
      answer: { cacheKey, key, confidence: answer.confidence },
      now: deps.now(),
    });
    // Operational metrics only; the gift name is never logged.
    console.log(
      JSON.stringify({ event: "jev", model: answer.model, tokens: answer.inputTokens, ms: deps.now() - started }),
    );
    return iconResponse(key, answer.confidence, minConfidence);
  } catch (error) {
    // Attempts that may have been billed without reporting usage are charged at their upper bound.
    const unknown = error instanceof JevError ? error.unknownUsageAttempts : MAX_ATTEMPTS;
    await limiter.settle({ reservationId: admission.reservationId, costMicros: unknown * attemptMicros, now: deps.now() });
    console.log(
      JSON.stringify({ event: "jev_error", reason: error instanceof Error ? error.message : "unknown", ms: deps.now() - started }),
    );
    return json({ error: "unavailable" }, 503);
  }
}

/**
 * The trimmed, NFC-normalized name with collapsed whitespace, or null when the body is invalid.
 * Length counts user-perceived characters, matching Swift's `String.count` in the app.
 */
async function readName(request: Request): Promise<string | null> {
  if (!(request.headers.get("Content-Type") ?? "").toLowerCase().startsWith("application/json")) return null;
  const bytes = await readAtMost(request, MAX_BODY_BYTES);
  if (bytes === null) return null;
  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
  } catch {
    return null;
  }
  const raw = (body as { name?: unknown } | null)?.name;
  if (typeof raw !== "string") return null;
  // Control characters are replaced like whitespace so they never reach the provider.
  const name = raw.normalize("NFC").replace(/[\p{Cc}\p{Z}]+/gu, " ").trim();
  const length = [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(name)].length;
  return length >= MIN_NAME_LENGTH && length <= MAX_NAME_LENGTH ? name : null;
}

/** The body bytes, or null as soon as it exceeds `limit`, without buffering the rest. */
async function readAtMost(request: Request, limit: number): Promise<Uint8Array | null> {
  if (Number(request.headers.get("Content-Length") ?? "0") > limit) return null;
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function iconResponse(key: string | null, confidence: number, minConfidence: number): Response {
  const emoji = key !== null && confidence >= minConfidence ? (ICONS[key]?.emoji ?? null) : null;
  return json({ emoji, confidence: Math.round(confidence * 1000) / 1000 });
}

function limits(env: Env): Limits {
  return {
    monthlyBudgetMicros: Math.round(Number(env.MONTHLY_BUDGET_USD) * 1_000_000),
    dailyBudgetMicros: Math.round(Number(env.DAILY_BUDGET_USD) * 1_000_000),
    perInstallPerDay: Number(env.PER_INSTALL_PER_DAY),
    perIpPerMinute: Number(env.PER_IP_PER_MINUTE),
    globalPerMinute: Number(env.GLOBAL_PER_MINUTE),
  };
}

function invalid(): Response {
  return json({ error: "invalid_request" }, 400);
}

function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers },
  });
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
