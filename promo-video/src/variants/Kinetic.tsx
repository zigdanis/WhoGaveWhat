// Variant E, after the App Store previews of Structured, Fantastical, Todoist and YNAB: big kinetic
// type on full-screen brand colour, then the app full bleed with nothing on top. Scenes stack like a
// feed: each one slides up over the last, landing on the beat. At each payoff a card of the real
// screen lifts off it, floats to the middle of the frame and rides on into the next headline.
import {Audio} from '@remotion/media';
import type {CSSProperties} from 'react';
import {fitText} from '@remotion/layout-utils';
import {AbsoluteFill, Easing, Img, interpolate, Sequence, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {EndCard, fontFamily, Logo} from '../components/Brand';
import {Footage, type Tap, type Zoom} from '../components/Footage';
import {Lock} from '../components/Motion';
import {colors, footageFrames, FPS, type Locale, move, pieceStarts, type Segment, win} from '../data';
import tapsJson from '../taps.json';

const T = 12; // frames each scene takes to slide up over the previous one
const BEAT = 16; // frames per beat: music-bright.wav is 112.5 bpm
const PIECE_FADE = 4;
const LIFT_Y = 860; // where a lifted card's centre floats to
const CARRY_Y = 430; // where it rides while the next headline comes in
const CARRY_SHIFT = 140; // how far a headline under a carried card moves down
const END_CARRY_Y = 560; // on the end card the carried row sits higher in a lowered layout
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ease = Easing.bezier(0.7, 0, 0.2, 1);
const taps = tapsJson as Record<string, Tap[]>;
const onBeat = (frame: number) => Math.round(frame / BEAT) * BEAT;

type Bg = 'navy' | 'emerald';
/**
 * A card's lines; the word in *stars* is the accent: coloured and underlined with a drawn stroke.
 * `couplet` splits the lines into two groups: the first dims as the second comes in.
 */
type Card = {lines: string[]; bg: Bg; logo?: boolean; couplet?: number};

export const cards: Record<Locale, {hook: Card; add: Card; both: Card; even: Card; tagline: string}> = {
  en: {
    hook: {
      lines: ['Never forget', 'who gave', '*what*.'],
      bg: 'navy',
      logo: true,
    },
    add: {lines: ['Log a gift', 'in *seconds*.'], bg: 'emerald'},
    both: {
      lines: ['What', 'you gave.', 'What', 'you *got*.'],
      bg: 'navy',
      couplet: 2,
    },
    even: {lines: ['One gift', 'each *way*.'], bg: 'emerald'},
    tagline: 'Every gift, remembered.',
  },
  ru: {
    hook: {
      lines: ['Не забудьте,', 'кто *что*', 'подарил.'],
      bg: 'navy',
      logo: true,
    },
    add: {lines: ['Запишите', 'подарок', 'за *секунды*.'], bg: 'emerald'},
    both: {
      lines: ['Что дарили', 'вы.', 'Что дарили', '*вам*.'],
      bg: 'navy',
      couplet: 2,
    },
    even: {lines: ['Подарок', 'за *подарок*.'], bg: 'emerald'},
    tagline: 'Каждый подарок — на счету.',
  },
};

type Rect = {x: number; y: number; w: number; h: number};
/**
 * A card of the real screen that lifts off at a payoff: image cut by scripts/lift-crops.sh, rect in
 * video px. `burst` is where the confetti starts and `pill` the Even pill that pops there, in the card's own px.
 */
type Lift = Rect & {
  img: string;
  burst?: {x: number; y: number};
  pill?: Rect & {img: string};
};
const LIFTS: Record<Locale, {add: Lift; person: Lift; even: Lift}> = {
  en: {
    add: {img: 'lift/en-row.png', x: 36, y: 446, w: 814, h: 152},
    person: {img: 'lift/en-rows.png', x: 38, y: 1242, w: 808, h: 310},
    even: {
      img: 'lift/en-even.png',
      x: 36,
      y: 566,
      w: 812,
      h: 124,
      burst: {x: 697, y: 37},
      pill: {img: 'lift/en-pill.png', x: 610, y: 9, w: 174, h: 56},
    },
  },
  ru: {
    add: {img: 'lift/ru-row.png', x: 36, y: 446, w: 814, h: 152},
    person: {img: 'lift/ru-rows.png', x: 38, y: 1242, w: 808, h: 310},
    even: {
      img: 'lift/ru-even.png',
      x: 36,
      y: 488,
      w: 812,
      h: 150,
      burst: {x: 664, y: 50},
      pill: {img: 'lift/ru-pill.png', x: 545, y: 23, w: 239, h: 55},
    },
  },
};

/** The money under Grandpa Pavel's Even pill, painted out (row colour): the payoff is one gift each way. */
const MONEY: Record<Locale, Rect> = {
  en: {x: 738, y: 628, w: 104, h: 46},
  ru: {x: 680, y: 566, w: 162, h: 44},
};
/** Centres and sizes of the form's suggested icon and price, video px. */
const ICON = {x: 112, y: 1217, w: 112, h: 112};
const PRICE = {x: 735, y: 1586, w: 170, h: 62};
const FROM = {x: 388, y: 1365, w: 690, h: 104};
/** The English To picker opens with Lena ticked from an earlier take; the tick is painted out (row colour). */
const STALE_TICK = {x: 776, y: 566, w: 46, h: 46};

/** Insights pushes in toward Grandpa Pavel's row before it lifts. */
const INSIGHTS_ZOOM = {scale: 1.1, x: 0.5, y: 0.3};

type Mark = {
  kind: 'pulse' | 'patch';
  rect: Rect;
  from: number;
  to: number;
  color?: string;
};
type AppScene = {
  kind: 'footage';
  segs: Segment[];
  taps: Tap[];
  frames: number;
  lift: Lift;
  liftAt: number;
  zoom: boolean;
  marks: Mark[];
};
type Scene = {kind: 'card'; card: Card; frames: number; carried: boolean} | AppScene | {kind: 'end'; frames: number};

/** Frame of the scene where source second `t` of the recordings plays. */
const frameAt = (segs: Segment[], t: number) => {
  const starts = pieceStarts(segs, PIECE_FADE);
  const i = segs.findIndex((s) => t >= s.from && t < s.to);
  const s = segs[i];
  return Math.round(starts[i] + ((t - s.from) / (s.to - s.from)) * s.dur * FPS);
};

/** The add flow, cut tighter than variant D: Home, the form, From already Anton, To Grandpa Pavel, Save. */
const addSegs = (en: boolean): Segment[] => [
  win('add', 9.95, 10.4, 1, 0), // Home for a beat
  ...move('add', 10.4, 16.2), // tap Add a gift, the form slides up
  en ? win('add', 18.8, 22.6, 4, 3) : win('add', 18.8, 23.0, 4.2, 3), // typing
  en ? win('add', 22.6, 23.1, 1, 0) : win('add', 23.0, 24.25, 2.1, 0), // the icon is in
  en ? win('add', 23.1, 24.05, 1.2, 0) : win('add', 24.25, 25.2, 1.2, 0), // the price appears
  en ? win('add', 51.2, 52.0, 1, 0) : win('add', 50.8, 51.6, 1, 0), // From: Anton; tap To
  en ? win('add', 65.9, 66.3, 1, 0) : win('add', 65.5, 65.9, 1, 0), // the To picker, Grandpa Pavel in view
  ...move('add', en ? 66.3 : 65.9, en ? 70.9 : 70.5), // pick Grandpa Pavel
  en ? win('add', 70.9, 71.25, 1, 0) : win('add', 70.5, 70.85, 1, 0), // the filled form
  ...move('add', en ? 73.2 : 72.8, en ? 77.8 : 77.1), // Save
  en ? win('add', 77.8, 79.1, 1, 0) : win('add', 77.1, 78.4, 1, 0), // the sheet clears, the new row slides in
  en ? win('add', 79.1, 79.5, 0.5, 0) : win('add', 78.4, 78.8, 0.5, 0), // and holds while it lifts
];

export const kineticPlan = (locale: Locale) => {
  const en = locale === 'en';
  const c = cards[locale];
  const lifts = LIFTS[locale];
  const add = addSegs(en);
  const person = [win('person', 16.2, 16.75, 1, 0), ...move('person', 16.75, 21.6), win('person', 22.5, 25.1, 1, 0)];
  const insights = [win('insights', 52.9, 53.9, 0.22, 0)]; // readable for a while before the payoff
  const pulse = (r: Rect, at: number): Mark => ({
    kind: 'pulse',
    rect: {x: r.x - r.w / 2, y: r.y - r.h / 2, w: r.w, h: r.h},
    from: at,
    to: at + 14,
  });
  const addMarks: Mark[] = [
    pulse(ICON, frameAt(add, en ? 22.7 : 23.3)),
    pulse(PRICE, frameAt(add, en ? 23.2 : 24.33)),
    pulse(FROM, frameAt(add, en ? 51.2 : 50.8) + 3), // From fills in on a cut: mark it as filled for you
    ...(en
      ? [
          {
            kind: 'patch' as const,
            rect: STALE_TICK,
            from: frameAt(add, 65.9),
            to: frameAt(add, 66.9),
            color: '#2A2A2D',
          },
        ]
      : []),
  ];
  const footage = (segs: Segment[], clip: string, lift: Lift, liftBeforeEnd: number, marks: Mark[] = [], zoom = false): AppScene => {
    const frames = footageFrames(segs, PIECE_FADE);
    return {
      kind: 'footage',
      segs,
      taps: taps[`${locale}-${clip}`] ?? [],
      frames,
      lift,
      liftAt: frames - liftBeforeEnd,
      zoom,
      marks,
    };
  };
  const scenes: Scene[] = [
    {kind: 'card', card: c.hook, frames: 68, carried: false},
    {kind: 'card', card: c.add, frames: 54, carried: false},
    footage(add, 'add', lifts.add, 30, addMarks),
    {kind: 'card', card: c.both, frames: 76, carried: true},
    footage(person, 'person', lifts.person, 34),
    {kind: 'card', card: c.even, frames: 64, carried: true},
    footage(
      insights,
      'insights',
      lifts.even,
      58,
      [
        {
          kind: 'patch',
          rect: MONEY[locale],
          from: 0,
          to: 9999,
          color: '#1A1A1C',
        },
      ],
      true,
    ),
    {kind: 'end', frames: 104},
  ];
  // Every scene lands (finishes sliding in) on a beat; a footage scene that grows or shrinks to fit
  // holds its last, still piece longer or shorter. Lifts land on beats too.
  const starts: number[] = [0];
  for (let i = 1; i < scenes.length; i++) {
    const prev = scenes[i - 1];
    const start = onBeat(starts[i - 1] + prev.frames) - T;
    const delta = start + T - (starts[i - 1] + prev.frames);
    if (prev.kind === 'footage') {
      const last = prev.segs[prev.segs.length - 1];
      prev.segs = [...prev.segs.slice(0, -1), {...last, dur: last.dur + delta / FPS}];
      prev.liftAt += delta;
    }
    prev.frames += delta;
    starts.push(start);
  }
  scenes.forEach((s, i) => {
    if (s.kind === 'footage') s.liftAt = onBeat(starts[i] + s.liftAt) - starts[i];
  });
  const last = scenes.length - 1;
  const total = starts[last] + scenes[last].frames;
  const evenIndex = scenes.findIndex((s) => s.kind === 'footage' && s.lift.burst);
  const chime = starts[evenIndex] + (scenes[evenIndex] as AppScene).liftAt + BEAT;
  return {scenes, starts, total, tagline: c.tagline, chime};
};

export const Kinetic = ({locale}: {locale: Locale}) => {
  const p = kineticPlan(locale);
  return (
    <AbsoluteFill style={{backgroundColor: colors.navy, fontFamily}}>
      {p.scenes.map((scene, i) => {
        // A lifted card rides above the scene after its own and under the one after that.
        const prev = p.scenes[i - 1];
        return [
          <Sequence key={`s${i}`} from={p.starts[i]} durationInFrames={scene.frames} name={scene.kind}>
            <Slide id={i} enter={i > 0} exit={i < p.scenes.length - 1} frames={scene.frames} sheet={scene.kind === 'footage'}>
              {scene.kind === 'card' && <CardScene card={scene.card} shift={scene.carried ? CARRY_SHIFT : 0} />}
              {scene.kind === 'footage' && <FootageScene scene={scene} locale={locale} />}
              {scene.kind === 'end' && (
                <EndCard locale={locale} privacyIcon={<Lock size={34} />} logoSize={280} drift tagline={p.tagline} shift={CARRY_SHIFT} />
              )}
            </Slide>
            {scene.kind === 'footage' && (
              <Sequence from={scene.liftAt} layout="none">
                <Audio src={staticFile('sfx-pop.wav')} volume={scene.lift.burst ? 0.4 : 0.75} />
              </Sequence>
            )}
          </Sequence>,
          prev?.kind === 'footage' && (
            <LiftLayer
              key={`l${i}`}
              scene={prev}
              start={p.starts[i - 1]}
              carryAt={p.starts[i]}
              carryY={scene.kind === 'end' ? END_CARRY_Y : CARRY_Y}
              exitAt={p.starts[i + 1]}
              total={p.total}
            />
          ),
        ];
      })}
      <Sequence from={p.chime} layout="none">
        <Audio src={staticFile('sfx-chime.wav')} volume={0.9} />
      </Sequence>
      <Audio
        src={staticFile('music-bright.wav')}
        // Full level, a two-beat dip under the "one gift each way" chime, then back in for the end.
        volume={(f) =>
          interpolate(
            f,
            [0, 6, p.chime - 2 * BEAT, p.chime - 2 * BEAT + 6, p.chime, p.chime + 4, p.total - 30, p.total],
            [0, 0.95, 0.95, 0.4, 0.4, 0.95, 0.95, 0],
            clamp,
          )
        }
      />
    </AbsoluteFill>
  );
};

/**
 * Slides a scene up from below over the previous one with a vertical motion blur; app scenes come in
 * as a rounded sheet that grows to full bleed. On its way out a scene drifts up and darkens.
 */
const Slide = ({
  id,
  enter,
  exit,
  frames,
  sheet,
  children,
}: {
  id: number;
  enter: boolean;
  exit: boolean;
  frames: number;
  sheet: boolean;
  children: React.ReactNode;
}) => {
  const frame = useCurrentFrame();
  const inP = enter ? interpolate(frame, [0, T], [0, 1], {...clamp, easing: ease}) : 1;
  const outP = exit
    ? interpolate(frame, [frames - T, frames], [0, 1], {
        ...clamp,
        easing: ease,
      })
    : 0;
  const blur = Math.sin(inP * Math.PI) * 16; // fastest mid-slide
  const filters = [blur > 0.3 ? `url(#vblur-${id})` : '', outP > 0 ? `brightness(${1 - outP * 0.55})` : ''].filter(Boolean).join(' ');
  return (
    <AbsoluteFill
      style={{
        translate: `0 ${(1 - inP) * 1920 - outP * 520}px`,
        scale: sheet ? String(interpolate(inP, [0, 1], [0.94, 1])) : undefined,
        borderRadius: sheet ? interpolate(inP, [0, 1], [64, 0]) : 0,
        filter: filters || undefined,
        overflow: 'hidden',
      }}
    >
      <svg width={0} height={0} style={{position: 'absolute'}}>
        <filter id={`vblur-${id}`} x="-5%" y="-10%" width="110%" height="120%">
          <feGaussianBlur stdDeviation={`0 ${blur.toFixed(2)}`} />
        </filter>
      </svg>
      {children}
    </AbsoluteFill>
  );
};

/** Big words on brand colour, rising in one by one; the accent word gets a drawn underline. */
const CardScene = ({card, shift}: {card: Card; shift: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const navy = card.bg === 'navy';
  // Each line is fitted to the column on its own, so short lines ("What", «вам.») go huge.
  const sizes = card.lines.map((l) =>
    Math.min(
      210,
      Math.floor(
        fitText({
          text: l.replace(/\*/g, ''),
          withinWidth: 728,
          fontFamily,
          fontWeight: 800,
          letterSpacing: '-0.035em',
        }).fontSize,
      ),
    ),
  );
  const accent = navy ? colors.emeraldGlow : colors.navy;
  const start = card.logo ? 1 : shift ? 8 : 3;
  const wordAt: number[][] = [];
  let n = 0;
  card.lines.forEach((line, li) => (wordAt[li] = line.split(' ').map(() => start + n++ * 4)));
  const dim = card.couplet ? interpolate(frame, [wordAt[card.couplet][0], wordAt[card.couplet][0] + 8], [1, 0.45], clamp) : 1;
  return (
    <AbsoluteFill
      style={{
        background: navy
          ? `radial-gradient(ellipse 90% 60% at 20% 30%, rgba(32,169,113,0.22) 0%, rgba(0,0,0,0) 65%), linear-gradient(180deg, ${colors.navy} 0%, ${colors.navyDeep} 100%)`
          : `radial-gradient(ellipse 90% 60% at 80% 70%, rgba(255,255,255,0.18) 0%, rgba(0,0,0,0) 65%), linear-gradient(180deg, #23B479 0%, #1A925F 100%)`,
      }}
    >
      <DriftingMarks navy={navy} />
      <div
        style={{
          position: 'absolute',
          left: 72,
          right: 60,
          top: shift,
          bottom: 0,
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          paddingBottom: 60,
        }}
      >
        {card.logo && (
          <div style={{marginBottom: 54, marginLeft: -6}}>
            <Logo size={150} delay={-30} />
          </div>
        )}
        {card.lines.map((line, li) => {
          const size = sizes[li];
          return (
            <div
              key={li}
              style={{
                fontSize: size,
                fontWeight: 800,
                letterSpacing: '-0.035em',
                lineHeight: 1.04,
                color: colors.white,
                whiteSpace: 'nowrap',
                opacity: card.couplet && li < card.couplet ? dim : 1,
              }}
            >
              {line.split(' ').map((raw, wi) => {
                const isAccent = raw.startsWith('*');
                const word = raw.replace(/\*/g, '');
                const at = wordAt[li][wi];
                const s = spring({
                  frame: frame - at,
                  fps,
                  config: {damping: 18, mass: 0.7},
                });
                const o = interpolate(frame - at, [0, 6], [0, 1], clamp);
                return (
                  <span
                    key={wi}
                    style={{
                      display: 'inline-block',
                      position: 'relative',
                      marginRight: '0.24em',
                      opacity: o,
                      translate: `0 ${interpolate(s, [0, 1], [0.55 * size, 0])}px`,
                      filter: o < 1 ? `blur(${interpolate(o, [0, 1], [10, 0])}px)` : undefined,
                      color: isAccent ? accent : undefined,
                    }}
                  >
                    {isAccent ? <Accent word={word} at={at + 8} color={accent} /> : word}
                  </span>
                );
              })}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

/** The accent word with a hand-drawn stroke under it, drawn left to right. Punctuation stays white. */
const Accent = ({word, at, color}: {word: string; at: number; color: string}) => {
  const frame = useCurrentFrame();
  const m = word.match(/^(.*?)([.,!?…]*)$/)!;
  const draw = interpolate(frame - at, [0, 10], [0, 1], {
    ...clamp,
    easing: Easing.out(Easing.cubic),
  });
  return (
    <>
      <span style={{position: 'relative', display: 'inline-block'}}>
        {m[1]}
        <svg
          viewBox="0 0 200 26"
          preserveAspectRatio="none"
          style={{
            position: 'absolute',
            left: '-2%',
            bottom: '-0.16em',
            width: '104%',
            height: '0.22em',
            overflow: 'visible',
          }}
        >
          <path
            d="M3 17 C 52 7, 120 3, 197 11"
            fill="none"
            stroke={color}
            strokeWidth={14}
            strokeLinecap="round"
            pathLength={1}
            strokeDasharray={1}
            strokeDashoffset={1 - draw}
          />
        </svg>
      </span>
      <span style={{color: colors.white}}>{m[2]}</span>
    </>
  );
};

/** Large faint logo triangles drifting behind the words: the brand mark as texture. */
const DriftingMarks = ({navy}: {navy: boolean}) => {
  const frame = useCurrentFrame();
  const up = navy ? 'rgba(255,255,255,0.045)' : 'rgba(255,255,255,0.14)';
  const down = navy ? 'rgba(61,211,154,0.10)' : 'rgba(18,22,28,0.10)';
  const tri = (pts: string, fill: string, style: CSSProperties) => (
    <svg width={900} height={900} viewBox="0 0 600 600" style={{position: 'absolute', ...style}}>
      <polygon points={pts} fill={fill} />
    </svg>
  );
  return (
    <AbsoluteFill>
      {tri('20,420 580,420 300,40', up, {
        left: 260,
        top: -260,
        rotate: `${-8 + frame * 0.08}deg`,
        translate: `0 ${frame * 0.6}px`,
      })}
      {tri('20,140 580,140 300,520', down, {
        left: -380,
        top: 1180,
        rotate: `${10 - frame * 0.06}deg`,
        translate: `0 ${-frame * 0.5}px`,
      })}
    </AbsoluteFill>
  );
};

/** Footage zoom of a scene at its frame, as Footage applies it. */
const zoomOf = (scene: AppScene): Zoom | undefined =>
  scene.zoom
    ? (fr) => ({
        scale: interpolate(fr, [0, scene.liftAt], [1, INSIGHTS_ZOOM.scale], {
          ...clamp,
          easing: Easing.inOut(Easing.quad),
        }),
        x: INSIGHTS_ZOOM.x,
        y: INSIGHTS_ZOOM.y,
      })
    : undefined;

/**
 * The app full bleed, with its pulses and patches. At `liftAt` an empty slot opens where the payoff
 * card was (the card itself is drawn by LiftLayer); the screen dims, softens and glows emerald behind it.
 */
const FootageScene = ({scene, locale}: {scene: AppScene; locale: Locale}) => {
  const frame = useCurrentFrame();
  const f = frame - scene.liftAt;
  const dim = interpolate(f, [0, 12], [0, 1], {
    ...clamp,
    easing: Easing.out(Easing.quad),
  });
  const {lift} = scene;
  const ring = interpolate(f, [-10, -6, 0, 3], [0, 1, 1, 0], clamp);
  return (
    <AbsoluteFill style={{backgroundColor: colors.navyDeep}}>
      <Footage
        segs={scene.segs}
        theme="story"
        locale={locale}
        overlap={PIECE_FADE}
        taps={scene.taps}
        zoom={zoomOf(scene)}
        style={{
          filter: dim > 0 ? `blur(${dim * 18}px) brightness(${1 - dim * 0.38})` : undefined,
          scale: String(1 + dim * 0.04),
        }}
      >
        {scene.marks.map((m, i) => (frame >= m.from && frame < m.to ? <MarkView key={i} mark={m} frame={frame} /> : null))}
        {scene.zoom && ring > 0 && (
          <div
            style={{
              position: 'absolute',
              left: lift.x - 6,
              top: lift.y - 6,
              width: lift.w + 12,
              height: lift.h + 12,
              borderRadius: 34,
              border: `4px solid ${colors.emeraldGlow}`,
              opacity: ring,
            }}
          />
        )}
        {f >= 0 && (
          <div
            style={{
              position: 'absolute',
              left: lift.x,
              top: lift.y,
              width: lift.w,
              height: lift.h,
              borderRadius: 30,
              backgroundColor: '#0B0B0D',
              opacity: interpolate(f, [0, 3], [0, 1], clamp),
            }}
          />
        )}
      </Footage>
      <AbsoluteFill
        style={{
          opacity: dim,
          background: `radial-gradient(ellipse 95% 34% at 50% ${LIFT_Y}px, rgba(32,169,113,0.5), rgba(32,169,113,0) 70%)`,
        }}
      />
    </AbsoluteFill>
  );
};

const MarkView = ({mark, frame}: {mark: Mark; frame: number}) => {
  const {rect} = mark;
  if (mark.kind === 'patch') {
    return (
      <div
        style={{
          position: 'absolute',
          left: rect.x,
          top: rect.y,
          width: rect.w,
          height: rect.h,
          borderRadius: 10,
          backgroundColor: mark.color,
        }}
      />
    );
  }
  const t = frame - mark.from;
  return (
    <div
      style={{
        position: 'absolute',
        left: rect.x,
        top: rect.y,
        width: rect.w,
        height: rect.h,
        borderRadius: 26,
        border: `3px solid ${colors.emeraldGlow}`,
        boxShadow: `0 0 24px rgba(61,211,154,0.5)`,
        opacity: interpolate(t, [0, 4, 9, 14], [0, 1, 1, 0], clamp),
        scale: String(
          interpolate(t, [0, 14], [1, 1.15], {
            ...clamp,
            easing: Easing.out(Easing.quad),
          }),
        ),
      }}
    />
  );
};

/**
 * The lifted card, above the footage and the headline after it. It leaves the screen where it sat
 * (zoomed with the footage), floats to the middle of the frame tilting and catching a sweep of light,
 * then rides up to make room as the next headline slides in, and leaves with that headline.
 */
const LiftLayer = ({
  scene,
  start,
  carryAt,
  carryY,
  exitAt,
  total,
}: {
  scene: AppScene;
  start: number;
  carryAt: number;
  carryY: number;
  exitAt?: number;
  total: number;
}) => {
  const from = start + scene.liftAt;
  const until = exitAt === undefined ? total : exitAt + T;
  return (
    <Sequence from={from} durationInFrames={until - from} name="lift" layout="none">
      <LiftCard scene={scene} carry={carryAt - from} carryY={carryY} exit={exitAt === undefined ? undefined : exitAt - from} />
    </Sequence>
  );
};

const LiftCard = ({scene, carry, carryY, exit}: {scene: AppScene; carry: number; carryY: number; exit?: number}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const {lift} = scene;
  // Where the card sits on screen when it leaves: the footage may be zoomed in by then.
  const z = zoomOf(scene)?.(scene.liftAt) ?? {scale: 1, x: 0.5, y: 0.5};
  const ox = z.x * 886;
  const oy = z.y * 1920;
  const cx = ox + (lift.x + lift.w / 2 - ox) * z.scale;
  const cy = oy + (lift.y + lift.h / 2 - oy) * z.scale;
  const s = spring({frame: f, fps, config: {damping: 15, mass: 1}});
  const c = interpolate(f, [carry, carry + T], [0, 1], {
    ...clamp,
    easing: ease,
  });
  const out = exit === undefined ? 0 : interpolate(f, [exit, exit + T], [0, 1], {...clamp, easing: ease});
  const sway = f > 0 ? Math.sin(f / 18) * (1 - c * 0.7) : 0;
  const tilt = interpolate(s, [0, 0.5, 1], [0, 16, 4], clamp) * (1 - c);
  const y = cy + (LIFT_Y - cy) * s + (carryY - LIFT_Y) * c - 520 * out;
  const scale = interpolate(s, [0, 1], [z.scale, 1.07]) + (1 - 1.07) * c;
  // One sweep of light as it lifts, another as the headline's accent word is underlined.
  const sweepAt = f < carry ? 6 : carry + 26;
  const sweep = interpolate(f, [sweepAt, sweepAt + 14], [-260, lift.w + 260], {
    ...clamp,
    easing: Easing.inOut(Easing.quad),
  });
  const pop = interpolate(f - BEAT, [0, 5, 14], [1, 1.45, 1.3], {
    ...clamp,
    easing: Easing.out(Easing.quad),
  });
  return (
    <div
      style={{
        position: 'absolute',
        left: cx - lift.w / 2,
        top: y - lift.h / 2,
        width: lift.w,
        height: lift.h,
        transformOrigin: '50% 50%',
        transform: `perspective(1600px) scale(${scale}) rotateX(${tilt + sway * 0.75}deg) rotateY(${sway * 1.5}deg)`,
        filter: out > 0 ? `brightness(${1 - out * 0.55})` : undefined,
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 0,
          borderRadius: 30,
          overflow: 'hidden',
          backgroundColor: '#1A1A1C',
          boxShadow: [
            `0 ${interpolate(s, [0, 1], [0, 50])}px ${interpolate(s, [0, 1], [0, 100])}px rgba(0,0,0,${interpolate(s, [0, 1], [0, 0.7], clamp)})`,
            `0 0 0 ${interpolate(s, [0, 1], [0, 3], clamp)}px rgba(61,211,154,0.7)`,
            `0 0 ${interpolate(s, [0, 1], [0, 60], clamp)}px rgba(61,211,154,0.35)`,
          ].join(', '),
        }}
      >
        <Img src={staticFile(lift.img)} style={{width: '100%', height: '100%', display: 'block'}} />
        <div
          style={{
            position: 'absolute',
            top: -80,
            bottom: -80,
            left: sweep,
            width: 120,
            rotate: '20deg',
            background: 'linear-gradient(90deg, rgba(255,255,255,0) 0%, rgba(255,255,255,0.18) 50%, rgba(255,255,255,0) 100%)',
          }}
        />
      </div>
      {lift.pill && (
        <div
          style={{
            position: 'absolute',
            left: lift.pill.x,
            top: lift.pill.y,
            width: lift.pill.w,
            height: lift.pill.h,
            borderRadius: lift.pill.h / 2,
            overflow: 'hidden',
            transformOrigin: '100% 50%',
            scale: String(pop),
            boxShadow: pop > 1 ? `0 8px 24px rgba(0,0,0,0.5)` : undefined,
          }}
        >
          <Img src={staticFile(lift.pill.img)} style={{width: '100%', height: '100%', display: 'block'}} />
        </div>
      )}
      {lift.burst && <Burst x={lift.burst.x} y={lift.burst.y} at={BEAT} />}
    </div>
  );
};

/** A burst of logo triangles, white and emerald, from the Even pill, with a ring going out under it. */
const Burst = ({x, y, at}: {x: number; y: number; at: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const t = (frame - at) / fps;
  if (t < 0) return null;
  const rnd = (i: number, k: number) => {
    const v = Math.sin(i * 127.1 + k * 311.7) * 43758.5453;
    return v - Math.floor(v);
  };
  const ringP = interpolate(frame - at, [0, 14], [0, 1], {
    ...clamp,
    easing: Easing.out(Easing.cubic),
  });
  return (
    <svg
      width={800}
      height={800}
      viewBox="-400 -400 800 800"
      style={{
        position: 'absolute',
        left: x - 400,
        top: y - 400,
        overflow: 'visible',
        pointerEvents: 'none',
      }}
    >
      {ringP < 1 && <circle r={20 + 200 * ringP} fill="none" stroke={colors.emeraldGlow} strokeWidth={4 * (1 - ringP)} opacity={0.8 * (1 - ringP)} />}
      {Array.from({length: 34}, (_, i) => {
        // Upward and outward only, so nothing crosses the row's text.
        const angle = -Math.PI * (0.06 + 0.66 * (i / 33)) + (rnd(i, 1) - 0.5) * 0.2;
        const reach = 240 + rnd(i, 2) * 180;
        const d = 70 + (reach - 70) * Easing.out(Easing.cubic)(Math.min(1, t / 0.6));
        const size = (14 + rnd(i, 3) * 12) / 2;
        const up = i % 2 === 0;
        const op = interpolate(t, [0, 0.04, 0.85, 1.2], [0, 1, 1, 0], clamp);
        return (
          <polygon
            key={i}
            points={up ? `${-size},${size * 0.6} ${size},${size * 0.6} 0,${-size * 0.75}` : `${-size},${-size * 0.6} ${size},${-size * 0.6} 0,${size * 0.75}`}
            fill={up ? colors.white : colors.emeraldGlow}
            opacity={op}
            transform={`translate(${Math.cos(angle) * d} ${Math.sin(angle) * d * 0.8 + 60 * t * t}) rotate(${(rnd(i, 4) - 0.5) * 360 * t})`}
          />
        );
      })}
    </svg>
  );
};
