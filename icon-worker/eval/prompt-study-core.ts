// Pure part of the Jev prompt study (eval/prompt-study.ts): prompt variants, the request-rewriting fetcher, deterministic
// sampling, scoring and report rendering. No Node imports, so the Worker test runtime can load it.
//
// The production `chooseIcon` runs unchanged (retries, shared deadline, confidence = min of both stages). A variant only
// rewrites `instructions` and `criteria` text of the questions on their way out; the option keys, the question types and the
// gift name stay exactly as production sends them. Variants never see the gold labels.
import { CATALOG_VERSION, GENERIC_KEY, ICONS, SUBGROUPS, describeIcon } from "../src/cldr-catalog.ts";
import { JevError, PICKER_VERSION, chooseIcon, jevRequestBody, type JevAnswer } from "../src/jev.ts";
import type { Currency } from "../src/prices.ts";
import { SUBGROUP_NOTES } from "../scripts/build-cldr-catalog.ts";

export interface Case {
  name: string;
  accept: string[];
  tag: string;
  part?: string;
}

export type Stage = 1 | 2;

export interface QuestionText {
  instructions: string;
  criteria: Record<string, string>;
}

export interface Variant {
  name: string;
  description: string;
  /** New text for one question; it must keep exactly the keys of `original.criteria`. */
  rewrite(stage: Stage, original: QuestionText): QuestionText;
}

// ---------- production constants mirrored by the study ----------

export const MIN_CONFIDENCE = 0.35; // wrangler.jsonc MIN_CONFIDENCE
export const ATTEMPT_TIMEOUT_MS = 3_000; // src/index.ts
export const MAX_ATTEMPTS = 2; // src/index.ts
export const TOTAL_TIMEOUT_MS = 7_000; // chooseIcon default
export const DEFAULT_CURRENCY: Currency = "RUB";
export const DEFAULT_MODEL = "jev-1.14.0"; // wrangler.jsonc JEV_MODEL
/** TypeSafe list price; unknown-usage attempts are charged at the 65,536-token ceiling, like eval/bench.ts. */
export const INPUT_USD_PER_MILLION = 0.042;
export const UNKNOWN_USAGE_TOKENS = 65_536;

/** Statuses that mean the key or the balance is unusable: further requests cannot succeed. */
export const FATAL_STATUSES: ReadonlySet<number> = new Set([401, 402, 403]);
const FATAL_BODY =
  /insufficient[ _-]+(?:balance|credits?|funds)|(?:balance|credits?|funds).*(?:exhausted|depleted|too low)|payment[ _-]+required|credit[ _-]+limit/i;

export const normalize = (emoji: string | null) => (emoji ?? "🎁").replace(/️/g, "");

// ---------- variants ----------

const SHORT_STAGE1 =
  "The state is a gift name, usually Russian, maybe with typos or brands. " +
  "Choose the subgroup holding the emoji that best depicts the gift: the item itself, otherwise what it makes, does or is for. " +
  "The gift need not literally belong to the subgroup. Choose none only for a vague or abstract gift.";

const SHORT_STAGE2 =
  "The state is a gift name, usually Russian, maybe with typos or brands. " +
  "Choose the emoji that best depicts the gift: the item itself, otherwise what it makes, does or is for. " +
  "Prefer the common general depiction. Choose none only for a vague or abstract gift.";

const MAX_EXAMPLES = 5;
const MAX_KEYWORDS = 4;

/** Up to `count` entries spread evenly over the list, so a long subgroup is represented from end to end. */
export function spread<T>(items: readonly T[], count: number): T[] {
  if (items.length <= count) return [...items];
  return Array.from({ length: count }, (_, i) => items[Math.round((i * (items.length - 1)) / (count - 1))]);
}

/** Same "Includes; excludes; examples" shape as the production text, with at most five CLDR example names per language. */
function compactSubgroup(key: string): string {
  const subgroup = SUBGROUPS[key];
  const note = SUBGROUP_NOTES[subgroup.subgroup];
  if (!note) throw new Error(`no SUBGROUP_NOTES entry for ${subgroup.subgroup}`);
  const names = spread(subgroup.keys, MAX_EXAMPLES).map((iconKey) => ICONS[iconKey]);
  return (
    `Includes: ${note.en[0]}; excludes: ${note.en[1]}; examples: ${names.map((i) => i.en.tts).join(", ")} | ` +
    `Включает: ${note.ru[0]}; не включает: ${note.ru[1]}; примеры: ${names.map((i) => i.ru.tts).join(", ")}`
  );
}

const mapCriteria = (original: Record<string, string>, text: (key: string) => string) =>
  Object.fromEntries(Object.keys(original).map((key) => [key, key === GENERIC_KEY ? original[key] : text(key)]));

export const VARIANTS: Record<string, Variant> = {
  baseline: {
    name: "baseline",
    description: "Current production prompt, unaltered.",
    rewrite: (_stage, original) => original,
  },
  short: {
    name: "short",
    description: "Very short task-specific instructions per stage; production criteria unchanged.",
    rewrite: (stage, original) => ({
      instructions: stage === 1 ? SHORT_STAGE1 : SHORT_STAGE2,
      criteria: original.criteria,
    }),
  },
  compact: {
    name: "compact",
    description:
      "Short instructions; stage 1 criteria keep includes/excludes/examples (EN+RU) with at most 5 spread CLDR examples; " +
      "stage 2 criteria are the bilingual CLDR name plus at most 4 keywords.",
    rewrite: (stage, original) => ({
      instructions: stage === 1 ? SHORT_STAGE1 : SHORT_STAGE2,
      criteria: mapCriteria(original.criteria, (key) =>
        stage === 1 ? compactSubgroup(key) : describeIcon(ICONS[key], MAX_KEYWORDS),
      ),
    }),
  },
};

export function parseVariantNames(list: string): Variant[] {
  const names = list.split(",").map((name) => name.trim());
  if (names.some((name) => !Object.hasOwn(VARIANTS, name))) {
    throw new Error(`--variants must list some of ${Object.keys(VARIANTS).join(", ")}`);
  }
  if (new Set(names).size !== names.length) throw new Error("--variants lists a variant twice");
  return names.map((name) => VARIANTS[name]);
}

interface JevBody {
  state: string;
  model: string;
  questions: Record<string, { type: string; instructions: string; criteria: Record<string, string> }>;
}

/** Applies a variant to a serialized Jev request; throws if the option keys or question set would change. */
export function rewriteBody(variant: Variant, bodyText: string): { text: string; stage: Stage } {
  const body = JSON.parse(bodyText) as JevBody;
  const name = body.questions.group ? "group" : body.questions.icon ? "icon" : undefined;
  if (!name) throw new Error("request has neither a group nor an icon question");
  const stage: Stage = name === "group" ? 1 : 2;
  const original = body.questions[name];
  const rewritten = variant.rewrite(stage, { instructions: original.instructions, criteria: original.criteria });
  const same =
    Object.keys(rewritten.criteria).length === Object.keys(original.criteria).length &&
    Object.keys(original.criteria).every((key, i) => Object.keys(rewritten.criteria)[i] === key);
  if (!same) throw new Error(`variant ${variant.name} changed the choice keys of stage ${stage}`);
  if (!rewritten.instructions.trim())
    throw new Error(`variant ${variant.name} left stage ${stage} without instructions`);
  if (Object.values(rewritten.criteria).some((text) => !text.trim())) {
    throw new Error(`variant ${variant.name} left an empty criterion in stage ${stage}`);
  }
  body.questions[name] = { ...original, instructions: rewritten.instructions, criteria: rewritten.criteria };
  return { text: JSON.stringify(body), stage };
}

// ---------- tracing fetcher ----------

/** One request to Jev, as the retry loop made it. */
export interface TraceAttempt {
  stage: Stage;
  status: number;
  ms: number;
  choice?: string;
  confidence?: number;
  inputTokens?: number;
  /** Network/timeout error name or a fixed provider-status label; raw error bodies are not retained. */
  error?: string;
  billingFailure?: boolean;
}

/** Wraps `inner`: rewrites the request for the variant, and records a lean trace of every attempt. */
export function studyFetcher(variant: Variant, inner: typeof fetch, trace: TraceAttempt[]): typeof fetch {
  return (async (input: Parameters<typeof fetch>[0], init?: Parameters<typeof fetch>[1]) => {
    const { text, stage } = rewriteBody(variant, String(init?.body));
    const started = performance.now();
    let response: Response;
    try {
      response = await inner(input, { ...init, body: text });
    } catch (error) {
      trace.push({
        stage,
        status: 0,
        ms: performance.now() - started,
        error: error instanceof Error ? error.name : "error",
      });
      throw error;
    }
    const attempt: TraceAttempt = { stage, status: response.status, ms: performance.now() - started };
    trace.push(attempt);
    try {
      if (response.ok) {
        const json = (await response.clone().json()) as {
          answers?: Record<string, { choice?: unknown; confidence?: unknown }>;
          usage?: { input_tokens?: unknown };
        };
        const answer = json.answers?.[stage === 1 ? "group" : "icon"];
        if (typeof answer?.choice === "string") attempt.choice = answer.choice;
        if (typeof answer?.confidence === "number") attempt.confidence = answer.confidence;
        if (typeof json.usage?.input_tokens === "number") attempt.inputTokens = json.usage.input_tokens;
      } else {
        const errorBody = await response.clone().text();
        attempt.billingFailure = FATAL_BODY.test(errorBody);
        attempt.error = attempt.billingFailure
          ? "provider balance/payment error"
          : `provider status ${response.status}`;
      }
    } catch {
      // The production parser decides what a malformed reply means; the trace stays partial.
    }
    return response;
  }) as typeof fetch;
}

// ---------- one case ----------

export interface RunOptions {
  apiKey: string;
  /** null measures the icon-only API used by older clients. */
  currency?: Currency | null;
  model: string;
  fetcher?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
}

interface StageSummary {
  choice: string;
  confidence: number;
  inputTokens: number;
}

export interface StudyResult {
  variant: string;
  /** Index of the case in the full, file-ordered case list. */
  caseIndex: number;
  name: string;
  tag: string;
  part?: string;
  accept: string[];
  trace: TraceAttempt[];
  stage1: StageSummary | null;
  stage2: StageSummary | null;
  /** Emoji of the final choice before the confidence threshold (🎁 for none); null when the request failed. */
  candidate: string | null;
  /** min(stage 1, stage 2) confidence as production computes it. */
  confidence: number | null;
  /** What the app would show: the candidate above the threshold, otherwise null (→ 🎁). */
  output: string | null;
  failed: boolean;
  failure?: { status: number; message: string };
  /** Pass counts failures as failures, even when 🎁 is an accepted answer. */
  pass: boolean;
  top1: boolean;
  /** Candidate was accepted regardless of the threshold. */
  candidateAccepted: boolean;
  /** Stage 1 routed to a subgroup holding an accepted glyph (or to none while 🎁 is accepted); null without an answer. */
  stage1Reachable: boolean | null;
  cause: string;
  ms: number;
  inputTokens: number;
  unknownUsageAttempts: number;
}

const iconIndex = new Map(
  Object.entries(ICONS)
    .filter(([key]) => key !== GENERIC_KEY)
    .map(([key, icon]) => [normalize(icon.emoji), { key, subgroup: icon.subgroup }]),
);
const subgroupKeyOf = new Map(Object.entries(SUBGROUPS).map(([key, group]) => [group.subgroup, key]));

/** Where the accepted glyphs live in the catalog. */
export function acceptedRouting(accept: readonly string[]) {
  const accepted = new Set(accept.map(normalize));
  const subgroups = new Set<string>();
  for (const emoji of accepted) {
    const hit = iconIndex.get(emoji);
    if (hit) subgroups.add(subgroupKeyOf.get(hit.subgroup)!);
  }
  const acceptsGift = accepted.has(normalize(ICONS[GENERIC_KEY].emoji));
  return { accepted, subgroups, acceptsGift, inCatalog: subgroups.size > 0 || acceptsGift };
}

const lastGood = (trace: TraceAttempt[], stage: Stage): StageSummary | null => {
  const hit = trace.findLast(
    (a) => a.stage === stage && a.status === 200 && a.choice !== undefined && a.confidence !== undefined,
  );
  return hit ? { choice: hit.choice!, confidence: hit.confidence!, inputTokens: hit.inputTokens ?? 0 } : null;
};

/** Runs production `chooseIcon` under a variant and scores it against the gold labels afterwards. */
export async function runCase(
  variant: Variant,
  item: Case,
  caseIndex: number,
  options: RunOptions,
): Promise<StudyResult> {
  const trace: TraceAttempt[] = [];
  const started = performance.now();
  let answer: JevAnswer | undefined;
  let failure: StudyResult["failure"];
  let inputTokens = 0;
  let unknownUsageAttempts = 0;
  try {
    // Only the gift name goes in; the gold labels are scored below.
    const outcome = await chooseIcon(item.name, {
      apiKey: options.apiKey,
      model: options.model,
      currency: options.currency === null ? undefined : (options.currency ?? DEFAULT_CURRENCY),
      attemptTimeoutMs: ATTEMPT_TIMEOUT_MS,
      maxAttempts: MAX_ATTEMPTS,
      fetcher: studyFetcher(variant, options.fetcher ?? fetch, trace),
      sleep: options.sleep,
    });
    answer = outcome.answer;
    inputTokens = answer.inputTokens;
    unknownUsageAttempts = outcome.unknownUsageAttempts;
  } catch (error) {
    const jev = error instanceof JevError ? error : new JevError("unexpected error");
    failure = { status: jev.status ?? 0, message: jev.message };
    inputTokens = jev.inputTokens;
    unknownUsageAttempts = jev.unknownUsageAttempts;
  }
  const ms = performance.now() - started;

  const route = acceptedRouting(item.accept);
  const stage1 = lastGood(trace, 1);
  const stage2 = lastGood(trace, 2);
  const candidate = answer ? ICONS[answer.key].emoji : null;
  const output = answer && answer.key !== GENERIC_KEY && answer.confidence >= MIN_CONFIDENCE ? candidate : null;
  const stage1Reachable = stage1 ? route.acceptsGift || route.subgroups.has(stage1.choice) : null;
  const pass = !failure && route.accepted.has(normalize(output));
  const candidateAccepted = !failure && candidate !== null && route.accepted.has(normalize(candidate));
  let cause = "pass";
  if (failure) cause = `provider-error: ${failure.message}`;
  else if (!pass) {
    if (!route.inCatalog) cause = "not-in-catalog";
    else if (candidateAccepted) cause = "below-threshold";
    else if (stage1?.choice === GENERIC_KEY) cause = "stage1-none";
    else if (!stage1Reachable) cause = "stage1-misrouted";
    else if (stage2?.choice === GENERIC_KEY) cause = "stage2-none";
    else cause = "stage2-wrong";
  }
  return {
    variant: variant.name,
    caseIndex,
    name: item.name,
    tag: item.tag,
    ...(item.part !== undefined && { part: item.part }),
    accept: item.accept,
    trace,
    stage1,
    stage2,
    candidate,
    confidence: answer?.confidence ?? null,
    output,
    failed: failure !== undefined,
    ...(failure && { failure }),
    pass,
    top1: !failure && normalize(output) === normalize(item.accept[0]),
    candidateAccepted,
    stage1Reachable,
    cause,
    ms,
    inputTokens,
    unknownUsageAttempts,
  };
}

/** Auth or balance problems: no later request can succeed, so the study stops and keeps what it has. */
export function fatalReason(result: StudyResult): string | null {
  const bad = result.trace.find((a) => FATAL_STATUSES.has(a.status) || (a.status >= 400 && a.billingFailure === true));
  return bad
    ? `Jev answered ${bad.status}${bad.error ? ` (${bad.error.replace(/\s+/g, " ").slice(0, 80)})` : ""}`
    : null;
}

/** Validate the calendar date before creating a run folder or spending provider tokens. */
export function validRunDate(value: string): boolean {
  const time = Date.parse(`${value}T00:00:00Z`);
  return (
    /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(time) && new Date(time).toISOString().slice(0, 10) === value
  );
}

// ---------- sampling ----------

function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hashSeed(seed: string): number {
  let h = 2166136261;
  for (const char of seed) h = Math.imul(h ^ char.codePointAt(0)!, 16777619);
  return h >>> 0;
}

/** Fisher–Yates with a seeded generator: the same seed gives the same order on every machine. */
export function seededShuffle<T>(items: readonly T[], seed: string): T[] {
  const random = mulberry32(hashSeed(seed));
  const result = [...items];
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}

export interface Sampled {
  index: number;
  item: Case;
}

/** A random subset in shuffled order, so a run cut short is still an unbiased sample. `limit` 0 means every case. */
export function sampleCases(cases: readonly Case[], limit: number, seed: string): Sampled[] {
  const shuffled = seededShuffle(
    cases.map((item, index) => ({ index, item })),
    seed,
  );
  return limit > 0 ? shuffled.slice(0, limit) : shuffled;
}

// ---------- metrics ----------

export interface VariantMetrics {
  n: number;
  accuracy: number;
  /** 95% Wilson interval of the accuracy. */
  accuracyCi: [number, number];
  top1: number;
  /** Candidate accepted before the confidence threshold. */
  preThresholdAccuracy: number;
  failed: number;
  nullToGift: number;
  /** Cases whose gold glyph exists in the catalog. */
  inCatalog: number;
  /** Among answered cases whose gold is in the catalog: stage 1 routed to a subgroup holding it. */
  stage1Reachable: { hit: number; of: number };
  /** Among stage-1-reachable cases: the final candidate is accepted. */
  stage2Hit: { hit: number; of: number };
  causes: Record<string, number>;
  tokens: { stage1: number; stage2: number; perRequest: number; total: number };
  unknownUsageAttempts: number;
  usdPer1000: number;
  latencyMs: { mean: number; p50: number; p90: number };
  byTag: Record<string, { n: number; accuracy: number }>;
}

export function wilson(passes: number, n: number): [number, number] {
  if (n === 0) return [0, 0];
  const z = 1.96;
  const p = passes / n;
  const centre = (p + (z * z) / (2 * n)) / (1 + (z * z) / n);
  const half = (z * Math.sqrt((p * (1 - p)) / n + (z * z) / (4 * n * n))) / (1 + (z * z) / n);
  return [Math.max(0, centre - half), Math.min(1, centre + half)];
}

const mean = (values: number[]) => (values.length ? values.reduce((a, b) => a + b, 0) / values.length : 0);
const percentile = (sorted: number[], q: number) =>
  sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * q))] : 0;

export function summarizeVariant(results: StudyResult[]): VariantMetrics {
  const n = results.length;
  const count = (predicate: (r: StudyResult) => boolean) => results.filter(predicate).length;
  const passes = count((r) => r.pass);
  const routes = results.map((r) => acceptedRouting(r.accept));
  const answered = results.filter((r, i) => r.stage1 !== null && routes[i].inCatalog);
  const reachable = answered.filter((r) => r.stage1Reachable);
  const causes: Record<string, number> = {};
  for (const r of results) if (!r.pass) causes[r.cause] = (causes[r.cause] ?? 0) + 1;
  const stageTokens = (stage: Stage) =>
    mean(results.map((r) => r.trace.filter((a) => a.stage === stage).reduce((s, a) => s + (a.inputTokens ?? 0), 0)));
  const total = results.reduce((sum, r) => sum + r.inputTokens, 0);
  const unknown = results.reduce((sum, r) => sum + r.unknownUsageAttempts, 0);
  const latency = results.map((r) => r.ms).sort((a, b) => a - b);
  const byTag: VariantMetrics["byTag"] = {};
  for (const tag of [...new Set(results.map((r) => r.tag))].sort()) {
    const rows = results.filter((r) => r.tag === tag);
    byTag[tag] = { n: rows.length, accuracy: rows.filter((r) => r.pass).length / rows.length };
  }
  return {
    n,
    accuracy: n ? passes / n : 0,
    accuracyCi: wilson(passes, n),
    top1: n ? count((r) => r.top1) / n : 0,
    preThresholdAccuracy: n ? count((r) => r.candidateAccepted) / n : 0,
    failed: count((r) => r.failed),
    nullToGift: count((r) => !r.failed && r.output === null),
    inCatalog: routes.filter((route) => route.inCatalog).length,
    stage1Reachable: { hit: reachable.length, of: answered.length },
    stage2Hit: { hit: reachable.filter((r) => r.candidateAccepted).length, of: reachable.length },
    causes,
    tokens: { stage1: stageTokens(1), stage2: stageTokens(2), perRequest: n ? total / n : 0, total },
    unknownUsageAttempts: unknown,
    usdPer1000: n ? (((total + unknown * UNKNOWN_USAGE_TOKENS) / n) * 1000 * INPUT_USD_PER_MILLION) / 1_000_000 : 0,
    latencyMs: { mean: mean(latency), p50: percentile(latency, 0.5), p90: percentile(latency, 0.9) },
    byTag,
  };
}

/** Per-case head-to-head on the cases both variants completed. */
export function pairedDifference(a: StudyResult[], b: StudyResult[]) {
  const other = new Map(b.map((r) => [r.caseIndex, r]));
  let both = 0;
  let onlyA = 0;
  let onlyB = 0;
  let neither = 0;
  for (const r of a) {
    const o = other.get(r.caseIndex);
    if (!o) continue;
    if (r.pass && o.pass) both++;
    else if (r.pass) onlyA++;
    else if (o.pass) onlyB++;
    else neither++;
  }
  return { both, onlyA, onlyB, neither };
}

// ---------- document and report ----------

export interface StudyDocument {
  schema: 1;
  status: "complete" | "partial" | "aborted";
  abortReason?: string;
  startedAt: string;
  finishedAt: string;
  config: {
    variants: { name: string; description: string; instructions: { stage1: string; stage2: string } }[];
    model: string;
    currency: Currency | null;
    pickerVersion: string;
    catalogVersion: string;
    minConfidence: number;
    attemptTimeoutMs: number;
    maxAttempts: number;
    totalTimeoutMs: number;
    concurrency: number;
    pauseMs: number;
    seed: string;
    limit: number;
    totalCases: number;
    sampleSize: number;
    /** Share of the sample whose gold glyph exists in the catalog (the ceiling no prompt can beat). */
    sampleCeiling: number;
    sample: { index: number; name: string; tag: string; part?: string }[];
  };
  metrics: Record<string, VariantMetrics>;
  pairs: { a: string; b: string; both: number; onlyA: number; onlyB: number; neither: number }[];
  results: StudyResult[];
}

/** The instructions a variant sends, for the saved config. Taken from the real production bodies. */
export function variantInstructions(variant: Variant, currency: Currency | null = DEFAULT_CURRENCY) {
  const [first] = Object.keys(SUBGROUPS);
  const text = (subgroup?: string) => {
    const body = JSON.parse(
      rewriteBody(
        variant,
        JSON.stringify(
          jevRequestBody("x", "m", subgroup === undefined ? (currency ?? undefined) : undefined, subgroup),
        ),
      ).text,
    ) as JevBody;
    return (body.questions.group ?? body.questions.icon).instructions;
  };
  return { stage1: text(), stage2: text(first) };
}

/** Every question each variant sends (stage 1, and stage 2 for every subgroup), for the saved prompts file. */
export function variantPrompts(variant: Variant, currency: Currency | null = DEFAULT_CURRENCY) {
  const question = (subgroup?: string) => {
    const body = JSON.parse(
      rewriteBody(
        variant,
        JSON.stringify(
          jevRequestBody("x", "m", subgroup === undefined ? (currency ?? undefined) : undefined, subgroup),
        ),
      ).text,
    ) as JevBody;
    return body.questions;
  };
  return { stage1: question(), stage2: Object.fromEntries(Object.keys(SUBGROUPS).map((key) => [key, question(key)])) };
}

export function buildDocument(input: {
  variants: Variant[];
  sample: Sampled[];
  options: {
    model: string;
    currency?: Currency | null;
    concurrency: number;
    pauseMs: number;
    seed: string;
    limit: number;
    totalCases: number;
  };
  results: StudyResult[];
  startedAt: string;
  status: StudyDocument["status"];
  abortReason?: string;
}): StudyDocument {
  const byVariant = (name: string) => input.results.filter((r) => r.variant === name);
  const metrics = Object.fromEntries(input.variants.map((v) => [v.name, summarizeVariant(byVariant(v.name))]));
  // Every variant against the first one listed (baseline by default).
  const [reference, ...rest] = input.variants;
  const pairs = rest.map((v) => ({
    a: v.name,
    b: reference.name,
    ...pairedDifference(byVariant(v.name), byVariant(reference.name)),
  }));
  return {
    schema: 1,
    status: input.status,
    ...(input.abortReason && { abortReason: input.abortReason }),
    startedAt: input.startedAt,
    finishedAt: new Date().toISOString(),
    config: {
      variants: input.variants.map((v) => ({
        name: v.name,
        description: v.description,
        instructions: variantInstructions(
          v,
          input.options.currency === null ? null : (input.options.currency ?? DEFAULT_CURRENCY),
        ),
      })),
      model: input.options.model,
      currency: input.options.currency === null ? null : (input.options.currency ?? DEFAULT_CURRENCY),
      pickerVersion: PICKER_VERSION,
      catalogVersion: CATALOG_VERSION,
      minConfidence: MIN_CONFIDENCE,
      attemptTimeoutMs: ATTEMPT_TIMEOUT_MS,
      maxAttempts: MAX_ATTEMPTS,
      totalTimeoutMs: TOTAL_TIMEOUT_MS,
      concurrency: input.options.concurrency,
      pauseMs: input.options.pauseMs,
      seed: input.options.seed,
      limit: input.options.limit,
      totalCases: input.options.totalCases,
      sampleSize: input.sample.length,
      sampleCeiling: input.sample.length
        ? input.sample.filter((s) => acceptedRouting(s.item.accept).inCatalog).length / input.sample.length
        : 0,
      sample: input.sample.map(({ index, item }) => ({
        index,
        name: item.name,
        tag: item.tag,
        ...(item.part !== undefined && { part: item.part }),
      })),
    },
    metrics,
    pairs,
    results: input.results,
  };
}

const pct = (value: number) => `${(100 * value).toFixed(1)}%`;
const ratio = (r: { hit: number; of: number }) => (r.of ? `${pct(r.hit / r.of)} (${r.hit}/${r.of})` : "-");

export function renderMarkdown(doc: StudyDocument): string {
  const { config } = doc;
  const names = config.variants.map((v) => v.name);
  const lines = [
    `# Jev prompt study`,
    "",
    `Status: **${doc.status}**${doc.abortReason ? ` — ${doc.abortReason}` : ""}. ${doc.startedAt} → ${doc.finishedAt}.`,
    "",
    `- currency ${config.currency ?? "none"} (${config.currency ? "price question included" : "icon only"})`,
    `- model \`${config.model}\`, picker \`${config.pickerVersion}\`, catalog \`${config.catalogVersion}\`, min confidence ${config.minConfidence}`,
    `- production semantics: ${config.maxAttempts} attempts × ${config.attemptTimeoutMs} ms per stage, ${config.totalTimeoutMs} ms shared deadline`,
    `- sample: ${config.sampleSize} of ${config.totalCases} cases (seed \`${config.seed}\`, limit ${config.limit}); catalog ceiling of the sample ${pct(config.sampleCeiling)}`,
    `- concurrency ${config.concurrency}, pause ${config.pauseMs} ms; every provider failure counts as a failed case`,
    "",
    "## Results",
    "",
    `| variant | n | accuracy (95% CI) | top-1 | pre-threshold | failed | null→🎁 | stage 1 reachable | stage 2 hit | in tokens (s1+s2) | USD/1000 | p50 / p90 ms |`,
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ...names.map((name) => {
      const m = doc.metrics[name];
      return `| ${name} | ${m.n} | ${pct(m.accuracy)} (${pct(m.accuracyCi[0])}–${pct(m.accuracyCi[1])}) | ${pct(m.top1)} | ${pct(m.preThresholdAccuracy)} | ${m.failed} | ${m.nullToGift} | ${ratio(m.stage1Reachable)} | ${ratio(m.stage2Hit)} | ${m.tokens.perRequest.toFixed(0)} (${m.tokens.stage1.toFixed(0)}+${m.tokens.stage2.toFixed(0)}) | ${m.usdPer1000.toFixed(4)} | ${m.latencyMs.p50.toFixed(0)} / ${m.latencyMs.p90.toFixed(0)} |`;
    }),
    "",
    "Stage 1 reachable: among answered cases whose gold glyph is in the catalog, stage 1 chose a subgroup that holds an accepted glyph. Stage 2 hit: among those, the final candidate is accepted (before the threshold).",
    "",
  ];
  if (doc.pairs.length) {
    lines.push(
      `## Against ${doc.pairs[0].b} (same cases)`,
      "",
      "| variant | both pass | only variant | only reference | neither |",
      "|---|---:|---:|---:|---:|",
    );
    for (const p of doc.pairs) lines.push(`| ${p.a} | ${p.both} | ${p.onlyA} | ${p.onlyB} | ${p.neither} |`);
    lines.push("");
  }
  const causeNames = [...new Set(names.flatMap((name) => Object.keys(doc.metrics[name].causes)))].sort();
  lines.push("## Failure causes", "", `| cause | ${names.join(" | ")} |`, `|---|${names.map(() => "---:").join("|")}|`);
  for (const cause of causeNames)
    lines.push(`| ${cause} | ${names.map((name) => doc.metrics[name].causes[cause] ?? 0).join(" | ")} |`);
  lines.push(
    "",
    "## Accuracy by tag",
    "",
    `| tag | ${names.join(" | ")} |`,
    `|---|${names.map(() => "---:").join("|")}|`,
  );
  for (const tag of [...new Set(names.flatMap((name) => Object.keys(doc.metrics[name].byTag)))].sort()) {
    lines.push(
      `| ${tag} | ${names
        .map((name) => {
          const t = doc.metrics[name].byTag[tag];
          return t ? `${pct(t.accuracy)} (${t.n})` : "-";
        })
        .join(" | ")} |`,
    );
  }
  lines.push("", "## Variants", "");
  for (const v of config.variants) {
    lines.push(
      `### ${v.name}`,
      "",
      v.description,
      "",
      "Stage 1 instructions:",
      "",
      `> ${v.instructions.stage1}`,
      "",
      "Stage 2 instructions:",
      "",
      `> ${v.instructions.stage2}`,
      "",
    );
  }
  lines.push("Full criteria for every question are in `prompts.json`.", "", "## Misses", "");
  for (const name of names) {
    const misses = doc.results.filter((r) => r.variant === name && !r.pass);
    lines.push(`<details><summary>${name} (${misses.length})</summary>`, "");
    for (const r of misses) lines.push(`- ${r.name} → ${r.output ?? "null"} [${r.cause}] (want ${r.accept.join(" ")})`);
    lines.push("", "</details>", "");
  }
  lines.push(
    `<details><summary>Sample (${config.sampleSize} cases)</summary>`,
    "",
    ...config.sample.map((s) => `- ${s.name}`),
    "",
    "</details>",
    "",
  );
  return lines.join("\n");
}

// ---------- offline checks ----------

/** Offline stand-in for Jev: answers deterministically from the gift name and the offered keys. Used by tests and --dry-run. */
export function mockJev(): typeof fetch {
  return (async (_url: unknown, init?: { body?: unknown }) => {
    const body = JSON.parse(String(init?.body)) as JevBody;
    const [name, question] = Object.entries(body.questions)[0];
    const keys = Object.keys(question.criteria).filter((key) => key !== GENERIC_KEY);
    let hash = 0;
    for (const char of body.state) hash = (hash * 31 + char.codePointAt(0)!) >>> 0;
    return new Response(
      JSON.stringify({
        model: body.model,
        answers: { [name]: { choice: keys[hash % keys.length], confidence: 0.5 + (hash % 50) / 100 } },
        usage: { input_tokens: Math.ceil(JSON.stringify(body).length / 4) },
      }),
      { status: 200 },
    );
  }) as typeof fetch;
}

/**
 * Checks that every variant keeps production's option keys in every question (stage 1 and every stage 2 subgroup),
 * leaves baseline byte-identical, and that no gold glyph from the given cases appears in any question text.
 * Returns the problems found (empty when fine) and the mean request size per stage.
 */
export function selfCheck(
  cases: readonly Case[],
  variants: readonly Variant[],
  currency: Currency | null = DEFAULT_CURRENCY,
) {
  const problems: string[] = [];
  const gold = new Set(cases.flatMap((c) => c.accept.map(normalize)));
  const sizes: Record<string, { stage1: number; stage2: number }> = {};
  const bodies = [undefined, ...Object.keys(SUBGROUPS)].map((subgroup) =>
    jevRequestBody("x", "m", subgroup === undefined ? (currency ?? undefined) : undefined, subgroup),
  );
  for (const variant of variants) {
    let stage2 = 0;
    let stage1 = 0;
    for (const body of bodies) {
      const original = JSON.stringify(body);
      try {
        const { text, stage } = rewriteBody(variant, original);
        if (variant.name === "baseline" && text !== original) problems.push("baseline changed a request");
        const questions = JSON.stringify((JSON.parse(text) as JevBody).questions);
        for (const emoji of gold)
          if (questions.includes(emoji)) problems.push(`${variant.name} sends gold glyph ${emoji}`);
        if (stage === 1) stage1 = text.length;
        else stage2 += text.length / (bodies.length - 1);
      } catch (error) {
        problems.push(`${variant.name}: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    sizes[variant.name] = { stage1, stage2: Math.round(stage2) };
  }
  return { problems: [...new Set(problems)], sizes };
}
