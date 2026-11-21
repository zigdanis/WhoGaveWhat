// Footage cut points and copy for every variant. Times are seconds in the source clips that
// capture/record.sh recorded; `dur` is how long the piece lasts in the video, so the playback
// rate is (to - from) / dur.

export type Locale = 'en' | 'ru';
/** `slow` is the dark theme recorded with the Simulator's slow animations on (UI transitions ~4-5x slower). */
export type Theme = 'dark' | 'light' | 'slow' | 'story';
export type Clip = 'home' | 'add' | 'person' | 'insights';

export type Segment = {
  clip: Clip;
  from: number;
  to: number;
  dur: number;
  /** Frames this piece crossfades over the previous one; 0 is a hard cut (for cuts on a still screen). */
  fade?: number;
};

/** A piece played at `rate` (1 = real time). */
export const win = (clip: Clip, from: number, to: number, rate = 1, fade?: number): Segment => ({
  clip,
  from,
  to,
  dur: (to - from) / rate,
  fade,
});

export const FPS = 30;
export const WIDTH = 886;
export const HEIGHT = 1920;
/** Source footage: iPhone 17 Pro screen. */
export const SRC_W = 1206;
export const SRC_H = 2622;

export const footageSrc = (theme: Theme, locale: Locale, clip: Clip) =>
  `footage/${theme}/${locale}-${clip}.mp4`;

/** Where things happen in each recording; English and Russian differ because typing takes longer. */
const cuts: Record<Locale, Record<string, [number, number]>> = {
  en: {
    home: [1.3, 8.8],
    addOpen: [5.75, 7.1],
    typing: [8.9, 14.5],
    pick: [16.5, 30.4],
    person: [3.9, 11.4],
    insights: [2.0, 10.0],
  },
  ru: {
    home: [1.3, 8.8],
    addOpen: [2.65, 4.05],
    typing: [5.8, 13.2],
    pick: [14.6, 29.4],
    person: [3.9, 11.4],
    insights: [2.0, 10.0],
  },
};

const seg = (locale: Locale, key: string, clip: Clip, dur: number): Segment => ({
  clip,
  from: cuts[locale][key][0],
  to: cuts[locale][key][1],
  dur,
});

/** The app tour shared by the variants: Home, adding a gift, a person's history, Insights. */
export const tour = (locale: Locale, pace: 'calm' | 'fast') => {
  const k = pace === 'fast' ? 0.84 : 1;
  return {
    home: [seg(locale, 'home', 'home', 4.6 * k)],
    add: [
      seg(locale, 'addOpen', 'add', 1.2),
      seg(locale, 'typing', 'add', 3.6 * k),
      seg(locale, 'pick', 'add', 7.0 * k),
    ],
    person: [seg(locale, 'person', 'person', 5.0 * k)],
    insights: [seg(locale, 'insights', 'insights', 5.0 * k)],
  };
};

export const appName: Record<Locale, string> = {
  en: 'Who Gave What',
  ru: 'Кто Че Подарил',
};

type Copy = {
  home: string;
  addOpen: string;
  typing: string;
  pick: string;
  person: string;
  insights: string;
  tagline: string;
  privacy: string;
  hook1: string;
  hook2: string;
  storyAdd: string;
  storyPerson: string;
  storyInsights: string;
  showcaseIntro: string;
  storyWatch: string;
  storyBack: string;
  storyGrandpa: string;
  storySuggest: string;
  storyEach: string;
};

export const copy: Record<Locale, Copy> = {
  en: {
    home: 'Every gift, given and received',
    addOpen: 'Log a gift in seconds',
    typing: 'The icon and price fill in for you',
    pick: 'Choose who gave it and who got it',
    person: 'A gift history with everyone',
    insights: 'See how giving balances out',
    tagline: 'Now you’re the one with the best memory in the family',
    privacy: 'No account · No ads · No tracking',
    hook1: 'Who gave you that watch?',
    hook2: 'And what did you give back?',
    storyAdd: 'Write it down in seconds',
    storyPerson: 'Everyone gets a history',
    storyInsights: 'See who’s even',
    showcaseIntro: 'Remember who gave you what',
    storyWatch: 'Every gift is written down',
    storyBack: 'And what you gave back',
    storyGrandpa: 'Gifts with Grandpa',
    storySuggest: 'Icon and price suggested',
    storyEach: 'One gift each way',
  },
  ru: {
    home: 'Все подарки: подаренные и полученные',
    addOpen: 'Запишите подарок за секунды',
    typing: 'Значок и цена подставятся сами',
    pick: 'Выберите, кто подарил и кому',
    person: 'История подарков с каждым',
    insights: 'Баланс подарков как на ладони',
    tagline: 'Теперь самая хорошая память в семье — у вас',
    privacy: 'Без аккаунта · Без рекламы · Без слежки',
    hook1: 'Кто подарил вам эти часы?',
    hook2: 'А что вы подарили в\u00A0ответ?',
    storyAdd: 'Запишите за секунды',
    storyPerson: 'У каждого своя история',
    storyInsights: 'Видно, где поровну',
    showcaseIntro: 'Помните, кто что подарил',
    storyWatch: 'Каждый подарок записан',
    storyBack: 'И что подарили в\u00A0ответ',
    storyGrandpa: 'Подарки с\u00A0дедушкой',
    storySuggest: 'Значок и цена — автоматически',
    storyEach: 'По одному подарку друг другу',
  },
};

export const colors = {
  navy: '#12161C',
  navyDeep: '#0B0E13',
  emerald: '#20A971',
  emeraldGlow: '#3DD39A',
  white: '#FFFFFF',
  muted: 'rgba(255,255,255,0.68)',
};

/** Frames of a segment list laid end to end with `overlap` frames of crossfade between pieces. */
export const segmentFrames = (segs: Segment[], overlap: number) =>
  segs.reduce((sum, s, i) => sum + Math.round(s.dur * FPS) - (i > 0 ? overlap : 0), 0);

/** Total frames of a segment list as Footage lays it out. */
export const footageFrames = (segs: Segment[], overlap: number) =>
  segs.reduce((sum, s, i) => sum + Math.round(s.dur * FPS) - (i === 0 ? 0 : (s.fade ?? overlap)), 0);

/**
 * Speed-ramped pieces for variant D, cut around the taps that the recordings logged
 * (public/footage/telemetry). UI animations play in real time; typing runs faster and the
 * still screen between taps is cut on a hard cut, so the cut does not show.
 */
export const rampedTour = (locale: Locale) => {
  const en = locale === 'en';
  const addTaps = en ? [17.4, 19.5, 21.7, 23.9, 25.9, 28.6] : [16.2, 18.3, 20.6, 22.8, 24.8, 27.5];
  const pick = addTaps.slice(0, 5).map((t) => win('add', t - 0.15, t + 0.8, 1, 3));
  const save = win('add', addTaps[5] - 0.15, addTaps[5] + 1.45, 1, 3);
  // Still form with the suggested icon and price, held (slowed) for the callout.
  const hold = en ? win('add', 16.6, 17.25, 0.5, 8) : win('add', 15.4, 16.05, 0.5, 8);
  pick[0] = {...pick[0], fade: 0, from: hold.to};
  pick[0].dur = pick[0].to - pick[0].from;
  const add = [
    en ? win('add', 5.75, 7.1) : win('add', 2.65, 4.05),
    en ? win('add', 8.9, 14.55, 1.5, 6) : win('add', 5.8, 13.2, 1.9, 6),
    hold,
    ...pick,
    save,
  ];
  const personTaps = en ? [4.4, 7.5, 9.9] : [4.4, 7.4, 9.8];
  const person = [
    win('person', personTaps[0] - 0.15, personTaps[0] + 0.95),
    win('person', personTaps[1] - 0.15, personTaps[1] + 0.75, 1, 3),
    win('person', personTaps[2] - 0.15, personTaps[2] + 0.85, 1, 3),
  ];
  const scrollAt = en ? 5.7 : 5.6;
  const insights = [win('insights', 2.2, 3.6), win('insights', scrollAt - 0.1, scrollAt + 2.0, 1, 3)];
  return {add, person, insights, holdIndex: 2};
};

/**
 * One UI transition from the slow-animation recordings: the first `split` of it plays at `slow`
 * (slower than real life), the settling tail at `fast`. The first piece crossfades in over `fade` frames.
 */
const ramp = (clip: Clip, from: number, to: number, fade = 3, split = 0.7, slow = 2.8, fast = 7): Segment[] => {
  const mid = from + (to - from) * split;
  return [win(clip, from, mid, slow, fade), win(clip, mid, to, fast, 0)];
};

/**
 * Variant D's app tour cut from the slow-animation recordings (public/footage/slow). Tap times come from
 * the recordings' telemetry and the motion spans from scripts/motion-spans.py; the still screen between
 * transitions is cut out on hard cuts, typing runs faster than real time.
 */
export const slowTour = (locale: Locale) => {
  const en = locale === 'en';
  const add = en
    ? [
        ...ramp('add', 10.4, 16.2, 0),
        win('add', 18.8, 24.2, 1.9, 4),
        win('add', 24.2, 25.6, 1, 0), // icon and price appear and hold
        ...ramp('add', 37.9, 43.3),
        ...ramp('add', 45.25, 48.7),
        ...ramp('add', 52.3, 57.8),
        ...ramp('add', 59.7, 63.9),
        ...ramp('add', 66.6, 69.5),
        ...ramp('add', 76.45, 81.5),
        win('add', 81.5, 82.3, 1, 0),
      ]
    : [
        ...ramp('add', 10.4, 16.3, 0),
        win('add', 18.8, 25.7, 2.2, 4),
        win('add', 25.7, 27.1, 1, 0),
        ...ramp('add', 39.7, 45.5),
        ...ramp('add', 47.1, 50.8),
        ...ramp('add', 54.2, 59.6),
        ...ramp('add', 61.6, 65.9),
        ...ramp('add', 68.5, 71.3),
        ...ramp('add', 78.4, 83.3),
        win('add', 83.3, 84.1, 1, 0),
      ];
  const person = [
    ...ramp('person', 16.7, en ? 21.7 : 21.8, 0),
    win('person', en ? 21.7 : 21.8, en ? 22.3 : 22.4, 1, 0),
    ...ramp('person', 28.6, en ? 33.1 : 33.2),
  ];
  const insights = [
    ...ramp('insights', 9.4, 13.0, 0),
    win('insights', 13.0, 13.8, 1, 0),
    ...ramp('insights', 24.3, 27.5),
    win('insights', 27.5, 28.3, 1, 0),
  ];
  return {add, person, insights, holdIndex: 3, calloutDelay: en ? 9 : 2};
};

/** Frame where each piece starts when Footage lays the list out. */
export const pieceStarts = (segs: Segment[], overlap: number) => {
  const starts: number[] = [];
  let at = 0;
  segs.forEach((s, i) => {
    const from = i === 0 ? 0 : at - (s.fade ?? overlap);
    starts.push(from);
    at = from + Math.round(s.dur * FPS);
  });
  return starts;
};

/** A transition of the slow-animation footage: its first 65% slower than real life, the tail quick. */
export const move = (clip: Clip, from: number, to: number, fade = 0): Segment[] => {
  const mid = from + (to - from) * 0.65;
  return [win(clip, from, mid, 3.5, fade), win(clip, mid, to, 9, 0)];
};

/**
 * Variant D's tour from public/footage/story (slow animations; You give Grandpa Pavel a scarf back).
 * Times come from the recordings' tap telemetry (src/taps.json) and scripts/motion-spans.py. Still
 * screens between transitions are cut on hard cuts; holds give the viewer time to read.
 */
export const storyTour = (locale: Locale) => {
  const en = locale === 'en';
  const add: Segment[] = [
    win('add', 4.0, 5.4, 0.74, 0), // Home with Grandpa's watch, ringed
    ...move('add', 10.4, 16.2), // tap Add a gift, the form slides up
    en ? win('add', 18.8, 22.6, 2.8, 3) : win('add', 18.8, 23.0, 3.0, 3), // typing
    en ? win('add', 22.6, 23.1, 1, 0) : win('add', 23.0, 24.25, 2.1, 0), // the icon is in
    en ? win('add', 23.1, 24.05, 0.7, 0) : win('add', 24.25, 25.2, 0.7, 0), // the price appears and holds
    en ? win('add', 65.9, 66.3, 1, 0) : win('add', 65.5, 65.9, 1, 0), // straight to the To picker, Grandpa Pavel in view
    ...move('add', en ? 66.3 : 65.9, en ? 70.9 : 70.5), // pick Grandpa Pavel
    en ? win('add', 70.9, 71.6, 1, 0) : win('add', 70.5, 71.2, 1, 0), // the filled form: Anton → Grandpa Pavel
    ...move('add', en ? 73.2 : 72.8, en ? 77.8 : 77.1), // Save
    en ? win('add', 77.8, 79.1, 1, 0) : win('add', 77.1, 78.4, 1, 0), // the new row, ringed
  ];
  const person: Segment[] = [
    win('person', 16.3, 16.75, 1, 0), // People list, where the drawn avatars land
    ...move('person', 16.75, 21.6), // open Grandpa Pavel
    win('person', 22.5, 24.3, 1, 0), // the scarf and the watch together
  ];
  const insights: Segment[] = [win('insights', 52.9, 53.9, 0.38, 0)]; // Grandpa Pavel even, one gift each way
  return {
    add,
    person,
    insights,
    watchHold: 0,
    suggestHold: 4, // and the next piece
    newRow: add.length - 1,
    priceAt: en ? 23.17 : 24.3,
    personHold: person.length - 1,
    formHold: add.length - 4, // the filled form before Save
  };
};
