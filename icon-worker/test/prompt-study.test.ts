/// <reference types="vite/client" />
import { describe, expect, it } from "vitest";
import {
  VARIANTS,
  variantPrompts,
  validRunDate,
  acceptedRouting,
  buildDocument,
  fatalReason,
  mockJev,
  normalize,
  parseVariantNames,
  renderMarkdown,
  rewriteBody,
  runCase,
  sampleCases,
  selfCheck,
  seededShuffle,
  spread,
  summarizeVariant,
  type Case,
} from "../eval/prompt-study-core";
import { GENERIC_KEY, ICONS, SUBGROUPS } from "../src/cldr-catalog";
import { jevRequestBody } from "../src/jev";
import partA from "../eval/cases1000/part-a.json";

const cases: Case[] = partA as Case[];
const variants = parseVariantNames("baseline,short,compact");

describe("variants", () => {
  it("keep production's choice keys and send no gold glyph", () => {
    expect(selfCheck(cases, variants).problems).toEqual([]);
  });

  it("leave baseline byte-identical and change only instructions and criteria text", () => {
    const original = JSON.stringify(jevRequestBody("букет роз", "jev-test"));
    expect(rewriteBody(VARIANTS.baseline, original).text).toBe(original);
    for (const variant of [VARIANTS.short, VARIANTS.compact]) {
      const before = JSON.parse(original);
      const after = JSON.parse(rewriteBody(variant, original).text);
      expect(after.state).toBe(before.state);
      expect(after.model).toBe(before.model);
      expect(Object.keys(after.questions)).toEqual(Object.keys(before.questions));
      expect(after.questions.group.type).toBe(before.questions.group.type);
      expect(Object.keys(after.questions.group.criteria)).toEqual(Object.keys(before.questions.group.criteria));
      expect(after.questions.group.instructions.length).toBeLessThan(before.questions.group.instructions.length);
    }
  });

  it("preserves the app's price question for both currencies and keeps icon-only requests available", () => {
    for (const currency of ["RUB", "USD"] as const) {
      const original = jevRequestBody("гитара", "jev-test", currency);
      const price = "price" in original.questions ? original.questions.price : undefined;
      expect(price).toBeDefined();
      for (const variant of variants) {
        const changed = JSON.parse(rewriteBody(variant, JSON.stringify(original)).text);
        expect(changed.questions.price).toEqual(price);
        expect(variantPrompts(variant, currency).stage1.price).toEqual(price);
      }
    }
    expect(Object.keys(variantPrompts(VARIANTS.baseline, null).stage1)).toEqual(["group"]);
  });

  it("rejects a variant that changes the keys", () => {
    const broken = {
      name: "broken",
      description: "",
      rewrite: (_: unknown, q: { instructions: string; criteria: Record<string, string> }) => ({
        ...q,
        criteria: { ...q.criteria, extra: "x" },
      }),
    };
    expect(() => rewriteBody(broken as never, JSON.stringify(jevRequestBody("x", "m")))).toThrow(
      /changed the choice keys/,
    );
  });

  it("compact stage 1 keeps the includes/excludes/examples shape in both languages with at most five examples", () => {
    const body = JSON.parse(rewriteBody(VARIANTS.compact, JSON.stringify(jevRequestBody("x", "m"))).text);
    for (const [key, text] of Object.entries<string>(body.questions.group.criteria)) {
      if (key === GENERIC_KEY) continue;
      expect(text).toMatch(/^Includes: .+; excludes: .+; examples: .+ \| Включает: .+; не включает: .+; примеры: .+$/);
      const examples = text.split("; examples: ")[1].split(" | ")[0].split(", ");
      expect(examples.length).toBeLessThanOrEqual(5);
      expect(examples.length).toBe(Math.min(5, SUBGROUPS[key].keys.length));
    }
  });
});

describe("run dates", () => {
  it("rejects impossible calendar dates before a run directory is created", () => {
    expect(validRunDate("2026-10-28")).toBe(true);
    expect(validRunDate("2028-02-29")).toBe(true);
    for (const date of ["2026-13-45", "2026-02-29", "2026-02-30", "not-a-date"]) expect(validRunDate(date)).toBe(false);
  });
});

describe("sampling", () => {
  it("is deterministic per seed, differs between seeds and is not a stride", () => {
    const a = sampleCases(cases, 50, "seed");
    expect(sampleCases(cases, 50, "seed")).toEqual(a);
    expect(sampleCases(cases, 50, "other").map((s) => s.index)).not.toEqual(a.map((s) => s.index));
    expect(new Set(a.map((s) => s.index)).size).toBe(50);
    const gaps = a.slice(1).map((s, i) => s.index - a[i].index);
    expect(new Set(gaps).size).toBeGreaterThan(10);
    expect(sampleCases(cases, 0, "seed")).toHaveLength(cases.length);
  });

  it("shuffles without losing items, and spread keeps ends", () => {
    expect(seededShuffle([1, 2, 3, 4, 5, 6], "x").toSorted()).toEqual([1, 2, 3, 4, 5, 6]);
    expect(spread([1, 2, 3], 5)).toEqual([1, 2, 3]);
    expect(
      spread(
        Array.from({ length: 25 }, (_, i) => i),
        5,
      ),
    ).toEqual([0, 6, 12, 18, 24]);
  });
});

describe("runCase", () => {
  const options = { apiKey: "k", model: "jev-test", fetcher: mockJev(), sleep: async () => {} };

  it("runs both stages through production chooseIcon and traces them without gold", async () => {
    const result = await runCase(VARIANTS.compact, cases[0], 0, options);
    expect(result.failed).toBe(false);
    expect(result.trace.map((a) => a.stage)).toEqual([1, 2]);
    expect(result.stage1?.choice).toBe(result.trace[0].choice);
    expect(Object.hasOwn(SUBGROUPS, result.stage1!.choice)).toBe(true);
    expect(result.candidate).toBe(ICONS[result.stage2!.choice].emoji);
    expect(result.inputTokens).toBe(result.stage1!.inputTokens + result.stage2!.inputTokens);
    expect(result.confidence).toBe(Math.min(result.stage1!.confidence, result.stage2!.confidence));
  });

  it("never lets a provider failure pass, even when the gift emoji is accepted", async () => {
    const gift: Case = { name: "что-то", accept: ["🎁"], tag: "vague" };
    const failing = (async () => new Response("down", { status: 500 })) as typeof fetch;
    const result = await runCase(VARIANTS.baseline, gift, 0, { ...options, fetcher: failing });
    expect(result.failed).toBe(true);
    expect(result.output).toBeNull();
    expect(result.pass).toBe(false);
    expect(result.cause).toBe("provider-error: status 500");
    expect(result.trace.filter((a) => a.status === 500)).toHaveLength(2);
  });

  it("flags auth and balance failures as fatal", async () => {
    for (const status of [401, 402, 403]) {
      const fetcher = (async () => new Response("no", { status })) as typeof fetch;
      const result = await runCase(VARIANTS.baseline, cases[0], 0, { ...options, fetcher });
      expect(fatalReason(result)).toContain(String(status));
    }
    const echo = (async () => new Response("invalid key k-do-not-save", { status: 401 })) as typeof fetch;
    expect(JSON.stringify(await runCase(VARIANTS.baseline, cases[0], 0, { ...options, fetcher: echo }))).not.toContain(
      "k-do-not-save",
    );
    const fine = await runCase(VARIANTS.baseline, cases[0], 0, options);
    expect(fatalReason(fine)).toBeNull();
    const busy = (async () => new Response("slow down", { status: 429 })) as typeof fetch;
    expect(fatalReason(await runCase(VARIANTS.baseline, cases[0], 0, { ...options, fetcher: busy }))).toBeNull();
    const broke = (async () => new Response("Insufficient balance", { status: 429 })) as typeof fetch;
    expect(fatalReason(await runCase(VARIANTS.baseline, cases[0], 0, { ...options, fetcher: broke }))).toContain(
      "balance",
    );
  });

  it("applies the production threshold and separates routing from the final pick", async () => {
    // Gold: the first icon of a subgroup; the fake Jev routes there but answers with low confidence.
    const [subgroupKey, subgroup] = Object.entries(SUBGROUPS)[3];
    const want = ICONS[subgroup.keys[0]].emoji;
    const item: Case = { name: "x", accept: [want], tag: "en" };
    const fake = (confidence: number, stage2: string) =>
      (async (_u: unknown, init?: { body?: unknown }) => {
        const body = JSON.parse(String(init?.body));
        const stage1 = "group" in body.questions;
        return new Response(
          JSON.stringify({
            model: "m",
            answers: { [stage1 ? "group" : "icon"]: { choice: stage1 ? subgroupKey : stage2, confidence } },
            usage: { input_tokens: 10 },
          }),
        );
      }) as typeof fetch;
    const low = await runCase(VARIANTS.short, item, 0, { ...options, fetcher: fake(0.2, subgroup.keys[0]) });
    expect(low).toMatchObject({
      candidate: want,
      output: null,
      pass: false,
      candidateAccepted: true,
      stage1Reachable: true,
      cause: "below-threshold",
    });
    const fallback = await runCase(VARIANTS.short, { ...item, accept: ["🎁"] }, 0, {
      ...options,
      fetcher: fake(0.9, GENERIC_KEY),
    });
    expect(fallback).toMatchObject({ pass: true, candidateAccepted: true, stage1Reachable: true });
    const high = await runCase(VARIANTS.short, item, 0, { ...options, fetcher: fake(0.9, subgroup.keys[0]) });
    expect(high).toMatchObject({ output: want, pass: true, top1: true, cause: "pass", inputTokens: 20 });
    const wrongKey = subgroup.keys.length > 1 ? subgroup.keys[1] : GENERIC_KEY;
    const wrong = await runCase(VARIANTS.short, item, 0, { ...options, fetcher: fake(0.9, wrongKey) });
    expect(wrong.cause).toBe(wrongKey === GENERIC_KEY ? "stage2-none" : "stage2-wrong");
    expect(wrong.stage1Reachable).toBe(true);
  });
});

describe("reachability and report", () => {
  it("maps accepted glyphs to subgroups, ignoring variation selectors", () => {
    const route = acceptedRouting(["❤", "🎁", "no such glyph"]);
    expect(route.subgroups.has("heart")).toBe(true);
    expect(route.acceptsGift).toBe(true);
    expect(acceptedRouting(["🧿🧿🧿"]).inCatalog).toBe(false);
    expect(normalize("❤️")).toBe("❤");
  });

  it("summarizes and renders a study for several variants", async () => {
    const sample = sampleCases(cases, 6, "report");
    const options = { apiKey: "k", model: "jev-test", fetcher: mockJev(), sleep: async () => {} };
    const results = [];
    for (const { index, item } of sample)
      for (const variant of variants) results.push(await runCase(variant, item, index, options));
    const doc = buildDocument({
      variants,
      sample,
      options: { model: "jev-test", concurrency: 2, pauseMs: 0, seed: "report", limit: 6, totalCases: cases.length },
      results,
      startedAt: "t0",
      status: "complete",
    });
    expect(doc.metrics.baseline.n).toBe(6);
    expect(summarizeVariant([]).accuracy).toBe(0);
    expect(doc.config.sample.map((s) => s.name)).toEqual(sample.map((s) => s.item.name));
    expect(doc.config.variants.map((v) => v.instructions.stage2.length)).toHaveLength(3);
    expect(doc.pairs.map((p) => p.a)).toEqual(["short", "compact"]);
    const markdown = renderMarkdown(doc);
    expect(markdown).toContain("| compact | 6 |");
    expect(JSON.stringify(doc)).not.toContain('"k"');
  });
});
