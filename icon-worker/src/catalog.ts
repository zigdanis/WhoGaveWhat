import { GENERIC_KEY, ICONS, SUBGROUPS, describeIcon } from "./cldr-catalog.ts";

const NONE =
  "Includes: no suitable depiction or an unclear gift. Excludes: gifts depicted by another option. Examples EN: something, surprise. RU: что-то, сюрприз.";

/** Every subgroup uses the same includes/excludes/examples structure, generated from CLDR. */
export function groupCriteria(): Record<string, string> {
  return Object.fromEntries([
    ...Object.entries(SUBGROUPS).map(([key, group]) => [key, group.description]),
    [GENERIC_KEY, NONE],
  ]);
}

/** Only the selected subgroup is sent to Jev; never normalize away emoji presentation selectors. */
export function emojiCriteria(subgroup: string): Record<string, string> {
  if (!Object.hasOwn(SUBGROUPS, subgroup)) throw new Error("unknown subgroup");
  return Object.fromEntries([
    ...SUBGROUPS[subgroup].keys.map((key) => [key, describeIcon(ICONS[key])]),
    [GENERIC_KEY, NONE],
  ]);
}
