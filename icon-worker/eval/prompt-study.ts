// Prompt study for the two-stage Jev picker: runs production `chooseIcon` under several prompt variants on a seeded
// random sample of eval/cases1000 and writes machine- and human-readable results. Eval only; the Worker is untouched.
//
// Usage (from icon-worker/):
//   JEV_API_KEY=… node --experimental-strip-types eval/prompt-study.ts --out-dir eval/results/<date>/<run>
//     [--limit 200]        sample size; 0 = all cases
//     [--seed prompt-study-1]
//     [--variants baseline,short,compact]
//     [--concurrency 2]    1–4
//     [--pause-ms 300]
//     [--model jev-1.14.0]
//     [--currency RUB]    RUB (default), USD or none; includes the app's price question
//   node --experimental-strip-types eval/prompt-study.ts --dry-run [--limit N] [--variants …]
//     offline: checks the variants (same choice keys as production, no gold labels) and runs a few cases against a mock
//     Jev; needs no key and writes nothing.
//
// Output (new directory only; an existing one is never touched):
//   config.json     settings and sampled case names, written before the first request
//   prompts.json    every question each variant sends
//   results.jsonl   one line per finished case and variant, appended as they finish
//   study.json      config, metrics and all results (rewritten at the end, also after a failure or Ctrl-C)
//   study.md        report
// A 401/402/403 (or a balance message) from Jev stops the study at once and keeps the partial results.
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { relative, resolve, sep } from "node:path";
import type { Currency } from "../src/prices.ts";
import { fileURLToPath } from "node:url";
import {
  DEFAULT_MODEL,
  DEFAULT_CURRENCY,
  validRunDate,
  VARIANTS,
  buildDocument,
  fatalReason,
  mockJev,
  parseVariantNames,
  renderMarkdown,
  runCase,
  sampleCases,
  selfCheck,
  variantPrompts,
  type Case,
  type StudyResult,
} from "./prompt-study-core.ts";

const FLAGS = new Set([
  "--out-dir",
  "--limit",
  "--seed",
  "--variants",
  "--concurrency",
  "--pause-ms",
  "--model",
  "--currency",
  "--dry-run",
]);
const args = process.argv.slice(2);
for (const arg of args) if (arg.startsWith("--") && !FLAGS.has(arg)) throw new Error(`unknown flag ${arg}`);
const option = (flag: string) => {
  const index = args.indexOf(flag);
  if (index < 0) return undefined;
  const value = args[index + 1];
  if (value === undefined || value.startsWith("--")) throw new Error(`${flag} needs a value`);
  return value;
};
const integer = (flag: string, fallback: string, min: number, max: number) => {
  const value = Number(option(flag) ?? fallback);
  if (!Number.isInteger(value) || value < min || value > max)
    throw new Error(`${flag} must be an integer ${min}–${max}`);
  return value;
};

const casesDir = new URL("./cases1000/", import.meta.url);
const resultsDir = fileURLToPath(new URL("./results", import.meta.url));

function loadCases(): Case[] {
  const cases: Case[] = [];
  for (const file of readdirSync(casesDir)
    .filter((f) => f.endsWith(".json"))
    .sort()) {
    const part = file.replace(/^part-|\.json$/g, "");
    for (const item of JSON.parse(readFileSync(new URL(file, casesDir), "utf8")) as Case[])
      cases.push({ ...item, part });
  }
  return cases;
}

/** eval/results/<date>/<run>, not existing yet: a study never overwrites a finished run. */
function newRunDirectory(raw: string): string {
  const dir = resolve(raw);
  const parts = relative(resultsDir, dir).split(sep);
  if (parts.length !== 2 || !validRunDate(parts[0]))
    throw new Error("--out-dir must be eval/results/<date>/<unique-run>");
  if (existsSync(dir)) throw new Error(`${dir} already exists; choose a new run directory`);
  mkdirSync(dir, { recursive: true });
  return dir;
}

async function main() {
  const dryRun = args.includes("--dry-run");
  const limit = integer("--limit", "200", 0, 100_000);
  const seed = option("--seed") ?? "prompt-study-1";
  const variants = parseVariantNames(option("--variants") ?? Object.keys(VARIANTS).join(","));
  const concurrency = integer("--concurrency", "2", 1, 4);
  const pauseMs = integer("--pause-ms", "300", 0, 60_000);
  const model = option("--model") ?? DEFAULT_MODEL;
  const currencyOption = option("--currency") ?? DEFAULT_CURRENCY;
  if (!["RUB", "USD", "none"].includes(currencyOption)) throw new Error("--currency must be RUB, USD or none");
  const currency: Currency | null = currencyOption === "none" ? null : (currencyOption as Currency);
  const cases = loadCases();
  const sample = sampleCases(cases, limit, seed);

  const check = selfCheck(cases, variants, currency);
  if (check.problems.length) throw new Error(`variant check failed:\n- ${check.problems.join("\n- ")}`);
  console.error(
    `variants keep production's choice keys and send no gold glyph; mean request chars: ${JSON.stringify(check.sizes)}`,
  );

  if (dryRun) {
    const mock = mockJev();
    const some = sample.slice(0, 8);
    const results: StudyResult[] = [];
    for (const { index, item } of some) {
      for (const variant of variants)
        results.push(await runCase(variant, item, index, { apiKey: "dry-run", model, currency, fetcher: mock }));
    }
    const doc = buildDocument({
      variants,
      sample,
      options: { model, currency, concurrency, pauseMs, seed, limit, totalCases: cases.length },
      results,
      startedAt: new Date().toISOString(),
      status: "partial",
      abortReason: "dry run against a mock Jev",
    });
    console.log(renderMarkdown(doc).split("## Variants")[0]);
    return;
  }

  const apiKey = process.env.JEV_API_KEY;
  if (!apiKey) throw new Error("JEV_API_KEY is not set");
  const outRaw = option("--out-dir");
  if (!outRaw) throw new Error("--out-dir eval/results/<date>/<unique-run> is required");
  const dir = newRunDirectory(outRaw);
  const startedAt = new Date().toISOString();
  const docOptions = { model, currency, concurrency, pauseMs, seed, limit, totalCases: cases.length };
  const initial = buildDocument({ variants, sample, options: docOptions, results: [], startedAt, status: "partial" });
  writeFileSync(`${dir}/config.json`, JSON.stringify(initial.config, null, 1));
  writeFileSync(
    `${dir}/prompts.json`,
    JSON.stringify(Object.fromEntries(variants.map((v) => [v.name, variantPrompts(v, currency)])), null, 1),
  );
  writeFileSync(`${dir}/results.jsonl`, "");

  // Case-major order, so every variant sees the same moment of Jev's day.
  const jobs = sample.flatMap(({ index, item }) => variants.map((variant) => ({ index, item, variant })));
  const results: StudyResult[] = [];
  let next = 0;
  let abortReason: string | undefined;
  process.once("SIGINT", () => {
    abortReason ??= "interrupted";
  });
  const worker = async () => {
    while (!abortReason && next < jobs.length) {
      const { index, item, variant } = jobs[next++];
      const result = await runCase(variant, item, index, { apiKey, model, currency });
      results.push(result);
      appendFileSync(`${dir}/results.jsonl`, JSON.stringify(result) + "\n");
      abortReason ??= fatalReason(result) ?? undefined;
      if (results.length % 50 === 0) console.error(`${results.length}/${jobs.length}`);
      if (pauseMs && next < jobs.length) await new Promise((resolve) => setTimeout(resolve, pauseMs));
    }
  };
  try {
    await Promise.all(Array.from({ length: concurrency }, worker));
  } finally {
    const status = abortReason ? "aborted" : results.length < jobs.length ? "partial" : "complete";
    const doc = buildDocument({ variants, sample, options: docOptions, results, startedAt, status, abortReason });
    writeFileSync(`${dir}/study.json`, JSON.stringify(doc, null, 1));
    writeFileSync(`${dir}/study.md`, renderMarkdown(doc));
    console.log(renderMarkdown(doc).split("## Variants")[0]);
    console.error(`wrote ${dir}`);
    if (abortReason) process.exitCode = 2;
  }
}

await main();
