import {Audio} from '@remotion/media';
import {AbsoluteFill, interpolate, Sequence, staticFile, useCurrentFrame} from 'remotion';
import {EndCard, FadeBlock, fontFamily, RiseText} from '../components/Brand';
import {Footage} from '../components/Footage';
import {colors, type Locale} from '../data';
import {OVERLAP, plan} from '../plan';

/**
 * Variant A, "Clean": the dark app full screen, one short caption at a time on a scrim at the top,
 * dissolves between scenes, then the closing card. Closest to Apple's app preview guidance.
 */
export const Clean = ({locale}: {locale: Locale}) => {
  const p = plan('clean', locale);
  return (
    <AbsoluteFill style={{backgroundColor: colors.navyDeep}}>
      <Sequence durationInFrames={p.footageFrames} name="App footage">
        <Footage segs={p.segs} theme="dark" locale={locale} overlap={OVERLAP} />
      </Sequence>
      <TopScrim until={p.endStart + 10} />
      {p.cues.map((c) => (
        <Sequence key={c.key} from={c.from} durationInFrames={c.dur} name={`Caption: ${c.key}`}>
          <FadeBlock outAt={c.dur} inAt={0} style={{position: 'absolute', top: 128, left: 70, right: 70}}>
            <RiseText
              text={c.text}
              style={{fontSize: 66, fontWeight: 800, lineHeight: 1.08, letterSpacing: -1.2, color: colors.white, textAlign: 'center'}}
            />
          </FadeBlock>
        </Sequence>
      ))}
      <Sequence from={p.endStart} durationInFrames={p.endFrames} name="End card">
        <FadeIn frames={10}>
          <EndCard locale={locale} />
        </FadeIn>
      </Sequence>
      <Music src="music-warm.wav" total={p.total} />
    </AbsoluteFill>
  );
};

const TopScrim = ({until}: {until: number}) => {
  const frame = useCurrentFrame();
  const o = interpolate(frame, [0, 8, until - 10, until], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <AbsoluteFill
      style={{
        opacity: o,
        background:
          'linear-gradient(180deg, rgba(11,14,19,1) 0px, rgba(11,14,19,0.98) 360px, rgba(11,14,19,0.75) 410px, rgba(11,14,19,0) 480px)',
      }}
    />
  );
};

export const FadeIn = ({frames, children}: {frames: number; children: React.ReactNode}) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{opacity: interpolate(frame, [0, frames], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>
      {children}
    </AbsoluteFill>
  );
};

export const Music = ({src, total}: {src: string; total: number}) => (
  <Audio
    src={staticFile(src)}
    volume={(f) => interpolate(f, [0, 6, total - 30, total], [0, 0.9, 0.9, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}
  />
);

export {fontFamily};
