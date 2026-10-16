// Runs the evaluation cases against a deployed icon Worker and prints accuracy by tag.
// Usage: node --experimental-strip-types eval/run.ts [BASE_URL] [--out results.json]
//        node --experimental-strip-types eval/run.ts --summarize results.json [--tail tail.jsonl]
// Requests are paced under the per-IP limit. `--summarize` prints a Markdown summary of saved
// results, adding Jev token usage and latency from `wrangler tail --format json` output if given.
import { readFileSync, writeFileSync } from "node:fs";
import { randomUUID } from "node:crypto";

interface Case {
  name: string;
  accept: Array<string | null>;
  tag: string;
}

const args = process.argv.slice(2);
const option = (flag: string) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};
const base = args.find((arg) => arg.startsWith("http")) ?? "https://whogavewhat-icons.zigdanis.workers.dev";
const pauseMs = Number(option("--pause-ms") ?? "2100");
const cases: Case[] = JSON.parse(readFileSync(new URL("./cases.json", import.meta.url), "utf8"));

interface Result extends Case {
  status: number;
  emoji: string | null;
  confidence: number | null;
  ms: number;
  pass: boolean;
}

const summarizePath = option("--summarize");
const results: Result[] = summarizePath ? JSON.parse(readFileSync(summarizePath, "utf8")).results : [];
for (const [index, item] of (summarizePath ? [] : cases).entries()) {
  const started = performance.now();
  let status = 0;
  let emoji: string | null = null;
  let confidence: number | null = null;
  try {
    const response = await fetch(`${base}/v1/gift-icon`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Install-ID": randomUUID() },
      body: JSON.stringify({ name: item.name }),
      signal: AbortSignal.timeout(15_000),
    });
    status = response.status;
    const body = (await response.json()) as { emoji?: string | null; confidence?: number };
    emoji = body.emoji ?? null;
    confidence = body.confidence ?? null;
  } catch (error) {
    status = -1;
  }
  const ms = Math.round(performance.now() - started);
  const pass = status === 200 && item.accept.includes(emoji);
  results.push({ ...item, status, emoji, confidence, ms, pass });
  console.log(
    `${String(index + 1).padStart(3)} ${pass ? "PASS" : "FAIL"} ${status} ${String(emoji ?? "∅").padEnd(3)} ` +
      `${confidence?.toFixed(2) ?? "-   "} ${String(ms).padStart(5)}ms  [${item.tag}] ${item.name} → want ${item.accept.map((e) => e ?? "∅").join(" ")}`,
  );
  if (index < cases.length - 1) await new Promise((resolve) => setTimeout(resolve, pauseMs));
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
const latencies = answered.map((r) => r.ms).sort((a, b) => a - b);
const pct = (p: number) => latencies[Math.min(latencies.length - 1, Math.floor(p * latencies.length))] ?? 0;
const summary: Record<string, unknown> = {
  total: results.length,
  passed: results.filter((r) => r.pass).length,
  errors: results.filter((r) => r.status !== 200).length,
  byTag: Object.fromEntries(byTag),
  latencyMs: { p50: pct(0.5), p90: pct(0.9), max: latencies.at(-1) ?? 0 },
};

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
} else {
  console.log(JSON.stringify(summary, null, 2));
}
const out = option("--out");
if (out) writeFileSync(out, JSON.stringify({ summary, results }, null, 2));
