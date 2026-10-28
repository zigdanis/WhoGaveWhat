import { CATALOG_VERSION, GENERIC_KEY, ICONS } from "./cldr-catalog";
import { chooseIcon, JevError, PICKER_VERSION, type JevOptions } from "./jev";
import { CURRENCIES, PRICE_VERSION, priceFor, type Currency } from "./prices";
import type { IconLimiter, Limits } from "./limiter";

export { IconLimiter } from "./limiter";

export interface Env {
  LIMITER: DurableObjectNamespace<IconLimiter>;
  JEV_API_KEY?: string;
  JEV_MODEL: string;
  JEV_MAX_REQUEST_TOKENS: string;
  JEV_PRICE_PER_MTOK_USD: string;
  MIN_CONFIDENCE: string;
  MIN_PRICE_CONFIDENCE: string;
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
/** Every 503 says when to retry, so clients don't wait longer than needed after a passing failure. */
const PROVIDER_RETRY_AFTER_SECONDS = 30;
const CONFIG_RETRY_AFTER_SECONDS = 300;
/** A reply without a usable price is asked again after this, instead of after the usual 30 days. */
const MISSING_PRICE_TTL_MS = 60 * 60 * 1000;
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
  const parsed = await readRequest(request);
  if (parsed === null) return invalid();
  const { name, currency } = parsed;
  // Without a key or valid limits, spending cannot be bounded; fail closed.
  const config = readConfig(env);
  if (!env.JEV_API_KEY || config === null) return unavailable(CONFIG_RETRY_AFTER_SECONDS);
  const { maxRequestTokens, pricePerToken, minConfidence, minPriceConfidence } = config;

  const limiter = env.LIMITER.get(env.LIMITER.idFromName("global"));
  // The generated catalog version invalidates choices from older catalogs.
  const cacheKey = await sha256(
    currency === null
      ? `${CATALOG_VERSION}\n${PICKER_VERSION}\n${env.JEV_MODEL}\n${name.toLowerCase()}`
      : `${CATALOG_VERSION}\n${PICKER_VERSION}\n${PRICE_VERSION}\n${env.JEV_MODEL}\n${currency}\n${name.toLowerCase()}`,
  );
  // Every attempt may be billed, so each is reserved at the provider-enforced request ceiling.
  const attemptMicros = Math.ceil(maxRequestTokens * pricePerToken);

  const admission = await limiter.admit({
    cacheKey,
    installID,
    ip: request.headers.get("CF-Connecting-IP") ?? "unknown",
    now: deps.now(),
    limits: config.limits,
    reservationMicros: attemptMicros * MAX_ATTEMPTS * 2,
  });

  switch (admission.kind) {
    case "cached":
      return answerResponse({
        key: admission.key,
        confidence: admission.confidence,
        name,
        currency,
        bucket: admission.price,
        priceConfidence: admission.priceConfidence ?? 0,
        minConfidence,
        minPriceConfidence,
      });
    case "rate_limited":
      return json({ error: "rate_limited" }, 429, { "Retry-After": String(admission.retryAfterSeconds) });
    case "budget_exhausted":
      return json({ error: "budget_exhausted" }, 503, { "Retry-After": String(admission.retryAfterSeconds) });
  }

  const options: JevOptions = {
    apiKey: env.JEV_API_KEY,
    model: env.JEV_MODEL,
    currency: currency ?? undefined,
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
      // Without a usable price answer the bucket is null and its confidence 0, like a low-confidence price.
      // Such a reply is cached only briefly, so one bad reply doesn't hide the price for 30 days.
      answer: {
        cacheKey,
        key,
        confidence: answer.confidence,
        price: currency === null ? null : (answer.price?.bucket ?? null),
        priceConfidence: currency === null ? null : (answer.price?.confidence ?? 0),
        ...(currency !== null && !answer.price && { ttlMs: MISSING_PRICE_TTL_MS }),
      },
      now: deps.now(),
    });
    // Operational metrics only; the gift name is never logged.
    console.log(
      JSON.stringify({
        event: "jev",
        model: answer.model,
        tokens: answer.inputTokens,
        ms: deps.now() - started,
        ...(currency !== null && { price: answer.price?.source ?? "none" }),
      }),
    );
    return answerResponse({
      key,
      confidence: answer.confidence,
      name,
      currency,
      bucket: answer.price?.bucket ?? null,
      priceConfidence: answer.price?.confidence ?? 0,
      minConfidence,
      minPriceConfidence,
    });
  } catch (error) {
    // Attempts that may have been billed without reporting usage are charged at their upper bound.
    const unknown = error instanceof JevError ? error.unknownUsageAttempts : MAX_ATTEMPTS * 2;
    const knownTokens = error instanceof JevError ? error.inputTokens : 0;
    await limiter.settle({
      reservationId: admission.reservationId,
      costMicros: Math.ceil(knownTokens * pricePerToken) + unknown * attemptMicros,
      now: deps.now(),
    });
    console.log(
      JSON.stringify({
        event: "jev_error",
        reason: error instanceof Error ? error.message : "unknown",
        ms: deps.now() - started,
      }),
    );
    // A rejected key is a configuration problem that won't pass in seconds.
    const rejected = error instanceof JevError && (error.status === 401 || error.status === 403);
    return unavailable(rejected ? CONFIG_RETRY_AFTER_SECONDS : PROVIDER_RETRY_AFTER_SECONDS);
  }
}

interface GiftRequest {
  name: string;
  /** Null for older clients, which get the icon-only answer. */
  currency: Currency | null;
}

/**
 * The trimmed, NFC-normalized name with collapsed whitespace and the optional currency, or null
 * when the body is invalid. Length counts user-perceived characters, matching Swift's
 * `String.count` in the app.
 */
async function readRequest(request: Request): Promise<GiftRequest | null> {
  if (!(request.headers.get("Content-Type") ?? "").toLowerCase().startsWith("application/json")) return null;
  const bytes = await readAtMost(request, MAX_BODY_BYTES);
  if (bytes === null) return null;
  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
  } catch {
    return null;
  }
  const fields = body as { name?: unknown; currency?: unknown } | null;
  const raw = fields?.name;
  if (typeof raw !== "string") return null;
  // Absent means an older client; anything else must be a supported code.
  let currency: Currency | null = null;
  if (fields !== null && Object.hasOwn(fields, "currency")) {
    const code = CURRENCIES.find((supported) => supported === fields.currency);
    if (code === undefined) return null;
    currency = code;
  }
  // Control characters are replaced like whitespace so they never reach the provider.
  const name = raw
    .normalize("NFC")
    .replace(/[\p{Cc}\p{Z}]+/gu, " ")
    .trim();
  const length = [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(name)].length;
  return length >= MIN_NAME_LENGTH && length <= MAX_NAME_LENGTH ? { name, currency } : null;
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

interface Answer {
  key: string | null;
  confidence: number;
  name: string;
  currency: Currency | null;
  /** Jev's price bucket, null when it gave none. */
  bucket: number | null;
  priceConfidence: number;
  minConfidence: number;
  minPriceConfidence: number;
}

/** Built the same way for fresh and cached answers, so both produce identical responses. */
function answerResponse(answer: Answer): Response {
  const { key, confidence, minConfidence } = answer;
  const emoji = key !== null && confidence >= minConfidence ? (ICONS[key]?.emoji ?? null) : null;
  const icon = { emoji, confidence: round(confidence) };
  if (answer.currency === null) return json(icon);
  const price = priceFor(
    { key, confidence, minConfidence },
    answer.name,
    answer.bucket,
    answer.priceConfidence,
    answer.minPriceConfidence,
  );
  return json({ ...icon, price, priceConfidence: round(answer.priceConfidence) });
}

function round(confidence: number): number {
  return Math.round(confidence * 1000) / 1000;
}

interface Config {
  maxRequestTokens: number;
  /** Micro-dollars per token, numerically equal to USD per million tokens. */
  pricePerToken: number;
  minConfidence: number;
  /** Below this, the price bucket is reported as null. */
  minPriceConfidence: number;
  limits: Limits;
}

/**
 * Parses the numeric settings, or returns null when any is missing or invalid. A NaN
 * limit would make every comparison false and silently disable that limit.
 */
function readConfig(env: Env): Config | null {
  const number = (raw: string | undefined) => (raw === undefined || raw.trim() === "" ? Number.NaN : Number(raw));
  const count = (raw: string | undefined) => {
    const value = number(raw);
    return Number.isInteger(value) && value >= 0 ? value : null;
  };
  const amount = (raw: string | undefined) => {
    const value = number(raw);
    return Number.isFinite(value) && value >= 0 ? value : null;
  };
  const maxRequestTokens = count(env.JEV_MAX_REQUEST_TOKENS);
  const pricePerToken = amount(env.JEV_PRICE_PER_MTOK_USD);
  const minConfidence = amount(env.MIN_CONFIDENCE);
  const minPriceConfidence = amount(env.MIN_PRICE_CONFIDENCE);
  const monthly = amount(env.MONTHLY_BUDGET_USD);
  const daily = amount(env.DAILY_BUDGET_USD);
  const perInstallPerDay = count(env.PER_INSTALL_PER_DAY);
  const perIpPerMinute = count(env.PER_IP_PER_MINUTE);
  const globalPerMinute = count(env.GLOBAL_PER_MINUTE);
  if (
    !maxRequestTokens ||
    !pricePerToken ||
    minConfidence === null ||
    minConfidence > 1 ||
    minPriceConfidence === null ||
    minPriceConfidence > 1 ||
    monthly === null ||
    daily === null ||
    perInstallPerDay === null ||
    perIpPerMinute === null ||
    globalPerMinute === null
  ) {
    return null;
  }
  return {
    maxRequestTokens,
    pricePerToken,
    minConfidence,
    minPriceConfidence,
    limits: {
      monthlyBudgetMicros: Math.round(monthly * 1_000_000),
      dailyBudgetMicros: Math.round(daily * 1_000_000),
      perInstallPerDay,
      perIpPerMinute,
      globalPerMinute,
    },
  };
}

function unavailable(retryAfterSeconds: number): Response {
  return json({ error: "unavailable" }, 503, { "Retry-After": String(retryAfterSeconds) });
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
