// Icon-picking benchmark over eval/cases1000/*.json (gold emoji per gift name, unrestricted Unicode set).
//
// Usage: node --experimental-strip-types eval/bench.ts --picker ceiling|cldr|worker|jev-flat|jev-two-stage
//          [--limit N] [--out results.json] [--base URL] [--pause-ms 2100]
//        node --experimental-strip-types eval/bench.ts --compare a.json b.json ...
//
// Pickers:
//   ceiling        no requests; passes when any accepted emoji exists in the current catalog (src/icons.ts).
//                  This is the best the current approach could ever score.
//   cldr           local keyword match over Unicode CLDR ru+en emoji annotations (what the iOS keyboard uses).
//   worker         the deployed Worker (current Jev + curated catalog). Rotates install IDs under the per-install cap.
//   jev-flat       Jev directly with the current catalog (needs JEV_API_KEY in the environment).
//   jev-two-stage  Jev directly, stage 1 picks a Unicode group, stage 2 picks an emoji from that group, described by
//                  CLDR en+ru keywords (needs JEV_API_KEY). Catalog = all gift-relevant single emoji (~1,100).
//
// Scoring: a pick passes when it is in the case's `accept` list (variation selectors ignored). `null` counts as 🎁.
// `top1` is the stricter share where the pick equals the first (best) accepted emoji.
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { ICONS, criteria } from "../src/icons.ts";

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
const dir = new URL("./cases1000/", import.meta.url);
const dataDir = new URL("./data/", import.meta.url);

export const normalize = (emoji: string | null) => (emoji ?? "🎁").replace(/️/g, "");

function loadCases(): Case[] {
  const files = readdirSync(dir).filter((f) => f.endsWith(".json")).sort();
  const cases: Case[] = [];
  for (const file of files) {
    const part = file.replace(/^part-|\.json$/g, "");
    for (const item of JSON.parse(readFileSync(new URL(file, dir), "utf8")) as Case[]) cases.push({ ...item, part });
  }
  return cases;
}

// ---------- CLDR data ----------

interface Annotations {
  [emoji: string]: { default?: string[]; tts?: string[] };
}
function loadAnnotations(lang: "ru" | "en"): Annotations {
  return JSON.parse(readFileSync(new URL(`cldr-${lang}.json`, dataDir), "utf8")).annotations.annotations;
}

/** Fully-qualified single emoji from emoji-test.txt with their Unicode group, excluding things no gift looks like. */
function loadEmojiGroups(): Map<string, string> {
  const skipGroups = new Set(["Component", "Flags", "Symbols"]);
  const result = new Map<string, string>();
  let group = "";
  for (const line of readFileSync(new URL("emoji-test.txt", dataDir), "utf8").split("\n")) {
    if (line.startsWith("# group:")) group = line.slice(8).trim();
    if (!line.includes("; fully-qualified") || skipGroups.has(group)) continue;
    const codepoints = line.split(";")[0].trim().split(" ").map((h) => parseInt(h, 16));
    // Skip skin-tone and ZWJ sequences; one base emoji per concept keeps the catalog small.
    if (codepoints.some((c) => c === 0x200d || (c >= 0x1f3fb && c <= 0x1f3ff))) continue;
    const emoji = String.fromCodePoint(...codepoints);
    if (group === "Smileys & Emotion" && !/[\u{1F48B}\u{1F48C}\u{1F49D}\u{2764}\u{1F495}]/u.test(emoji)) continue;
    if (group === "People & Body" && !/^[\u{1F440}-\u{1F450}\u{1F485}]/u.test(emoji) && codepoints[0] !== 0x1f9b6) continue;
    result.set(emoji, group);
  }
  return result;
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
  const ru = loadAnnotations("ru");
  const en = loadAnnotations("en");
  const groups = loadEmojiGroups();
  // Keyword index: stem → emoji → weight (tts name 3, plain keyword 1).
  const index = new Map<string, Map<string, number>>();
  const add = (word: string, emoji: string, weight: number) => {
    const key = stem(word.replace(/ё/g, "е"));
    let bucket = index.get(key);
    if (!bucket) index.set(key, (bucket = new Map()));
    bucket.set(emoji, Math.max(bucket.get(emoji) ?? 0, weight));
  };
  for (const [emoji] of groups) {
    for (const ann of [ru[emoji], en[emoji]]) {
      if (!ann) continue;
      for (const name of ann.tts ?? []) for (const w of tokenize(name)) add(w, emoji, 3);
      for (const keyword of ann.default ?? []) {
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
    let body: { emoji?: string | null; confidence?: number } = {};
    try {
      const response = await fetch(`${base}/v1/gift-icon`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Install-ID": installId },
        body: JSON.stringify({ name: item.name }),
      });
      status = response.status;
      body = (await response.json()) as typeof body;
    } catch {
      status = 0;
    }
    return { emoji: body.emoji ?? null, confidence: body.confidence ?? null, ms: performance.now() - started, status };
  };
}

async function askJev(state: string, questions: Record<string, unknown>) {
  const apiKey = process.env.JEV_API_KEY;
  if (!apiKey) throw new Error("JEV_API_KEY is not set");
  const response = await fetch("https://api.typesafe.ai/v1/systemone", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ state, model: option("--model") ?? "jev-1.13.0", questions }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new Error(`jev status ${response.status}`);
  return (await response.json()) as {
    answers: Record<string, { choice: string; confidence: number; probabilities?: Record<string, number> }>;
    usage?: { input_tokens?: number };
  };
}

const INSTRUCTIONS =
  "The state is the name of a present someone gave or received, written by the user " +
  "in any language (often Russian), possibly with typos or brand names. " +
  "Which icon best depicts the gift item or experience itself?";

function makeJevFlatPicker() {
  const options = criteria(true);
  return async (item: Case): Promise<Pick> => {
    const started = performance.now();
    try {
      const reply = await askJev(item.name, { icon: { type: "choice", instructions: INSTRUCTIONS, criteria: options } });
      const answer = reply.answers.icon;
      const emoji = ICONS[answer.choice]?.emoji ?? null;
      return {
        emoji: answer.confidence < 0.35 ? null : emoji,
        confidence: answer.confidence,
        ms: performance.now() - started,
        inputTokens: reply.usage?.input_tokens,
      };
    } catch (error) {
      return { emoji: null, confidence: null, ms: performance.now() - started, status: 0 };
    }
  };
}

/** Stage 1: Unicode group; stage 2: one emoji in that group, described by its CLDR names (en + ru). */
function makeJevTwoStagePicker() {
  const ru = loadAnnotations("ru");
  const en = loadAnnotations("en");
  const groups = loadEmojiGroups();
  const byGroup = new Map<string, Record<string, string>>();
  for (const [emoji, group] of groups) {
    const description = [en[emoji]?.tts?.[0], ...(en[emoji]?.default ?? []).slice(0, 4), ru[emoji]?.tts?.[0], ...(ru[emoji]?.default ?? []).slice(0, 4)]
      .filter(Boolean)
      .join(", ");
    let bucket = byGroup.get(group);
    if (!bucket) byGroup.set(group, (bucket = {}));
    bucket[emoji] = description;
  }
  const groupCriteria: Record<string, string> = {
    "Animals & Nature": "Animals, pets, flowers, plants, trees, weather (животные, цветы, растения)",
    "Food & Drink": "Food, sweets, fruit, meals, drinks, alcohol, tableware (еда, сладости, напитки, посуда)",
    "Travel & Places": "Vehicles, transport, buildings, places, trips, hotels (транспорт, поездки, места)",
    Activities: "Sports, games, music, arts, celebrations, tickets, medals (спорт, игры, праздники, билеты)",
    Objects: "Clothing, accessories, devices, tools, household items, books, money, medical (одежда, техника, вещи, книги, деньги)",
    "People & Body": "Body care, hands, eyes, hearts, kisses (уход за телом, романтика)",
    "Smileys & Emotion": "Love, hearts, romance (любовь, сердечки)",
    other: "Nothing specific; an abstract or unclear gift",
  };
  for (const key of Object.keys(groupCriteria)) if (key !== "other" && !byGroup.has(key)) delete groupCriteria[key];
  return async (item: Case): Promise<Pick> => {
    const started = performance.now();
    let tokens = 0;
    try {
      const first = await askJev(item.name, {
        group: { type: "choice", instructions: INSTRUCTIONS + " First, which group of icons holds it?", criteria: groupCriteria },
      });
      tokens += first.usage?.input_tokens ?? 0;
      const group = first.answers.group.choice;
      if (group === "other" || !byGroup.has(group)) {
        return { emoji: null, confidence: first.answers.group.confidence, ms: performance.now() - started, inputTokens: tokens };
      }
      const options = byGroup.get(group)!;
      const keys = Object.keys(options);
      // Choice takes at most 255 options; split the group into chunks and keep the best-probability chunk winner.
      let best: { emoji: string; p: number; confidence: number } | null = null;
      for (let i = 0; i < keys.length; i += 250) {
        const chunk: Record<string, string> = { none: "None of these icons depicts the gift" };
        for (const key of keys.slice(i, i + 250)) chunk[key] = options[key];
        const second = await askJev(item.name, {
          icon: { type: "choice", instructions: INSTRUCTIONS, criteria: chunk },
        });
        tokens += second.usage?.input_tokens ?? 0;
        const answer = second.answers.icon;
        const p = answer.probabilities?.[answer.choice] ?? answer.confidence;
        if (answer.choice !== "none" && (!best || p > best.p)) best = { emoji: answer.choice, p, confidence: answer.confidence };
      }
      return { emoji: best?.emoji ?? null, confidence: best?.confidence ?? 0, ms: performance.now() - started, inputTokens: tokens };
    } catch {
      return { emoji: null, confidence: null, ms: performance.now() - started, status: 0 };
    }
  };
}

// ---------- reporting ----------

function summarize(label: string, results: Result[]) {
  const pct = (n: number, d: number) => (d === 0 ? "-" : `${((100 * n) / d).toFixed(1)}%`);
  const row = (name: string, rows: Result[]) =>
    `| ${name} | ${rows.length} | ${pct(rows.filter((r) => r.pass).length, rows.length)} | ${pct(rows.filter((r) => r.top1).length, rows.length)} | ${pct(rows.filter((r) => r.pick.emoji === null).length, rows.length)} |`;
  const lines = [`### ${label}`, "", "| slice | n | accept | top-1 | null→🎁 |", "|---|---:|---:|---:|---:|", row("all", results)];
  for (const key of ["part", "tag"] as const) {
    for (const value of [...new Set(results.map((r) => r[key]))].sort()) lines.push(row(`${key}=${value}`, results.filter((r) => r[key] === value)));
  }
  const latency = results.map((r) => r.pick.ms).filter((ms) => ms > 0).sort((a, b) => a - b);
  if (latency.length) lines.push("", `latency p50 ${latency[Math.floor(latency.length / 2)].toFixed(0)} ms, p90 ${latency[Math.floor(latency.length * 0.9)].toFixed(0)} ms`);
  const tokens = results.map((r) => r.pick.inputTokens ?? 0).filter(Boolean);
  if (tokens.length) lines.push(`mean input tokens ${(tokens.reduce((a, b) => a + b, 0) / tokens.length).toFixed(0)}`);
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
      console.log(summarize(`${saved.picker} (${file})`, saved.results).split("\nMisses")[0], "\n");
    }
    return;
  }
  const picker = option("--picker") ?? "ceiling";
  const limit = Number(option("--limit") ?? "0");
  const pauseMs = Number(option("--pause-ms") ?? (picker === "worker" ? "2100" : picker.startsWith("jev") ? "300" : "0"));
  let cases = loadCases();
  if (limit > 0) cases = cases.slice(0, limit);
  const pick: (item: Case) => Pick | Promise<Pick> =
    picker === "ceiling"
      ? ceilingPicker
      : picker === "cldr"
        ? makeCldrPicker()
        : picker === "worker"
          ? makeWorkerPicker()
          : picker === "jev-flat"
            ? makeJevFlatPicker()
            : picker === "jev-two-stage"
              ? makeJevTwoStagePicker()
              : (() => {
                  throw new Error(`unknown picker ${picker}`);
                })();
  const results: Result[] = [];
  for (const [i, item] of cases.entries()) {
    const result = await pick(item);
    const accepted = new Set(item.accept.map(normalize));
    results.push({ ...item, pick: result, pass: accepted.has(normalize(result.emoji)), top1: normalize(result.emoji) === normalize(item.accept[0]) });
    if (pauseMs && i < cases.length - 1) await new Promise((r) => setTimeout(r, pauseMs));
    if ((i + 1) % 100 === 0) console.error(`${i + 1}/${cases.length}`);
  }
  const out = option("--out");
  if (out) writeFileSync(out, JSON.stringify({ picker, at: new Date().toISOString(), results }, null, 1));
  console.log(summarize(picker, results));
}

await main();
