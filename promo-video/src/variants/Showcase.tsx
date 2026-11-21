import {AbsoluteFill, Easing, interpolate, Sequence, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {BrandBackground, EndCard, FadeBlock, Logo, RiseText} from '../components/Brand';
import {Footage} from '../components/Footage';
import {appName, colors, HEIGHT, type Locale, SRC_H, SRC_W, WIDTH} from '../data';
import {OVERLAP, plan} from '../plan';
import {FadeIn, Music, fontFamily} from './Clean';

const SCREEN_W = 610;
const SCREEN_H = Math.round((SCREEN_W * SRC_H) / SRC_W);
const SCREEN_TOP = HEIGHT - SCREEN_H - 96;

/**
 * Variant B, "Showcase": the light app on a rounded screen over the navy brand background, a big
 * headline above it, and a gentle zoom on the name field while the icon and price fill in.
 */
export const Showcase = ({locale}: {locale: Locale}) => {
  const p = plan('showcase', locale);
  return (
    <AbsoluteFill style={{fontFamily}}>
      <BrandBackground glowY={0.62} />
      <Screen until={p.endStart + 10} pop={p.typing}>
        <Footage segs={p.segs} theme="light" locale={locale} overlap={OVERLAP} />
      </Screen>
      <Sequence durationInFrames={44} name="Intro mark">
        <IntroMark locale={locale} />
      </Sequence>
      {p.cues.map((c, i) => {
        const from = i === 0 ? 40 : c.from;
        const dur = i === 0 ? c.dur - 40 : c.dur;
        return (
          <Sequence key={c.key} from={from} durationInFrames={dur} name={`Headline: ${c.key}`}>
            <FadeBlock outAt={dur} style={{position: 'absolute', top: 150, left: 64, right: 64, height: SCREEN_TOP - 190, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
              <RiseText
                text={c.text}
                style={{fontSize: 70, fontWeight: 800, lineHeight: 1.06, letterSpacing: -1.4, color: colors.white, textAlign: 'center'}}
              />
            </FadeBlock>
          </Sequence>
        );
      })}
      <Sequence from={p.endStart} durationInFrames={p.endFrames} name="End card">
        <FadeIn frames={10}>
          <EndCard locale={locale} />
        </FadeIn>
      </Sequence>
      <Music src="music-warm.wav" total={p.total} />
    </AbsoluteFill>
  );
};

/** The rounded screen that carries the footage; rises in at the start. */
const Screen = ({until, pop, children}: {until: number; pop: {from: number; to: number}; children: React.ReactNode}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  // While the icon and price fill in, the whole screen comes forward (nothing is cropped at the sides).
  const forward = interpolate(frame, [pop.from, pop.from + 14, pop.to - 8, pop.to + 8], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.bezier(0.33, 0, 0.2, 1),
  });
  const rise = spring({frame, fps, config: {damping: 18, mass: 0.9}});
  const fade = interpolate(frame, [until - 12, until], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div
      style={{
        position: 'absolute',
        left: (WIDTH - SCREEN_W) / 2,
        top: SCREEN_TOP,
        width: SCREEN_W,
        height: SCREEN_H,
        borderRadius: 84,
        overflow: 'hidden',
        translate: `0 ${interpolate(rise, [0, 1], [380, 0]) + forward * 150}px`,
        scale: String(1 + forward * 0.24),
        transformOrigin: '50% 64%',
        opacity: fade,
        boxShadow: '0 40px 120px rgba(0,0,0,0.55), 0 0 0 2px rgba(255,255,255,0.10), 0 0 140px rgba(61,211,154,0.22)',
        backgroundColor: '#F2F2F7',
      }}
    >
      {children}
    </div>
  );
};

/** Opening: the mark and the name in the headline space before the first caption. */
const IntroMark = ({locale}: {locale: Locale}) => {
  const frame = useCurrentFrame();
  const out = interpolate(frame, [32, 44], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div
      style={{
        position: 'absolute',
        top: 150,
        left: 0,
        right: 0,
        height: SCREEN_TOP - 190,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 26,
        opacity: out,
      }}
    >
      <Logo size={120} />
      <div style={{fontSize: 62, fontWeight: 800, color: colors.white, letterSpacing: -1.2, opacity: interpolate(frame, [6, 16], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>
        {appName[locale]}
      </div>
    </div>
  );
};

export {RiseText};
