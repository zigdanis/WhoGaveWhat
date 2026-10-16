/**
 * The curated icons Jev chooses from. Each key is a Jev Choice option: a short English
 * name plus a description of what it depicts. `ru` holds optional Russian hints that
 * can be appended to the description (see `criteria`). Several keys may share an emoji.
 *
 * Bump `CATALOG_VERSION` whenever keys, emoji or descriptions change, so cached answers
 * from an older catalog are not reused.
 */
export const CATALOG_VERSION = "2026-10-16.1";

/** The option meaning "nothing specific fits"; the app keeps its own icon then. */
export const GENERIC_KEY = "generic_gift";

export interface GiftIcon {
  emoji: string;
  description: string;
  ru?: string;
}

export const ICONS: Record<string, GiftIcon> = {
  generic_gift: {
    emoji: "🎁",
    description: "Unclear, abstract or unrecognisable gift that none of the other options depicts",
  },

  // Flowers and plants
  flower_bouquet: { emoji: "💐", description: "Bouquet or arrangement of flowers", ru: "букет, цветы" },
  rose: { emoji: "🌹", description: "Roses", ru: "розы" },
  tulip: { emoji: "🌷", description: "Tulips or spring flowers", ru: "тюльпаны" },
  sunflower: { emoji: "🌻", description: "Sunflowers, daisies or chamomile", ru: "подсолнухи, ромашки" },
  potted_plant: { emoji: "🪴", description: "Houseplant in a pot, orchid, succulent", ru: "комнатное растение, орхидея" },
  cactus: { emoji: "🌵", description: "Cactus", ru: "кактус" },
  tree_seedling: { emoji: "🌱", description: "Seeds, seedlings or gardening supplies", ru: "семена, рассада" },
  christmas_tree: { emoji: "🎄", description: "Christmas or New Year tree and decorations", ru: "ёлка, ёлочные игрушки" },

  // Sweets and food
  chocolate: { emoji: "🍫", description: "Chocolate bar or box of chocolates", ru: "шоколад, конфеты в коробке" },
  candy: { emoji: "🍬", description: "Candies, sweets, marmalade", ru: "конфеты, мармелад" },
  lollipop: { emoji: "🍭", description: "Lollipop", ru: "леденец, чупа-чупс" },
  birthday_cake: { emoji: "🎂", description: "Cake or birthday cake", ru: "торт" },
  cupcake: { emoji: "🧁", description: "Cupcakes, pastries, desserts", ru: "пирожные, капкейки" },
  cookie: { emoji: "🍪", description: "Cookies, biscuits, gingerbread", ru: "печенье, пряники" },
  doughnut: { emoji: "🍩", description: "Doughnuts", ru: "пончики" },
  pie: { emoji: "🥧", description: "Pie or tart", ru: "пирог" },
  ice_cream: { emoji: "🍨", description: "Ice cream", ru: "мороженое" },
  honey: { emoji: "🍯", description: "Honey", ru: "мёд" },
  jam_jar: { emoji: "🫙", description: "Jar of jam, preserves or pickles", ru: "варенье, соленья" },
  cheese: { emoji: "🧀", description: "Cheese", ru: "сыр" },
  bread: { emoji: "🍞", description: "Bread or baked goods", ru: "хлеб, выпечка" },
  fruit: { emoji: "🍎", description: "Apples or a basket of fruit", ru: "яблоки, фрукты" },
  strawberries: { emoji: "🍓", description: "Strawberries or berries", ru: "клубника, ягоды" },
  grapes: { emoji: "🍇", description: "Grapes", ru: "виноград" },
  citrus: { emoji: "🍊", description: "Oranges, tangerines, citrus", ru: "мандарины, апельсины" },
  nuts: { emoji: "🥜", description: "Nuts or dried fruit", ru: "орехи, сухофрукты" },
  meat: { emoji: "🥩", description: "Meat, steak, barbecue", ru: "мясо, шашлык" },
  sausage: { emoji: "🌭", description: "Sausages, salami, deli meats", ru: "колбаса" },
  fish: { emoji: "🐟", description: "Fish, caviar, seafood delicacies", ru: "рыба, икра" },
  sushi: { emoji: "🍣", description: "Sushi or rolls", ru: "суши, роллы" },
  pizza: { emoji: "🍕", description: "Pizza", ru: "пицца" },
  dumplings: { emoji: "🥟", description: "Dumplings", ru: "пельмени, вареники" },
  cooked_meal: { emoji: "🍲", description: "Home-cooked meal, soup or food delivery", ru: "еда, суп, доставка еды" },
  restaurant_dinner: { emoji: "🍽️", description: "Restaurant visit, dinner out, or tableware and plates", ru: "ресторан, ужин, посуда" },
  groceries: { emoji: "🛒", description: "Groceries or a food hamper", ru: "продукты" },
  eggs: { emoji: "🥚", description: "Eggs or Easter eggs", ru: "яйца, пасхальные яйца" },

  // Drinks
  coffee: { emoji: "☕", description: "Coffee, coffee beans, mug or cup", ru: "кофе, кружка, чашка" },
  tea: { emoji: "🍵", description: "Tea", ru: "чай" },
  teapot: { emoji: "🫖", description: "Teapot or tea set", ru: "чайник, чайный сервиз" },
  wine: { emoji: "🍷", description: "Wine", ru: "вино" },
  champagne: { emoji: "🍾", description: "Champagne or sparkling wine", ru: "шампанское" },
  beer: { emoji: "🍺", description: "Beer", ru: "пиво" },
  spirits: { emoji: "🥃", description: "Whisky, cognac, brandy, vodka or other spirits", ru: "виски, коньяк, водка" },
  cocktail: { emoji: "🍸", description: "Cocktails, liqueur, gin", ru: "коктейль, ликёр" },
  juice: { emoji: "🧃", description: "Juice or soft drinks", ru: "сок, лимонад" },

  // Technology
  smartphone: { emoji: "📱", description: "Smartphone, iPhone, phone case or tablet", ru: "телефон, смартфон, айфон, планшет" },
  laptop: { emoji: "💻", description: "Laptop or MacBook", ru: "ноутбук" },
  desktop_computer: { emoji: "🖥️", description: "Desktop computer or monitor", ru: "компьютер, монитор" },
  keyboard: { emoji: "⌨️", description: "Computer keyboard", ru: "клавиатура" },
  computer_mouse: { emoji: "🖱️", description: "Computer mouse", ru: "мышка" },
  headphones: { emoji: "🎧", description: "Headphones, earbuds, AirPods", ru: "наушники" },
  speaker: { emoji: "🔊", description: "Speaker, smart speaker, soundbar", ru: "колонка" },
  watch: { emoji: "⌚", description: "Wristwatch, smartwatch, Apple Watch, fitness tracker", ru: "часы, смарт-часы" },
  camera: { emoji: "📷", description: "Photo camera or lens", ru: "фотоаппарат" },
  video_camera: { emoji: "🎥", description: "Video camera, action camera, projector", ru: "видеокамера, проектор" },
  television: { emoji: "📺", description: "TV set or streaming subscription", ru: "телевизор, подписка" },
  game_console: { emoji: "🎮", description: "Game console, gamepad or video game", ru: "приставка, игра, геймпад" },
  vr_headset: { emoji: "🥽", description: "VR headset, goggles", ru: "VR-очки, очки виртуальной реальности" },
  power_bank: { emoji: "🔋", description: "Power bank or batteries", ru: "пауэрбанк, аккумулятор" },
  charger: { emoji: "🔌", description: "Charger, cable or adapter", ru: "зарядка, кабель" },
  printer: { emoji: "🖨️", description: "Printer", ru: "принтер" },
  radio: { emoji: "📻", description: "Radio", ru: "радио, радиоприёмник" },
  ebook_reader: { emoji: "📖", description: "E-book reader, Kindle", ru: "электронная книга" },
  robot: { emoji: "🤖", description: "Robot vacuum, robot toy, smart gadget", ru: "робот-пылесос, робот" },
  light_bulb: { emoji: "💡", description: "Lamp, night light, smart bulb", ru: "лампа, ночник, светильник" },

  // Home and kitchen
  frying_pan: { emoji: "🍳", description: "Frying pan, cookware, kitchen appliance", ru: "сковорода, кухонная техника" },
  kitchen_knife: { emoji: "🔪", description: "Kitchen knives", ru: "ножи" },
  candle: { emoji: "🕯️", description: "Candles", ru: "свечи" },
  vase: { emoji: "🏺", description: "Vase or decorative pottery", ru: "ваза" },
  picture_frame: { emoji: "🖼️", description: "Painting, poster, picture or photo frame", ru: "картина, постер, фоторамка" },
  mirror: { emoji: "🪞", description: "Mirror", ru: "зеркало" },
  clock: { emoji: "🕰️", description: "Wall clock or alarm clock", ru: "настенные часы, будильник" },
  bed: { emoji: "🛏️", description: "Bedding, pillow, blanket, bed linen", ru: "постельное бельё, подушка, плед, одеяло" },
  sofa: { emoji: "🛋️", description: "Sofa, armchair or furniture", ru: "диван, кресло, мебель" },
  chair: { emoji: "🪑", description: "Chair or stool", ru: "стул" },
  bathtub: { emoji: "🛁", description: "Bath products, bath bombs, towels, bathrobe", ru: "для ванны, полотенце, халат" },
  soap: { emoji: "🧼", description: "Soap or shower gel", ru: "мыло, гель для душа" },
  lotion: { emoji: "🧴", description: "Cream, lotion, skincare, shampoo", ru: "крем, уход за кожей, шампунь" },
  basket: { emoji: "🧺", description: "Basket, gift hamper or laundry basket", ru: "корзина" },
  broom: { emoji: "🧹", description: "Vacuum cleaner or cleaning supplies", ru: "пылесос, уборка" },
  umbrella: { emoji: "☂️", description: "Umbrella", ru: "зонт" },
  house_key: { emoji: "🔑", description: "Keys, keychain, apartment or house", ru: "ключи, брелок, квартира" },
  toolbox: { emoji: "🧰", description: "Toolbox, tool set, drill", ru: "инструменты, дрель" },
  hammer: { emoji: "🔨", description: "Hammer or hand tools", ru: "молоток" },
  sewing: { emoji: "🧵", description: "Sewing kit, thread, sewing machine", ru: "швейные принадлежности, швейная машинка" },
  yarn: { emoji: "🧶", description: "Yarn or knitting supplies", ru: "пряжа, вязание" },
  scissors: { emoji: "✂️", description: "Scissors", ru: "ножницы" },
  magnet: { emoji: "🧲", description: "Fridge magnet or souvenir magnet", ru: "магнит на холодильник" },
  thermometer: { emoji: "🌡️", description: "Thermometer or weather station", ru: "градусник, метеостанция" },

  // Clothing and accessories
  t_shirt: { emoji: "👕", description: "T-shirt, top, pajamas", ru: "футболка, пижама" },
  shirt_tie: { emoji: "👔", description: "Shirt or necktie", ru: "рубашка, галстук" },
  dress: { emoji: "👗", description: "Dress or skirt", ru: "платье, юбка" },
  jeans: { emoji: "👖", description: "Jeans or trousers", ru: "джинсы, брюки" },
  coat: { emoji: "🧥", description: "Coat, jacket, sweater, hoodie", ru: "пальто, куртка, свитер, худи" },
  scarf: { emoji: "🧣", description: "Scarf or shawl", ru: "шарф, платок" },
  gloves: { emoji: "🧤", description: "Gloves or mittens", ru: "перчатки, варежки" },
  socks: { emoji: "🧦", description: "Socks or tights", ru: "носки, колготки" },
  cap: { emoji: "🧢", description: "Cap or beanie", ru: "кепка, шапка" },
  top_hat: { emoji: "🎩", description: "Hat", ru: "шляпа" },
  sneakers: { emoji: "👟", description: "Sneakers, trainers, running shoes", ru: "кроссовки, кеды" },
  boots: { emoji: "👢", description: "Boots", ru: "сапоги, ботинки" },
  high_heels: { emoji: "👠", description: "High heels or women's shoes", ru: "туфли" },
  slippers: { emoji: "🩴", description: "Slippers or flip-flops", ru: "тапочки, шлёпанцы" },
  swimsuit: { emoji: "👙", description: "Swimsuit or bikini", ru: "купальник" },
  underwear: { emoji: "🩲", description: "Underwear or lingerie", ru: "нижнее бельё, трусы" },
  bathrobe: { emoji: "👘", description: "Kimono, robe, dressing gown", ru: "кимоно, халат" },
  handbag: { emoji: "👜", description: "Handbag", ru: "сумка, сумочка" },
  backpack: { emoji: "🎒", description: "Backpack or school bag", ru: "рюкзак, портфель" },
  wallet: { emoji: "👛", description: "Wallet, purse, cardholder", ru: "кошелёк, портмоне" },
  briefcase: { emoji: "💼", description: "Briefcase or work bag", ru: "портфель, деловая сумка" },
  suitcase: { emoji: "🧳", description: "Suitcase or luggage", ru: "чемодан" },
  sunglasses: { emoji: "🕶️", description: "Sunglasses", ru: "солнечные очки" },
  glasses: { emoji: "👓", description: "Eyeglasses", ru: "очки" },
  hair_bow: { emoji: "🎀", description: "Hair accessories, bow, ribbon", ru: "заколки, бантик, резинки" },
  crown: { emoji: "👑", description: "Crown or tiara", ru: "корона, диадема" },

  // Jewelry and beauty
  ring: { emoji: "💍", description: "Ring or engagement ring", ru: "кольцо" },
  gem: { emoji: "💎", description: "Jewelry, earrings, diamonds, bracelet", ru: "украшения, серьги, браслет" },
  necklace: { emoji: "📿", description: "Necklace, pendant, chain, beads", ru: "ожерелье, кулон, цепочка, бусы" },
  perfume: { emoji: "🌸", description: "Perfume, fragrance, eau de toilette, cologne", ru: "духи, парфюм, туалетная вода" },
  lipstick: { emoji: "💄", description: "Lipstick, makeup, cosmetics", ru: "помада, косметика" },
  nail_polish: { emoji: "💅", description: "Nail polish or manicure", ru: "лак для ногтей, маникюр" },
  razor: { emoji: "🪒", description: "Razor or shaver", ru: "бритва" },
  hairdresser: { emoji: "💇", description: "Haircut, hair dryer, hair styler, beauty salon", ru: "стрижка, фен, стайлер, салон красоты" },
  spa_massage: { emoji: "💆", description: "Spa day, massage, massager", ru: "спа, массаж, массажёр" },
  toothbrush: { emoji: "🪥", description: "Toothbrush or electric toothbrush", ru: "зубная щётка" },
  comb: { emoji: "🪮", description: "Comb or hairbrush", ru: "расчёска" },

  // Toys and kids
  teddy_bear: { emoji: "🧸", description: "Teddy bear or plush toy", ru: "плюшевый мишка, мягкая игрушка" },
  doll: { emoji: "🪆", description: "Doll or matryoshka", ru: "кукла, матрёшка" },
  building_blocks: { emoji: "🧱", description: "LEGO or building blocks", ru: "конструктор, лего" },
  puzzle: { emoji: "🧩", description: "Jigsaw puzzle", ru: "пазл" },
  board_game: { emoji: "🎲", description: "Board game or dice", ru: "настольная игра" },
  chess: { emoji: "♟️", description: "Chess or checkers", ru: "шахматы, шашки" },
  toy_car: { emoji: "🏎️", description: "Toy car or remote-control car", ru: "машинка, радиоуправляемая машина" },
  toy_train: { emoji: "🚂", description: "Toy train or railway set", ru: "железная дорога, паровозик" },
  balloon: { emoji: "🎈", description: "Balloons", ru: "воздушные шары" },
  kite: { emoji: "🪁", description: "Kite", ru: "воздушный змей" },
  dinosaur: { emoji: "🦖", description: "Dinosaur toy", ru: "динозавр" },
  unicorn: { emoji: "🦄", description: "Unicorn toy", ru: "единорог" },
  baby_bottle: { emoji: "🍼", description: "Baby items, baby bottle, stroller, diapers", ru: "для малыша, бутылочка, коляска, подгузники" },
  magic_wand: { emoji: "🪄", description: "Magic set or magic wand", ru: "фокусы, волшебная палочка" },
  crayons: { emoji: "🖍️", description: "Crayons, coloring book, kids drawing set", ru: "мелки, раскраска, набор для рисования" },
  art_palette: { emoji: "🎨", description: "Paints, art supplies, painting kit", ru: "краски, набор для творчества" },

  // Books, stationery and learning
  books: { emoji: "📚", description: "Book or books", ru: "книга, книги" },
  notebook: { emoji: "📓", description: "Notebook, diary, planner", ru: "блокнот, ежедневник" },
  pen: { emoji: "🖊️", description: "Pen or stationery", ru: "ручка, канцелярия" },
  greeting_card: { emoji: "💌", description: "Greeting card, postcard or love letter", ru: "открытка, письмо" },
  magazine: { emoji: "📰", description: "Magazine or newspaper subscription", ru: "журнал, подписка на журнал" },
  globe: { emoji: "🌍", description: "Globe or world map", ru: "глобус, карта мира" },
  telescope: { emoji: "🔭", description: "Telescope or binoculars", ru: "телескоп, бинокль" },
  microscope: { emoji: "🔬", description: "Microscope or science kit", ru: "микроскоп, набор юного химика" },
  graduation: { emoji: "🎓", description: "Course, lessons, education or workshop", ru: "курсы, уроки, обучение, мастер-класс" },
  calendar: { emoji: "📅", description: "Calendar", ru: "календарь" },

  // Music
  guitar: { emoji: "🎸", description: "Guitar or ukulele", ru: "гитара, укулеле" },
  piano: { emoji: "🎹", description: "Piano or synthesizer", ru: "пианино, синтезатор" },
  violin: { emoji: "🎻", description: "Violin or cello", ru: "скрипка, виолончель" },
  drum: { emoji: "🥁", description: "Drums", ru: "барабан" },
  trumpet: { emoji: "🎺", description: "Trumpet or brass instrument", ru: "труба" },
  saxophone: { emoji: "🎷", description: "Saxophone", ru: "саксофон" },
  accordion: { emoji: "🪗", description: "Accordion", ru: "аккордеон, баян, гармонь" },
  vinyl_record: { emoji: "💿", description: "Vinyl record, CD or record player", ru: "пластинка, проигрыватель" },
  microphone: { emoji: "🎤", description: "Microphone or karaoke", ru: "микрофон, караоке" },

  // Sport and outdoors
  bicycle: { emoji: "🚲", description: "Bicycle", ru: "велосипед" },
  scooter: { emoji: "🛴", description: "Kick scooter or electric scooter", ru: "самокат" },
  skateboard: { emoji: "🛹", description: "Skateboard", ru: "скейтборд" },
  skis: { emoji: "🎿", description: "Skis", ru: "лыжи" },
  snowboard: { emoji: "🏂", description: "Snowboard", ru: "сноуборд" },
  ice_skates: { emoji: "⛸️", description: "Ice skates", ru: "коньки" },
  roller_skates: { emoji: "🛼", description: "Roller skates", ru: "ролики" },
  sled: { emoji: "🛷", description: "Sled", ru: "санки, ватрушка" },
  fishing: { emoji: "🎣", description: "Fishing rod or fishing gear", ru: "удочка, рыбалка" },
  tent: { emoji: "⛺", description: "Tent or camping gear", ru: "палатка, туризм" },
  dumbbell: { emoji: "🏋️", description: "Dumbbells, gym membership, fitness equipment", ru: "гантели, абонемент в зал, тренажёр" },
  yoga: { emoji: "🧘", description: "Yoga mat or yoga classes", ru: "коврик для йоги, йога" },
  boxing: { emoji: "🥊", description: "Boxing gloves or punching bag", ru: "боксёрские перчатки, груша" },
  soccer_ball: { emoji: "⚽", description: "Football or soccer ball", ru: "футбольный мяч" },
  basketball: { emoji: "🏀", description: "Basketball", ru: "баскетбольный мяч" },
  volleyball: { emoji: "🏐", description: "Volleyball", ru: "волейбольный мяч" },
  tennis: { emoji: "🎾", description: "Tennis racket or balls", ru: "теннисная ракетка" },
  golf: { emoji: "⛳", description: "Golf", ru: "гольф" },
  swimming: { emoji: "🏊", description: "Swimming pool pass or swimming gear", ru: "бассейн, плавание" },
  darts: { emoji: "🎯", description: "Darts", ru: "дартс" },
  bowling: { emoji: "🎳", description: "Bowling", ru: "боулинг" },
  billiards: { emoji: "🎱", description: "Billiards", ru: "бильярд" },
  horse_riding: { emoji: "🏇", description: "Horse riding", ru: "конная прогулка, верховая езда" },
  kayak: { emoji: "🛶", description: "Kayak, canoe or SUP board", ru: "байдарка, каяк, сап-доска" },
  surfing: { emoji: "🏄", description: "Surfing or wakeboarding", ru: "сёрфинг" },
  parachute: { emoji: "🪂", description: "Skydiving or paragliding", ru: "прыжок с парашютом, параплан" },

  // Experiences and travel
  theater: { emoji: "🎭", description: "Theater, opera or ballet", ru: "театр, опера, балет" },
  cinema: { emoji: "🎬", description: "Cinema or movie night", ru: "кино" },
  tickets: { emoji: "🎟️", description: "Tickets to a concert, show or event", ru: "билеты, концерт" },
  circus: { emoji: "🎪", description: "Circus", ru: "цирк" },
  amusement_park: { emoji: "🎢", description: "Amusement park or attractions", ru: "парк аттракционов" },
  museum: { emoji: "🏛️", description: "Museum or exhibition", ru: "музей, выставка" },
  zoo: { emoji: "🦁", description: "Zoo, aquarium or oceanarium visit", ru: "зоопарк, океанариум" },
  airplane: { emoji: "✈️", description: "Flight or plane tickets", ru: "перелёт, авиабилеты" },
  beach_vacation: { emoji: "🏖️", description: "Vacation, holiday trip, beach", ru: "отпуск, путешествие, море" },
  mountains: { emoji: "🏔️", description: "Mountain trip or hiking", ru: "поездка в горы, поход" },
  hotel: { emoji: "🏨", description: "Hotel stay", ru: "отель, гостиница" },
  train_trip: { emoji: "🚆", description: "Train trip", ru: "поездка на поезде" },
  cruise: { emoji: "🚢", description: "Cruise or boat trip", ru: "круиз, прогулка на теплоходе" },
  photo_session: { emoji: "📸", description: "Photo shoot", ru: "фотосессия" },
  party: { emoji: "🥳", description: "Party or celebration", ru: "вечеринка, праздник" },
  fireworks: { emoji: "🎆", description: "Fireworks", ru: "фейерверк, салют" },

  // Money and vouchers
  money: { emoji: "💸", description: "Money, cash, envelope with money", ru: "деньги, наличные, конверт" },
  banknotes: { emoji: "💵", description: "Banknotes or foreign currency", ru: "купюры, валюта" },
  gift_card: { emoji: "💳", description: "Gift card, gift certificate, voucher, bank transfer", ru: "подарочная карта, сертификат, перевод" },
  coins: { emoji: "🪙", description: "Coins, gold or crypto", ru: "монеты, золото, крипта" },
  piggy_bank: { emoji: "🐷", description: "Piggy bank or savings", ru: "копилка" },
  stocks: { emoji: "📈", description: "Stocks or investments", ru: "акции, инвестиции" },

  // Pets
  dog: { emoji: "🐶", description: "Puppy, dog or dog supplies", ru: "щенок, собака" },
  cat: { emoji: "🐱", description: "Kitten, cat or cat supplies", ru: "котёнок, кошка" },
  aquarium_fish: { emoji: "🐠", description: "Aquarium or pet fish", ru: "аквариум, рыбки" },
  bird: { emoji: "🦜", description: "Parrot or pet bird", ru: "попугай" },
  hamster: { emoji: "🐹", description: "Hamster or small pet", ru: "хомяк" },
  rabbit: { emoji: "🐰", description: "Rabbit", ru: "кролик" },
  pet_supplies: { emoji: "🦴", description: "Pet food or pet toys", ru: "корм, игрушки для питомца" },

  // Vehicles
  car: { emoji: "🚗", description: "Car or car accessories", ru: "машина, автомобиль" },
  motorcycle: { emoji: "🏍️", description: "Motorcycle", ru: "мотоцикл" },
  sailboat: { emoji: "⛵", description: "Boat or yacht", ru: "лодка, яхта" },

  // Health
  medicine: { emoji: "💊", description: "Vitamins, medicine or supplements", ru: "витамины, лекарства" },
  first_aid: { emoji: "🩹", description: "First aid kit", ru: "аптечка" },

  // Celebration and miscellaneous
  party_popper: { emoji: "🎉", description: "Party supplies or confetti", ru: "хлопушка, конфетти" },
  lantern: { emoji: "🏮", description: "Lantern or decorative lights, garland", ru: "фонарь, гирлянда" },
  hourglass: { emoji: "⏳", description: "Hourglass", ru: "песочные часы" },
  compass: { emoji: "🧭", description: "Compass", ru: "компас" },
  map: { emoji: "🗺️", description: "Map or travel guide", ru: "карта, путеводитель" },
  heart: { emoji: "❤️", description: "Romantic gift, something made with love", ru: "романтический подарок" },
};

export const ICON_KEYS = Object.keys(ICONS);

/** Jev Choice criteria: option name → description, optionally with Russian hints. */
export function criteria(includeRussianHints: boolean): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, icon] of Object.entries(ICONS)) {
    result[key] = includeRussianHints && icon.ru ? `${icon.description} (${icon.ru})` : icon.description;
  }
  return result;
}
