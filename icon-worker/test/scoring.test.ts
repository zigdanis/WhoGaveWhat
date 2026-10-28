import { describe, expect, it } from "vitest";
import { alignResults, scoreResult } from "../eval/scoring";

describe("benchmark scoring", () => {
  const vague = { name: "что-то", accept: ["🎁"] };
  it.each([0, 400, 429, 500, 503])("does not award a gift fallback to HTTP %i", (status) => {
    expect(scoreResult(vague, { emoji: null, status })).toMatchObject({ pass: false, top1: false });
  });
  it("does not normalize malformed values from failed responses", () => {
    expect(scoreResult(vague, { emoji: 123 as unknown as string, status: 503 })).toMatchObject({
      pass: false,
      top1: false,
    });
  });
  it("distinguishes intentional null from a malformed success reply", () => {
    expect(scoreResult(vague, { emoji: null, status: 200 })).toMatchObject({ pass: true, top1: true });
    expect(scoreResult(vague, { emoji: null })).toMatchObject({ pass: true, top1: true });
    expect(scoreResult(vague, { emoji: null, status: 200, failed: true })).toMatchObject({ pass: false, top1: false });
  });
  it("ignores presentation selectors and evaluates top-1 separately", () => {
    expect(scoreResult({ name: "сердце", accept: ["💝", "❤"] }, { emoji: "❤️" })).toMatchObject({
      pass: true,
      top1: false,
    });
  });
  it("aligns old duplicates and changed labels against current cases", () => {
    const cases = [{ name: "цветы", accept: ["🌼"], tag: "ru" }];
    const saved = [
      { name: "removed", pick: { emoji: "🎁" } },
      { name: "цветы", pick: { emoji: "🌹" } },
      { name: "цветы", pick: { emoji: "🌼" } },
    ];
    expect(alignResults(cases, saved)).toEqual([{ ...cases[0], pick: { emoji: "🌼" }, pass: true, top1: true }]);
  });
  it("rejects a comparison with missing cases instead of changing its denominator", () => {
    expect(() => alignResults([{ name: "missing", accept: ["🎁"] }], [])).toThrow("no answer for missing");
  });
});
