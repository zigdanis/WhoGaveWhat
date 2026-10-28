import { GENERIC_KEY } from "./cldr-catalog.ts";
import { groupCriteria, emojiCriteria } from "./catalog.ts";
import { bucketFromKey, medianBucket, priceCriteria, priceInstructions, type Currency } from "./prices.ts";

/** Bump when routing, instructions, criteria formatting or confidence semantics change. */
export const PICKER_VERSION = "jev-two-stage-v1";

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
  /**
   * Only when a currency was asked for; null when the price answer is missing or invalid. `source` says
   * whether it came from the whole distribution or only from the top choice.
   */
  price?: { bucket: number; confidence: number; source: "distribution" | "choice" } | null;
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
  /** Valid usage already reported by earlier stages. */
  inputTokens = 0;

  constructor(message: string, status?: number) {
    super(message);
    this.status = status;
  }
}

export interface JevOptions {
  apiKey: string;
  model: string;

  /** Adds the price question in this currency. */
  currency?: Currency;
  attemptTimeoutMs: number;
  maxAttempts: number;
  /** Shared deadline keeps both stages and retries within the iOS client's eight seconds. */
  totalTimeoutMs?: number;
  fetcher?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
}

export function jevRequestBody(name: string, model: string, currency?: Currency, subgroup?: string) {
  return {
    state: name,
    model,
    questions:
      subgroup === undefined
        ? {
            group: {
              type: "choice",
              instructions:
                INSTRUCTIONS +
                " Choose the subgroup containing the best depiction, including experiences. Use none only when no subgroup fits.",
              criteria: groupCriteria(),
            },
            ...(currency && {
              price: { type: "choice", instructions: priceInstructions(currency), criteria: priceCriteria(currency) },
            }),
          }
        : {
            icon: { type: "choice", instructions: INSTRUCTIONS, criteria: emojiCriteria(subgroup) },
          },
  };
}

/** Two sequential choices; only the selected subgroup is sent in stage two. */
export async function chooseIcon(name: string, options: JevOptions): Promise<JevOutcome> {
  let inputTokens = 0;
  let unknownUsageAttempts = 0;
  const deadline = AbortSignal.timeout(options.totalTimeoutMs ?? 7_000);
  const ask = async (subgroup?: string) => {
    const outcome = await requestStage(name, options, deadline, subgroup);
    inputTokens += outcome.answer.inputTokens;
    unknownUsageAttempts += outcome.unknownUsageAttempts;
    return outcome.answer;
  };
  try {
    const first = await ask();
    if (first.key === GENERIC_KEY) return { answer: { ...first, inputTokens }, unknownUsageAttempts };
    const second = await ask(first.key);
    return {
      answer: {
        ...second,
        confidence: Math.min(first.confidence, second.confidence),
        inputTokens,
        ...(options.currency && { price: first.price ?? null }),
      },
      unknownUsageAttempts,
    };
  } catch (error) {
    const failure = error instanceof JevError ? error : new JevError("invalid answer");
    failure.inputTokens += inputTokens;
    failure.unknownUsageAttempts += unknownUsageAttempts;
    throw failure;
  }
}

/** Retry each stage independently, never repeating a successful first stage. */
async function requestStage(
  name: string,
  options: JevOptions,
  deadline: AbortSignal,
  subgroup?: string,
): Promise<JevOutcome> {
  const fetcher = options.fetcher ?? fetch;
  const sleep = options.sleep ?? ((ms: number) => new Promise((resolve) => setTimeout(resolve, ms)));
  const body = JSON.stringify(
    jevRequestBody(name, options.model, subgroup === undefined ? options.currency : undefined, subgroup),
  );
  let lastError = new JevError("no attempt made");
  let unknownUsageAttempts = 0;
  let inputTokens = 0;
  for (let attempt = 1; attempt <= options.maxAttempts; attempt++) {
    if (deadline.aborted) {
      lastError = new JevError("timeout");
      break;
    }
    if (attempt > 1) await sleep(200 * attempt + Math.floor(Math.random() * 200));
    if (deadline.aborted) {
      lastError = new JevError("timeout");
      break;
    }
    let response: Response;
    let json: unknown;
    try {
      response = await fetcher(JEV_URL, {
        method: "POST",
        headers: { Authorization: `Bearer ${options.apiKey}`, "Content-Type": "application/json" },
        body,
        signal: AbortSignal.any([deadline, AbortSignal.timeout(options.attemptTimeoutMs)]),
      });
      if (!response.ok) {
        await response.body?.cancel();
        lastError = new JevError(`status ${response.status}`, response.status);
        if (response.status >= 500 && response.status !== 529) unknownUsageAttempts += 1;
        if (!isRetryable(response.status)) break;
        continue;
      }
      json = await response.json();
    } catch (error) {
      unknownUsageAttempts += 1;
      if (error instanceof SyntaxError) {
        lastError = new JevError("malformed reply");
        break;
      }
      lastError = new JevError(error instanceof Error && error.name === "TimeoutError" ? "timeout" : "network");
      continue;
    }
    try {
      // A malformed choice can still carry valid billable usage.
      inputTokens = parseUsage(json);
      return {
        answer: parseAnswer(json, subgroup, subgroup === undefined ? options.currency : undefined),
        unknownUsageAttempts,
      };
    } catch (error) {
      if (!hasUsage(json)) unknownUsageAttempts += 1;
      lastError = error instanceof JevError ? error : new JevError("invalid answer");
      break;
    }
  }
  lastError.inputTokens = inputTokens;
  lastError.unknownUsageAttempts = unknownUsageAttempts;
  throw lastError;
}

function hasUsage(json: unknown): boolean {
  try {
    parseUsage(json);
    return true;
  } catch {
    return false;
  }
}

function parseUsage(json: unknown): number {
  const tokens = (json as { usage?: { input_tokens?: unknown } } | null)?.usage?.input_tokens;
  if (typeof tokens !== "number" || !Number.isSafeInteger(tokens) || tokens < 0) throw new JevError("bad usage");
  return tokens;
}

function isRetryable(status: number): boolean {
  return status === 429 || status === 529 || status >= 500;
}

/**
 * Validates Jev's reply instead of trusting it: the choice must be one of our keys. A bad
 * price answer only drops the price; the icon is still usable. The price is read from the whole
 * distribution (`medianBucket`) when Jev sends one.
 */
export function parseAnswer(json: unknown, subgroup?: string, currency?: Currency): JevAnswer {
  const root = json as {
    model?: unknown;
    answers?: {
      icon?: { choice?: unknown; confidence?: unknown };
      group?: { choice?: unknown; confidence?: unknown };
      price?: { choice?: unknown; confidence?: unknown; probabilities?: unknown };
    };
    usage?: { input_tokens?: unknown };
  } | null;
  const answer = subgroup === undefined ? root?.answers?.group : root?.answers?.icon;
  const key = answer?.choice;
  const confidence = answer?.confidence;
  const inputTokens = parseUsage(json);
  const choices = subgroup === undefined ? groupCriteria() : emojiCriteria(subgroup);
  if (typeof key !== "string" || !Object.hasOwn(choices, key)) throw new JevError("unknown choice");
  if (typeof confidence !== "number" || !(confidence >= 0 && confidence <= 1)) throw new JevError("bad confidence");
  const result = { key, confidence, inputTokens, model: typeof root?.model === "string" ? root.model : "unknown" };
  if (currency === undefined) return result;
  const price = root?.answers?.price;
  const median = medianBucket(currency, price?.probabilities);
  if (median !== null) return { ...result, price: { ...median, source: "distribution" } };
  // Without a usable distribution, fall back to the single choice and Jev's confidence in it.
  const bucket = bucketFromKey(currency, price?.choice);
  const priceConfidence = price?.confidence;
  if (bucket === null || typeof priceConfidence !== "number" || !(priceConfidence >= 0 && priceConfidence <= 1)) {
    return { ...result, price: null };
  }
  return { ...result, price: { bucket, confidence: priceConfidence, source: "choice" } };
}
