// Icon-picking benchmark over eval/cases1000/*.json (gold emoji per gift name, unrestricted Unicode set).
//
// Usage: node --experimental-strip-types eval/bench.ts --picker ceiling|cldr|worker|jev-two-stage
//          [--limit N] [--out results.json] [--base URL] [--pause-ms 2100] [--concurrency 1|2|3|4] [--currency RUB|USD|none]
//        node --experimental-strip-types eval/bench.ts --compare a.json b.json ...
//
// Pickers:
//   ceiling        no requests; passes when any accepted emoji exists in the current catalog (src/cldr-catalog.ts).
//                  This is the best the current approach could ever score.
//   cldr           local keyword match over Unicode CLDR ru+en emoji annotations (what the iOS keyboard uses).
//   worker         the deployed Worker. Rotates install IDs under the per-install cap.
//   jev-two-stage  Jev directly, stage 1 picks a Unicode subgroup, stage 2 picks an emoji from that subgroup, described by
//                  CLDR en+ru keywords (needs JEV_API_KEY). Catalog = the same generated CLDR module as the Worker.
//
// Scoring: a pick passes when it is in the case's `accept` list (variation selectors ignored). `null` counts as 🎁.
// `top1` is the stricter share where the pick equals the first (best) accepted emoji.
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { normalize, failedPick, scoreResult, alignResults } from "./scoring.ts";
import { ICONS, GENERIC_KEY, CATALOG_VERSION } from "../src/cldr-catalog.ts";
import type { Currency } from "../src/prices.ts";
import { chooseIcon, JevError, PICKER_VERSION } from "../src/jev.ts";

interface Case {
  name: string;
  accept: string[];
  tag: string;
  part?: string;
}
interface Pick {
  emoji: string | null;
  confidence?: number | null;
  ms: number;
  status?: number;
  inputTokens?: number;
  unknownUsageAttempts?: number;
  failed?: boolean;
}
interface Result extends Case {
  pick: Pick;
  pass: boolean;
  top1: boolean;
}

const args = process.argv.slice(2);
const option = (flag: string) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};
const currencyOption = option("--currency") ?? "none";
if (!["RUB", "USD", "none"].includes(currencyOption)) throw new Error("--currency must be RUB, USD or none");
const currency: Currency | undefined = currencyOption === "none" ? undefined : (currencyOption as Currency);
const dir = new URL("./cases1000/", import.meta.url);

export { normalize } from "./scoring.ts";

function loadCases(): Case[] {
  const files = readdirSync(dir)
    .filter((f) => f.endsWith(".json"))
    .sort();
  const cases: Case[] = [];
  for (const file of files) {
    const part = file.replace(/^part-|\.json$/g, "");
    for (const item of JSON.parse(readFileSync(new URL(file, dir), "utf8")) as Case[]) cases.push({ ...item, part });
  }
  return cases;
}

// ---------- pickers ----------

const catalogEmoji = new Set(Object.values(ICONS).map((i) => normalize(i.emoji)));

function ceilingPicker(item: Case): Pick {
  const hit = item.accept.find((e) => catalogEmoji.has(normalize(e)));
  return { emoji: hit ?? null, ms: 0 };
}

const tokenize = (text: string) =>
  text
    .toLowerCase()
    .replace(/ё/g, "е")
    .split(/[^a-zа-я0-9]+/u)
    .filter((t) => t.length >= 2);

/** Crude stem: strip common Russian/English endings so "ракеты" meets "ракета". */
const stem = (word: string) =>
  word.length <= 4
    ? word
    : word.replace(/(ами|ями|ов|ев|ей|ой|ый|ий|ая|яя|ое|ее|ом|ем|ах|ях|ую|юю|ы|и|а|я|о|е|у|ю|ь|es|s|ed|ing)$/u, "");

function makeCldrPicker() {
  // Keyword index: stem → emoji → weight (tts name 3, plain keyword 1).
  const index = new Map<string, Map<string, number>>();
  const add = (word: string, emoji: string, weight: number) => {
    const key = stem(word.replace(/ё/g, "е"));
    let bucket = index.get(key);
    if (!bucket) index.set(key, (bucket = new Map()));
    bucket.set(emoji, Math.max(bucket.get(emoji) ?? 0, weight));
  };
  for (const [key, icon] of Object.entries(ICONS)) {
    if (key === GENERIC_KEY) continue;
    const emoji = icon.emoji;
    for (const ann of [icon.en, icon.ru]) {
      for (const w of tokenize(ann.tts)) add(w, emoji, 3);
      for (const keyword of ann.keywords) {
        const words = tokenize(keyword);
        // Multi-word keywords ("горные лыжи") count once per word but lighter, to not drown single-word matches.
        for (const w of words) add(w, emoji, words.length === 1 ? 2 : 1);
      }
    }
  }
  return (item: Case): Pick => {
    const started = performance.now();
    const scores = new Map<string, number>();
    for (const word of tokenize(item.name)) {
      const bucket = index.get(stem(word));
      if (!bucket) continue;
      for (const [emoji, weight] of bucket) scores.set(emoji, (scores.get(emoji) ?? 0) + weight);
    }
    let best: string | null = null;
    let bestScore = 0;
    for (const [emoji, score] of scores) {
      if (score > bestScore) {
        best = emoji;
        bestScore = score;
      }
    }
    return { emoji: best, confidence: bestScore, ms: performance.now() - started };
  };
}

function makeWorkerPicker() {
  const base = option("--base") ?? "https://whogavewhat-icons.zigdanis.workers.dev";
  let installId = randomUUID();
  let used = 0;
  return async (item: Case): Promise<Pick> => {
    if (used >= 90) {
      installId = randomUUID();
      used = 0;
    }
    used += 1;
    const started = performance.now();
    let status = 0;
    let body: { emoji?: string | null; confidence?: number } | null = {};
    let failed = false;
    try {
      const response = await fetch(`${base}/v1/gift-icon`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Install-ID": installId },
        body: JSON.stringify({ name: item.name, ...(currency && { currency }) }),
      });
      status = response.status;
      if (status !== 200) {
        await response.body?.cancel();
        failed = true;
        body = null;
      } else {
        body = (await response.json()) as typeof body;
        if (
          !body ||
          !(body.emoji === null || typeof body.emoji === "string") ||
          typeof body.confidence !== "number" ||
          !(body.confidence >= 0 && body.confidence <= 1)
        ) {
          throw new Error("Malformed Worker reply");
        }
      }
    } catch {
      failed = true; // Preserve an HTTP status even when JSON parsing fails.
      body = null; // Never forward an invalid emoji value into scoring.
    }
    return {
      emoji: body?.emoji ?? null,
      confidence: body?.confidence ?? null,
      ms: performance.now() - started,
      status,
      ...(failed && { failed }),
    };
  };
}

/** Exactly the production picker, catalog, confidence threshold, retries and timeouts. */
function makeJevTwoStagePicker() {
  const apiKey = process.env.JEV_API_KEY;
  if (!apiKey) throw new Error("JEV_API_KEY is not set");
  return async (item: Case): Promise<Pick> => {
    const started = performance.now();
    try {
      const { answer, unknownUsageAttempts } = await chooseIcon(item.name, {
        apiKey,
        model: option("--model") ?? "jev-1.14.0",
        currency,
        attemptTimeoutMs: 3_000,
        maxAttempts: 2,
      });
      return {
        emoji: answer.key !== GENERIC_KEY && answer.confidence >= 0.35 ? (ICONS[answer.key]?.emoji ?? null) : null,
        confidence: answer.confidence,
        ms: performance.now() - started,
        inputTokens: answer.inputTokens,
        unknownUsageAttempts,
      };
    } catch (error) {
      return {
        emoji: null,
        confidence: null,
        ms: performance.now() - started,
        status: error instanceof JevError ? (error.status ?? 0) : 0,
        inputTokens: error instanceof JevError ? error.inputTokens : 0,
        unknownUsageAttempts: error instanceof JevError ? error.unknownUsageAttempts : 4,
      };
    }
  };
}

// ---------- reporting ----------

function summarize(label: string, results: Result[]) {
  const pct = (n: number, d: number) => (d === 0 ? "-" : `${((100 * n) / d).toFixed(1)}%`);
  const row = (name: string, rows: Result[]) =>
    `| ${name} | ${rows.length} | ${pct(rows.filter((r) => r.pass).length, rows.length)} | ${pct(rows.filter((r) => r.top1).length, rows.length)} | ${pct(rows.filter((r) => !failedPick(r.pick) && r.pick.emoji === null).length, rows.length)} |`;
  const lines = [
    `### ${label}`,
    "",
    "| slice | n | accept | top-1 | null→🎁 |",
    "|---|---:|---:|---:|---:|",
    row("all", results),
  ];
  for (const key of ["part", "tag"] as const) {
    for (const value of [...new Set(results.map((r) => r[key]))].sort())
      lines.push(
        row(
          `${key}=${value}`,
          results.filter((r) => r[key] === value),
        ),
      );
  }
  const latency = results
    .map((r) => r.pick.ms)
    .filter((ms) => ms > 0)
    .sort((a, b) => a - b);
  if (latency.length)
    lines.push(
      "",
      `latency p50 ${latency[Math.floor(latency.length / 2)].toFixed(0)} ms, p90 ${latency[Math.floor(latency.length * 0.9)].toFixed(0)} ms`,
    );
  const tokens = results.map((r) => r.pick.inputTokens ?? 0);
  if (results.some((r) => r.pick.inputTokens !== undefined))
    lines.push(`mean input tokens ${(tokens.reduce((a, b) => a + b, 0) / tokens.length).toFixed(0)}`);
  const unknown = results.reduce((n, r) => n + (r.pick.unknownUsageAttempts ?? 0), 0);
  const failed = results.filter((r) => failedPick(r.pick)).length;
  lines.push(`failed requests ${failed}`);
  if (tokens.some(Boolean)) {
    const billed = tokens.reduce((a, b) => a + b, 0) + unknown * 65_536;
    lines.push(
      `unknown-usage attempts ${unknown}; estimated USD per 1000 requests ${(((billed / results.length) * 1000 * 0.042) / 1_000_000).toFixed(4)} (unknown usage at 65,536 tokens/attempt)`,
    );
  }
  const misses = results.filter((r) => !r.pass);
  lines.push("", `Misses (${misses.length}):`, "");
  for (const r of misses) lines.push(`- ${r.name} → ${r.pick.emoji ?? "null"} (want ${r.accept.join(" ")})`);
  return lines.join("\n");
}

async function main() {
  const compareIndex = args.indexOf("--compare");
  if (compareIndex >= 0) {
    for (const file of args.slice(compareIndex + 1)) {
      const saved = JSON.parse(readFileSync(file, "utf8")) as { picker: string; results: Result[] };
      console.log(
        summarize(
          `${saved.picker} (${file}; aligned to ${loadCases().length} current cases)`,
          alignResults(loadCases(), saved.results),
        )
          .split("\nMisses")[0]
          .trimEnd() + "\n",
      );
    }
    return;
  }
  const picker = option("--picker") ?? "ceiling";
  const limit = Number(option("--limit") ?? "0");
  const pauseMs = Number(
    option("--pause-ms") ?? (picker === "worker" ? "2100" : picker.startsWith("jev") ? "300" : "0"),
  );
  let cases = loadCases();
  if (limit > 0) cases = cases.slice(0, limit);
  const pick: (item: Case) => Pick | Promise<Pick> =
    picker === "ceiling"
      ? ceilingPicker
      : picker === "cldr"
        ? makeCldrPicker()
        : picker === "worker"
          ? makeWorkerPicker()
          : picker === "jev-two-stage"
            ? makeJevTwoStagePicker()
            : (() => {
                throw new Error(`unknown picker ${picker}`);
              })();
  const concurrency = Number(option("--concurrency") ?? "1");
  if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 4)
    throw new Error("--concurrency must be 1–4");
  if (picker === "worker" && concurrency !== 1) throw new Error("worker uses concurrency 1 to respect its rate limits");
  const results: Result[] = [];
  const out = option("--out");
  const checkpoint = () => {
    if (out)
      writeFileSync(
        out,
        JSON.stringify(
          {
            picker,
            currency: currency ?? null,
            catalogVersion: CATALOG_VERSION,
            pickerVersion: PICKER_VERSION,
            minConfidence: 0.35,
            model: option("--model") ?? "jev-1.14.0",
            at: new Date().toISOString(),
            results: results.filter(Boolean),
            concurrency,
          },
          null,
          1,
        ),
      );
  };
  let nextIndex = 0;
  let completed = 0;
  const run = async () => {
    while (nextIndex < cases.length) {
      const i = nextIndex++;
      const item = cases[i];
      const result = await pick(item);
      results[i] = scoreResult(item, result);
      completed++;
      checkpoint();
      if (completed % 100 === 0) console.error(`${completed}/${cases.length}`);
      if (pauseMs && nextIndex < cases.length) await new Promise((r) => setTimeout(r, pauseMs));
    }
  };
  await Promise.all(Array.from({ length: concurrency }, run));
  checkpoint();
  console.log(summarize(picker, results));
}

await main();
