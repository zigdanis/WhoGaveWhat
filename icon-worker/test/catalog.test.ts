/// <reference types="vite/client" />
import { describe, expect, it } from "vitest";
import {
  GENERIC_KEY as GENERATOR_GENERIC_KEY,
  MAX_CHOICE_OPTIONS,
  SUBGROUP_NOTES,
  buildCatalog,
  catalogVersion,
  generateModule,
  iconKey,
  isEligible,
  parseEmojiTest,
  sha256,
  subgroupKey,
  type Annotations,
  type Sources,
} from "../scripts/build-cldr-catalog";
import { CATALOG_VERSION, GENERIC_KEY, ICONS, SUBGROUPS, describeIcon } from "../src/cldr-catalog";
import { emojiCriteria as iconCriteria, groupCriteria as subgroupCriteria } from "../src/catalog";
import committedModule from "../src/cldr-catalog.ts?raw";
import emojiTest from "../eval/data/emoji-test.txt?raw";
import cldrEn from "../eval/data/cldr-en.json";
import cldrRu from "../eval/data/cldr-ru.json";

const sources: Sources = {
  emojiTest,
  en: cldrEn.annotations.annotations as Annotations,
  ru: cldrRu.annotations.annotations as Annotations,
};

const withoutNone = Object.entries(ICONS).filter(([key]) => key !== GENERIC_KEY);
const graphemes = (text: string) =>
  [...new Intl.Segmenter("en", { granularity: "grapheme" }).segment(text)].map((s) => s.segment);
const codepointsOf = (emoji: string) => [...emoji].map((c) => c.codePointAt(0)!);

describe("regeneration", () => {
  it("is deterministic and matches the committed src/cldr-catalog.ts", async () => {
    const first = await generateModule(sources);
    expect(await generateModule(structuredClone(sources))).toBe(first);
    // If this fails: node --experimental-strip-types scripts/build-cldr-catalog.ts
    expect(committedModule).toBe(first);
  });

  it("exports the catalog it was built from", async () => {
    const catalog = await buildCatalog(sources);
    expect(ICONS).toEqual(catalog.icons);
    expect(SUBGROUPS).toEqual(catalog.subgroups);
    expect(CATALOG_VERSION).toBe(catalog.version);
    expect(GENERIC_KEY).toBe(GENERATOR_GENERIC_KEY);
    expect(GENERIC_KEY).toBe("none");
  });

  it("derives the version from the content hash", async () => {
    const catalog = await buildCatalog(sources);
    expect(CATALOG_VERSION).toMatch(/^cldr-[0-9a-f]{12}$/);
    expect(await catalogVersion(catalog.icons, catalog.subgroups)).toBe(CATALOG_VERSION);

    const changedKeyword = structuredClone(catalog);
    changedKeyword.icons.e_1f381.en.keywords.push("extra");
    expect(await catalogVersion(changedKeyword.icons, changedKeyword.subgroups)).not.toBe(CATALOG_VERSION);
    const changedDescription = structuredClone(catalog);
    changedDescription.subgroups.event.description += " ";
    expect(await catalogVersion(changedDescription.icons, changedDescription.subgroups)).not.toBe(CATALOG_VERSION);
  });

  it("hashes with SHA-256", async () => {
    expect(await sha256("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    expect(await sha256("")).toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    expect(await sha256("a".repeat(1000))).toBe("41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3");
  });
});

describe("eligibility", () => {
  const entries = parseEmojiTest(emojiTest);

  it("keeps exactly the benchmark's filter: single fully-qualified emoji, no ZWJ, skin tones, flags, symbols, components", () => {
    // Independent copy of eval/bench.ts loadEmojiGroups, the baseline for the catalog.
    const skipGroups = new Set(["Component", "Flags", "Symbols"]);
    const baseline = new Set<string>();
    for (const { codepoints, group } of entries) {
      if (skipGroups.has(group)) continue;
      if (codepoints.some((c) => c === 0x200d || (c >= 0x1f3fb && c <= 0x1f3ff))) continue;
      const emoji = String.fromCodePoint(...codepoints);
      if (group === "Smileys & Emotion" && !/[\u{1F48B}\u{1F48C}\u{1F49D}\u{2764}\u{1F495}]/u.test(emoji)) continue;
      if (group === "People & Body" && !/^[\u{1F440}-\u{1F450}\u{1F485}]/u.test(emoji) && codepoints[0] !== 0x1f9b6)
        continue;
      baseline.add(emoji);
    }
    expect(new Set(withoutNone.map(([, icon]) => icon.emoji))).toEqual(baseline);
    expect(entries.filter(isEligible).map((e) => e.emoji)).toEqual(withoutNone.map(([, icon]) => icon.emoji));
  });

  it("drops what no gift looks like", () => {
    const groups = new Set(withoutNone.map(([, icon]) => icon.group));
    expect([...groups].sort()).toEqual([
      "Activities",
      "Animals & Nature",
      "Food & Drink",
      "Objects",
      "People & Body",
      "Smileys & Emotion",
      "Travel & Places",
    ]);
    for (const [, icon] of withoutNone) {
      const codepoints = codepointsOf(icon.emoji);
      expect(codepoints).not.toContain(0x200d);
      expect(codepoints.filter((c) => c >= 0x1f3fb && c <= 0x1f3ff)).toEqual([]);
      expect(codepoints.some((c) => c >= 0x1f1e6 && c <= 0x1f1ff)).toBe(false);
    }
    // Smileys keep the hearts and the kiss only; People & Body only hands and body parts.
    expect(withoutNone.filter(([, i]) => i.group === "Smileys & Emotion").map(([, i]) => i.emoji)).toEqual([
      "💌",
      "💝",
      "💕",
      "❤️",
      "💋",
    ]);
    const people = withoutNone.filter(([, i]) => i.group === "People & Body");
    expect(people.map(([, i]) => i.emoji)).toEqual(
      expect.arrayContaining(["👋", "👌", "👍", "👏", "💅", "👀", "👅", "🦶"]),
    );
    expect(people.every(([, i]) => /^(hand|body)|^hands$/.test(i.subgroup))).toBe(true);
  });

  it("flags the cases directly", () => {
    const entry = (hex: string, group: string) => ({ codepoints: hex.split(" ").map((h) => parseInt(h, 16)), group });
    expect(isEligible(entry("1F381", "Activities"))).toBe(true);
    expect(isEligible(entry("1F44D 1F3FD", "People & Body"))).toBe(false); // skin tone
    expect(isEligible(entry("2764 FE0F 200D 1F525", "Smileys & Emotion"))).toBe(false); // ZWJ
    expect(isEligible(entry("1F600", "Smileys & Emotion"))).toBe(false); // plain face
    expect(isEligible(entry("1F9D1", "People & Body"))).toBe(false); // person
    expect(isEligible(entry("1F1E9 1F1EA", "Flags"))).toBe(false);
    expect(isEligible(entry("1F44D", "Component"))).toBe(false);
    expect(isEligible(entry("1F4AF", "Symbols"))).toBe(false);
  });
});

describe("entries", () => {
  it("has a stable ASCII key per fully-qualified emoji, derived from its codepoints", () => {
    const qualified = new Set(parseEmojiTest(emojiTest).map((e) => e.emoji));
    for (const [key, icon] of withoutNone) {
      expect(key).toMatch(/^e_[0-9a-f]+(_[0-9a-f]+)*$/);
      expect(key).toBe(iconKey(codepointsOf(icon.emoji)));
      expect(qualified.has(icon.emoji)).toBe(true);
    }
    expect(iconKey([0x1f381])).toBe("e_1f381");
    expect(iconKey([0x2764, 0xfe0f])).toBe("e_2764_fe0f");
  });

  it("is one grapheme per emoji and keeps FE0F where Unicode requires it", () => {
    for (const [key, icon] of withoutNone) {
      expect(graphemes(icon.emoji), key).toEqual([icon.emoji]);
      // GiftEmoji.validated: emoji base; text-default bases require an emoji presentation selector.
      const first = [...icon.emoji][0];
      expect(/\p{Emoji}/u.test(first), key).toBe(true);
      expect(/\p{Emoji_Presentation}/u.test(first) || icon.emoji.includes("\uFE0F"), key).toBe(true);
    }
    expect(ICONS.e_2764_fe0f.emoji).toBe("❤️");
    expect(ICONS.e_2708_fe0f.emoji).toBe("✈️");
    expect(ICONS.e_1f381.emoji).toBe("\u{1F381}");
    // The 119 text-default emoji (✈️, ☀️, ❄️, ...) keep the selector that makes them emoji.
    const selected = withoutNone.filter(([, icon]) => icon.emoji.includes("\uFE0F"));
    expect(selected.length).toBe(119);
    for (const [key, icon] of selected) expect(key, icon.emoji).toMatch(/_fe0f$/);
  });

  it("carries the group, subgroup, and CLDR en/ru names and all keywords, including for emoji CLDR stores without FE0F", () => {
    for (const [key, icon] of withoutNone) {
      expect(icon.group, key).not.toBe("");
      expect(icon.en.tts, key).not.toBe("");
      expect(icon.ru.tts, key).not.toBe("");
      expect(icon.en.keywords.length, key).toBeGreaterThan(0);
      expect(icon.ru.keywords.length, key).toBeGreaterThan(0);
      const table = (annotations: Annotations) => annotations[icon.emoji] ?? annotations[icon.emoji.replace(/️/g, "")];
      expect(icon.en.keywords, key).toEqual(table(sources.en).default);
      expect(icon.ru.keywords, key).toEqual(table(sources.ru).default);
      expect(icon.en.tts, key).toBe(table(sources.en).tts![0]);
      expect(icon.ru.tts, key).toBe(table(sources.ru).tts![0]);
    }
    expect(ICONS.e_1f381).toMatchObject({
      group: "Activities",
      subgroup: "event",
      en: { tts: "wrapped gift" },
      ru: { tts: "подарок" },
    });
    expect(ICONS.e_1f381.en.keywords).toContain("present");
    // The benchmark loader found no annotation for ❤️ because CLDR's key is "❤".
    expect(ICONS.e_2764_fe0f.ru.tts).toBe("алое сердце");
    expect(ICONS.e_2764_fe0f.en.keywords).toEqual(["emotion", "heart", "love", "red"]);
  });

  it("includes none as a generic 🎁 outside every subgroup", () => {
    expect(ICONS.none.emoji).toBe("🎁");
    expect(Object.keys(ICONS)[0]).toBe("none");
    for (const subgroup of Object.values(SUBGROUPS)) expect(subgroup.keys).not.toContain("none");
  });
});

describe("counts", () => {
  it("matches the Unicode 16 data: 873 emoji in 58 subgroups, at most 63 per subgroup", () => {
    expect(withoutNone.length).toBe(873);
    expect(Object.keys(ICONS).length).toBe(874);
    expect(Object.keys(SUBGROUPS).length).toBe(58);
    expect(Math.max(...Object.values(SUBGROUPS).map((s) => s.keys.length))).toBe(63);
    expect(new Set(withoutNone.map(([, i]) => i.subgroup)).size).toBe(58);
  });

  it("puts every icon in exactly one subgroup, in CLDR order", () => {
    const listed = Object.values(SUBGROUPS).flatMap((s) => s.keys);
    expect(listed.length).toBe(withoutNone.length);
    expect(new Set(listed).size).toBe(listed.length);
    expect(new Set(listed)).toEqual(new Set(withoutNone.map(([key]) => key)));
    for (const [id, subgroup] of Object.entries(SUBGROUPS)) {
      expect(id).toBe(subgroupKey(subgroup.subgroup));
      expect(id).toMatch(/^[a-z0-9_]+$/);
      for (const key of subgroup.keys) {
        expect(ICONS[key].subgroup).toBe(subgroup.subgroup);
        expect(ICONS[key].group).toBe(subgroup.group);
      }
    }
  });
});

describe("subgroup descriptions", () => {
  it("are uniform, bilingual, and exist for exactly the subgroups in the catalog", () => {
    expect(Object.keys(SUBGROUP_NOTES).sort()).toEqual(
      Object.values(SUBGROUPS)
        .map((s) => s.subgroup)
        .sort(),
    );
    for (const [id, subgroup] of Object.entries(SUBGROUPS)) {
      expect(subgroup.description, id).toMatch(
        /^Includes: [^;|]+; excludes: [^;|]+; examples: [^|]+ \| Включает: [^;|]+; не включает: [^;|]+; примеры: [^|]+$/,
      );
      expect(subgroup.description.length, id).toBeLessThan(700);
    }
  });

  it("makes the generator fail rather than ship a subgroup without a description", async () => {
    const withNew = { ...sources, emojiTest: emojiTest.replace("# subgroup: event", "# subgroup: brand-new-subgroup") };
    await expect(buildCatalog(withNew)).rejects.toThrow(/no description for subgroup "brand-new-subgroup"/);
  });

  it("fails on a missing CLDR annotation", async () => {
    const en = { ...sources.en };
    delete en["🎁"];
    await expect(buildCatalog({ ...sources, en })).rejects.toThrow(/no English CLDR annotation for 🎁/);
    const ru = { ...sources.ru };
    delete ru["🎁"];
    await expect(buildCatalog({ ...sources, ru })).rejects.toThrow(/no Russian CLDR annotation for 🎁/);
  });
});

describe("criteria", () => {
  it("keeps stage 1 within the Choice limit, with none", () => {
    const options = subgroupCriteria();
    expect(Object.keys(options).length).toBe(Object.keys(SUBGROUPS).length + 1);
    expect(Object.keys(options).length).toBeLessThanOrEqual(MAX_CHOICE_OPTIONS);
    expect(options.none).toBeTruthy();
    for (const [key, description] of Object.entries(options)) {
      expect(key).toMatch(/^[a-z0-9_]+$/);
      expect(description.length).toBeGreaterThan(0);
    }
    expect(options.animal_mammal).toBe(SUBGROUPS.animal_mammal.description);
  });

  it("keeps every stage 2 within the Choice limit, with none", () => {
    for (const [id, subgroup] of Object.entries(SUBGROUPS)) {
      const options = iconCriteria(id);
      expect(Object.keys(options)).toEqual([...subgroup.keys, "none"]);
      expect(Object.keys(options).length).toBeLessThanOrEqual(MAX_CHOICE_OPTIONS);
    }
    expect(Math.max(...Object.keys(SUBGROUPS).map((id) => Object.keys(iconCriteria(id)).length))).toBe(64);
    expect(() => iconCriteria("no_such_subgroup")).toThrow("unknown subgroup");
  });

  it("describes an icon by its names and keywords in both languages", () => {
    expect(describeIcon(ICONS.e_1f381)).toBe(
      "wrapped gift: birthday, bow, box, celebration, christmas, gift, present, surprise, wrapped | подарок: бант, бантик, год, день, коробка, новый, праздник, рождения, Рождество",
    );
    expect(describeIcon(ICONS.e_1f381, 2)).toBe(
      "wrapped gift: birthday, bow | подарок: " + ICONS.e_1f381.ru.keywords.slice(0, 2).join(", "),
    );
    expect(iconCriteria("event").e_1f381).toBe(describeIcon(ICONS.e_1f381));
  });
});
