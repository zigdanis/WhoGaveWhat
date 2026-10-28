import { GENERIC_KEY, ICONS, SUBGROUPS, describeIcon } from "./cldr-catalog.ts";

const NONE =
  "Includes: unknown, vague or abstract gifts with no meaningful visual association; excludes: a specific gift that can be represented by a related object, function, product or activity, even without an exact emoji; examples: something, an unspecified surprise | Включает: неизвестные, неясные и абстрактные подарки без узнаваемого образа; не включает: конкретный подарок, который можно показать связанным предметом, функцией, результатом или занятием, даже без точного эмодзи; примеры: что-то, неопределённый сюрприз";

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
