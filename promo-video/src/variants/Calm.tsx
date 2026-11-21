// Variant F, after the App Store previews of Things 3 and Streaks: no captions at all. A brand title
// card, the app at an unhurried pace with soft crossfades between screens, and the closing card.
import {AbsoluteFill, interpolate, Sequence, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {BrandBackground, EndCard, fontFamily, Logo} from '../components/Brand';
import {Footage, type Tap} from '../components/Footage';
import {Lock} from '../components/Motion';
import {appName, colors, footageFrames, type Locale, type Segment, storyTour, win} from '../data';
import tapsJson from '../taps.json';
import {Music} from './Clean';
import {cards} from './Kinetic';

const X = 14; // crossfade between scenes
const PIECE_FADE = 4;
const SLOWER = 1.2; // every piece 20% slower than variant D cut it
const taps = tapsJson as Record<string, Tap[]>;

const slower = (segs: Segment[]) => segs.map((s) => ({...s, dur: s.dur * SLOWER}));

export const calmPlan = (locale: Locale) => {
  const t = storyTour(locale);
  const clips: {segs: Segment[]; clip: string}[] = [
    {segs: slower([win('add', 2.6, 4.0, 1, 0), ...t.add.slice(1)]), clip: 'add'},
    {segs: slower([win('person', 15.8, 16.75, 1, 0), ...t.person.slice(1)]), clip: 'person'},
    {segs: [win('insights', 52.9, 53.9, 0.4, 0)], clip: 'insights'},
  ];
  const scenes = [
    {kind: 'title' as const, frames: 66},
    ...clips.map((c) => ({kind: 'footage' as const, segs: c.segs, taps: taps[`${locale}-${c.clip}`] ?? [], frames: footageFrames(c.segs, PIECE_FADE)})),
    {kind: 'end' as const, frames: 100},
  ];
  const starts: number[] = [];
  let at = 0;
  scenes.forEach((s, i) => {
    starts.push(i === 0 ? 0 : at - X);
    at = starts[i] + s.frames;
  });
  return {scenes, starts, total: at};
};

export const Calm = ({locale}: {locale: Locale}) => {
  const p = calmPlan(locale);
  return (
    <AbsoluteFill style={{backgroundColor: colors.navy, fontFamily}}>
      {p.scenes.map((scene, i) => (
        <Sequence key={i} from={p.starts[i]} durationInFrames={scene.frames} name={scene.kind}>
          <Fade frames={scene.frames} enter={i > 0}>
            {scene.kind === 'title' && <Title locale={locale} />}
            {scene.kind === 'footage' && <Footage segs={scene.segs} theme="story" locale={locale} overlap={PIECE_FADE} taps={scene.taps} />}
            {scene.kind === 'end' && <EndCard locale={locale} privacyIcon={<Lock size={34} />} logoSize={280} drift tagline={cards[locale].tagline} />}
          </Fade>
        </Sequence>
      ))}
      <Music src="music-warm.wav" total={p.total} />
    </AbsoluteFill>
  );
};

const Fade = ({frames, enter, children}: {frames: number; enter: boolean; children: React.ReactNode}) => {
  const frame = useCurrentFrame();
  const o = enter ? interpolate(frame, [0, X], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}) : 1;
  const s = interpolate(frame, [0, frames], [1.0, 1.015]);
  return <AbsoluteFill style={{opacity: o, scale: String(s)}}>{children}</AbsoluteFill>;
};

/** The logo and the name on navy, nothing else. */
const Title = ({locale}: {locale: Locale}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const name = spring({frame: frame - 12, fps, config: {damping: 200}});
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', color: colors.white}}>
      <BrandBackground glowY={0.45} />
      <div style={{position: 'relative', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 40}}>
        <Logo size={260} />
        <div style={{fontSize: 80, fontWeight: 800, letterSpacing: -2, opacity: name, translate: `0 ${interpolate(name, [0, 1], [24, 0])}px`}}>{appName[locale]}</div>
      </div>
    </AbsoluteFill>
  );
};
