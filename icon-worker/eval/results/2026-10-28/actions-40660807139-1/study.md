# Jev prompt study

Status: **complete**. 2026-10-28T09:00:02.519Z → 2026-10-28T09:02:49.540Z.

- currency RUB (price question included)
- model `jev-1.14.0`, picker `jev-two-stage-v2`, catalog `cldr-e074edda57dd`, min confidence 0.35
- production semantics: 2 attempts × 3000 ms per stage, 7000 ms shared deadline
- sample: 200 of 969 cases (seed `prompt-study-1`, limit 200); catalog ceiling of the sample 100.0%
- concurrency 2, pause 300 ms; every provider failure counts as a failed case

## Results

| variant | n | accuracy (95% CI) | top-1 | pre-threshold | failed | null→🎁 | stage 1 reachable | stage 2 hit | in tokens (s1+s2) | USD/1000 | p50 / p90 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 200 | 74.0% (67.5%–79.6%) | 64.5% | 75.5% | 0 | 22 | 88.0% (176/200) | 85.8% (151/176) | 24150 (21743+2407) | 1.0143 | 267 / 313 |
| short | 200 | 69.0% (62.3%–75.0%) | 60.5% | 72.5% | 0 | 33 | 83.5% (167/200) | 86.8% (145/167) | 23906 (21638+2268) | 1.0041 | 266 / 304 |
| compact | 200 | 68.5% (61.8%–74.5%) | 60.5% | 73.5% | 0 | 39 | 82.0% (164/200) | 89.6% (147/164) | 15188 (13344+1844) | 0.6379 | 226 / 269 |

Stage 1 reachable: among answered cases whose gold glyph is in the catalog, stage 1 chose a subgroup that holds an accepted glyph. Stage 2 hit: among those, the final candidate is accepted (before the threshold).

## Against baseline (same cases)

| variant | both pass | only variant | only reference | neither |
|---|---:|---:|---:|---:|
| short | 135 | 3 | 13 | 49 |
| compact | 129 | 8 | 19 | 44 |

## Failure causes

| cause | baseline | short | compact |
|---|---:|---:|---:|
| below-threshold | 3 | 7 | 10 |
| stage1-misrouted | 24 | 30 | 33 |
| stage1-none | 0 | 3 | 3 |
| stage2-none | 2 | 2 | 2 |
| stage2-wrong | 23 | 20 | 15 |

## Accuracy by tag

| tag | baseline | short | compact |
|---|---:|---:|---:|
| brand | 66.7% (21) | 61.9% (21) | 61.9% (21) |
| en | 67.4% (43) | 65.1% (43) | 65.1% (43) |
| ru | 76.7% (116) | 70.7% (116) | 69.0% (116) |
| typo | 72.7% (11) | 72.7% (11) | 81.8% (11) |
| vague | 88.9% (9) | 77.8% (9) | 77.8% (9) |

## Variants

### baseline

Current production prompt, unaltered.

Stage 1 instructions:

> The state is the name of a present someone gave or received, written by the user in any language (often Russian), possibly with typos or brand names. Choose the closest recognizable emoji representation of the gift item or experience. Use a literal depiction when available; otherwise use its function, what it produces, or a related object or activity. The exact object does not need its own emoji: appliances can be represented by the food or drink they make, services by the activity, branded products by their product type, and a gift certificate by what it buys. Prefer the gift contents over generic packaging. Among similar variants prefer a common general depiction. Use none only for an unknown, vague or abstract gift without a meaningful visual association. Choose the subgroup containing that closest recognizable representation, even when the gift itself is not a literal member of the subgroup.

Stage 2 instructions:

> The state is the name of a present someone gave or received, written by the user in any language (often Russian), possibly with typos or brand names. Choose the closest recognizable emoji representation of the gift item or experience. Use a literal depiction when available; otherwise use its function, what it produces, or a related object or activity. The exact object does not need its own emoji: appliances can be represented by the food or drink they make, services by the activity, branded products by their product type, and a gift certificate by what it buys. Prefer the gift contents over generic packaging. Among similar variants prefer a common general depiction. Use none only for an unknown, vague or abstract gift without a meaningful visual association.

### short

Very short task-specific instructions per stage; production criteria unchanged.

Stage 1 instructions:

> The state is a gift name, usually Russian, maybe with typos or brands. Choose the subgroup holding the emoji that best depicts the gift: the item itself, otherwise what it makes, does or is for. The gift need not literally belong to the subgroup. Choose none only for a vague or abstract gift.

Stage 2 instructions:

> The state is a gift name, usually Russian, maybe with typos or brands. Choose the emoji that best depicts the gift: the item itself, otherwise what it makes, does or is for. Prefer the common general depiction. Choose none only for a vague or abstract gift.

### compact

Short instructions; stage 1 criteria keep includes/excludes/examples (EN+RU) with at most 5 spread CLDR examples; stage 2 criteria are the bilingual CLDR name plus at most 4 keywords.

Stage 1 instructions:

> The state is a gift name, usually Russian, maybe with typos or brands. Choose the subgroup holding the emoji that best depicts the gift: the item itself, otherwise what it makes, does or is for. The gift need not literally belong to the subgroup. Choose none only for a vague or abstract gift.

Stage 2 instructions:

> The state is a gift name, usually Russian, maybe with typos or brands. Choose the emoji that best depicts the gift: the item itself, otherwise what it makes, does or is for. Prefer the common general depiction. Choose none only for a vague or abstract gift.

Full criteria for every question are in `prompts.json`.

## Misses

<details><summary>baseline (52)</summary>

- массажный коврик → 💆 [stage1-misrouted] (want 🧘)
- микроволновка → null [stage1-misrouted] (want 🍲 🔥)
- утюг → null [stage1-misrouted] (want 👕)
- restaurant gift card → 💳 [stage1-misrouted] (want 🎫 🍽)
- фен → null [stage1-misrouted] (want 💇 🪮)
- скакалка → null [stage1-misrouted] (want 🤸)
- набор солдатиков → ♟️ [stage1-misrouted] (want 🪖)
- cash → 💰 [stage2-wrong] (want 💸 💵)
- серёжки → null [below-threshold] (want 💎)
- экскурсия по Москве → 🏙️ [stage1-misrouted] (want 🗺 🏛)
- шампусик → 🧴 [stage1-misrouted] (want 🍾 🥂)
- JBL колонка → 🔉 [stage2-wrong] (want 🔊)
- набор кастрюль → 🪣 [stage1-misrouted] (want 🍲 🥘)
- дрель → null [stage2-wrong] (want 🔧 🛠)
- коробки для хранения → 🧺 [stage1-misrouted] (want 📦)
- Яндекс Станция → 🔉 [stage2-wrong] (want 🔊)
- cinema tickets → 🎫 [stage2-wrong] (want 🎬 🎟)
- модель самолёта → 🛩️ [stage2-wrong] (want ✈)
- гортензия → 🪻 [stage2-wrong] (want 💐 🌸)
- Аэрофлот билеты → 🎫 [stage1-misrouted] (want ✈)
- серьги → null [below-threshold] (want 💎)
- акции Сбера → 💹 [stage1-misrouted] (want 📈)
- 1000 → null [stage2-none] (want 💸)
- деньги в конверте → 💰 [stage2-wrong] (want 💌 💸)
- brownies → 🍪 [stage2-wrong] (want 🍫)
- копилка → 🪙 [stage2-wrong] (want 🐷 💰)
- колонка → 🔉 [stage2-wrong] (want 🔊)
- Nutella → 🍯 [stage2-wrong] (want 🍫 🫙)
- Spotify подписка → null [stage2-wrong] (want 🎵)
- свитер → null [below-threshold] (want 🧥 👕)
- блендер → null [stage2-wrong] (want 🥤 🍹)
- ботинки зимние → 👞 [stage2-wrong] (want 🥾)
- аэрогриль → null [stage2-wrong] (want 🍟 🍗)
- cat toy → 🧸 [stage1-misrouted] (want 🐈 🧶)
- паводок для сабаки → null [stage1-misrouted] (want 🐕 🦮)
- muffins → 🍞 [stage1-misrouted] (want 🧁)
- iPad → 📋 [stage1-misrouted] (want 📱)
- e-scooter → 🛵 [stage2-wrong] (want 🛴)
- maple syrup → 🍯 [stage1-misrouted] (want 🍁 🥞)
- bike helmet → 🪖 [stage2-wrong] (want ⛑ 🚲)
- flight tickets → 🎫 [stage2-wrong] (want ✈ 🎟)
- медовуха → 🍷 [stage2-wrong] (want 🍯 🍺)
- fruit basket → null [stage2-none] (want 🧺 🍎)
- детский плед → 🛏️ [stage1-misrouted] (want 👶)
- chocolate box → 🍬 [stage2-wrong] (want 🍫 🎁)
- dumbbells → null [stage1-misrouted] (want 🏋)
- ужин в ресторане → null [stage1-misrouted] (want 🍽)
- строительный уровень → null [stage1-misrouted] (want 📐 📏)
- книга → 📕 [stage2-wrong] (want 📖 📚)
- bluetooth speaker → 🔉 [stage2-wrong] (want 🔊 🎵)
- романтический ужин → 💕 [stage1-misrouted] (want 🍽 🥂 🕯)
- секатор → 🪚 [stage1-misrouted] (want ✂ 🌿)

</details>

<details><summary>short (62)</summary>

- массажный коврик → 💆 [stage1-misrouted] (want 🧘)
- микроволновка → null [stage1-misrouted] (want 🍲 🔥)
- утюг → null [stage1-misrouted] (want 👕)
- брошь → null [below-threshold] (want 💎 🎀)
- restaurant gift card → 💳 [stage1-misrouted] (want 🎫 🍽)
- фен → null [stage1-misrouted] (want 💇 🪮)
- скакалка → null [stage1-misrouted] (want 🤸)
- набор солдатиков → ♟️ [stage1-misrouted] (want 🪖)
- cash → 💰 [stage2-wrong] (want 💸 💵)
- серёжки → null [below-threshold] (want 💎)
- экскурсия по Москве → 🏙️ [stage1-misrouted] (want 🗺 🏛)
- шампусик → 🧴 [stage1-misrouted] (want 🍾 🥂)
- набор кастрюль → 🪣 [stage1-misrouted] (want 🍲 🥘)
- дрель → null [stage2-wrong] (want 🔧 🛠)
- коробки для хранения → 🧺 [stage1-misrouted] (want 📦)
- Яндекс Станция → 🔉 [stage2-wrong] (want 🔊)
- cinema tickets → 🎫 [stage2-wrong] (want 🎬 🎟)
- модель самолёта → 🛩️ [stage2-wrong] (want ✈)
- курс английского → null [stage1-none] (want 📚 🗣)
- гортензия → null [stage2-wrong] (want 💐 🌸)
- pajamas → null [below-threshold] (want 👘 🛌)
- Аэрофлот билеты → 🎫 [stage1-misrouted] (want ✈)
- серьги → null [below-threshold] (want 💎)
- акции Сбера → 💹 [stage1-misrouted] (want 📈)
- 1000 → null [stage1-none] (want 💸)
- деньги в конверте → 💰 [stage2-wrong] (want 💌 💸)
- brownies → 🍪 [stage2-wrong] (want 🍫)
- копилка → 🪙 [stage2-wrong] (want 🐷 💰)
- тостер → null [stage1-misrouted] (want 🍞)
- колонка → null [below-threshold] (want 🔊)
- Nutella → 🍯 [stage2-wrong] (want 🍫 🫙)
- Spotify подписка → null [stage2-wrong] (want 🎵)
- Starbucks gift card → 💳 [stage1-misrouted] (want ☕ 🎫)
- блендер → null [stage1-misrouted] (want 🥤 🍹)
- ботинки зимние → 👞 [stage2-wrong] (want 🥾)
- острый соус → 🧂 [stage1-misrouted] (want 🌶)
- самовар → ☕ [stage2-wrong] (want 🫖)
- аэрогриль → null [stage1-misrouted] (want 🍟 🍗)
- cat toy → 🧸 [stage1-misrouted] (want 🐈 🧶)
- паводок для сабаки → null [below-threshold] (want 🐕 🦮)
- muffins → null [stage1-misrouted] (want 🧁)
- iPad → 📋 [stage1-misrouted] (want 📱)
- оливковое масло → 🧈 [stage1-misrouted] (want 🫒)
- e-scooter → 🛵 [stage2-wrong] (want 🛴)
- домик для кошки → 🛏️ [stage1-misrouted] (want 🐈 🏠)
- Pokémon cards → null [below-threshold] (want 🃏)
- maple syrup → 🍯 [stage1-misrouted] (want 🍁 🥞)
- bike helmet → 🪖 [stage2-wrong] (want ⛑ 🚲)
- что-то почитать → null [stage2-none] (want 📖 📚)
- flight tickets → 🎫 [stage2-wrong] (want ✈ 🎟)
- медовуха → 🍷 [stage2-wrong] (want 🍯 🍺)
- fruit basket → null [stage2-none] (want 🧺 🍎)
- онлайн курс → null [stage1-none] (want 💻 🎓)
- chocolate box → 🍬 [stage2-wrong] (want 🍫 🎁)
- dumbbells → null [stage1-misrouted] (want 🏋)
- ужин в ресторане → null [stage1-misrouted] (want 🍽)
- строительный уровень → ⚖️ [stage1-misrouted] (want 📐 📏)
- книга → 📕 [stage2-wrong] (want 📖 📚)
- фитнес браслет → null [stage1-misrouted] (want ⌚ 🏃)
- bluetooth speaker → 🔉 [stage2-wrong] (want 🔊 🎵)
- романтический ужин → null [stage1-misrouted] (want 🍽 🥂 🕯)
- секатор → 🪚 [stage1-misrouted] (want ✂ 🌿)

</details>

<details><summary>compact (63)</summary>

- шарики → null [below-threshold] (want 🎈)
- массажный коврик → 💆 [stage1-misrouted] (want 🧘)
- микроволновка → null [stage1-misrouted] (want 🍲 🔥)
- утюг → null [stage1-misrouted] (want 👕)
- брошь → null [below-threshold] (want 💎 🎀)
- restaurant gift card → 💳 [stage1-misrouted] (want 🎫 🍽)
- фен → null [stage1-misrouted] (want 💇 🪮)
- скакалка → null [stage1-misrouted] (want 🤸)
- набор мыльных пузырей → null [stage1-misrouted] (want 🫧)
- набор солдатиков → ♟️ [stage1-misrouted] (want 🪖)
- термокружка → 🏺 [stage1-misrouted] (want ☕)
- подписка на аудиокниги → null [below-threshold] (want 🎧 📖)
- cash → null [stage2-wrong] (want 💸 💵)
- серёжки → null [below-threshold] (want 💎)
- экскурсия по Москве → 🎫 [stage1-misrouted] (want 🗺 🏛)
- шампусик → 🧴 [stage1-misrouted] (want 🍾 🥂)
- matcha set → null [stage1-misrouted] (want 🍵)
- набор кастрюль → 🪣 [stage1-misrouted] (want 🍲 🥘)
- дрель → null [stage2-wrong] (want 🔧 🛠)
- коробки для хранения → 🧺 [stage1-misrouted] (want 📦)
- Яндекс Станция → 🔉 [stage2-wrong] (want 🔊)
- cinema tickets → 🎫 [stage2-wrong] (want 🎬 🎟)
- курс английского → null [stage1-none] (want 📚 🗣)
- гортензия → null [stage2-wrong] (want 💐 🌸)
- pajamas → null [below-threshold] (want 👘 🛌)
- Аэрофлот билеты → 🎫 [stage1-misrouted] (want ✈)
- серьги → null [below-threshold] (want 💎)
- акции Сбера → 💹 [stage1-misrouted] (want 📈)
- 1000 → null [stage1-none] (want 💸)
- деньги в конверте → 💰 [stage2-wrong] (want 💌 💸)
- brownies → 🍪 [stage2-wrong] (want 🍫)
- копилка → 🪙 [stage2-wrong] (want 🐷 💰)
- колонка → null [below-threshold] (want 🔊)
- Spotify подписка → null [stage2-wrong] (want 🎵)
- свитер → null [below-threshold] (want 🧥 👕)
- Starbucks gift card → 💳 [stage1-misrouted] (want ☕ 🎫)
- блендер → null [stage1-misrouted] (want 🥤 🍹)
- ботинки зимние → 👞 [stage2-wrong] (want 🥾)
- острый соус → 🧂 [stage1-misrouted] (want 🌶)
- чайник электрический → null [stage1-misrouted] (want 🫖)
- аэрогриль → null [stage1-misrouted] (want 🍟 🍗)
- cat toy → 🧸 [stage1-misrouted] (want 🐈 🧶)
- iPad → null [stage1-misrouted] (want 📱)
- e-scooter → 🛵 [stage2-wrong] (want 🛴)
- домик для кошки → 🛏️ [stage1-misrouted] (want 🐈 🏠)
- Pokémon cards → null [below-threshold] (want 🃏)
- maple syrup → 🍯 [stage1-misrouted] (want 🍁 🥞)
- bike helmet → 🪖 [stage2-wrong] (want ⛑ 🚲)
- Chanel No 5 → 💄 [stage1-misrouted] (want 🧴 🌸)
- что-то почитать → null [stage2-none] (want 📖 📚)
- flight tickets → 🎫 [stage2-wrong] (want ✈ 🎟)
- заварочный чайничек → 🏺 [stage1-misrouted] (want 🫖 🍵)
- медовуха → 🍷 [stage2-wrong] (want 🍯 🍺)
- fruit basket → null [stage2-none] (want 🧺 🍎)
- онлайн курс → null [stage1-none] (want 💻 🎓)
- e-reader → null [below-threshold] (want 📖 📱)
- chocolate box → 🍬 [stage2-wrong] (want 🍫 🎁)
- dumbbells → null [stage1-misrouted] (want 🏋)
- ужин в ресторане → null [stage1-misrouted] (want 🍽)
- строительный уровень → ⚖️ [stage1-misrouted] (want 📐 📏)
- фитнес браслет → null [stage1-misrouted] (want ⌚ 🏃)
- романтический ужин → null [stage1-misrouted] (want 🍽 🥂 🕯)
- секатор → 🪚 [stage1-misrouted] (want ✂ 🌿)

</details>

<details><summary>Sample (200 cases)</summary>

- выпрямитель для волос
- шарики
- костюм мужской
- массажный коврик
- drone
- зарядка для телефона
- Moleskine
- вкусняшки
- топор
- микроволновка
- bullet journal
- утюг
- домашнее молоко
- плойка
- волейбольный мяч
- контейнеры для еды
- лаванда в горшочке
- Pampers
- духи Dior
- skydiving
- брошь
- restaurant gift card
- постельное белье
- парашут
- видеорегистратор
- фен
- зонтик складной
- метеостанция
- Барби
- басаножки
- банджо
- flip flops
- cookies
- скакалка
- настольная игра
- набор мыльных пузырей
- набор солдатиков
- саксофон
- объектив
- wireless charger
- вкусный подарок
- термокружка
- ракетка
- винишко
- солнцезащитные очки
- санки
- fireworks
- sneakers
- акции
- подписка на аудиокниги
- cash
- тирамису
- набор для коктейлей
- шоколдка
- серёжки
- пуэр
- коврик для йоги
- улитка ахатина
- конная прогулка
- шторы
- экскурсия по Москве
- шампусик
- matcha set
- набор для вязания
- JBL колонка
- beard trimmer
- лимонад
- набор кастрюль
- AirPods Pro
- аквариумные рыбки
- дрель
- фейерверк
- коробки для хранения
- худи
- стендап
- шкатулка для украшений
- Яндекс Станция
- мольберт
- cinema tickets
- модель самолёта
- видеоигра
- торт Наполеон
- тюльпаны
- что-то для дома
- кросовки
- шампунь
- first aid kit
- курс английского
- гортензия
- витамины
- pajamas
- бенгальские огни
- струны для гитары
- Аэрофлот билеты
- car phone mount
- серьги
- банка
- акции Сбера
- 1000
- очки для плавания
- деньги в конверте
- brownies
- копилка
- тостер
- колонка
- умная лампочка
- Nutella
- Spotify подписка
- Монополия
- свитер
- парк аттракционов
- дегустация сыров
- пуховик
- баскетбольный мяч
- ящик мандаринов
- PlayStation 5
- Starbucks gift card
- вино и сыр
- MAC помада
- угги
- ноутбук
- hiking boots
- блендер
- cheese board
- ботинки зимние
- галстук-бабочка
- острый соус
- knife set
- детский велосипед
- самовар
- чайник электрический
- ракета
- аэрогриль
- cat toy
- стремянка
- паводок для сабаки
- muffins
- горный велосипед
- iPad
- пауэрбанк
- дартс
- оливковое масло
- e-scooter
- домик для кошки
- телевизор
- Pokémon cards
- coffee beans
- maple syrup
- bike helmet
- микрофон
- umbrella
- whiskey glasses
- Chanel No 5
- дрон для ребёнка
- Omron тонометр
- домашнее печенье
- подарок
- деньги на карту
- dumplings
- diamond earrings
- leather jacket
- продуктовая корзина
- что-то почитать
- прыжок с парашютом
- настолная игра
- ice cream
- букет роз
- flight tickets
- подсолнухи
- набор ножей
- fishing rod
- заварочный чайничек
- самокат
- медовуха
- fruit basket
- канструктор
- детский плед
- онлайн курс
- e-reader
- chocolate box
- Nespresso
- dumbbells
- что-то в машину
- espresso machine
- ужин в ресторане
- курсы вождения
- строительный уровень
- суши сет
- рамен
- книга
- noise cancelling headphones
- Dyson
- фитнес браслет
- plush bunny
- шарлотка
- букет полевых цветов
- bluetooth speaker
- романтический ужин
- hot chocolate
- секатор

</details>
