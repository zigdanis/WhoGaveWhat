import {Video} from '@remotion/media';
import type {CSSProperties} from 'react';
import {AbsoluteFill, interpolate, Sequence, staticFile, useCurrentFrame} from 'remotion';
import {type Locale, type Segment, type Theme, footageSrc, FPS} from '../data';
import {TapRing} from './Motion';

export type Tap = {t: number; x: number; y: number};

/** Zoom applied to the footage over the frames of the whole list: scale and focus point (0..1). */
export type Zoom = (frame: number) => {scale: number; x: number; y: number};

type Props = {
  segs: Segment[];
  theme: Theme;
  locale: Locale;
  /** Frames each piece fades over the previous one. */
  overlap?: number;
  zoom?: Zoom;
  style?: CSSProperties;
  videoStyle?: CSSProperties;
  /** Taps logged while recording (source seconds, video pixels), drawn as rings where they fall. */
  taps?: Tap[];
  /** Drawn over the footage inside the zoom, in video pixels, so it stays on the screen it marks. */
  children?: React.ReactNode;
};

/** Real app recordings played back to back, each trimmed and sped up as the segment says. */
export const Footage = ({segs, theme, locale, overlap = 5, zoom, style, videoStyle, taps = [], children}: Props) => {
  let start = 0;
  const pieces = segs.map((s, i) => {
    const frames = Math.round(s.dur * FPS);
    const fade = i === 0 ? 0 : (s.fade ?? overlap);
    const from = i === 0 ? 0 : start - fade;
    start = from + frames;
    return {s, from, frames, fadeIn: fade};
  });
  return (
    <AbsoluteFill style={{overflow: 'hidden', ...style}}>
      <ZoomLayer zoom={zoom}>
        {pieces.map(({s, from, frames, fadeIn}, i) => (
          <Sequence key={i} from={from} durationInFrames={frames} name={`${s.clip} ${s.from}-${s.to}s`}>
            <Piece seg={s} theme={theme} locale={locale} fadeIn={fadeIn} videoStyle={videoStyle} />
            {taps
              .filter((tap) => tap.t >= s.from && tap.t < s.to)
              .map((tap) => (
                <Sequence key={tap.t} from={Math.round(((tap.t - s.from) / ((s.to - s.from) / s.dur)) * FPS)} durationInFrames={14} layout="none">
                  <TapRing x={tap.x} y={tap.y} />
                </Sequence>
              ))}
          </Sequence>
        ))}
        {children}
      </ZoomLayer>
    </AbsoluteFill>
  );
};

const ZoomLayer = ({zoom, children}: {zoom?: Zoom; children: React.ReactNode}) => {
  const frame = useCurrentFrame();
  const z = zoom ? zoom(frame) : {scale: 1, x: 0.5, y: 0.5};
  return (
    <AbsoluteFill style={{scale: String(z.scale), transformOrigin: `${z.x * 100}% ${z.y * 100}%`}}>
      {children}
    </AbsoluteFill>
  );
};

const Piece = ({
  seg,
  theme,
  locale,
  fadeIn,
  videoStyle,
}: {
  seg: Segment;
  theme: Theme;
  locale: Locale;
  fadeIn: number;
  videoStyle?: CSSProperties;
}) => {
  const frame = useCurrentFrame();
  const rate = (seg.to - seg.from) / seg.dur;
  return (
    <AbsoluteFill
      style={{
        opacity: fadeIn ? interpolate(frame, [0, fadeIn], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}) : 1,
      }}
    >
      <Video
        src={staticFile(footageSrc(theme, locale, seg.clip))}
        trimBefore={Math.round(seg.from * FPS)}
        playbackRate={rate}
        muted
        objectFit="cover"
        style={{width: '100%', height: '100%', ...videoStyle}}
      />
    </AbsoluteFill>
  );
};
