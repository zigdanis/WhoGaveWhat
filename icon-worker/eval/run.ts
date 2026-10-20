// Runs the evaluation cases against a deployed icon Worker and prints accuracy by tag.
// Usage: node --experimental-strip-types eval/run.ts [BASE_URL] [--out results.json] [--currency RUB|USD|both]
//        node --experimental-strip-types eval/run.ts --summarize results.json [--tail tail.jsonl]
// Cases with expected price ranges ("rub", "usd") are asked once per selected currency (default both) and
// the icon is judged once, from the first answer; other cases are asked without a currency. Requests are
// paced under the per-IP limit, so every currency adds a request per priced case. `--summarize` prints a Markdown summary of saved
// results, adding Jev token usage and latency from `wrangler tail --format json` output if given.
import { readFileSync, writeFileSync } from "node:fs";
import { randomUUID } from "node:crypto";

type Currency = "RUB" | "USD";

interface Case {
  name: string;
  accept: Array<string | null>;
  tag: string;
  /** Acceptable price range per currency, inclusive. */
  rub?: [number, number];
  usd?: [number, number];
}

const args = process.argv.slice(2);
const option = (flag: string) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};
const base = args.find((arg) => arg.startsWith("http")) ?? "https://whogavewhat-icons.zigdanis.workers.dev";
const pauseMs = Number(option("--pause-ms") ?? "2100");
const currencyArgs = args.flatMap((arg, index) => (args[index - 1] === "--currency" ? [arg] : []));
const currencies: Currency[] = (currencyArgs.length === 0 ? ["both"] : currencyArgs).flatMap((value) => {
  if (value === "both") return ["RUB", "USD"] as Currency[];
  if (value === "RUB" || value === "USD") return [value];
  throw new Error(`Unknown currency ${value}; use RUB, USD or both`);
});
const cases: Case[] = JSON.parse(readFileSync(new URL("./cases.json", import.meta.url), "utf8"));

interface PriceResult {
  status: number;
  price: number | null;
  priceConfidence: number | null;
  ms: number;
  /** Null price counts as a miss; see `nullRate` in the summary for how often that is the reason. */
  pass: boolean;
}

interface Result extends Case {
  status: number;
  emoji: string | null;
  confidence: number | null;
  ms: number;
  pass: boolean;
  prices?: Partial<Record<Currency, PriceResult>>;
}

const priceRange = (item: Case, currency: Currency) => (currency === "RUB" ? item.rub : item.usd);

async function ask(name: string, currency?: Currency) {
  const started = performance.now();
  let status = 0;
  let body: { emoji?: string | null; confidence?: number; price?: number | null; priceConfidence?: number } = {};
  try {
    const response = await fetch(`${base}/v1/gift-icon`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Install-ID": randomUUID() },
      body: JSON.stringify(currency ? { name, currency } : { name }),
      signal: AbortSignal.timeout(15_000),
    });
    status = response.status;
    body = (await response.json()) as typeof body;
  } catch (error) {
    status = -1;
  }
  return { status, body, ms: Math.round(performance.now() - started) };
}

const summarizePath = option("--summarize");
const results: Result[] = summarizePath ? JSON.parse(readFileSync(summarizePath, "utf8")).results : [];
const pause = () => new Promise((resolve) => setTimeout(resolve, pauseMs));
for (const [index, item] of (summarizePath ? [] : cases).entries()) {
  const asked = currencies.filter((currency) => priceRange(item, currency));
  const prices: Partial<Record<Currency, PriceResult>> = {};
  let first: Awaited<ReturnType<typeof ask>> | undefined;
  for (const currency of asked.length > 0 ? asked : [undefined]) {
    if (first) await pause();
    const answer = await ask(item.name, currency);
    first ??= answer;
    if (currency) {
      const range = priceRange(item, currency)!;
      const price = answer.body.price ?? null;
      prices[currency] = {
        status: answer.status,
        price,
        priceConfidence: answer.body.priceConfidence ?? null,
        ms: answer.ms,
        pass: answer.status === 200 && price !== null && price >= range[0] && price <= range[1],
      };
    }
  }
  const { status, body, ms } = first!;
  const emoji = body.emoji ?? null;
  const confidence = body.confidence ?? null;
  const pass = status === 200 && item.accept.includes(emoji);
  results.push({ ...item, status, emoji, confidence, ms, pass, ...(asked.length > 0 && { prices }) });
  const priceText = asked.map((currency) => `${currency} ${prices[currency]!.pass ? "ok" : "MISS"} ${prices[currency]!.price ?? "∅"}`).join(", ");
  console.log(
    `${String(index + 1).padStart(3)} ${pass ? "PASS" : "FAIL"} ${status} ${String(emoji ?? "∅").padEnd(3)} ` +
      `${confidence?.toFixed(2) ?? "-   "} ${String(ms).padStart(5)}ms  [${item.tag}] ${item.name} → want ${item.accept.map((e) => e ?? "∅").join(" ")}` +
      (priceText ? `  | ${priceText}` : ""),
  );
  if (index < cases.length - 1) await pause();
}

const byTag = new Map<string, { pass: number; total: number }>();
for (const result of results) {
  const group = result.tag.split("-")[0];
  const entry = byTag.get(group) ?? { pass: 0, total: 0 };
  entry.total += 1;
  if (result.pass) entry.pass += 1;
  byTag.set(group, entry);
}
const answered = results.filter((r) => r.status === 200);
const priced = results.flatMap((r) => Object.entries(r.prices ?? {}).map(([currency, price]) => ({ ...r, currency, price: price! })));
const latencies = [...answered.map((r) => r.ms), ...priced.map((r) => r.price.ms)].sort((a, b) => a - b);
const pct = (p: number) => latencies[Math.min(latencies.length - 1, Math.floor(p * latencies.length))] ?? 0;
const summary: Record<string, unknown> = {
  total: results.length,
  passed: results.filter((r) => r.pass).length,
  errors: results.filter((r) => r.status !== 200).length,
  byTag: Object.fromEntries(byTag),
  latencyMs: { p50: pct(0.5), p90: pct(0.9), max: latencies.at(-1) ?? 0 },
};
// Price accuracy: the answer lies inside the expected range. A null price counts as a miss and is
// also reported as `nullRate`, so a conservative threshold shows up apart from wrong buckets.
const priceSummary: Record<string, unknown> = {};
for (const currency of ["RUB", "USD"] as const) {
  const rows = priced.filter((r) => r.currency === currency && r.price.status === 200);
  if (rows.length === 0) continue;
  priceSummary[currency] = {
    cases: rows.length,
    withinRange: rows.filter((r) => r.price.pass).length,
    accuracy: Number((rows.filter((r) => r.price.pass).length / rows.length).toFixed(3)),
    nullRate: Number((rows.filter((r) => r.price.price === null).length / rows.length).toFixed(3)),
    errors: priced.filter((r) => r.currency === currency && r.price.status !== 200).length,
  };
}
if (Object.keys(priceSummary).length > 0) summary.price = priceSummary;

const tailPath = option("--tail");
if (tailPath) {
  // `wrangler tail --format json` writes one JSON event per line or pretty-printed objects; collect our log lines.
  const text = readFileSync(tailPath, "utf8");
  const tokens = [...text.matchAll(/\\?"event\\?":\\?"jev\\?",\\?"model\\?":\\?"([^"\\]+)\\?",\\?"tokens\\?":(\d+),\\?"ms\\?":(\d+)/g)];
  const counts = tokens.map((match) => Number(match[2]));
  const providerMs = tokens.map((match) => Number(match[3])).sort((a, b) => a - b);
  if (counts.length > 0) {
    const mean = counts.reduce((a, b) => a + b, 0) / counts.length;
    summary.jev = {
      model: tokens[0][1],
      calls: counts.length,
      meanInputTokens: Math.round(mean),
      usdPer1000Requests: Number(((mean * 1000 * 0.042) / 1_000_000).toFixed(4)),
      providerMsP50: providerMs[Math.floor(providerMs.length / 2)],
    };
  }
}

if (summarizePath) {
  const failures = results.filter((r) => !r.pass);
  console.log("## Icon evaluation\n");
  console.log("```json\n" + JSON.stringify(summary, null, 2) + "\n```\n");
  console.log(`### Misses (${failures.length})\n`);
  console.log("| Name | Tag | Got | Confidence | Wanted |\n| --- | --- | --- | --- | --- |");
  for (const r of failures) {
    const got = r.status === 200 ? (r.emoji ?? "none") : `HTTP ${r.status}`;
    console.log(`| ${r.name} | ${r.tag} | ${got} | ${r.confidence ?? "-"} | ${r.accept.map((e) => e ?? "none").join(" ")} |`);
  }
  const priceMisses = priced.filter((r) => !r.price.pass);
  console.log(`\n### Price misses (${priceMisses.length} of ${priced.length})\n`);
  console.log("| Name | Currency | Got | Confidence | Wanted |\n| --- | --- | --- | --- | --- |");
  for (const r of priceMisses) {
    const got = r.price.status === 200 ? (r.price.price ?? "none") : `HTTP ${r.price.status}`;
    const [min, max] = priceRange(r, r.currency as Currency)!;
    console.log(`| ${r.name} | ${r.currency} | ${got} | ${r.price.priceConfidence ?? "-"} | ${min}–${max} |`);
  }
} else {
  console.log(JSON.stringify(summary, null, 2));
}
const out = option("--out");
if (out) writeFileSync(out, JSON.stringify({ summary, results }, null, 2));
