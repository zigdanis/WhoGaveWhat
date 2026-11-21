import {Audio} from '@remotion/media';
import {AbsoluteFill, Easing, interpolate, Sequence, staticFile, useCurrentFrame} from 'remotion';
import {BrandBackground, EndCard, FadeBlock, RiseText} from '../components/Brand';
import {Footage, type Tap} from '../components/Footage';
import {AMBER, EvenBadge, GRANDPA_ROW, HighlightRect, HookScene, Lock, NetworkScene, ScaleScene, SuggestCallout} from '../components/Motion';
import {colors, copy, footageFrames, FPS, type Locale, pieceStarts, type Segment, storyTour} from '../data';
import tapsJson from '../taps.json';
import {Music, fontFamily} from './Clean';

const PIECE_FADE = 4;
const OUT = 6; // frames an app scene fades to navy before a drawn scene
const HANDOVER = 6; // frames the People list fades in over the network's landed avatars
const UNDER_FLIGHT = 10; // frames Insights starts under the flying Even badge

type Overlay = {from: number; frames: number; node: React.ReactNode};
/** A slow push-in on a hold: scale 1 → peak over [from, to], back to 1 over the last 8 frames unless it ends the scene. */
type Push = {from: number; to: number; peak: number; x: number; y: number; settle?: boolean};
type Band = 'top' | 'bottom';
type Scene =
  | {kind: 'hook' | 'network' | 'scale' | 'end'; frames: number}
  | {kind: 'footage'; segs: Segment[]; frames: number; taps: Tap[]; reveal?: boolean; band: Band; overlays: Overlay[]; pushes: Push[]};
type Cue = {key: string; text: string; from: number; to: number; band: Band};

const taps = tapsJson as Record<string, Tap[]>;
const sec = (s: number) => Math.round(s * FPS);
const rate = (s: Segment) => (s.to - s.from) / s.dur;

/** Builds variant D's scenes, overlays and captions for one language. Scenes play back to back. */
export const motionPlan = (locale: Locale) => {
  const t = storyTour(locale);
  const c = copy[locale];
  const addStarts = pieceStarts(t.add, PIECE_FADE);
  const personStarts = pieceStarts(t.person, PIECE_FADE);
  const len = (s: Segment) => sec(s.dur);
  // The suggestion hold is two pieces: the icon in, then the price appearing and staying.
  const holdA = t.add[t.suggestHold];
  const holdB = t.add[t.suggestHold + 1];
  const holdStart = addStarts[t.suggestHold];
  const holdEnd = addStarts[t.suggestHold + 1] + len(holdB);
  const priceAt = addStarts[t.suggestHold + 1] - holdStart + Math.max(0, Math.round(((t.priceAt - holdB.from) / rate(holdB)) * FPS));
  const row = GRANDPA_ROW[locale];
  const scenes: Scene[] = [
    {kind: 'hook', frames: sec(4.3)},
    {
      kind: 'footage',
      segs: t.add,
      frames: footageFrames(t.add, PIECE_FADE),
      taps: taps[`${locale}-add`],
      reveal: true,
      band: 'top',
      pushes: [
        {from: 14, to: addStarts[1], peak: 1.04, x: 443, y: 1525},
        {from: holdStart, to: holdEnd, peak: 1.05, x: 443, y: 1400},
        {from: addStarts[t.formHold], to: addStarts[t.formHold] + len(t.add[t.formHold]), peak: 1.04, x: 443, y: 1300},
        {from: addStarts[t.newRow], to: addStarts[t.newRow] + len(t.add[t.newRow]), peak: 1.04, x: 443, y: 524, settle: false},
      ],
      overlays: [
        {from: addStarts[t.watchHold] + 6, frames: len(t.add[t.watchHold]) - 6, node: <HighlightRect x={40} y={1450} w={808} h={150} />},
        {from: holdStart, frames: holdEnd - holdStart + 4, node: <SuggestCallout priceAt={priceAt} />},
        {from: addStarts[t.newRow], frames: len(t.add[t.newRow]), node: <HighlightRect x={40} y={450} w={808} h={148} />},
      ],
    },
    {kind: 'network', frames: sec(3.1)},
    {
      kind: 'footage',
      segs: t.person,
      frames: footageFrames(t.person, PIECE_FADE),
      taps: taps[`${locale}-person`],
      band: 'bottom',
      pushes: [{from: personStarts[t.personHold], to: personStarts[t.personHold] + len(t.person[t.personHold]), peak: 1.04, x: 443, y: 1400, settle: false}],
      overlays: [
        // Grandpa's overall totals (he also gave Sofia a doll) are dimmed; the story is the two rows below.
        {from: personStarts[t.personHold], frames: len(t.person[t.personHold]), node: <Dim y={760} h={240} />},
        {from: personStarts[t.personHold] + 4, frames: len(t.person[t.personHold]) - 4, node: <HighlightRect x={36} y={1246} w={814} h={306} />},
      ],
    },
    {kind: 'scale', frames: sec(3.1)},
    {
      kind: 'footage',
      segs: t.insights,
      frames: footageFrames(t.insights, PIECE_FADE),
      taps: [],
      band: 'top',
      pushes: [{from: UNDER_FLIGHT, to: footageFrames(t.insights, PIECE_FADE), peak: 1.05, x: 443, y: row.y + row.h / 2, settle: false}],
      overlays: [
        {from: UNDER_FLIGHT + 4, frames: footageFrames(t.insights, PIECE_FADE) - UNDER_FLIGHT - 4, node: <Spotlight {...row} />},
        {from: UNDER_FLIGHT + 4, frames: footageFrames(t.insights, PIECE_FADE) - UNDER_FLIGHT - 4, node: <HighlightRect x={row.x} y={row.y} w={row.w} h={row.h} color={AMBER} />},
      ],
    },
    {kind: 'end', frames: sec(3.0)},
  ];
  const starts: number[] = [];
  let at = 0;
  scenes.forEach((s, i) => {
    // The People list fades in over the drawn avatars as they land on it.
    const prev = scenes[i - 1]?.kind;
    const overlap = s.kind === 'footage' && prev === 'network' ? HANDOVER : s.kind === 'footage' && prev === 'scale' ? UNDER_FLIGHT : 0;
    starts.push(at - overlap);
    at = at - overlap + s.frames;
  });
  const total = at;
  const end = (i: number) => starts[i] + scenes[i].frames;
  const a = starts[1];
  const scaleLevel = starts[4] + 34; // the second gift has landed and the beam is level
  const raw: Omit<Cue, 'to'>[] = [
    {key: 'watch', text: c.storyWatch, from: a + 2, band: 'top'},
    {key: 'add', text: c.storyAdd, from: a + addStarts[1], band: 'top'},
    {key: 'suggest', text: c.storySuggest, from: a + holdStart, band: 'top'},
    {key: 'back', text: c.storyBack, from: a + holdEnd + 2, band: 'top'},
    {key: 'network', text: c.storyPerson, from: starts[2] + 4, band: 'top'},
    {key: 'grandpa', text: c.storyGrandpa, from: starts[3] + personStarts[t.personHold], band: 'bottom'},
    {key: 'scale', text: c.storyInsights, from: starts[4] + 4, band: 'top'},
    {key: 'each', text: c.storyEach, from: scaleLevel, band: 'top'},
  ];
  const stops = [raw[1].from, raw[2].from, raw[3].from, end(1) - OUT, starts[3], end(3) - OUT, scaleLevel, end(5) - OUT];
  const cues: Cue[] = raw.map((r, i) => ({...r, to: stops[i] - 2}));
  // Soft chimes on the payoffs: the price appears, the scarf row is saved, "Even".
  const chimes = [a + holdStart + priceAt, a + addStarts[t.newRow] + 2, starts[4] + 46];
  return {scenes, starts, total, cues, chimes};
};

/**
 * Variant D, "Story + motion": a drawn hook (Grandpa gave you a watch; what did you give back?), the
 * app answering it from slow-animation recordings (the scarf you gave back, the gifts with Grandpa,
 * one gift each way), drawn interludes that hand over to the app on match cuts, and the closing card.
 */
export const StoryMotion = ({locale}: {locale: Locale}) => {
  const p = motionPlan(locale);
  const c = copy[locale];
  return (
    <AbsoluteFill style={{backgroundColor: colors.navyDeep, fontFamily}}>
      <BrandBackground glowY={0.55} />
      {p.scenes.map((s, i) => (
        <Sequence key={i} from={p.starts[i]} durationInFrames={s.frames} name={`${i + 1}. ${s.kind}`} style={{zIndex: s.kind === 'scale' ? 2 : 1}}>
          {s.kind === 'hook' ? <HookScene locale={locale} hook1={c.hook1} hook2={c.hook2} frames={s.frames} /> : null}
          {s.kind === 'network' ? <NetworkScene locale={locale} frames={s.frames} /> : null}
          {s.kind === 'scale' ? <ScaleScene locale={locale} frames={s.frames} /> : null}
          {s.kind === 'end' ? (
            <FadeInFill frames={8}>
              <EndCard locale={locale} privacyIcon={<Lock size={34} />} logoSize={300} drift />
            </FadeInFill>
          ) : null}
          {s.kind === 'footage' ? <FootageScene scene={s} locale={locale} /> : null}
        </Sequence>
      ))}
      <Sequence from={p.starts[5] + UNDER_FLIGHT} durationInFrames={14} name="Even badge hand-over" style={{zIndex: 3}}>
        <EvenBadge locale={locale} />
      </Sequence>
      {p.cues.map((cue) => (
        <Sequence key={cue.key} from={cue.from} durationInFrames={cue.to - cue.from} name={`Caption: ${cue.key}`} style={{zIndex: 4}}>
          <FadeBlock outAt={cue.to - cue.from} style={{position: 'absolute', ...(cue.band === 'top' ? {top: 136} : {top: 1640}), left: 64, right: 64}}>
            <RiseText
              text={cue.text}
              stagger={1}
              highlight={
                locale === 'en'
                  ? ['written', 'seconds', 'history', 'even', 'icon', 'price', 'back', 'Grandpa', 'One', 'gift']
                  : ['записан', 'секунды', 'история', 'поровну', 'Значок', 'цена', 'в\u00A0ответ', 'с\u00A0дедушкой', 'По', 'одному']
              }
              style={{fontSize: 76, fontWeight: 800, lineHeight: 1.04, letterSpacing: -2, color: colors.white, textAlign: 'center'}}
            />
          </FadeBlock>
        </Sequence>
      ))}
      <Music src="music-bright.wav" total={p.total} />
      {p.chimes.map((f, i) => (
        <Sequence key={`chime${i}`} from={f} durationInFrames={24} name={`Chime ${i + 1}`}>
          <Audio src={staticFile('sfx-chime.wav')} volume={0.55} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};

const FootageScene = ({scene, locale}: {scene: Extract<Scene, {kind: 'footage'}>; locale: Locale}) => {
  const frame = useCurrentFrame();
  const push = scene.pushes.find((z) => frame >= z.from && frame <= z.to + 4);
  const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
  const z = push
    ? push.settle === false
      ? interpolate(frame, [push.from, push.to], [1, push.peak], clamp)
      : interpolate(frame, [push.from, push.to - 8, push.to], [1, push.peak, 1], {...clamp, easing: Easing.inOut(Easing.sin)})
    : 1;
  const fadeIn = scene.reveal ? 1 : interpolate(frame, [0, HANDOVER], [0, 1], clamp);
  const fadeOut = interpolate(frame, [scene.frames - OUT, scene.frames], [1, 0], clamp);
  return (
    <AbsoluteFill style={{opacity: fadeIn * fadeOut, maskImage: MASK[scene.band], WebkitMaskImage: MASK[scene.band]}}>
      <Reveal on={Boolean(scene.reveal)}>
        <AbsoluteFill style={{scale: String(z), transformOrigin: push ? `${push.x}px ${push.y}px` : '50% 50%'}}>
          <Footage segs={scene.segs} theme="story" locale={locale} overlap={PIECE_FADE} taps={scene.taps} />
          {scene.overlays.map((o, i) => (
            <Sequence key={i} from={o.from} durationInFrames={o.frames} layout="none">
              <FadeBlock outAt={o.frames}>{o.node}</FadeBlock>
            </Sequence>
          ))}
        </AbsoluteFill>
      </Reveal>
    </AbsoluteFill>
  );
};

/** Dims a horizontal band of the app (full width). */
const Dim = ({y, h}: {y: number; h: number}) => (
  <div style={{position: 'absolute', left: 0, top: y, width: 886, height: h, background: 'rgba(11,14,19,0.72)'}} />
);

/** Darkens everything but one rounded rectangle of the app. */
const Spotlight = ({x, y, w, h}: {x: number; y: number; w: number; h: number}) => (
  <svg width={886} height={1920} viewBox="0 0 886 1920" style={{position: 'absolute', inset: 0}}>
    <defs>
      <mask id="spot">
        <rect width={886} height={1920} fill="white" />
        <rect x={x} y={y} width={w} height={h} rx={34} fill="black" />
      </mask>
    </defs>
    <rect width={886} height={1920} fill="rgba(11,14,19,0.62)" mask="url(#spot)" />
  </svg>
);

/** The app is masked out under the caption band, so its own titles never show behind or between captions. */
const MASK: Record<Band, string> = {
  top: 'linear-gradient(180deg, transparent 0px, transparent 400px, #000 500px)',
  bottom: 'linear-gradient(0deg, transparent 0px, transparent 330px, #000 372px)',
};

const FadeInFill = ({frames, children}: {frames: number; children: React.ReactNode}) => {
  const frame = useCurrentFrame();
  return <AbsoluteFill style={{opacity: interpolate(frame, [0, frames], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>{children}</AbsoluteFill>;
};

/** Opens the first app scene from a phone-sized window in the middle of the frame. */
const Reveal = ({on, children}: {on: boolean; children: React.ReactNode}) => {
  const frame = useCurrentFrame();
  if (!on) return <AbsoluteFill>{children}</AbsoluteFill>;
  const p = interpolate(frame, [0, 14], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.bezier(0.6, 0, 0.2, 1)});
  return (
    <AbsoluteFill
      style={{
        clipPath: `inset(${interpolate(p, [0, 1], [570, 0])}px ${interpolate(p, [0, 1], [263, 0])}px round ${interpolate(p, [0, 1], [70, 0])}px)`,
        scale: String(interpolate(p, [0, 1], [0.94, 1])),
        opacity: interpolate(frame, [0, 3], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}),
      }}
    >
      {children}
    </AbsoluteFill>
  );
};
