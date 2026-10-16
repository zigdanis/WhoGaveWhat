import { ICONS, criteria } from "./icons.ts";

export const JEV_URL = "https://api.typesafe.ai/v1/systemone";

const INSTRUCTIONS =
  "The state is the name of a present someone gave or received, written by the user " +
  "in any language (often Russian), possibly with typos or brand names. " +
  "Which icon best depicts the gift item or experience itself?";

export interface JevAnswer {
  key: string;
  confidence: number;
  inputTokens: number;
  model: string;
}

export class JevError extends Error {
  readonly status?: number;

  constructor(message: string, status?: number) {
    super(message);
    this.status = status;
  }
}

export interface JevOptions {
  apiKey: string;
  model: string;
  russianHints: boolean;
  attemptTimeoutMs: number;
  maxAttempts: number;
  fetcher?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
}

export function jevRequestBody(name: string, model: string, russianHints: boolean) {
  return {
    state: name,
    model,
    questions: {
      icon: { type: "choice", instructions: INSTRUCTIONS, criteria: criteria(russianHints) },
    },
  };
}

/**
 * Asks Jev to choose an icon for the gift name. Retries only throttling, overload,
 * server errors and timeouts, with a short jittered backoff; every attempt is bounded.
 */
export async function chooseIcon(name: string, options: JevOptions): Promise<JevAnswer> {
  const fetcher = options.fetcher ?? fetch;
  const sleep = options.sleep ?? ((ms: number) => new Promise((resolve) => setTimeout(resolve, ms)));
  const body = JSON.stringify(jevRequestBody(name, options.model, options.russianHints));
  let lastError: JevError = new JevError("no attempt made");

  for (let attempt = 1; attempt <= options.maxAttempts; attempt++) {
    if (attempt > 1) await sleep(200 * attempt + Math.floor(Math.random() * 200));
    let response: Response;
    try {
      response = await fetcher(JEV_URL, {
        method: "POST",
        headers: { Authorization: `Bearer ${options.apiKey}`, "Content-Type": "application/json" },
        body,
        signal: AbortSignal.timeout(options.attemptTimeoutMs),
      });
    } catch (error) {
      lastError = new JevError(error instanceof Error && error.name === "TimeoutError" ? "timeout" : "network");
      continue;
    }
    if (response.ok) return parseAnswer(await response.json().catch(() => null));
    // Drain the body so the connection can be reused; its content is not needed.
    await response.body?.cancel();
    lastError = new JevError(`status ${response.status}`, response.status);
    if (!isRetryable(response.status)) break;
  }
  throw lastError;
}

function isRetryable(status: number): boolean {
  return status === 429 || status === 529 || status >= 500;
}

/** Validates Jev's reply instead of trusting it: the choice must be one of our keys. */
export function parseAnswer(json: unknown): JevAnswer {
  const root = json as {
    model?: unknown;
    answers?: { icon?: { choice?: unknown; confidence?: unknown } };
    usage?: { input_tokens?: unknown };
  } | null;
  const answer = root?.answers?.icon;
  const key = answer?.choice;
  const confidence = answer?.confidence;
  const inputTokens = root?.usage?.input_tokens;
  if (typeof key !== "string" || !Object.hasOwn(ICONS, key)) throw new JevError("unknown choice");
  if (typeof confidence !== "number" || !(confidence >= 0 && confidence <= 1)) throw new JevError("bad confidence");
  if (typeof inputTokens !== "number" || !Number.isInteger(inputTokens) || inputTokens < 0) {
    throw new JevError("bad usage");
  }
  return { key, confidence, inputTokens, model: typeof root?.model === "string" ? root.model : "unknown" };
}
