/**
 * The price question Jev answers next to the icon: one Choice option per round price bucket
 * in the requested currency. The app holds the same bucket lists in `GiftPriceBuckets.swift`;
 * keep them identical.
 *
 * Bump `PRICE_VERSION` whenever buckets, descriptions or instructions change, so cached
 * answers from an older price question are not reused.
 */
export const PRICE_VERSION = "2026-10-20.1";

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
  const matches = [...name.toLowerCase().matchAll(AMOUNT)];
  if (matches.length !== 1) return null;
  const [whole, digits, suffix] = matches[0];
  const grouped = /^\d{1,3}([\s  .,]\d{3})+$/.test(digits);
  const number = Number(grouped ? digits.replace(/[\s  .,]/g, "") : digits.replace(",", "."));
  const thousands = suffix !== undefined || /тысяч?\p{L}*$/u.test(whole);
  const value = thousands ? number * 1_000 : number;
  return Number.isInteger(value) && value > 0 && value <= MAX_EXPLICIT_AMOUNT ? value : null;
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
