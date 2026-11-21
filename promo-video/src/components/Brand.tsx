import {loadFont} from '@remotion/google-fonts/Inter';
import type {CSSProperties} from 'react';
import {AbsoluteFill, Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {appName, colors, copy, type Locale} from '../data';

export const {fontFamily} = loadFont('normal', {
  weights: ['500', '600', '700', '800'],
  subsets: ['latin', 'cyrillic'],
});

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/**
 * The app's mark: a white triangle pointing up (given) above an emerald one pointing down (received).
 * `progress` 0..1 slides them in from opposite sides.
 */
export const Logo = ({size, delay = 0}: {size: number; delay?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const p = spring({frame: frame - delay, fps, config: {damping: 16, mass: 0.8}});
  const q = spring({frame: frame - delay - 4, fps, config: {damping: 16, mass: 0.8}});
  return (
    <svg width={size} height={size} viewBox="200 220 624 690" style={{overflow: 'visible'}}>
      <polygon
        points="240,544 688,544 464,244"
        fill={colors.white}
        style={{translate: `${interpolate(p, [0, 1], [-140, 0])}px ${interpolate(p, [0, 1], [-60, 0])}px`, opacity: p}}
      />
      <polygon
        points="336,584 784,584 560,884"
        fill={colors.emerald}
        style={{translate: `${interpolate(q, [0, 1], [140, 0])}px ${interpolate(q, [0, 1], [60, 0])}px`, opacity: q}}
      />
    </svg>
  );
};

/** Navy background with a soft emerald glow, as on the App Store header art. */
export const BrandBackground = ({glowY = 0.42, style}: {glowY?: number; style?: CSSProperties}) => {
  const frame = useCurrentFrame();
  const drift = Math.sin(frame / 45) * 0.03;
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(ellipse 85% 55% at 50% ${(glowY + drift) * 100}%, rgba(32,169,113,0.30) 0%, rgba(32,169,113,0.08) 45%, rgba(0,0,0,0) 70%), linear-gradient(180deg, ${colors.navy} 0%, ${colors.navyDeep} 100%)`,
        ...style,
      }}
    />
  );
};

/** Text that rises in word by word. */
export const RiseText = ({
  text,
  delay = 0,
  stagger = 3,
  style,
  highlight,
}: {
  text: string;
  delay?: number;
  stagger?: number;
  style?: CSSProperties;
  /** Words (exact) drawn in emerald. */
  highlight?: string[];
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const words = text.split(' ');
  return (
    <div style={{fontFamily, display: 'flex', flexWrap: 'wrap', justifyContent: 'center', columnGap: '0.26em', ...style}}>
      {words.map((w, i) => {
        const s = spring({frame: frame - delay - i * stagger, fps, config: {damping: 200}, durationInFrames: 16});
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              opacity: s,
              translate: `0 ${interpolate(s, [0, 1], [28, 0])}px`,
              filter: `blur(${interpolate(s, [0, 1], [8, 0])}px)`,
              color: highlight?.includes(w) ? colors.emeraldGlow : undefined,
            }}
          >
            {w}
          </span>
        );
      })}
    </div>
  );
};

/** Fades a block in at `inAt` and out at `outAt` (frames relative to its sequence). */
export const FadeBlock = ({
  inAt = 0,
  outAt,
  children,
  style,
}: {
  inAt?: number;
  outAt: number;
  children: React.ReactNode;
  style?: CSSProperties;
}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [inAt, inAt + 6, outAt - 6, outAt], [0, 1, 1, 0], {
    ...clamp,
    easing: Easing.inOut(Easing.quad),
  });
  return <div style={{opacity, ...style}}>{children}</div>;
};

/** Closing card: logo, name, tagline and the privacy line. */
export const EndCard = ({
  locale,
  privacyIcon,
  logoSize = 250,
  drift = false,
  tagline = copy[locale].tagline,
  shift = 0,
}: {
  locale: Locale;
  privacyIcon?: React.ReactNode;
  logoSize?: number;
  drift?: boolean;
  tagline?: string;
  /** Moves the column down, to make room for something above it. */
  shift?: number;
}) => {
  const {durationInFrames} = useVideoConfig();
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const name = spring({frame: frame - 10, fps, config: {damping: 200}});
  const line = spring({frame: frame - 22, fps, config: {damping: 200}});
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', fontFamily, color: colors.white}}>
      <BrandBackground glowY={0.4} />
      <div style={{position: 'relative', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 34, padding: '0 80px', translate: `0 ${shift}px`, scale: drift ? String(interpolate(frame, [0, durationInFrames], [1, 1.04])) : undefined}}>
        <Logo size={logoSize} />
        <div
          style={{
            fontSize: 84,
            fontWeight: 800,
            letterSpacing: -2,
            textAlign: 'center',
            lineHeight: 1.02,
            opacity: name,
            translate: `0 ${interpolate(name, [0, 1], [24, 0])}px`,
          }}
        >
          {appName[locale]}
        </div>
        <div
          style={{
            fontSize: 44,
            fontWeight: 600,
            lineHeight: 1.22,
            textAlign: 'center',
            color: colors.muted,
            opacity: line,
            translate: `0 ${interpolate(line, [0, 1], [20, 0])}px`,
            maxWidth: 700,
          }}
        >
          {tagline}
        </div>
        <div
          style={{
            marginTop: 30,
            display: 'flex',
            alignItems: 'center',
            gap: 14,
            fontSize: locale === 'ru' ? 29 : 34, // the Russian line fits on one line only at 29
            fontWeight: 600,
            whiteSpace: 'nowrap',
            color: colors.emeraldGlow,
            letterSpacing: 0.3,
            opacity: interpolate(frame, [20, 32], [0, 1], clamp),
          }}
        >
          {privacyIcon}
          {copy[locale].privacy}
        </div>
      </div>
    </AbsoluteFill>
  );
};
