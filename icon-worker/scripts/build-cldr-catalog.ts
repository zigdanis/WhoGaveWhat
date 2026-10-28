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
const SMILEYS_KEPT = new Set([0x1f48b, 0x1f48c, 0x1f49d, 0x2764, 0x1f495]); // kiss mark, love letter, gift heart, heart, two hearts

/**
 * Whether an emoji can depict a gift: single-glyph (no ZWJ sequences, no skin tones), and not a flag, symbol or
 * component. Smileys keep only the hearts and the kiss; People & Body keeps hands, eyes and other body parts and
 * the nail polish, never people. Same rules as the benchmark's loadEmojiGroups.
 */
export function isEligible(entry: Pick<EmojiTestEntry, "codepoints" | "group">): boolean {
  const { codepoints, group } = entry;
  if (SKIPPED_GROUPS.has(group)) return false;
  if (codepoints.some((codepoint) => codepoint === 0x200d || isSkinTone(codepoint))) return false;
  if (group === "Smileys & Emotion") return codepoints.some((codepoint) => SMILEYS_KEPT.has(codepoint));
  if (group === "People & Body") {
    const [first] = codepoints;
    return (first >= 0x1f440 && first <= 0x1f450) || first === 0x1f485 || first === 0x1f9b6;
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
  en: Triplet;
  ru: Triplet;
}

/**
 * Stage-1 text per Unicode subgroup, always "Includes; excludes; examples" in English then Russian. The generator
 * fails when a subgroup of the catalog has no note here (and when a note matches no subgroup), so a Unicode update
 * that adds a subgroup cannot slip through without a description.
 */
export const SUBGROUP_NOTES: Record<string, SubgroupNote> = {
  heart: {
    en: [
      "romantic hearts and love letters",
      "faces, kisses, feelings in general",
      "heart, love letter, heart with ribbon, two hearts",
    ],
    ru: [
      "романтические сердечки и любовные письма",
      "лица, поцелуи, эмоции вообще",
      "сердце, любовное письмо, сердце с лентой, два сердца",
    ],
  },
  emotion: {
    en: ["the kiss mark", "hearts, faces, hand gestures", "kiss mark, lipstick kiss"],
    ru: ["след поцелуя", "сердечки, лица, жесты руками", "след поцелуя, поцелуй помадой"],
  },
  "hand-fingers-open": {
    en: ["the waving hand", "other gestures, applause, people", "waving hand, hello, goodbye"],
    ru: ["машущая рука", "другие жесты, аплодисменты, люди", "машущая рука, привет, пока"],
  },
  "hand-fingers-partial": {
    en: ["the OK hand gesture", "other gestures, thumbs up, pointing", "OK hand, perfect, approval"],
    ru: ["жест «окей»", "другие жесты, большой палец, указывающие руки", "жест окей, отлично, одобрение"],
  },
  "hand-single-finger": {
    en: [
      "pointing hands (up, down, left, right)",
      "thumbs, fists, open hands",
      "pointing up, pointing right, this one",
    ],
    ru: [
      "указывающие руки (вверх, вниз, влево, вправо)",
      "большие пальцы, кулаки, открытые ладони",
      "указывающий палец вверх, вправо, вот этот",
    ],
  },
  "hand-fingers-closed": {
    en: [
      "thumbs up, thumbs down, the fist",
      "open hands, pointing, applause",
      "thumbs up, like, thumbs down, fist bump",
    ],
    ru: [
      "большой палец вверх и вниз, кулак",
      "открытые ладони, указывающие руки, аплодисменты",
      "лайк, дизлайк, кулак, удар кулаком",
    ],
  },
  hands: {
    en: [
      "clapping hands and open hands",
      "single-hand gestures, handshakes with people",
      "clapping, applause, open hands, praise",
    ],
    ru: [
      "хлопающие руки и раскрытые ладони",
      "жесты одной рукой, люди",
      "аплодисменты, хлопки, раскрытые ладони, похвала",
    ],
  },
  "hand-prop": {
    en: ["nail polish and manicure", "lipstick, perfume, lotions, hair care", "nail polish, manicure, nails"],
    ru: ["лак для ногтей и маникюр", "помада, духи, кремы, уход за волосами", "лак для ногтей, маникюр, ногти"],
  },
  "body-parts": {
    en: [
      "eyes, ears, nose, mouth, tongue, foot",
      "teeth and medicine, people, faces",
      "eyes, ear, nose, mouth, tongue, foot",
    ],
    ru: ["глаза, уши, нос, рот, язык, ступня", "зубы и медицина, люди, лица", "глаза, ухо, нос, рот, язык, ступня"],
  },
  "animal-mammal": {
    en: [
      "pets, farm and wild mammals",
      "birds, fish, insects, reptiles, toys shaped as animals, pet food",
      "dog, cat, horse, cow, bear, rabbit, mouse",
    ],
    ru: [
      "домашние, сельскохозяйственные и дикие млекопитающие",
      "птицы, рыбы, насекомые, рептилии, игрушки-животные, корм для животных",
      "собака, кошка, лошадь, корова, медведь, кролик, мышь",
    ],
  },
  "animal-bird": {
    en: [
      "birds and poultry",
      "mammals, insects, eggs and chicken meat as food",
      "chicken, owl, parrot, peacock, swan, dove",
    ],
    ru: [
      "птицы и домашняя птица",
      "млекопитающие, насекомые, яйца и мясо птицы как еда",
      "курица, сова, попугай, павлин, лебедь, голубь",
    ],
  },
  "animal-amphibian": {
    en: ["the frog", "reptiles, fish, other animals", "frog, toad"],
    ru: ["лягушка", "рептилии, рыбы, другие животные", "лягушка, жаба"],
  },
  "animal-reptile": {
    en: [
      "reptiles, dinosaurs and dragons",
      "mammals, fish, amphibians",
      "turtle, snake, lizard, crocodile, dinosaur, dragon",
    ],
    ru: [
      "рептилии, динозавры и драконы",
      "млекопитающие, рыбы, амфибии",
      "черепаха, змея, ящерица, крокодил, динозавр, дракон",
    ],
  },
  "animal-marine": {
    en: [
      "sea animals, fish and seafood, whether living or edible",
      "boats, land mammals, meat and dishes without seafood",
      "fish, whale, dolphin, shark, octopus, crab, shrimp, lobster, oyster, shell",
    ],
    ru: [
      "морские животные, рыба и морепродукты, живые или съедобные",
      "лодки, сухопутные млекопитающие, мясо и блюда без морепродуктов",
      "рыба, кит, дельфин, акула, осьминог, краб, креветка, омар, устрица, ракушка",
    ],
  },
  "animal-bug": {
    en: [
      "insects, spiders and small crawling animals",
      "birds, reptiles, flowers",
      "butterfly, bee, ladybug, ant, spider, snail",
    ],
    ru: [
      "насекомые, пауки и мелкие ползающие животные",
      "птицы, рептилии, цветы",
      "бабочка, пчела, божья коровка, муравей, паук, улитка",
    ],
  },
  "plant-flower": {
    en: [
      "flowers and bouquets",
      "trees, houseplants, herbs, leaves, flower-shaped decorations",
      "bouquet, rose, tulip, sunflower, cherry blossom, hibiscus",
    ],
    ru: [
      "цветы и букеты",
      "деревья, комнатные растения, травы, листья, украшения в форме цветов",
      "букет, роза, тюльпан, подсолнух, сакура, гибискус",
    ],
  },
  "plant-other": {
    en: [
      "trees, houseplants, cacti, seedlings, leaves, mushrooms, herbs",
      "flowers, vegetables, the Christmas tree",
      "tree, cactus, potted plant, seedling, four-leaf clover, mushroom",
    ],
    ru: [
      "деревья, комнатные растения, кактусы, рассада, листья, грибы, травы",
      "цветы, овощи, новогодняя ёлка",
      "дерево, кактус, растение в горшке, росток, клевер, гриб",
    ],
  },
  "food-fruit": {
    en: [
      "fruit and berries, also tomato, olive and coconut",
      "vegetables, juice and fruit drinks, sweets with fruit",
      "apple, banana, grapes, strawberry, orange, watermelon, cherries",
    ],
    ru: [
      "фрукты и ягоды, а также помидор, оливка и кокос",
      "овощи, соки и напитки, сладости с фруктами",
      "яблоко, банан, виноград, клубника, апельсин, арбуз, вишня",
    ],
  },
  "food-vegetable": {
    en: [
      "vegetables, legumes, nuts, garlic and ginger",
      "fruit, cooked dishes, mushrooms, houseplants",
      "avocado, potato, carrot, corn, hot pepper, cucumber, garlic, peanuts",
    ],
    ru: [
      "овощи, бобовые, орехи, чеснок и имбирь",
      "фрукты, готовые блюда, грибы, комнатные растения",
      "авокадо, картофель, морковь, кукуруза, острый перец, огурец, чеснок, арахис",
    ],
  },
  "food-prepared": {
    en: [
      "bread, pastries, cheese, meat, eggs, pancakes, cooked savory dishes, fast food",
      "sweets and desserts, rice and noodle dishes, seafood, raw produce, drinks",
      "bread, croissant, cheese, meat, bacon, pizza, burger, fries, eggs, sandwich, popcorn",
    ],
    ru: [
      "хлеб, выпечка, сыр, мясо, яйца, блины, готовые солёные блюда, фастфуд",
      "сладости и десерты, рис и лапша, морепродукты, сырые продукты, напитки",
      "хлеб, круассан, сыр, мясо, бекон, пицца, бургер, картошка фри, яйца, сэндвич, попкорн",
    ],
  },
  "food-asian": {
    en: [
      "rice dishes, noodles and pasta, dumplings, takeout, moon cakes and fortune cookies",
      "bread, meat cuts, candy, drinks and chopsticks",
      "sushi, dumpling, bento box, rice, curry rice, spaghetti, fortune cookie, takeout box",
    ],
    ru: [
      "блюда из риса, лапша и паста, пельмени, еда навынос, лунные пряники и печенье с предсказанием",
      "хлеб, мясная нарезка, конфеты, напитки и палочки для еды",
      "суши, пельмень, бенто, рис, карри с рисом, спагетти, печенье с предсказанием, коробка навынос",
    ],
  },
  "food-sweet": {
    en: [
      "cakes, pastries, ice cream, chocolate, candy, cookies, honey",
      "savory food, fruit, drinks, bread",
      "birthday cake, cupcake, ice cream, chocolate bar, candy, cookie, doughnut, honey",
    ],
    ru: [
      "торты, выпечка, мороженое, шоколад, конфеты, печенье, мёд",
      "солёная еда, фрукты, напитки, хлеб",
      "торт, капкейк, мороженое, шоколад, конфета, печенье, пончик, мёд",
    ],
  },
  drink: {
    en: [
      "coffee, tea, wine, beer, spirits, juice, milk, ice and other drinks and their glasses",
      "food, tableware, water in nature",
      "hot beverage, tea, wine glass, champagne, beer mug, cocktail, milk, bubble tea, mate",
    ],
    ru: [
      "кофе, чай, вино, пиво, крепкий алкоголь, сок, молоко, лёд и другие напитки и бокалы",
      "еда, посуда, вода в природе",
      "горячий напиток, чай, бокал вина, шампанское, пивная кружка, коктейль, молоко, бабл-ти, мате",
    ],
  },
  dishware: {
    en: [
      "tableware, cutlery, jars and kitchen knives",
      "food and drinks themselves, household appliances",
      "fork and knife, plate, spoon, chopsticks, jar, kitchen knife, amphora",
    ],
    ru: [
      "посуда, столовые приборы, банки и кухонные ножи",
      "сама еда и напитки, бытовая техника",
      "вилка и нож, тарелка, ложка, палочки, банка, кухонный нож, амфора",
    ],
  },
  "place-map": {
    en: [
      "globes, world maps and compasses",
      "mountains, beaches, buildings, vehicles",
      "globe, world map, compass, map of Japan",
    ],
    ru: ["глобусы, карты мира и компасы", "горы, пляжи, здания, транспорт", "глобус, карта мира, компас, карта Японии"],
  },
  "place-geographic": {
    en: [
      "landscapes: mountains, volcano, beach, desert, island, national park",
      "buildings, weather, vehicles, trees",
      "mountain, snow-capped mountain, volcano, camping, beach, desert, island",
    ],
    ru: [
      "ландшафты: горы, вулкан, пляж, пустыня, остров, национальный парк",
      "здания, погода, транспорт, деревья",
      "гора, заснеженная гора, вулкан, кемпинг, пляж, пустыня, остров",
    ],
  },
  "place-building": {
    en: [
      "houses, offices, shops, schools, hospitals, banks, hotels, castles, stadiums, landmarks, wedding venues",
      "places of worship, vehicles, landscapes, amusement parks",
      "house, office building, hospital, bank, hotel, school, castle, stadium, department store, wedding",
    ],
    ru: [
      "дома, офисы, магазины, школы, больницы, банки, отели, замки, стадионы, достопримечательности, места свадеб",
      "места богослужений, транспорт, ландшафты, парки развлечений",
      "дом, офис, больница, банк, отель, школа, замок, стадион, универмаг, свадьба",
    ],
  },
  "place-religious": {
    en: [
      "places of worship",
      "ordinary buildings, religious symbols",
      "church, mosque, synagogue, Shinto shrine, Kaaba, hindu temple",
    ],
    ru: [
      "места богослужений",
      "обычные здания, религиозные символы",
      "церковь, мечеть, синагога, синтоистское святилище, Кааба, индуистский храм",
    ],
  },
  "place-other": {
    en: [
      "fairground, tents, fountains, bridges, cityscapes, night and sunrise views",
      "buildings, vehicles, landscapes, weather",
      "tent, fountain, Ferris wheel, roller coaster, carousel, circus tent, cityscape",
    ],
    ru: [
      "парк аттракционов, палатки, фонтаны, мосты, городские пейзажи, ночь и рассвет",
      "здания, транспорт, ландшафты, погода",
      "палатка, фонтан, колесо обозрения, американские горки, карусель, цирк, город",
    ],
  },
  "transport-ground": {
    en: [
      "cars, buses, trains, trams, bikes, scooters, trucks, skateboards, wheelchairs, traffic signs, fuel",
      "aircraft, ships, cable cars, buildings, toys",
      "car, taxi, bus, train, bicycle, motorcycle, scooter, truck, skateboard, wheelchair, fuel pump",
    ],
    ru: [
      "машины, автобусы, поезда, трамваи, велосипеды, самокаты, грузовики, скейтборды, инвалидные коляски, дорожные знаки, топливо",
      "самолёты, корабли, канатные дороги, здания, игрушки",
      "машина, такси, автобус, поезд, велосипед, мотоцикл, самокат, грузовик, скейтборд, инвалидная коляска, заправка",
    ],
  },
  "transport-water": {
    en: [
      "ships, boats and anchors",
      "cars, aircraft, sea animals, beaches",
      "ship, sailboat, speedboat, canoe, ferry, anchor, ring buoy",
    ],
    ru: [
      "корабли, лодки и якоря",
      "машины, самолёты, морские животные, пляжи",
      "корабль, парусник, катер, каноэ, паром, якорь, спасательный круг",
    ],
  },
  "transport-air": {
    en: [
      "aircraft, rockets, parachutes, cable cars and satellites",
      "cars, ships, space as scenery, stars",
      "airplane, helicopter, rocket, flying saucer, parachute, satellite, cableway",
    ],
    ru: [
      "самолёты, ракеты, парашюты, канатные дороги и спутники",
      "машины, корабли, космос как пейзаж, звёзды",
      "самолёт, вертолёт, ракета, летающая тарелка, парашют, спутник, канатная дорога",
    ],
  },
  hotel: {
    en: ["hotel services and luggage", "hotel buildings, beds, vehicles", "bellhop bell, luggage, suitcase"],
    ru: ["гостиничные услуги и багаж", "здания отелей, кровати, транспорт", "звонок на стойке, багаж, чемодан"],
  },
  time: {
    en: [
      "clocks, watches, timers and the hourglass",
      "calendars, schedules, tickets",
      "clock, alarm clock, watch, stopwatch, timer, hourglass",
    ],
    ru: [
      "часы, таймеры и песочные часы",
      "календари, расписания, билеты",
      "часы, будильник, наручные часы, секундомер, таймер, песочные часы",
    ],
  },
  "sky & weather": {
    en: [
      "sun, moon, stars, planets, clouds, rain, snow, rainbow, umbrella, fire, water drops, waves",
      "landscapes, buildings, vehicles, Christmas decorations",
      "sun, moon, star, rainbow, umbrella, snowman, snowflake, fire, droplet, water wave, high voltage",
    ],
    ru: [
      "солнце, луна, звёзды, планеты, облака, дождь, снег, радуга, зонт, огонь, капли воды, волны",
      "ландшафты, здания, транспорт, новогодние украшения",
      "солнце, луна, звезда, радуга, зонт, снеговик, снежинка, огонь, капля, волна, высокое напряжение",
    ],
  },
  event: {
    en: [
      "celebrations, gifts, balloons, fireworks, tickets, holiday decorations and festive items",
      "sports and game prizes, music, tableware, cakes",
      "wrapped gift, balloon, party popper, fireworks, Christmas tree, ticket, ribbon, red envelope",
    ],
    ru: [
      "праздники, подарки, шарики, фейерверки, билеты, праздничные украшения и атрибуты",
      "спортивные призы, музыка, посуда, торты",
      "подарок, воздушный шар, хлопушка, фейерверк, ёлка, билет, лента, красный конверт",
    ],
  },
  "award-medal": {
    en: [
      "trophies, medals and prizes",
      "tickets, party items, sports equipment",
      "trophy, sports medal, first place medal, military medal",
    ],
    ru: [
      "кубки, медали и призы",
      "билеты, праздничные атрибуты, спортивный инвентарь",
      "кубок, спортивная медаль, медаль за первое место, военная медаль",
    ],
  },
  sport: {
    en: [
      "sports balls and equipment, fitness, fishing, skiing, skating, martial arts, diving, golf",
      "video games, board games, prizes, sports venues",
      "soccer ball, basketball, tennis, skis, ice skate, fishing pole, boxing glove, flag in hole, bowling",
    ],
    ru: [
      "спортивные мячи и инвентарь, фитнес, рыбалка, лыжи, коньки, единоборства, дайвинг, гольф",
      "видеоигры, настольные игры, призы, спортивные сооружения",
      "футбольный мяч, баскетбол, теннис, лыжи, коньки, удочка, боксёрская перчатка, флажок на лунке, боулинг",
    ],
  },
  game: {
    en: [
      "video games, board games, cards, puzzles, toys, darts, billiards, kites, magic",
      "sports equipment, prizes, party items, musical instruments",
      "video game, joystick, game die, chess pawn, puzzle piece, teddy bear, joker, bullseye, pool 8 ball, kite, piñata",
    ],
    ru: [
      "видеоигры, настольные игры, карты, пазлы, игрушки, дартс, бильярд, воздушные змеи, магия",
      "спортивный инвентарь, призы, праздничные атрибуты, музыкальные инструменты",
      "видеоигра, джойстик, игральная кость, шахматная пешка, пазл, плюшевый мишка, джокер, мишень, бильярдный шар, воздушный змей, пиньята",
    ],
  },
  "arts & crafts": {
    en: [
      "painting, theatre, sewing and knitting supplies",
      "writing tools, books, musical instruments, clothing",
      "performing arts masks, framed picture, artist palette, thread, sewing needle, yarn, knot",
    ],
    ru: [
      "живопись, театр, принадлежности для шитья и вязания",
      "письменные принадлежности, книги, музыкальные инструменты, одежда",
      "театральные маски, картина в рамке, палитра художника, нитки, швейная игла, пряжа, узел",
    ],
  },
  clothing: {
    en: [
      "clothes, shoes, hats, bags, glasses, jewelry, lipstick, crown, ring, gem stone",
      "sports equipment, tools, household items, toys",
      "t-shirt, dress, shoes, boots, hat, handbag, backpack, glasses, ring, gem stone, lipstick, crown",
    ],
    ru: [
      "одежда, обувь, шапки, сумки, очки, украшения, помада, корона, кольцо, драгоценный камень",
      "спортивный инвентарь, инструменты, предметы быта, игрушки",
      "футболка, платье, туфли, ботинки, шапка, сумка, рюкзак, очки, кольцо, драгоценный камень, помада, корона",
    ],
  },
  sound: {
    en: [
      "speakers, bells, megaphones and alarms",
      "headphones, microphones, instruments, phones",
      "speaker, loudspeaker, megaphone, postal horn, bell, muted speaker",
    ],
    ru: [
      "колонки, колокольчики, мегафоны и сигналы",
      "наушники, микрофоны, инструменты, телефоны",
      "колонка, громкоговоритель, мегафон, почтовый рожок, колокольчик, колонка без звука",
    ],
  },
  music: {
    en: [
      "music notes, microphones, headphones, radio and studio equipment",
      "musical instruments, speakers, concerts and tickets",
      "musical score, musical note, studio microphone, microphone, headphone, radio, control knobs",
    ],
    ru: [
      "ноты, микрофоны, наушники, радио и студийное оборудование",
      "музыкальные инструменты, колонки, концерты и билеты",
      "партитура, нота, студийный микрофон, микрофон, наушники, радио, регуляторы",
    ],
  },
  "musical-instrument": {
    en: [
      "musical instruments",
      "music notes, headphones, microphones, speakers",
      "guitar, musical keyboard, violin, trumpet, saxophone, drum, accordion, banjo, flute, harp",
    ],
    ru: [
      "музыкальные инструменты",
      "ноты, наушники, микрофоны, колонки",
      "гитара, клавишные, скрипка, труба, саксофон, барабан, аккордеон, банджо, флейта, арфа",
    ],
  },
  phone: {
    en: [
      "mobile phones, landlines and pagers",
      "computers, cameras, headphones",
      "mobile phone, telephone, telephone receiver, pager, fax machine",
    ],
    ru: [
      "мобильные телефоны, стационарные телефоны и пейджеры",
      "компьютеры, камеры, наушники",
      "мобильный телефон, телефон, телефонная трубка, пейджер, факс",
    ],
  },
  computer: {
    en: [
      "laptops, desktops, printers, keyboards, mice, storage media, batteries, plugs, the abacus",
      "phones, cameras, TVs, game consoles, office supplies",
      "laptop, desktop computer, printer, keyboard, computer mouse, floppy disk, dvd, battery, abacus",
    ],
    ru: [
      "ноутбуки, компьютеры, принтеры, клавиатуры, мыши, носители данных, батарейки, вилки, счёты",
      "телефоны, камеры, телевизоры, игровые консоли, канцелярия",
      "ноутбук, компьютер, принтер, клавиатура, компьютерная мышь, дискета, dvd, батарейка, счёты",
    ],
  },
  "light & video": {
    en: [
      "cameras, film, video, TV, light bulbs, candles, lamps and lanterns",
      "phones, computers, music equipment, fire and weather",
      "camera, video camera, movie camera, television, light bulb, flashlight, candle, lantern, magnifying glass",
    ],
    ru: [
      "фотоаппараты, кино, видео, телевизоры, лампочки, свечи, лампы и фонари",
      "телефоны, компьютеры, музыкальное оборудование, огонь и погода",
      "фотоаппарат, видеокамера, кинокамера, телевизор, лампочка, фонарик, свеча, лампа, лупа",
    ],
  },
  "book-paper": {
    en: [
      "books, notebooks, newspapers, bookmarks, scrolls, labels and paper",
      "writing tools, mail, office supplies, money",
      "books, open book, notebook, newspaper, bookmark, scroll, page, label",
    ],
    ru: [
      "книги, блокноты, газеты, закладки, свитки, ярлыки и бумага",
      "письменные принадлежности, почта, канцелярия, деньги",
      "книги, открытая книга, блокнот, газета, закладка, свиток, страница, ярлык",
    ],
  },
  money: {
    en: [
      "cash, coins, credit cards, receipts and money bags",
      "gem stones and jewelry, gift boxes, bank buildings, office supplies",
      "money bag, coin, dollar banknote, euro banknote, credit card, receipt, money with wings",
    ],
    ru: [
      "наличные, монеты, кредитные карты, чеки и мешки денег",
      "драгоценные камни и украшения, подарочные коробки, здания банков, канцелярия",
      "мешок денег, монета, доллары, евро, кредитная карта, чек, деньги с крыльями",
    ],
  },
  mail: {
    en: [
      "envelopes, packages, mailboxes, postboxes and ballot boxes",
      "love letters, books, paper documents, gift boxes",
      "envelope, e-mail, package, mailbox, postbox, inbox tray, outbox tray, ballot box",
    ],
    ru: [
      "конверты, посылки, почтовые ящики и урны для голосования",
      "любовные письма, книги, бумажные документы, подарочные коробки",
      "конверт, электронное письмо, посылка, почтовый ящик, входящие, исходящие, урна для голосования",
    ],
  },
  writing: {
    en: [
      "pens, pencils, brushes, crayons and notes",
      "books, paper, office supplies, art supplies for painting",
      "pen, fountain pen, pencil, paintbrush, crayon, memo",
    ],
    ru: [
      "ручки, карандаши, кисти, мелки и заметки",
      "книги, бумага, канцелярия, принадлежности для живописи",
      "ручка, перьевая ручка, карандаш, кисть, мелок, заметка",
    ],
  },
  office: {
    en: [
      "briefcases, folders, calendars, clipboards, paper clips, scissors, rulers and charts",
      "books, writing tools, computers, money",
      "briefcase, file folder, calendar, clipboard, paperclip, scissors, ruler, pushpin, chart",
    ],
    ru: [
      "портфели, папки, календари, планшеты, скрепки, ножницы, линейки и диаграммы",
      "книги, письменные принадлежности, компьютеры, деньги",
      "портфель, папка, календарь, планшет, скрепка, ножницы, линейка, кнопка, диаграмма",
    ],
  },
  lock: {
    en: ["locks and keys", "tools, security guards, computers", "locked, unlocked, key, old key, lock with pen"],
    ru: [
      "замки и ключи",
      "инструменты, охрана, компьютеры",
      "замок, открытый замок, ключ, старинный ключ, замок с ручкой",
    ],
  },
  tool: {
    en: [
      "hand and power tools, hardware, weapons (dagger, swords, bow, bomb), shields, magnets, ladders, chains, scales",
      "household items, medical items, science equipment, sports equipment",
      "hammer, wrench, screwdriver, axe, saw, toolbox, magnet, ladder, shovel, bow and arrow, shield, chains",
    ],
    ru: [
      "ручные и электрические инструменты, крепёж, оружие (кинжал, мечи, лук, бомба), щиты, магниты, лестницы, цепи, весы",
      "предметы быта, медицинские предметы, научное оборудование, спортивный инвентарь",
      "молоток, гаечный ключ, отвёртка, топор, пила, ящик с инструментами, магнит, лестница, лопата, лук со стрелой, щит, цепи",
    ],
  },
  science: {
    en: [
      "laboratory equipment, telescopes, microscopes, DNA and atoms",
      "medical items, tools, computers, space vehicles",
      "test tube, petri dish, DNA, microscope, telescope, satellite antenna, alembic",
    ],
    ru: [
      "лабораторное оборудование, телескопы, микроскопы, ДНК и атомы",
      "медицинские предметы, инструменты, компьютеры, космический транспорт",
      "пробирка, чашка Петри, ДНК, микроскоп, телескоп, спутниковая антенна, перегонный куб",
    ],
  },
  medical: {
    en: [
      "medicine and first aid",
      "science equipment, body parts, household items",
      "pill, syringe, adhesive bandage, stethoscope, X-ray, crutch, drop of blood",
    ],
    ru: [
      "лекарства и первая помощь",
      "научное оборудование, части тела, предметы быта",
      "таблетка, шприц, пластырь, стетоскоп, рентген, костыль, капля крови",
    ],
  },
  household: {
    en: [
      "furniture, doors, windows, bathroom, cleaning, kitchen supplies and personal care items",
      "tableware, clothing, tools, electronics, toys",
      "bed, couch, chair, door, mirror, shower, bathtub, razor, lotion bottle, broom, soap, sponge, toothbrush, shopping cart",
    ],
    ru: [
      "мебель, двери, окна, ванная, уборка, кухонные принадлежности и средства личной гигиены",
      "посуда, одежда, инструменты, электроника, игрушки",
      "кровать, диван, стул, дверь, зеркало, душ, ванна, бритва, флакон с лосьоном, веник, мыло, губка, зубная щётка, тележка",
    ],
  },
  "other-object": {
    en: [
      "cigarettes, amulets, statues, memorial objects, placards and ID cards",
      "tools, household items, jewelry, religious buildings",
      "cigarette, nazar amulet, hamsa, moai, headstone, funeral urn, coffin, identification card",
    ],
    ru: [
      "сигареты, амулеты, статуи, мемориальные предметы, таблички и удостоверения",
      "инструменты, предметы быта, украшения, религиозные здания",
      "сигарета, амулет от сглаза, хамса, статуя моаи, надгробие, погребальная урна, гроб, удостоверение личности",
    ],
  },
};

const noteText = (parts: Triplet, labels: Triplet) =>
  `${labels[0]} ${parts[0]}; ${labels[1]} ${parts[1]}; ${labels[2]} ${parts[2]}`;

/** One line, uniform: "Includes: …; excludes: …; examples: … | Включает: …; не включает: …; примеры: …". */
export function describeSubgroup(subgroup: string): string {
  const note = SUBGROUP_NOTES[subgroup];
  if (!note) throw new Error(`no description for subgroup "${subgroup}"; add it to SUBGROUP_NOTES`);
  return `${noteText(note.en, ["Includes:", "excludes:", "examples:"])} | ${noteText(note.ru, ["Включает:", "не включает:", "примеры:"])}`;
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
      description: describeSubgroup(entry.subgroup),
    }).keys.push(key);
  }
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
// Gift-relevant single emoji (no flags, symbols, skin tones or ZWJ sequences; Smileys keep hearts and the kiss,
// People & Body keeps hands and body parts) with Unicode group/subgroup and CLDR English and Russian names.
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
