import {copy, FPS, type Locale, type Segment, tour} from './data';

export type Variant = 'clean' | 'showcase' | 'story';

export type Cue = {from: number; dur: number; text: string; key: string};

export type Plan = {
  /** Footage pieces in order (laid end to end with OVERLAP frames of crossfade). */
  segs: Segment[];
  /** Frame where the footage starts. */
  footageStart: number;
  footageFrames: number;
  /** Captions in composition frames. */
  cues: Cue[];
  endStart: number;
  endFrames: number;
  total: number;
  /** Frames (relative to the footage) of the typing piece, for the showcase zoom. */
  typing: {from: number; to: number};
};

export const OVERLAP = 6;
const END_FRAMES = Math.round(3.2 * FPS);
const END_OVERLAP = 10;

export const plan = (variant: Variant, locale: Locale): Plan => {
  const t = tour(locale, variant === 'story' ? 'fast' : 'calm');
  const c = copy[locale];
  const footageStart = variant === 'story' ? Math.round(2.7 * FPS) : 0;
  const segs = [...t.home, ...t.add, ...t.person, ...t.insights];
  if (variant === 'story') segs.shift(); // the hook already shows Home

  // Start frame of each piece within the footage.
  const starts: number[] = [];
  let at = 0;
  segs.forEach((s, i) => {
    const from = i === 0 ? 0 : at - OVERLAP;
    starts.push(from);
    at = from + Math.round(s.dur * FPS);
  });
  const footageFrames = at;
  const idx = (s: Segment) => segs.indexOf(s);
  const startOf = (s: Segment) => footageStart + starts[idx(s)];
  const endOf = (s: Segment) => startOf(s) + Math.round(s.dur * FPS);

  const cue = (key: string, text: string, from: number, to: number): Cue => ({key, text, from, dur: to - from});
  const [open, typing, pick] = t.add;
  let cues: Cue[];
  if (variant === 'story') {
    cues = [
      cue('hook1', c.hook1, 4, Math.round(1.35 * FPS)),
      cue('hook2', c.hook2, Math.round(1.35 * FPS), footageStart + 4),
      cue('add', c.storyAdd, startOf(open), endOf(pick)),
      cue('person', c.storyPerson, startOf(t.person[0]), endOf(t.person[0])),
      cue('insights', c.storyInsights, startOf(t.insights[0]), endOf(t.insights[0])),
    ];
  } else {
    cues = [
      cue('home', variant === 'showcase' ? c.showcaseIntro : c.home, 0, endOf(t.home[0])),
      cue('addOpen', c.addOpen, startOf(open), startOf(typing) + 4),
      cue('typing', c.typing, startOf(typing) + 4, startOf(pick) + 4),
      cue('pick', c.pick, startOf(pick) + 4, endOf(pick)),
      cue('person', c.person, startOf(t.person[0]), endOf(t.person[0])),
      cue('insights', c.insights, startOf(t.insights[0]), endOf(t.insights[0])),
    ];
  }
  const endStart = footageStart + footageFrames - END_OVERLAP;
  return {
    segs,
    footageStart,
    footageFrames,
    cues,
    endStart,
    endFrames: END_FRAMES,
    total: endStart + END_FRAMES,
    typing: {from: starts[idx(typing)], to: starts[idx(typing)] + Math.round(typing.dur * FPS)},
  };
};
