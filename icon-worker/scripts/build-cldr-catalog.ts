// Builds src/cldr-catalog.ts: every Unicode emoji that can plausibly depict a gift, with its Unicode group and
// subgroup and its CLDR English and Russian names and keywords. Used by the two-stage icon picker: stage 1 picks a
// subgroup from SUBGROUPS, stage 2 picks an emoji inside it.
//
// Usage (from icon-worker/): node --experimental-strip-types scripts/build-cldr-catalog.ts [--check]
//   no flag   rewrite src/cldr-catalog.ts from eval/data/{emoji-test.txt,cldr-en.json,cldr-ru.json}
//   --check   exit 1 when src/cldr-catalog.ts differs from what the data would generate
//
// Everything above `main` is pure (no Node imports) so the tests can import it inside the Worker test runtime.

export interface LocalizedName {
  /** CLDR short name ("text-to-speech" name), e.g. "wrapped gift" / "подарок". */
  tts: string;
  /** All CLDR keywords for the emoji in that language. */
  keywords: string[];
}

export interface CatalogIcon {
  /** Fully-qualified emoji, variation selectors kept. */
  emoji: string;
  /** Unicode group and subgroup from emoji-test.txt; empty for the generic option. */
  group: string;
  subgroup: string;
  en: LocalizedName;
  ru: LocalizedName;
}

export interface CatalogSubgroup {
  group: string;
  subgroup: string;
  /** ICONS keys in CLDR order. */
  keys: string[];
  /** Bilingual inclusion / exclusion / examples text for the stage-1 question. */
  description: string;
}

export interface Catalog {
  version: string;
  icons: Record<string, CatalogIcon>;
  subgroups: Record<string, CatalogSubgroup>;
}

export interface Annotation {
  default?: string[];
  tts?: string[];
}
export type Annotations = Record<string, Annotation>;

export interface Sources {
  /** Contents of eval/data/emoji-test.txt. */
  emojiTest: string;
  /** `annotations.annotations` of eval/data/cldr-en.json and cldr-ru.json. */
  en: Annotations;
  ru: Annotations;
}

/** Jev Choice takes at most 255 options; stage 1 has one per subgroup plus the generic one. */
export const MAX_CHOICE_OPTIONS = 255;
export const GENERIC_KEY = "none";
export const GENERIC_EMOJI = "🎁";

const FE0F = /️/g;
const SKIPPED_GROUPS = new Set(["Component", "Flags", "Symbols"]);

// ---------- parsing and eligibility ----------

export interface EmojiTestEntry {
  codepoints: number[];
  emoji: string;
  group: string;
  subgroup: string;
}

/** Every fully-qualified entry of emoji-test.txt, in CLDR order, with its group and subgroup. */
export function parseEmojiTest(text: string): EmojiTestEntry[] {
  const entries: EmojiTestEntry[] = [];
  let group = "";
  let subgroup = "";
  for (const line of text.split("\n")) {
    if (line.startsWith("# group:")) group = line.slice("# group:".length).trim();
    else if (line.startsWith("# subgroup:")) subgroup = line.slice("# subgroup:".length).trim();
    else if (line.includes("; fully-qualified")) {
      const codepoints = line
        .split(";")[0]
        .trim()
        .split(/\s+/)
        .map((hex) => parseInt(hex, 16));
      entries.push({ codepoints, emoji: String.fromCodePoint(...codepoints), group, subgroup });
    }
  }
  return entries;
}

const isSkinTone = (codepoint: number) => codepoint >= 0x1f3fb && codepoint <= 0x1f3ff;
const BODY_CARE = new Set([0x1f486, 0x1f487, 0x1f9d6, 0x1f6c0, 0x1f9d8, 0x1f6cc, 0x1f476, 0x1f930]); // body care, rest, baby and maternity care
const SMILEYS_KEPT = new Set([0x1f48b, 0x1f48c, 0x1f49d, 0x2764, 0x1f495, 0x1f916]); // hearts, love letter, kiss mark and toy robot

/**
 * Whether an emoji can depict a gift: single-glyph (no ZWJ sequences, no skin tones), and not a flag, symbol or
 * component. Smileys keep hearts, a kiss and the robot toy. People keeps hands/body parts, body/baby/maternity
 * care and sporting/rest activities meaningful as experiences or equipment gifts. Other faces/people are omitted.
 */
export function isEligible(entry: Pick<EmojiTestEntry, "codepoints" | "group"> & { subgroup?: string }): boolean {
  const { codepoints, group } = entry;
  if (SKIPPED_GROUPS.has(group)) return false;
  if (codepoints.some((codepoint) => codepoint === 0x200d || isSkinTone(codepoint))) return false;
  if (group === "Smileys & Emotion") return codepoints.some((codepoint) => SMILEYS_KEPT.has(codepoint));
  if (group === "People & Body") {
    const [first] = codepoints;
    return (
      (first >= 0x1f440 && first <= 0x1f450) ||
      first === 0x1f485 ||
      first === 0x1f9b6 ||
      BODY_CARE.has(first) ||
      entry.subgroup === "person-sport"
    );
  }
  return true;
}

/** `e_` + lowercase hex codepoints, e.g. "e_1f381" for 🎁 and "e_2764_fe0f" for ❤️. Stable and ASCII. */
export const iconKey = (codepoints: number[]) => `e_${codepoints.map((c) => c.toString(16)).join("_")}`;

/** `animal-mammal` → `animal_mammal`, `sky & weather` → `sky_weather`. */
export const subgroupKey = (subgroup: string) => subgroup.replace(/[^a-z0-9]+/gi, "_").toLowerCase();

/** CLDR omits the variation selector in its annotation keys ("❤" not "❤️"), so fall back to the stripped form. */
const annotationFor = (table: Annotations, emoji: string): Annotation | undefined =>
  table[emoji] ?? table[emoji.replace(FE0F, "")];

function localized(table: Annotations, emoji: string, language: string): LocalizedName {
  const annotation = annotationFor(table, emoji);
  const tts = annotation?.tts?.[0];
  if (!tts || !annotation.default?.length) throw new Error(`no ${language} CLDR annotation for ${emoji}`);
  return { tts, keywords: [...annotation.default] };
}

// ---------- subgroup descriptions ----------

/** [includes, excludes, examples]. */
type Triplet = [string, string, string];
interface SubgroupNote {
  en: [string, string];
  ru: [string, string];
}

/**
 * Stage-1 text per Unicode subgroup, always "Includes; excludes; examples" in English then Russian. The generator
 * fails when a subgroup of the catalog has no note here (and when a note matches no subgroup), so a Unicode update
 * that adds a subgroup cannot slip through without a description.
 */
export const SUBGROUP_NOTES: Record<string, SubgroupNote> = {
  "face-costume": {
    en: ["robot toys and robots", "ordinary faces and emotions"],
    ru: ["игрушечные роботы и роботы", "обычные лица и эмоции"],
  },
  person: {
    en: ["baby and newborn care and baby supplies", "adult clothing, toys for older children"],
    ru: [
      "уход за младенцами и новорождёнными и детские принадлежности",
      "одежда для взрослых, игрушки для детей постарше",
    ],
  },
  "person-role": {
    en: ["maternity and pregnancy care", "ordinary adult clothing and medical equipment"],
    ru: ["подарки и уход для беременных", "обычная одежда и медицинское оборудование"],
  },
  "person-sport": {
    en: [
      "sporting activities and equipment represented by people doing sports",
      "balls, rackets and equipment with their own literal emoji, sports awards",
    ],
    ru: [
      "спортивные занятия и инвентарь, показанные людьми за спортом",
      "мячи, ракетки и инвентарь с собственным точным эмодзи, спортивные награды",
    ],
  },
  "person-activity": {
    en: [
      "body-care services and equipment for massage, hair care and sauna",
      "cosmetics and hygiene products, furniture, hands",
    ],
    ru: ["услуги и оборудование для массажа, ухода за волосами и сауны", "косметика и средства гигиены, мебель, руки"],
  },
  "person-resting": {
    en: ["bathing, yoga, rest and sleep-related gifts", "bathroom furniture and plumbing, soap and cosmetics"],
    ru: ["купание, йога, отдых и подарки для сна", "мебель и сантехника ванной, мыло и косметика"],
  },
  heart: {
    en: ["romantic hearts and love letters", "faces, kisses, feelings in general"],
    ru: ["романтические сердечки и любовные письма", "лица, поцелуи, эмоции вообще"],
  },
  emotion: {
    en: ["the kiss mark", "hearts, faces, hand gestures"],
    ru: ["след поцелуя", "сердечки, лица, жесты руками"],
  },
  "hand-fingers-open": {
    en: ["the waving hand", "other gestures, applause, people"],
    ru: ["машущая рука", "другие жесты, аплодисменты, люди"],
  },
  "hand-fingers-partial": {
    en: ["the OK hand gesture", "other gestures, thumbs up, pointing"],
    ru: ["жест «окей»", "другие жесты, большой палец, указывающие руки"],
  },
  "hand-single-finger": {
    en: ["pointing hands (up, down, left, right)", "thumbs, fists, open hands"],
    ru: ["указывающие руки (вверх, вниз, влево, вправо)", "большие пальцы, кулаки, открытые ладони"],
  },
  "hand-fingers-closed": {
    en: ["thumbs up, thumbs down, the fist", "open hands, pointing, applause"],
    ru: ["большой палец вверх и вниз, кулак", "открытые ладони, указывающие руки, аплодисменты"],
  },
  hands: {
    en: ["clapping hands and open hands", "single-hand gestures, handshakes with people"],
    ru: ["хлопающие руки и раскрытые ладони", "жесты одной рукой, люди"],
  },
  "hand-prop": {
    en: ["nail polish and manicure", "lipstick, perfume, lotions, hair care"],
    ru: ["лак для ногтей и маникюр", "помада, духи, кремы, уход за волосами"],
  },
  "body-parts": {
    en: ["eyes, ears, nose, mouth, tongue, foot", "teeth and medicine, people, faces"],
    ru: ["глаза, уши, нос, рот, язык, ступня", "зубы и медицина, люди, лица"],
  },
  "animal-mammal": {
    en: ["pets, farm and wild mammals", "birds, fish, insects, reptiles, toys shaped as animals, pet food"],
    ru: [
      "домашние, сельскохозяйственные и дикие млекопитающие",
      "птицы, рыбы, насекомые, рептилии, игрушки-животные, корм для животных",
    ],
  },
  "animal-bird": {
    en: ["birds and poultry", "mammals, insects, eggs and chicken meat as food"],
    ru: ["птицы и домашняя птица", "млекопитающие, насекомые, яйца и мясо птицы как еда"],
  },
  "animal-amphibian": {
    en: ["the frog", "reptiles, fish, other animals"],
    ru: ["лягушка", "рептилии, рыбы, другие животные"],
  },
  "animal-reptile": {
    en: ["reptiles, dinosaurs and dragons", "mammals, fish, amphibians"],
    ru: ["рептилии, динозавры и драконы", "млекопитающие, рыбы, амфибии"],
  },
  "animal-marine": {
    en: [
      "sea animals, fish and seafood, whether living or edible",
      "boats, land mammals, meat and dishes without seafood",
    ],
    ru: [
      "морские животные, рыба и морепродукты, живые или съедобные",
      "лодки, сухопутные млекопитающие, мясо и блюда без морепродуктов",
    ],
  },
  "animal-bug": {
    en: ["insects, spiders and small crawling animals", "birds, reptiles, flowers"],
    ru: ["насекомые, пауки и мелкие ползающие животные", "птицы, рептилии, цветы"],
  },
  "plant-flower": {
    en: ["flowers and bouquets", "trees, houseplants, herbs, leaves, flower-shaped decorations"],
    ru: ["цветы и букеты", "деревья, комнатные растения, травы, листья, украшения в форме цветов"],
  },
  "plant-other": {
    en: ["trees, houseplants, cacti, seedlings, leaves, mushrooms, herbs", "flowers, vegetables, the Christmas tree"],
    ru: ["деревья, комнатные растения, кактусы, рассада, листья, грибы, травы", "цветы, овощи, новогодняя ёлка"],
  },
  "food-fruit": {
    en: ["fruit and berries, also tomato, olive and coconut", "vegetables, juice and fruit drinks, sweets with fruit"],
    ru: ["фрукты и ягоды, а также помидор, оливка и кокос", "овощи, соки и напитки, сладости с фруктами"],
  },
  "food-vegetable": {
    en: ["vegetables, legumes, nuts, garlic and ginger", "fruit, cooked dishes, mushrooms, houseplants"],
    ru: ["овощи, бобовые, орехи, чеснок и имбирь", "фрукты, готовые блюда, грибы, комнатные растения"],
  },
  "food-prepared": {
    en: [
      "bread, pastries, cheese, meat, eggs, pancakes, cooked savory dishes, fast food",
      "sweets and desserts, rice and noodle dishes, seafood, raw produce, drinks",
    ],
    ru: [
      "хлеб, выпечка, сыр, мясо, яйца, блины, готовые солёные блюда, фастфуд",
      "сладости и десерты, рис и лапша, морепродукты, сырые продукты, напитки",
    ],
  },
  "food-asian": {
    en: [
      "rice dishes, noodles and pasta, dumplings, takeout, moon cakes and fortune cookies",
      "bread, meat cuts, candy, drinks and chopsticks",
    ],
    ru: [
      "блюда из риса, лапша и паста, пельмени, еда навынос, лунные пряники и печенье с предсказанием",
      "хлеб, мясная нарезка, конфеты, напитки и палочки для еды",
    ],
  },
  "food-sweet": {
    en: ["cakes, pastries, ice cream, chocolate, candy, cookies, honey", "savory food, fruit, drinks, bread"],
    ru: ["торты, выпечка, мороженое, шоколад, конфеты, печенье, мёд", "солёная еда, фрукты, напитки, хлеб"],
  },
  drink: {
    en: [
      "coffee, tea, wine, beer, spirits, juice, milk, ice and other drinks and their glasses",
      "food, tableware, water in nature",
    ],
    ru: [
      "кофе, чай, вино, пиво, крепкий алкоголь, сок, молоко, лёд и другие напитки и бокалы",
      "еда, посуда, вода в природе",
    ],
  },
  dishware: {
    en: ["tableware, cutlery, jars and kitchen knives", "food and drinks themselves, household appliances"],
    ru: ["посуда, столовые приборы, банки и кухонные ножи", "сама еда и напитки, бытовая техника"],
  },
  "place-map": {
    en: ["globes, world maps and compasses", "mountains, beaches, buildings, vehicles"],
    ru: ["глобусы, карты мира и компасы", "горы, пляжи, здания, транспорт"],
  },
  "place-geographic": {
    en: ["landscapes: mountains, volcano, beach, desert, island, national park", "buildings, weather, vehicles, trees"],
    ru: ["ландшафты: горы, вулкан, пляж, пустыня, остров, национальный парк", "здания, погода, транспорт, деревья"],
  },
  "place-building": {
    en: [
      "houses, offices, shops, schools, hospitals, banks, hotels, castles, stadiums, landmarks, wedding venues",
      "places of worship, vehicles, landscapes, amusement parks",
    ],
    ru: [
      "дома, офисы, магазины, школы, больницы, банки, отели, замки, стадионы, достопримечательности, места свадеб",
      "места богослужений, транспорт, ландшафты, парки развлечений",
    ],
  },
  "place-religious": {
    en: ["places of worship", "ordinary buildings, religious symbols"],
    ru: ["места богослужений", "обычные здания, религиозные символы"],
  },
  "place-other": {
    en: [
      "fairground, tents, fountains, bridges, cityscapes, night and sunrise views",
      "buildings, vehicles, landscapes, weather",
    ],
    ru: [
      "парк аттракционов, палатки, фонтаны, мосты, городские пейзажи, ночь и рассвет",
      "здания, транспорт, ландшафты, погода",
    ],
  },
  "transport-ground": {
    en: [
      "cars, buses, trains, trams, bikes, scooters, trucks, skateboards, wheelchairs, traffic signs, fuel",
      "aircraft, ships, cable cars, buildings, toys",
    ],
    ru: [
      "машины, автобусы, поезда, трамваи, велосипеды, самокаты, грузовики, скейтборды, инвалидные коляски, дорожные знаки, топливо",
      "самолёты, корабли, канатные дороги, здания, игрушки",
    ],
  },
  "transport-water": {
    en: ["ships, boats and anchors", "cars, aircraft, sea animals, beaches"],
    ru: ["корабли, лодки и якоря", "машины, самолёты, морские животные, пляжи"],
  },
  "transport-air": {
    en: ["aircraft, rockets, parachutes, cable cars and satellites", "cars, ships, space as scenery, stars"],
    ru: ["самолёты, ракеты, парашюты, канатные дороги и спутники", "машины, корабли, космос как пейзаж, звёзды"],
  },
  hotel: {
    en: ["hotel services and luggage", "hotel buildings, beds, vehicles"],
    ru: ["гостиничные услуги и багаж", "здания отелей, кровати, транспорт"],
  },
  time: {
    en: ["clocks, watches, timers and the hourglass", "calendars, schedules, tickets"],
    ru: ["часы, таймеры и песочные часы", "календари, расписания, билеты"],
  },
  "sky & weather": {
    en: [
      "sun, moon, stars, planets, clouds, rain, snow, rainbow, umbrella, fire, water drops, waves",
      "landscapes, buildings, vehicles, Christmas decorations",
    ],
    ru: [
      "солнце, луна, звёзды, планеты, облака, дождь, снег, радуга, зонт, огонь, капли воды, волны",
      "ландшафты, здания, транспорт, новогодние украшения",
    ],
  },
  event: {
    en: [
      "celebrations, gifts, balloons, fireworks, tickets, holiday decorations and festive items",
      "sports and game prizes, music, tableware, cakes",
    ],
    ru: [
      "праздники, подарки, шарики, фейерверки, билеты, праздничные украшения и атрибуты",
      "спортивные призы, музыка, посуда, торты",
    ],
  },
  "award-medal": {
    en: ["trophies, medals and prizes", "tickets, party items, sports equipment"],
    ru: ["кубки, медали и призы", "билеты, праздничные атрибуты, спортивный инвентарь"],
  },
  sport: {
    en: [
      "sports balls and equipment, fitness, fishing, skiing, skating, martial arts, diving, golf",
      "video games, board games, prizes, sports venues",
    ],
    ru: [
      "спортивные мячи и инвентарь, фитнес, рыбалка, лыжи, коньки, единоборства, дайвинг, гольф",
      "видеоигры, настольные игры, призы, спортивные сооружения",
    ],
  },
  game: {
    en: [
      "video games, board games, cards, puzzles, toys, darts, billiards, kites, magic",
      "sports equipment, prizes, party items, musical instruments",
    ],
    ru: [
      "видеоигры, настольные игры, карты, пазлы, игрушки, дартс, бильярд, воздушные змеи, магия",
      "спортивный инвентарь, призы, праздничные атрибуты, музыкальные инструменты",
    ],
  },
  "arts & crafts": {
    en: ["painting, theatre, sewing and knitting supplies", "writing tools, books, musical instruments, clothing"],
    ru: [
      "живопись, театр, принадлежности для шитья и вязания",
      "письменные принадлежности, книги, музыкальные инструменты, одежда",
    ],
  },
  clothing: {
    en: [
      "clothes, shoes, hats, bags, glasses, jewelry, lipstick, crown, ring, gem stone",
      "sports equipment, tools, household items, toys",
    ],
    ru: [
      "одежда, обувь, шапки, сумки, очки, украшения, помада, корона, кольцо, драгоценный камень",
      "спортивный инвентарь, инструменты, предметы быта, игрушки",
    ],
  },
  sound: {
    en: ["speakers, bells, megaphones and alarms", "headphones, microphones, instruments, phones"],
    ru: ["колонки, колокольчики, мегафоны и сигналы", "наушники, микрофоны, инструменты, телефоны"],
  },
  music: {
    en: [
      "music notes, microphones, headphones, radio and studio equipment",
      "musical instruments, speakers, concerts and tickets",
    ],
    ru: [
      "ноты, микрофоны, наушники, радио и студийное оборудование",
      "музыкальные инструменты, колонки, концерты и билеты",
    ],
  },
  "musical-instrument": {
    en: ["musical instruments", "music notes, headphones, microphones, speakers"],
    ru: ["музыкальные инструменты", "ноты, наушники, микрофоны, колонки"],
  },
  phone: {
    en: ["mobile phones, landlines and pagers", "computers, cameras, headphones"],
    ru: ["мобильные телефоны, стационарные телефоны и пейджеры", "компьютеры, камеры, наушники"],
  },
  computer: {
    en: [
      "laptops, desktops, printers, keyboards, mice, storage media, batteries, plugs, the abacus",
      "phones, cameras, TVs, game consoles, office supplies",
    ],
    ru: [
      "ноутбуки, компьютеры, принтеры, клавиатуры, мыши, носители данных, батарейки, вилки, счёты",
      "телефоны, камеры, телевизоры, игровые консоли, канцелярия",
    ],
  },
  "light & video": {
    en: [
      "cameras, film, video, TV, light bulbs, candles, lamps and lanterns",
      "phones, computers, music equipment, fire and weather",
    ],
    ru: [
      "фотоаппараты, кино, видео, телевизоры, лампочки, свечи, лампы и фонари",
      "телефоны, компьютеры, музыкальное оборудование, огонь и погода",
    ],
  },
  "book-paper": {
    en: [
      "books, notebooks, newspapers, bookmarks, scrolls, labels and paper",
      "writing tools, mail, office supplies, money",
    ],
    ru: [
      "книги, блокноты, газеты, закладки, свитки, ярлыки и бумага",
      "письменные принадлежности, почта, канцелярия, деньги",
    ],
  },
  money: {
    en: [
      "cash, coins, credit cards, receipts and money bags",
      "gem stones and jewelry, gift boxes, bank buildings, office supplies",
    ],
    ru: [
      "наличные, монеты, кредитные карты, чеки и мешки денег",
      "драгоценные камни и украшения, подарочные коробки, здания банков, канцелярия",
    ],
  },
  mail: {
    en: [
      "envelopes, packages, mailboxes, postboxes and ballot boxes",
      "love letters, books, paper documents, gift boxes",
    ],
    ru: [
      "конверты, посылки, почтовые ящики и урны для голосования",
      "любовные письма, книги, бумажные документы, подарочные коробки",
    ],
  },
  writing: {
    en: ["pens, pencils, brushes, crayons and notes", "books, paper, office supplies, art supplies for painting"],
    ru: ["ручки, карандаши, кисти, мелки и заметки", "книги, бумага, канцелярия, принадлежности для живописи"],
  },
  office: {
    en: [
      "briefcases, folders, calendars, clipboards, paper clips, scissors, rulers and charts",
      "books, writing tools, computers, money",
    ],
    ru: [
      "портфели, папки, календари, планшеты, скрепки, ножницы, линейки и диаграммы",
      "книги, письменные принадлежности, компьютеры, деньги",
    ],
  },
  lock: {
    en: ["locks and keys", "tools, security guards, computers"],
    ru: ["замки и ключи", "инструменты, охрана, компьютеры"],
  },
  tool: {
    en: [
      "hand and power tools, hardware, weapons (dagger, swords, bow, bomb), shields, magnets, ladders, chains, scales",
      "household items, medical items, science equipment, sports equipment",
    ],
    ru: [
      "ручные и электрические инструменты, крепёж, оружие (кинжал, мечи, лук, бомба), щиты, магниты, лестницы, цепи, весы",
      "предметы быта, медицинские предметы, научное оборудование, спортивный инвентарь",
    ],
  },
  science: {
    en: [
      "laboratory equipment, telescopes, microscopes, DNA and atoms",
      "medical items, tools, computers, space vehicles",
    ],
    ru: [
      "лабораторное оборудование, телескопы, микроскопы, ДНК и атомы",
      "медицинские предметы, инструменты, компьютеры, космический транспорт",
    ],
  },
  medical: {
    en: ["medicine and first aid", "science equipment, body parts, household items"],
    ru: ["лекарства и первая помощь", "научное оборудование, части тела, предметы быта"],
  },
  household: {
    en: [
      "furniture, doors, windows, bathroom, cleaning, kitchen supplies and personal care items",
      "tableware, clothing, tools, electronics, toys",
    ],
    ru: [
      "мебель, двери, окна, ванная, уборка, кухонные принадлежности и средства личной гигиены",
      "посуда, одежда, инструменты, электроника, игрушки",
    ],
  },
  "other-object": {
    en: [
      "cigarettes, amulets, statues, memorial objects, placards and ID cards",
      "tools, household items, jewelry, religious buildings",
    ],
    ru: [
      "сигареты, амулеты, статуи, мемориальные предметы, таблички и удостоверения",
      "инструменты, предметы быта, украшения, религиозные здания",
    ],
  },
};

const noteText = (parts: Triplet, labels: Triplet) =>
  `${labels[0]} ${parts[0]}; ${labels[1]} ${parts[1]}; ${labels[2]} ${parts[2]}`;

/** One line, uniform: "Includes: …; excludes: …; examples: … | Включает: …; не включает: …; примеры: …". */
export function describeSubgroup(subgroup: string, icons: CatalogIcon[]): string {
  const note = SUBGROUP_NOTES[subgroup];
  if (!note) throw new Error(`no description for subgroup "${subgroup}"; add it to SUBGROUP_NOTES`);
  const en: Triplet = [note.en[0], note.en[1], icons.map((icon) => icon.en.tts).join(", ")];
  const ru: Triplet = [note.ru[0], note.ru[1], icons.map((icon) => icon.ru.tts).join(", ")];
  return `${noteText(en, ["Includes:", "excludes:", "examples:"])} | ${noteText(ru, ["Включает:", "не включает:", "примеры:"])}`;
}

// ---------- building ----------

/** SHA-256 with the platform Web Crypto implementation (Node and Worker test runtime). */
export async function sha256(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** First 12 hex digits of the SHA-256 of the catalog content (icons and subgroup descriptions), `cldr-` prefixed. */
export async function catalogVersion(
  icons: Record<string, CatalogIcon>,
  subgroups: Record<string, CatalogSubgroup>,
): Promise<string> {
  return `cldr-${(await sha256(JSON.stringify({ icons, subgroups }))).slice(0, 12)}`;
}

/** The catalog, deterministic in its inputs. Includes `none` (🎁) first, outside every subgroup. */
export async function buildCatalog(sources: Sources): Promise<Catalog> {
  const icons: Record<string, CatalogIcon> = {
    [GENERIC_KEY]: {
      emoji: GENERIC_EMOJI,
      group: "",
      subgroup: "",
      en: { tts: "generic gift", keywords: ["gift", "present", "unclear", "none of the others"] },
      ru: { tts: "подарок", keywords: ["подарок", "неясно", "ничего из остального"] },
    },
  };
  const subgroups: Record<string, CatalogSubgroup> = {};
  for (const entry of parseEmojiTest(sources.emojiTest)) {
    if (!isEligible(entry)) continue;
    const key = iconKey(entry.codepoints);
    if (icons[key]) throw new Error(`duplicate icon key ${key}`);
    icons[key] = {
      emoji: entry.emoji,
      group: entry.group,
      subgroup: entry.subgroup,
      en: localized(sources.en, entry.emoji, "English"),
      ru: localized(sources.ru, entry.emoji, "Russian"),
    };
    const id = subgroupKey(entry.subgroup);
    (subgroups[id] ??= {
      group: entry.group,
      subgroup: entry.subgroup,
      keys: [],
      description: "",
    }).keys.push(key);
  }
  for (const subgroup of Object.values(subgroups))
    subgroup.description = describeSubgroup(
      subgroup.subgroup,
      subgroup.keys.map((key) => icons[key]),
    );
  const unused = Object.keys(SUBGROUP_NOTES).filter((name) => !subgroups[subgroupKey(name)]);
  if (unused.length) throw new Error(`SUBGROUP_NOTES has entries for no subgroup: ${unused.join(", ")}`);
  for (const [id, subgroup] of Object.entries(subgroups)) {
    if (subgroup.keys.length + 1 > MAX_CHOICE_OPTIONS)
      throw new Error(`subgroup ${id} has too many icons for one Choice question`);
  }
  if (Object.keys(subgroups).length + 1 > MAX_CHOICE_OPTIONS)
    throw new Error("too many subgroups for one Choice question");
  return { version: await catalogVersion(icons, subgroups), icons, subgroups };
}

// ---------- rendering ----------

/** JSON with the variation selector escaped, so the invisible FE0F survives editors and reviews. */
const literal = (value: unknown) => JSON.stringify(value).replace(/️/g, "\\uFE0F");

const MODULE_TEMPLATE_HEAD = `// Generated by scripts/build-cldr-catalog.ts from eval/data/{emoji-test.txt,cldr-en.json,cldr-ru.json}. Do not edit
// by hand: run \`node --experimental-strip-types scripts/build-cldr-catalog.ts\` in icon-worker/ (add --check to verify).
//
// Gift-relevant single emoji (no flags, symbols, skin tones or ZWJ sequences; Smileys keep hearts, a kiss and a toy robot,
// People & Body keeps hands, body/baby/maternity care and sporting/rest activities) with Unicode group/subgroup and CLDR English and Russian names.
// Stage 1 of the two-stage picker chooses a subgroup, stage 2 an emoji inside it; both options lists stay within
// Jev's 255-option limit. \`CATALOG_VERSION\` is a hash of the content, so cached answers never outlive a change.

export interface CatalogName {
  tts: string;
  keywords: string[];
}

export interface CatalogIcon {
  /** Fully-qualified emoji, variation selectors kept. */
  emoji: string;
  group: string;
  subgroup: string;
  en: CatalogName;
  ru: CatalogName;
}

export interface CatalogSubgroup {
  group: string;
  subgroup: string;
  keys: string[];
  description: string;
}

/** The option meaning "no icon here depicts the gift"; its emoji is 🎁 for compatibility with the flat catalog. */
export const GENERIC_KEY = ${literal(GENERIC_KEY)};
`;

const MODULE_TEMPLATE_TAIL = `
/** "wrapped gift: birthday, bow, … | подарок: день рождения, …"; \`maxKeywords\` trims each language's list. */
export function describeIcon(icon: CatalogIcon, maxKeywords = Infinity): string {
  const part = (name: CatalogName) => [name.tts, ...name.keywords.slice(0, maxKeywords)].filter((word, i, all) => all.indexOf(word) === i);
  const [en, ru] = [part(icon.en), part(icon.ru)];
  return \`\${en[0]}\${en.length > 1 ? \`: \${en.slice(1).join(", ")}\` : ""} | \${ru[0]}\${ru.length > 1 ? \`: \${ru.slice(1).join(", ")}\` : ""}\`;
}


`;

/** The full text of src/cldr-catalog.ts. */
export function renderModule(catalog: Catalog): string {
  const lines = [MODULE_TEMPLATE_HEAD];
  lines.push(`export const CATALOG_VERSION = ${literal(catalog.version)};`, "");
  lines.push("export const ICONS: Record<string, CatalogIcon> = {");
  for (const [key, icon] of Object.entries(catalog.icons)) lines.push(`  ${key}: ${literal(icon)},`);
  lines.push(
    "};",
    "",
    "/** Unicode subgroups (key = lowercase slug), each with its icons and the stage-1 description. */",
  );
  lines.push("export const SUBGROUPS: Record<string, CatalogSubgroup> = {");
  for (const [id, subgroup] of Object.entries(catalog.subgroups)) lines.push(`  ${id}: ${literal(subgroup)},`);
  lines.push("};");
  return lines.join("\n") + "\n" + MODULE_TEMPLATE_TAIL;
}

/** Everything from the raw source files to the module text. */
export async function generateModule(sources: Sources): Promise<string> {
  return renderModule(await buildCatalog(sources));
}

// ---------- command line ----------

async function main() {
  // Node-only imports stay inside main so the pure part above also loads in the Worker test runtime.
  // @ts-ignore -- icon-worker has no Node type definitions
  const { readFileSync, writeFileSync } = await import("node:fs");
  const data = (name: string) => new URL(`../eval/data/${name}`, import.meta.url);
  const annotations = (name: string): Annotations =>
    JSON.parse(readFileSync(data(name), "utf8")).annotations.annotations;
  const output = await generateModule({
    emojiTest: readFileSync(data("emoji-test.txt"), "utf8"),
    en: annotations("cldr-en.json"),
    ru: annotations("cldr-ru.json"),
  });
  const target = new URL("../src/cldr-catalog.ts", import.meta.url);
  // @ts-ignore -- no Node type definitions
  const check = (globalThis.process?.argv ?? []).includes("--check");
  if (check) {
    if (readFileSync(target, "utf8") !== output) {
      console.error("src/cldr-catalog.ts is stale; run: node --experimental-strip-types scripts/build-cldr-catalog.ts");
      // @ts-ignore -- no Node type definitions
      globalThis.process.exit(1);
    }
    console.log("src/cldr-catalog.ts is up to date");
    return;
  }
  writeFileSync(target, output);
  console.log(`wrote src/cldr-catalog.ts (${output.length} characters)`);
}

if ((import.meta as { main?: boolean }).main) await main();
