/**
 * The price question Jev answers next to the icon: one Choice option per round price bucket
 * in the requested currency. The app holds the same bucket lists in `GiftPriceBuckets.swift`;
 * keep them identical.
 *
 * Bump `PRICE_VERSION` whenever buckets, descriptions, instructions or the way an answer becomes a
 * price change, so cached answers from an older price question are not reused.
 */
export const PRICE_VERSION = "2026-10-23.1";

export type Currency = "RUB" | "USD";

export const CURRENCIES: readonly Currency[] = ["RUB", "USD"];

/** Big round steps; the top reaches a motorcycle (about 300k–1M RUB, 5k–20k USD). */
export const PRICE_BUCKETS: Record<Currency, readonly number[]> = {
  RUB: [300, 500, 1_000, 2_000, 3_000, 5_000, 10_000, 15_000, 20_000, 30_000, 50_000, 100_000, 200_000, 500_000, 1_000_000],
  USD: [5, 10, 20, 30, 50, 100, 150, 200, 300, 500, 1_000, 2_000, 5_000, 10_000, 20_000],
};

const CURRENCY_NAMES: Record<Currency, string> = { RUB: "Russian rubles", USD: "US dollars" };

export function priceInstructions(currency: Currency): string {
  return (
    `Estimate the typical present-day retail price, in ${CURRENCY_NAMES[currency]}, of a typical version of the gift ` +
    "named in the state. Experiences and services count too. For money, gift cards and certificates " +
    "with a stated amount, choose the option closest to that amount."
  );
}

/** Jev Choice criteria: option name (`rub_5000`) → short description. */
export function priceCriteria(currency: Currency): Record<string, string> {
  const result: Record<string, string> = {};
  for (const bucket of PRICE_BUCKETS[currency]) {
    result[priceKey(currency, bucket)] = `About ${bucket.toLocaleString("en-US")} ${CURRENCY_NAMES[currency]}`;
  }
  return result;
}

function priceKey(currency: Currency, bucket: number): string {
  return `${currency.toLowerCase()}_${bucket}`;
}

/** The bucket amount for a Jev option name, or null when it is not one of the currency's options. */
export function bucketFromKey(currency: Currency, key: unknown): number | null {
  if (typeof key !== "string") return null;
  return PRICE_BUCKETS[currency].find((bucket) => priceKey(currency, bucket) === key) ?? null;
}

/**
 * The bucket Jev's price distribution points to, or null when `probabilities` is missing or malformed.
 *
 * The buckets are ordered amounts, so the estimate is the weighted median rather than the single most
 * likely bucket: a bicycle spread over 10,000–50,000 rubles lands in the middle of that range. Its
 * confidence looks at the share of probability on that bucket and its neighbours, so a spread over
 * adjacent amounts still counts as agreement, while a flat or widely split distribution does not.
 * Jev's own `confidence` looks only at the top option, which falls to about 0 for such spreads.
 * Like Jev's, it is 0 for an even spread (or less probability nearby than that) and 1 when all of it
 * is nearby, so one threshold fits both.
 */
export function medianBucket(currency: Currency, probabilities: unknown): { bucket: number; confidence: number } | null {
  if (typeof probabilities !== "object" || probabilities === null) return null;
  const buckets = PRICE_BUCKETS[currency];
  const weights: number[] = [];
  for (const bucket of buckets) {
    const value = Object.hasOwn(probabilities, priceKey(currency, bucket))
      ? (probabilities as Record<string, unknown>)[priceKey(currency, bucket)]
      : 0;
    if (typeof value !== "number" || !(value >= 0 && value <= 1)) return null;
    weights.push(value);
  }
  const total = weights.reduce((sum, weight) => sum + weight, 0);
  // The options hold all of the probability. Jev rounds each value, so the sum can drift a little
  // from 1; further off means the distribution doesn't match the options asked.
  if (!(total >= 0.9 && total <= 1.1)) return null;
  let cumulative = 0;
  let index = 0;
  while (index < buckets.length - 1 && (cumulative += weights[index]) / total < 0.5) index += 1;
  const nearby = weights.slice(Math.max(0, index - 1), index + 2);
  const share = nearby.reduce((sum, weight) => sum + weight, 0) / total;
  // What the same buckets would hold under an even spread: 3/15, or 2/15 at either end.
  const even = nearby.length / buckets.length;
  return { bucket: buckets[index], confidence: Math.min(1, Math.max(0, (share - even) / (1 - even))) };
}

/** Icons whose gift is an amount of money, so an amount written in the name beats the estimate. */
const MONEY_KEYS = new Set(["money", "banknotes", "gift_card", "coins"]);
const MAX_EXPLICIT_AMOUNT = 10_000_000;

// "5000", "5 000", "5,000", "5.000" (thousand groups) or a plain or decimal number, with an
// optional "k"/"к"/"тыс" multiplier. The currency symbol or word after it is ignored.
const AMOUNT = /(\d{1,3}(?:[\s  .,]\d{3})+|\d+(?:[.,]\d+)?)(?:\s*(к|k|тыс)(?![\p{L}\d])|\s*тысяч?\p{L}*)?/giu;

/**
 * The one amount written in a money-like gift name ("Деньги 5000р", "5 000 ₽", "$100", "5к",
 * "10 тыс"), or null when the name has no number, several numbers, a non-whole or zero amount,
 * or one above 10,000,000. The currency is ignored: amounts are not converted.
 */
export function explicitAmount(name: string): number | null {
  const text = name.toLowerCase();
  const matches = [...text.matchAll(AMOUNT)];
  if (matches.length !== 1) return null;
  const [whole, digits, suffix] = matches[0];
  const grouped = /^\d{1,3}([\s  .,]\d{3})+$/.test(digits);
  const number = Number(grouped ? digits.replace(/[\s  .,]/g, "") : digits.replace(",", "."));
  const thousands = suffix !== undefined || /тысяч?\p{L}*$/u.test(whole);
  const value = thousands ? number * 1_000 : number;
  if (!thousands && !grouped && looksLikeYear(value) && !hasCurrencyMark(text, matches[0].index!, whole.length)) return null;
  return Number.isInteger(value) && value > 0 && value <= MAX_EXPLICIT_AMOUNT ? value : null;
}

/** "монета 1897", "конверт 2026": a bare year, not an amount. Round ones like 2000, or grouped "1 950", still read as amounts. */
function looksLikeYear(value: number): boolean {
  return value >= 1_800 && value <= 2_099 && value % 100 !== 0;
}

/** A currency symbol or word right before or after the number ("$1897", "1897 р", "1897 руб"). */
function hasCurrencyMark(text: string, start: number, length: number): boolean {
  const before = text.slice(0, start);
  const after = text.slice(start + length);
  return (
    /[$€₽]\s*$/u.test(before) ||
    /^\s*(?:[$€₽]|(?:р|руб|rub|usd|eur|евро|долл)(?!\p{L})|(?:рубл|доллар|dollar|ruble|rouble|euro)\p{L}*)/u.test(after)
  );
}

/**
 * The price to report: an explicit amount for a confidently money-like icon, else the bucket
 * when confident enough. The icon must pass the same threshold that decides whether it is shown.
 */
export function priceFor(
  icon: { key: string | null; confidence: number; minConfidence: number },
  name: string,
  bucket: number | null,
  confidence: number,
  minConfidence: number,
): number | null {
  if (icon.key !== null && MONEY_KEYS.has(icon.key) && icon.confidence >= icon.minConfidence) {
    const amount = explicitAmount(name);
    if (amount !== null) return amount;
  }
  return bucket !== null && confidence >= minConfidence ? bucket : null;
}
