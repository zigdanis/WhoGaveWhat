import { ICONS, criteria } from "./icons.ts";
import { bucketFromKey, priceCriteria, priceInstructions, type Currency } from "./prices.ts";

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
  /** Only when a currency was asked for; null when the price answer is missing or invalid. */
  price?: { bucket: number; confidence: number } | null;
}

/** The answer plus earlier failed attempts that may still have been billed (usage unknown). */
export interface JevOutcome {
  answer: JevAnswer;
  unknownUsageAttempts: number;
}

export class JevError extends Error {
  readonly status?: number;
  /** Attempts that may have been billed although no usage was reported. */
  unknownUsageAttempts = 0;

  constructor(message: string, status?: number) {
    super(message);
    this.status = status;
  }
}

export interface JevOptions {
  apiKey: string;
  model: string;
  russianHints: boolean;
  /** Adds the price question in this currency. */
  currency?: Currency;
  attemptTimeoutMs: number;
  maxAttempts: number;
  fetcher?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
}

export function jevRequestBody(name: string, model: string, russianHints: boolean, currency?: Currency) {
  return {
    state: name,
    model,
    questions: {
      icon: { type: "choice", instructions: INSTRUCTIONS, criteria: criteria(russianHints) },
      ...(currency && {
        price: { type: "choice", instructions: priceInstructions(currency), criteria: priceCriteria(currency) },
      }),
    },
  };
}

/**
 * Asks Jev to choose an icon for the gift name. Retries throttling, overload, server
 * errors and timeouts (including while reading the body) with a short jittered backoff;
 * every attempt is bounded. Malformed answers and client errors are not retried.
 */
export async function chooseIcon(name: string, options: JevOptions): Promise<JevOutcome> {
  const fetcher = options.fetcher ?? fetch;
  const sleep = options.sleep ?? ((ms: number) => new Promise((resolve) => setTimeout(resolve, ms)));
  const body = JSON.stringify(jevRequestBody(name, options.model, options.russianHints, options.currency));
  let lastError: JevError = new JevError("no attempt made");
  let unknownUsageAttempts = 0;

  for (let attempt = 1; attempt <= options.maxAttempts; attempt++) {
    if (attempt > 1) await sleep(200 * attempt + Math.floor(Math.random() * 200));
    let response: Response;
    let json: unknown;
    try {
      response = await fetcher(JEV_URL, {
        method: "POST",
        headers: { Authorization: `Bearer ${options.apiKey}`, "Content-Type": "application/json" },
        body,
        signal: AbortSignal.timeout(options.attemptTimeoutMs),
      });
      if (!response.ok) {
        // Drain the body so the connection can be reused; its content is not needed.
        await response.body?.cancel();
        lastError = new JevError(`status ${response.status}`, response.status);
        // Overload and throttling are rejected before any work; other server errors may have been billed.
        if (response.status >= 500 && response.status !== 529) unknownUsageAttempts += 1;
        if (!isRetryable(response.status)) break;
        continue;
      }
      json = await response.json();
    } catch (error) {
      // The provider may have processed (and billed) a request whose reply never arrived.
      unknownUsageAttempts += 1;
      if (error instanceof SyntaxError) {
        lastError = new JevError("malformed reply");
        break;
      }
      lastError = new JevError(error instanceof Error && error.name === "TimeoutError" ? "timeout" : "network");
      continue;
    }
    try {
      return { answer: parseAnswer(json, options.currency), unknownUsageAttempts };
    } catch (error) {
      unknownUsageAttempts += 1;
      lastError = error instanceof JevError ? error : new JevError("invalid answer");
      break;
    }
  }
  lastError.unknownUsageAttempts = unknownUsageAttempts;
  throw lastError;
}

function isRetryable(status: number): boolean {
  return status === 429 || status === 529 || status >= 500;
}

/**
 * Validates Jev's reply instead of trusting it: the choice must be one of our keys. A bad
 * price answer only drops the price; the icon is still usable.
 */
export function parseAnswer(json: unknown, currency?: Currency): JevAnswer {
  const root = json as {
    model?: unknown;
    answers?: { icon?: { choice?: unknown; confidence?: unknown }; price?: { choice?: unknown; confidence?: unknown } };
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
  const result = { key, confidence, inputTokens, model: typeof root?.model === "string" ? root.model : "unknown" };
  if (currency === undefined) return result;
  const price = root?.answers?.price;
  const bucket = bucketFromKey(currency, price?.choice);
  const priceConfidence = price?.confidence;
  if (bucket === null || typeof priceConfidence !== "number" || !(priceConfidence >= 0 && priceConfidence <= 1)) {
    return { ...result, price: null };
  }
  return { ...result, price: { bucket, confidence: priceConfidence } };
}
