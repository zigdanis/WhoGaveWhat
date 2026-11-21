import {AbsoluteFill, interpolate, Sequence, useCurrentFrame} from 'remotion';
import {EndCard, FadeBlock, RiseText} from '../components/Brand';
import {Footage} from '../components/Footage';
import {colors, FPS, type Locale, type Segment} from '../data';
import {OVERLAP, plan} from '../plan';
import {FadeIn, Music, fontFamily} from './Clean';

/** Where the Wristwatch row sits on the Home screen, as a fraction of the screen height. */
const WATCH_ROW_Y = 0.795;

/**
 * Variant C, "Story": opens on a question over the real Home screen with the gifted watch picked
 * out, then a faster tour with bold captions and the upbeat track.
 */
export const Story = ({locale}: {locale: Locale}) => {
  const p = plan('story', locale);
  const hookSeg: Segment = {clip: 'home', from: 0.3, to: 3.0, dur: p.footageStart / FPS + OVERLAP / FPS};
  const words = locale === 'en' ? ['watch?', 'back?', 'seconds', 'history', 'even'] : ['часы?', 'ответ?', 'секунды', 'история', 'поровну'];
  return (
    <AbsoluteFill style={{backgroundColor: colors.navyDeep, fontFamily}}>
      <Sequence durationInFrames={p.footageStart + OVERLAP} name="Hook footage">
        <Footage segs={[hookSeg]} theme="dark" locale={locale} />
        <Spotlight frames={p.footageStart + OVERLAP} />
      </Sequence>
      <Sequence from={p.footageStart} durationInFrames={p.footageFrames} name="App footage">
        <FadeIn frames={OVERLAP}>
          <Footage segs={p.segs} theme="dark" locale={locale} overlap={OVERLAP} />
        </FadeIn>
      </Sequence>
      <TopScrim from={0} until={p.endStart + 10} />
      {p.cues.map((c) => {
        const hook = c.key.startsWith('hook');
        return (
          <Sequence key={c.key} from={c.from} durationInFrames={c.dur} name={`Caption: ${c.key}`}>
            <FadeBlock
              outAt={c.dur}
              style={
                hook
                  ? {position: 'absolute', top: 250, left: 60, right: 60}
                  : {position: 'absolute', top: 136, left: 64, right: 64}
              }
            >
              <RiseText
                text={c.text}
                stagger={hook ? 4 : 3}
                highlight={words}
                style={{
                  fontSize: hook ? (locale === 'ru' ? 78 : 92) : 78,
                  fontWeight: 800,
                  lineHeight: 1.04,
                  letterSpacing: -2,
                  color: colors.white,
                  textAlign: 'center',
                  textShadow: hook ? '0 6px 40px rgba(0,0,0,0.6)' : undefined,
                }}
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
      <Music src="music-bright.wav" total={p.total} />
    </AbsoluteFill>
  );
};

/** Dims Home except for the Wristwatch row while the hook asks about it. */
const Spotlight = ({frames}: {frames: number}) => {
  const frame = useCurrentFrame();
  const dim = interpolate(frame, [0, 10, frames - 8, frames], [0.35, 0.8, 0.8, 0.2], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const r = interpolate(frame, [0, 14], [520, 230], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(ellipse ${r * 2.2}px ${r * 0.62}px at 50% ${WATCH_ROW_Y * 100}%, rgba(11,14,19,0) 0%, rgba(11,14,19,0) 55%, rgba(11,14,19,${dim}) 100%)`,
      }}
    />
  );
};

const TopScrim = ({from, until}: {from: number; until: number}) => {
  const frame = useCurrentFrame();
  const o = interpolate(frame, [from, from + 8, until - 10, until], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <AbsoluteFill
      style={{
        opacity: o,
        background:
          'linear-gradient(180deg, rgba(11,14,19,1) 0px, rgba(11,14,19,0.98) 370px, rgba(11,14,19,0.75) 420px, rgba(11,14,19,0) 490px)',
      }}
    />
  );
};
