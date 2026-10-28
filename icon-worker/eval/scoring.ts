/** Shared scoring for live runs and replayed answers; provider errors never count as gift-box fallbacks. */
export interface ScorableCase {
  name: string;
  accept: readonly string[];
}

export interface ScorablePick {
  emoji: string | null;
  status?: number;
  /** A response arrived but could not be read or did not match the Worker response schema. */
  failed?: boolean;
}

export const normalize = (emoji: string | null) => (emoji ?? "🎁").replace(/\uFE0F/g, "");
export const failedPick = (pick: ScorablePick) =>
  pick.failed === true || (pick.status !== undefined && pick.status !== 200);

export function scoreResult<C extends ScorableCase, P extends ScorablePick>(item: C, pick: P) {
  if (item.accept.length === 0) throw new Error(`Empty accepted set for ${item.name}`);
  if (failedPick(pick)) return { ...item, pick, pass: false, top1: false };
  const actual = normalize(pick.emoji);
  return {
    ...item,
    pick,
    pass: item.accept.some((emoji) => normalize(emoji) === actual),
    top1: normalize(item.accept[0]) === actual,
  };
}

/** Replay the last answer per name using the current cases/labels, rejecting incomplete comparisons. */
export function alignResults<C extends ScorableCase, P extends ScorablePick>(
  cases: readonly C[],
  saved: readonly { name: string; pick: P }[],
) {
  const answers = new Map(saved.map((row) => [row.name, row.pick]));
  return cases.map((item) => {
    const pick = answers.get(item.name);
    if (pick === undefined)
      throw new Error(`Saved run has no answer for ${item.name}; compare complete runs on the same cases`);
    return scoreResult(item, pick);
  });
}
