// Schematic motion graphics drawn in SVG for variant D: portraits, the gift and the watch, the people
// network, the balance, and overlays on the app footage (tap rings, highlight rings, the suggestion
// callout). Everything is driven by useCurrentFrame(); no CSS animations.
import {AbsoluteFill, Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {colors, type Locale} from '../data';
import {fontFamily} from './Brand';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const AVATAR_FILL = '#1C2230';
export const AMBER = '#FFD27A';
const SKIN = '#F1C9A5';
const INK = '#20242C';

const useSpring = (delay: number, config: {damping?: number; mass?: number; stiffness?: number} = {damping: 14}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return spring({frame: frame - delay, fps, config});
};

export type Face = 'grandpa' | 'you' | 'mom' | 'igor';

const shirts: Record<Face, string> = {grandpa: '#8B6B4E', you: colors.emerald, mom: '#B48AE6', igor: '#5B8FD1'};

/** A flat portrait inside a circle of radius r centred on (0,0). */
const Portrait = ({face, r, id}: {face: Face; r: number; id: string}) => {
  const head = {cx: 0, cy: -0.1 * r, r: 0.33 * r};
  const eyeY = head.cy - 0.02 * r;
  return (
    <g clipPath={`url(#clip-${id})`}>
      <defs>
        <clipPath id={`clip-${id}`}>
          <circle r={r} />
        </clipPath>
      </defs>
      <circle r={r} fill={AVATAR_FILL} />
      {face === 'mom' ? <ellipse cx={0} cy={head.cy + 0.16 * r} rx={0.54 * r} ry={0.6 * r} fill="#8A4B2E" /> : null}
      {/* Shoulders and neck. */}
      <path d={`M ${-0.72 * r} ${r} Q ${-0.68 * r} ${0.38 * r} 0 ${0.36 * r} Q ${0.68 * r} ${0.38 * r} ${0.72 * r} ${r} Z`} fill={shirts[face]} />
      <rect x={-0.12 * r} y={head.cy + 0.26 * r} width={0.24 * r} height={0.2 * r} fill={SKIN} />
      <g transform={`translate(0 ${head.cy}) scale(1.27) translate(0 ${-head.cy})`}>
      <circle cx={head.cx} cy={head.cy} r={head.r} fill={SKIN} />
      {face === 'grandpa' ? (
        <>
          <path d={`M ${-0.34 * r} ${head.cy - 0.02 * r} Q ${-0.36 * r} ${head.cy - 0.3 * r} ${-0.16 * r} ${head.cy - 0.33 * r}`} stroke="#D9DEE6" strokeWidth={0.1 * r} fill="none" strokeLinecap="round" />
          <path d={`M ${0.34 * r} ${head.cy - 0.02 * r} Q ${0.36 * r} ${head.cy - 0.3 * r} ${0.16 * r} ${head.cy - 0.33 * r}`} stroke="#D9DEE6" strokeWidth={0.1 * r} fill="none" strokeLinecap="round" />
          <path d={`M ${-0.3 * r} ${head.cy - 0.18 * r} Q 0 ${head.cy - 0.5 * r} ${0.3 * r} ${head.cy - 0.18 * r}`} stroke="#D9DEE6" strokeWidth={0.07 * r} fill="none" strokeLinecap="round" />
          <circle cx={-0.13 * r} cy={eyeY} r={0.1 * r} fill="none" stroke={INK} strokeWidth={0.035 * r} />
          <circle cx={0.13 * r} cy={eyeY} r={0.1 * r} fill="none" stroke={INK} strokeWidth={0.035 * r} />
          <line x1={-0.03 * r} y1={eyeY} x2={0.03 * r} y2={eyeY} stroke={INK} strokeWidth={0.03 * r} />
          <path d={`M ${-0.13 * r} ${head.cy + 0.15 * r} Q 0 ${head.cy + 0.08 * r} ${0.13 * r} ${head.cy + 0.15 * r} Q 0 ${head.cy + 0.2 * r} ${-0.13 * r} ${head.cy + 0.15 * r} Z`} fill="#E6E9EE" />
        </>
      ) : null}
      {face === 'you' ? (
        <path d={`M ${-0.35 * r} ${head.cy + 0.02 * r} Q ${-0.4 * r} ${head.cy - 0.42 * r} ${0.02 * r} ${head.cy - 0.38 * r} Q ${0.4 * r} ${head.cy - 0.36 * r} ${0.35 * r} ${head.cy - 0.02 * r} Q ${0.2 * r} ${head.cy - 0.22 * r} ${-0.35 * r} ${head.cy + 0.02 * r} Z`} fill="#5A3A26" />
      ) : null}
      {face === 'mom' ? (
        <path d={`M ${-0.36 * r} ${head.cy + 0.1 * r} Q ${-0.38 * r} ${head.cy - 0.42 * r} ${0.02 * r} ${head.cy - 0.38 * r} Q ${0.38 * r} ${head.cy - 0.38 * r} ${0.36 * r} ${head.cy + 0.1 * r} Q ${0.26 * r} ${head.cy - 0.2 * r} ${-0.05 * r} ${head.cy - 0.22 * r} Q ${-0.24 * r} ${head.cy - 0.2 * r} ${-0.36 * r} ${head.cy + 0.1 * r} Z`} fill="#8A4B2E" />
      ) : null}
      {face === 'igor' ? (
        <>
          <path d={`M ${-0.33 * r} ${head.cy - 0.05 * r} Q ${-0.3 * r} ${head.cy - 0.4 * r} 0 ${head.cy - 0.37 * r} Q ${0.3 * r} ${head.cy - 0.4 * r} ${0.33 * r} ${head.cy - 0.05 * r} Q 0 ${head.cy - 0.24 * r} ${-0.33 * r} ${head.cy - 0.05 * r} Z`} fill="#22262E" />
          <path d={`M ${-0.22 * r} ${head.cy + 0.1 * r} Q 0 ${head.cy + 0.48 * r} ${0.22 * r} ${head.cy + 0.1 * r} Q 0 ${head.cy + 0.3 * r} ${-0.22 * r} ${head.cy + 0.1 * r} Z`} fill="#3A3F49" />
          <path d={`M ${-0.07 * r} ${head.cy + 0.13 * r} Q 0 ${head.cy + 0.17 * r} ${0.07 * r} ${head.cy + 0.13 * r}`} stroke={INK} strokeWidth={0.025 * r} fill="none" strokeLinecap="round" />
        </>
      ) : null}
      <circle cx={(face === 'grandpa' ? -0.13 : -0.12) * r} cy={eyeY} r={(face === 'grandpa' ? 0.025 : 0.03) * r} fill={INK} />
      <circle cx={(face === 'grandpa' ? 0.13 : 0.12) * r} cy={eyeY} r={(face === 'grandpa' ? 0.025 : 0.03) * r} fill={INK} />
      {face !== 'igor' ? (
        <path
          d={`M ${-0.08 * r} ${head.cy + (face === 'grandpa' ? 0.21 : 0.13) * r} Q 0 ${head.cy + (face === 'grandpa' ? 0.26 : 0.19) * r} ${0.08 * r} ${head.cy + (face === 'grandpa' ? 0.21 : 0.13) * r}`}
          stroke={INK}
          strokeWidth={0.025 * r}
          fill="none"
          strokeLinecap="round"
        />
      ) : null}
      </g>
    </g>
  );
};

/** A person: a portrait in a coloured ring with an optional name below. */
export const Avatar = ({
  id,
  face,
  x,
  y,
  r,
  ring,
  label,
  delay = 0,
  labelSize = 34,
  labelOpacity = 1,
}: {
  id: string;
  face: Face;
  x: number;
  y: number;
  r: number;
  ring: string;
  label?: string;
  delay?: number;
  labelSize?: number;
  labelOpacity?: number;
}) => {
  const s = useSpring(delay, {damping: 13, mass: 0.7});
  return (
    <g style={{translate: `${x}px ${y}px`, scale: String(s)}}>
      <Portrait face={face} r={r} id={id} />
      <circle r={r} fill="none" stroke={ring} strokeWidth={Math.max(4, r * 0.07)} />
      {label ? (
        <text y={r + labelSize * 1.3} textAnchor="middle" fill={colors.white} opacity={labelOpacity} fontFamily={fontFamily} fontWeight={700} fontSize={labelSize}>
          {label}
        </text>
      ) : null}
    </g>
  );
};

/**
 * A wrapped gift box centred on (0,0), about 130 px wide. `open` 0..1 swings the lid up on a hinge at
 * its left corner and shows the dark inside.
 */
export const GiftBox = ({open = 0}: {open?: number}) => (
  <g>
    <defs>
      <linearGradient id="boxShade" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stopColor="#000" stopOpacity="0" />
        <stop offset="1" stopColor="#000" stopOpacity="0.18" />
      </linearGradient>
    </defs>
    <rect x={-56} y={-14} width={112} height={80} rx={12} fill={colors.emerald} />
    <rect x={-56} y={-14} width={112} height={80} rx={12} fill="url(#boxShade)" />
    <rect x={-10} y={-14} width={20} height={80} fill={colors.white} />
    <ellipse cx={0} cy={-14} rx={52} ry={11 * open} fill="#0B0E13" />
    <g style={{rotate: `${-75 * open}deg`, transformOrigin: '-56px -14px'}}>
      <rect x={-64} y={-42} width={128} height={30} rx={9} fill={colors.emeraldGlow} />
      <rect x={-10} y={-42} width={20} height={30} fill={colors.white} />
      <path d="M 0 -42 C -10 -70 -46 -66 -30 -48 C -24 -42 -10 -42 0 -42 Z" fill="none" stroke={colors.white} strokeWidth={8} strokeLinejoin="round" />
      <path d="M 0 -42 C 10 -70 46 -66 30 -48 C 24 -42 10 -42 0 -42 Z" fill="none" stroke={colors.white} strokeWidth={8} strokeLinejoin="round" />
    </g>
  </g>
);

/** A wristwatch centred on (0,0): hands at 10:10, emerald crown. */
export const Watch = () => (
  <g>
    <rect x={-24} y={-90} width={48} height={44} rx={10} fill="#C9CED6" />
    <rect x={-24} y={46} width={48} height={44} rx={10} fill="#C9CED6" />
    <rect x={50} y={-9} width={12} height={18} rx={4} fill={colors.emeraldGlow} />
    <circle r={52} fill={colors.white} />
    <circle r={45} fill="#11151B" />
    {Array.from({length: 12}).map((_, i) => {
      const a = (i / 12) * Math.PI * 2;
      const long = i % 3 === 0;
      return (
        <line key={i} x1={Math.sin(a) * (long ? 33 : 37)} y1={-Math.cos(a) * (long ? 33 : 37)} x2={Math.sin(a) * 41} y2={-Math.cos(a) * 41} stroke={colors.white} strokeWidth={long ? 4 : 2} strokeLinecap="round" />
      );
    })}
    <line x1={0} y1={0} x2={-19} y2={-11} stroke={colors.white} strokeWidth={6} strokeLinecap="round" />
    <line x1={0} y1={0} x2={22} y2={-21} stroke={colors.emeraldGlow} strokeWidth={4} strokeLinecap="round" />
    <circle r={5} fill={colors.white} />
  </g>
);

/** Up-pointing white triangle (given) or down-pointing emerald triangle (received), as in the logo. */
export const Token = ({kind, size = 26}: {kind: 'given' | 'received'; size?: number}) =>
  kind === 'given' ? (
    <polygon points={`${-size},${size * 0.6} ${size},${size * 0.6} 0,${-size * 0.75}`} fill={colors.white} />
  ) : (
    <polygon points={`${-size},${-size * 0.6} ${size},${-size * 0.6} 0,${size * 0.75}`} fill={colors.emerald} />
  );

/** A dashed path that draws itself from start to end as `progress` goes 0..1. */
const RevealPath = ({id, d, progress, stroke, opacity, dash, width = 7}: {id: string; d: string; progress: number; stroke: string; opacity: number; dash: string; width?: number}) => (
  <>
    <defs>
      <mask id={`reveal-${id}`} maskUnits="userSpaceOnUse" x={0} y={0} width={886} height={1920}>
        <path d={d} fill="none" stroke="white" strokeWidth={30} pathLength={1} strokeDasharray="1 1" strokeDashoffset={1 - progress} />
      </mask>
    </defs>
    <path d={d} fill="none" stroke={stroke} strokeOpacity={opacity} strokeWidth={width} strokeLinecap="round" strokeDasharray={dash} mask={`url(#reveal-${id})`} />
  </>
);

const quad = (t: number, a: number, c: number, b: number) => (1 - t) * (1 - t) * a + 2 * (1 - t) * t * c + t * t * b;

const labels = {
  en: {grandpa: 'Grandpa', you: 'You', youNamed: 'Anton (you)', mom: 'Mom', igor: 'Igor'},
  ru: {grandpa: 'Дедушка', you: 'Вы', youNamed: 'Антон (вы)', mom: 'Мама', igor: 'Игорь'},
};

/** A whole phrase rising in over 6 frames (no word-by-word stagger, so it reads at once). */
const Phrase = ({text, at, out, highlight}: {text: string; at: number; out?: number; highlight: string}) => {
  const frame = useCurrentFrame();
  const p = interpolate(frame, [at, at + 6], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const o = out === undefined ? 1 : interpolate(frame, [out, out + 6], [1, 0], clamp);
  const words = text.split(' ');
  return (
    <div
      style={{
        position: 'absolute',
        top: 230,
        left: 60,
        right: 60,
        textAlign: 'center',
        fontFamily,
        fontWeight: 800,
        fontSize: text.length > 24 ? 80 : 88,
        lineHeight: 1.05,
        letterSpacing: -2,
        color: colors.white,
        opacity: p * o,
        translate: `0 ${(1 - p) * 26}px`,
      }}
    >
      {words.map((w, i) => (
        <span key={i} style={{color: w === highlight ? colors.emeraldGlow : undefined}}>
          {w}
          {i < words.length - 1 ? ' ' : ''}
        </span>
      ))}
    </div>
  );
};

/** Opening: a gift flies from Grandpa to You and a watch comes out; then a dashed "?" goes back. */
export const HookScene = ({locale, hook1, hook2, frames}: {locale: Locale; hook1: string; hook2: string; frames: number}) => {
  const frame = useCurrentFrame();
  const L = labels[locale];
  const g = {x: 230, y: 1080};
  const you = {x: 656, y: 1400};
  const R = 100;
  const start = {x: g.x + 0.645 * (R + 6), y: g.y - 0.764 * (R + 6)};
  const ctrl = {x: 500, y: 760};
  const land = {x: 640, y: 1190};
  const fly = interpolate(frame, [14, 44], [0, 1], {...clamp, easing: Easing.bezier(0.45, 0, 0.25, 1)});
  const bx = quad(fly, start.x, ctrl.x, land.x);
  const by = quad(fly, start.y, ctrl.y, land.y);
  const lid = interpolate(frame, [46, 58], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const watch = useSpring(50, {damping: 12, mass: 0.6});
  const back = interpolate(frame, [72, 96], [0, 1], {...clamp, easing: Easing.inOut(Easing.quad)});
  const q = useSpring(86, {damping: 12});
  const backFrom = {x: you.x - R * 0.96, y: you.y + R * 0.28};
  const backTo = {x: g.x + 0.866 * (R + 12), y: g.y + 0.5 * (R + 12)};
  const backCtrl = {x: 380, y: 1640};
  const mid = {x: quad(0.5, backFrom.x, backCtrl.x, backTo.x), y: quad(0.5, backFrom.y, backCtrl.y, backTo.y)};
  const exit = interpolate(frame, [frames - 7, frames - 1], [0, 1], clamp);
  const giftIn = interpolate(frame, [8, 14], [0, 1], {...clamp, easing: Easing.out(Easing.back(2))});
  return (
    <AbsoluteFill style={{opacity: 1 - exit, scale: String(1 - 0.06 * exit)}}>
      <Phrase text={hook1} at={4} out={64} highlight={locale === 'en' ? 'watch?' : 'часы?'} />
      <Phrase text={hook2} at={70} highlight={locale === 'en' ? 'back?' : 'в\u00A0ответ?'} />
      <svg width={886} height={1920} viewBox="0 0 886 1920" style={{position: 'absolute'}}>
        <RevealPath id="trail" d={`M ${start.x} ${start.y} Q ${ctrl.x} ${ctrl.y} ${land.x} ${land.y}`} progress={fly} stroke={colors.emeraldGlow} opacity={0.8} dash="4 14" width={6} />
        <Avatar id="hook-g" face="grandpa" x={g.x} y={g.y} r={R} ring={AMBER} label={L.grandpa} />
        <Avatar id="hook-y" face="you" x={you.x} y={you.y} r={R} ring={colors.emeraldGlow} label={L.you} delay={4} />
        <RevealPath id="back" d={`M ${backFrom.x} ${backFrom.y} Q ${backCtrl.x} ${backCtrl.y} ${backTo.x} ${backTo.y}`} progress={back} stroke={colors.white} opacity={0.9} dash="16 14" width={6} />
        <polygon points="-18,12 18,12 0,-20" fill={colors.white} style={{translate: `${backTo.x}px ${backTo.y}px`, rotate: `${(Math.atan2(backTo.x - backCtrl.x, -(backTo.y - backCtrl.y)) * 180) / Math.PI}deg`, opacity: interpolate(back, [0.85, 1], [0, 1], clamp)}} />
        <g style={{translate: `${mid.x}px ${mid.y}px`, scale: String(q), rotate: `${Math.sin(frame / 7) * 5}deg`}}>
          <circle r={46} fill={colors.navy} stroke={colors.white} strokeWidth={6} />
          <text y={21} textAnchor="middle" fill={colors.white} fontFamily={fontFamily} fontWeight={800} fontSize={58}>
            ?
          </text>
        </g>
        <g style={{translate: `${land.x}px ${land.y - 20 - watch * 190}px`, scale: String(watch)}}>
          <Watch />
        </g>
        <g style={{translate: `${bx}px ${by}px`, scale: String(giftIn), rotate: `${interpolate(fly, [0, 0.5, 1], [-10, 8, 0])}deg`}}>
          <GiftBox open={lid} />
        </g>
      </svg>
    </AbsoluteFill>
  );
};

/** People list geometry of the app (People tab), so the network can land on it. */
export const PEOPLE_ROW = (i: number) => ({x: 113, y: 446 + 153.5 * i, r: 48});

/**
 * Anton (you) and three people. Lines grow from you, the watch comes in from Grandpa (emerald, received)
 * and the scarf goes back (white, given), Grandpa's history card rests for a second, then Mom and Igor
 * fade and you and Grandpa slide onto your rows of the app's People list.
 */
export const NetworkScene = ({locale, frames}: {locale: Locale; frames: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const L = labels[locale];
  const c = {x: 443, y: 1080};
  // Rows of the People list each person lands on (the list is sorted by name, so it differs by language).
  const rows = locale === 'en' ? {grandpa: 4} : {grandpa: 2};
  const g = {face: 'grandpa' as Face, label: L.grandpa, x: 196, y: 760, ring: AMBER};
  const others: {face: Face; label: string; x: number; y: number; ring: string}[] = [
    {face: 'mom', label: L.mom, x: 690, y: 760, ring: '#C9A7FF'},
    {face: 'igor', label: L.igor, x: 443, y: 1460, ring: '#8EC5FF'},
  ];
  const exitStart = frames - 16;
  const slideOf = (i: number) => spring({frame: frame - exitStart - i * 2, fps, config: {damping: 20, mass: 0.8}, durationInFrames: 12});
  const labelsOut = interpolate(frame, [exitStart - 4, exitStart], [1, 0], clamp);
  const othersOut = interpolate(frame, [exitStart - 8, exitStart - 2], [1, 0], clamp);
  const lerp = (a: number, b: number, i: number) => a + (b - a) * slideOf(i);
  const youRow = PEOPLE_ROW(1);
  const gRow = PEOPLE_ROW(rows.grandpa);
  const rim = (n: {x: number; y: number}, r1: number, r2: number) => {
    const dx = n.x - c.x;
    const dy = n.y - c.y;
    const len = Math.hypot(dx, dy);
    return {x1: c.x + (dx / len) * r1, y1: c.y + (dy / len) * r1, x2: n.x - (dx / len) * r2, y2: n.y - (dy / len) * r2};
  };
  const gl = rim(g, 100, 80);
  // The tokens travel from rim to rim and fade over their last 4 frames.
  const along = (t: number, back: boolean) => (back ? {x: gl.x1 + (gl.x2 - gl.x1) * t, y: gl.y1 + (gl.y2 - gl.y1) * t} : {x: gl.x2 + (gl.x1 - gl.x2) * t, y: gl.y2 + (gl.y1 - gl.y2) * t});
  const token = (start: number, kind: 'given' | 'received') => {
    const t = interpolate(frame, [start, start + 20], [0, 1], {...clamp, easing: Easing.inOut(Easing.quad)});
    const o = interpolate(frame, [start, start + 2, start + 16, start + 20], [0, 1, 1, 0], clamp);
    const pos = along(t, kind === 'given');
    return frame >= start && frame <= start + 20 ? (
      <g style={{translate: `${pos.x}px ${pos.y}px`}} opacity={o}>
        <Token kind={kind} size={30} />
      </g>
    ) : null;
  };
  const card = spring({frame: frame - 22, fps, config: {damping: 16}});
  const L2 = locale === 'en' ? {toYou: 'Grandpa → you', toHim: 'You → Grandpa'} : {toYou: 'Дедушка → вам', toHim: 'Вы → дедушке'};
  return (
    <AbsoluteFill>
      <svg width={886} height={1920} viewBox="0 0 886 1920" style={{position: 'absolute'}}>
        <line x1={gl.x1} y1={gl.y1} x2={gl.x1 + (gl.x2 - gl.x1) * interpolate(frame, [2, 12], [0, 1], clamp)} y2={gl.y1 + (gl.y2 - gl.y1) * interpolate(frame, [2, 12], [0, 1], clamp)} stroke="rgba(255,255,255,0.4)" strokeWidth={3} opacity={labelsOut} />
        {others.map((n, i) => {
          const draw = interpolate(frame, [5 + i * 3, 15 + i * 3], [0, 1], clamp);
          const l = rim(n, n.face === 'igor' ? 160 : 100, 82);
          return <line key={`l${i}`} x1={l.x1} y1={l.y1} x2={l.x1 + (l.x2 - l.x1) * draw} y2={l.y1 + (l.y2 - l.y1) * draw} stroke="rgba(255,255,255,0.3)" strokeWidth={3} opacity={othersOut} />;
        })}
        {token(12, 'received')}
        {token(30, 'given')}
        <g opacity={card * labelsOut} style={{translate: '46px 410px', scale: String(0.9 + 0.1 * card)}}>
          <rect width={540} height={190} rx={28} fill="#1C2230" stroke="rgba(255,255,255,0.16)" strokeWidth={2} />
          <g style={{translate: '62px 52px', scale: '0.46'}}>
            <Watch />
          </g>
          <text x={118} y={66} fill={colors.emeraldGlow} fontFamily={fontFamily} fontWeight={700} fontSize={40}>
            {L2.toYou}
          </text>
          <g style={{translate: '62px 140px', scale: '0.46'}}>
            <Scarf />
          </g>
          <text x={118} y={154} fill={colors.white} fontFamily={fontFamily} fontWeight={700} fontSize={40}>
            {L2.toHim}
          </text>
        </g>
        {others.map((n, i) => (
          <g key={`a${i}`} opacity={othersOut}>
            <Avatar id={`net-${i}`} face={n.face} x={n.x} y={n.y} r={80} ring={n.ring} label={n.label} delay={6 + i * 3} labelSize={30} />
          </g>
        ))}
        <Avatar id="net-g" face="grandpa" x={lerp(g.x, gRow.x, 1)} y={lerp(g.y, gRow.y, 1)} r={lerp(80, gRow.r, 1)} ring={g.ring} label={g.label} delay={3} labelSize={30} labelOpacity={labelsOut} />
        <Avatar id="net-you" face="you" x={lerp(c.x, youRow.x, 0)} y={lerp(c.y, youRow.y, 0)} r={lerp(100, youRow.r, 0)} ring={colors.emeraldGlow} label={L.youNamed} labelSize={34} labelOpacity={labelsOut} />
      </svg>
    </AbsoluteFill>
  );
};

/** A knitted red scarf like the app's 🧣, centred on (0,0) and about the size of the watch. */
export const Scarf = () => {
  const tail = (angle: number, length: number, shade: string) => (
    <g style={{rotate: `${angle}deg`, transformOrigin: '18px 4px'}}>
      <rect x={4} y={4} width={30} height={length} rx={6} fill={shade} />
      <rect x={4} y={length * 0.45} width={30} height={7} fill="#F28B82" opacity={0.85} />
      <rect x={4} y={length * 0.62} width={30} height={7} fill="#F28B82" opacity={0.85} />
      {[10, 19, 28].map((x) => (
        <line key={x} x1={x} y1={length + 2} x2={x} y2={length + 16} stroke={shade} strokeWidth={4} strokeLinecap="round" />
      ))}
    </g>
  );
  return (
    <g style={{translate: '-10px -30px'}}>
      <ellipse cx={0} cy={-6} rx={44} ry={24} fill="none" stroke="#D8453D" strokeWidth={26} />
      <ellipse cx={0} cy={-6} rx={44} ry={24} fill="none" stroke="#F28B82" strokeWidth={26} strokeDasharray="5 16" opacity={0.45} />
      {tail(14, 74, '#C23A33')}
      {tail(-8, 104, '#D8453D')}
      <rect x={4} y={-4} width={30} height={22} rx={8} fill="#B5332D" />
    </g>
  );
};

const scaleLabels = {
  en: {given: 'Given', received: 'Received', even: 'Even'},
  ru: {given: 'Подарено', received: 'Получено', even: 'Поровну'},
};

/** Where Grandpa Pavel's Even pill and row sit in the Insights footage that follows the balance. */
export const EVEN_PILL = {en: {x: 727, y: 602, scale: 0.6}, ru: {x: 700, y: 540, scale: 0.62}};
export const GRANDPA_ROW = {en: {x: 40, y: 548, w: 808, h: 150}, ru: {x: 36, y: 474, w: 814, h: 172}};

/**
 * A balance on a slim post: the scarf you gave lands on the left, the watch you got on the right; the
 * beam tips 5° on the first landing and levels when the second lands. "Even" then flies to its place
 * in Insights.
 */
export const ScaleScene = ({locale, frames}: {locale: Locale; frames: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const L = scaleLabels[locale];
  const pill = EVEN_PILL[locale];
  const pivot = {x: 443, y: 860};
  const half = 290;
  const leftLand = 18;
  const rightLand = 32;
  const tipIn = spring({frame: frame - leftLand, fps, config: {damping: 11}, durationInFrames: 12});
  const level = spring({frame: frame - rightLand, fps, config: {damping: 11}, durationInFrames: 14});
  const angle = -5 * tipIn * (1 - level);
  const rad = (angle * Math.PI) / 180;
  const ends = [-1, 1].map((d) => ({x: pivot.x + d * half * Math.cos(rad), y: pivot.y + d * half * Math.sin(rad)}));
  const flyStart = frames - 16;
  const badgeIn = spring({frame: frame - 46, fps, config: {damping: 12}});
  const fly = interpolate(frame, [flyStart, frames - 2], [0, 1], {...clamp, easing: Easing.inOut(Easing.cubic)});
  const fadeRest = interpolate(frame, [flyStart - 2, flyStart + 6], [1, 0], clamp);
  const drop = (land: number) => interpolate(frame, [land - 9, land], [0, 1], {...clamp, easing: Easing.in(Easing.quad)});
  const pan = (end: {x: number; y: number}, item: 'scarf' | 'watch', land: number) => {
    const d = drop(land);
    const bounce = spring({frame: frame - land, fps, config: {damping: 9}, durationInFrames: 10});
    return (
      <g>
        <line x1={end.x} y1={end.y} x2={end.x - 120} y2={end.y + 230} stroke="rgba(255,255,255,0.55)" strokeWidth={3} />
        <line x1={end.x} y1={end.y} x2={end.x + 120} y2={end.y + 230} stroke="rgba(255,255,255,0.55)" strokeWidth={3} />
        <path d={`M ${end.x - 150} ${end.y + 230} Q ${end.x} ${end.y + 320} ${end.x + 150} ${end.y + 230}`} fill="#1C2230" stroke={colors.white} strokeWidth={6} strokeLinecap="round" />
        {frame >= land - 9 ? (
          <g style={{translate: `${end.x}px ${end.y + 150 - (1 - d) * 160 - (frame > land ? (1 - bounce) * 10 : 0)}px`, scale: '0.9', opacity: Math.min(1, d * 2)}}>
            {item === 'scarf' ? <Scarf /> : <Watch />}
          </g>
        ) : null}
      </g>
    );
  };
  return (
    <AbsoluteFill>
      <svg width={886} height={1920} viewBox="0 0 886 1920" style={{position: 'absolute', opacity: fadeRest}}>
        <rect x={pivot.x - 7} y={pivot.y} width={14} height={480} rx={7} fill="rgba(255,255,255,0.85)" />
        <rect x={pivot.x - 120} y={pivot.y + 472} width={240} height={16} rx={8} fill="rgba(255,255,255,0.85)" />
        <line x1={ends[0].x} y1={ends[0].y} x2={ends[1].x} y2={ends[1].y} stroke={colors.white} strokeWidth={10} strokeLinecap="round" />
        <circle cx={pivot.x} cy={pivot.y} r={20} fill={colors.emerald} stroke={colors.white} strokeWidth={5} />
        {pan(ends[0], 'scarf', leftLand)}
        {pan(ends[1], 'watch', rightLand)}
        <text x={pivot.x - half} y={pivot.y + 400} textAnchor="middle" fill={colors.white} fontFamily={fontFamily} fontWeight={700} fontSize={38}>
          ↗ {L.given}
        </text>
        <text x={pivot.x + half} y={pivot.y + 400} textAnchor="middle" fill={colors.emeraldGlow} fontFamily={fontFamily} fontWeight={700} fontSize={38}>
          ↙ {L.received}
        </text>
      </svg>
      <div
        style={{
          position: 'absolute',
          left: 0,
          top: 0,
          transformOrigin: '0 0',
          translate: `${interpolate(fly, [0, 1], [443, pill.x])}px ${interpolate(fly, [0, 1], [1460, pill.y])}px`,
          scale: String(interpolate(badgeIn, [0, 1], [0.6, 1]) * interpolate(fly, [0, 1], [1, pill.scale])),
          opacity: badgeIn,
        }}
      >
        <div
          style={{
            translate: '-50% -50%',
            fontFamily,
            fontWeight: 800,
            fontSize: 54,
            color: AMBER,
            background: 'rgba(255,201,77,0.18)',
            padding: '14px 38px',
            borderRadius: 999,
            whiteSpace: 'nowrap',
          }}
        >
          {L.even} 🤝
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** Rings drawn around the suggested icon, then the estimated price, on the add-gift form. */
export const SuggestCallout = ({priceAt}: {priceAt: number}) => {
  const frame = useCurrentFrame();
  const icon = {x: 111, y: 1217};
  const price = {x: 722, y: 1588};
  const d1 = interpolate(frame, [3, 12], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const d2 = interpolate(frame, [priceAt, priceAt + 12], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const burst = interpolate(frame, [5, 22], [0, 1], clamp);
  return (
    <svg width={886} height={1920} viewBox="0 0 886 1920" style={{position: 'absolute', inset: 0}}>
      <defs>
        <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="5" result="b" />
          <feMerge>
            <feMergeNode in="b" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>
      <circle cx={icon.x} cy={icon.y} r={56} fill="none" stroke={colors.emeraldGlow} strokeWidth={6} pathLength={1} strokeDasharray="1 1" strokeDashoffset={1 - d1} filter="url(#glow)" style={{rotate: '-90deg', transformOrigin: `${icon.x}px ${icon.y}px`}} />
      {Array.from({length: 8}).map((_, i) => {
        const a = (i / 8) * Math.PI * 2 + 0.2;
        const r0 = 68 + burst * 18;
        const r1 = r0 + 22 * (1 - burst);
        return <line key={i} x1={icon.x + Math.cos(a) * r0} y1={icon.y + Math.sin(a) * r0} x2={icon.x + Math.cos(a) * r1} y2={icon.y + Math.sin(a) * r1} stroke={colors.emeraldGlow} strokeWidth={5} strokeLinecap="round" opacity={burst > 0 ? 1 - burst : 0} />;
      })}
      <rect x={price.x - 108} y={price.y - 38} width={216} height={76} rx={38} fill="none" stroke={colors.emeraldGlow} strokeWidth={6} pathLength={1} strokeDasharray="1 1" strokeDashoffset={1 - d2} filter="url(#glow)" />
    </svg>
  );
};

/** A rounded highlight that draws itself around a row of the app (x, y = top left). */
export const HighlightRect = ({x, y, w, h, color = colors.emeraldGlow}: {x: number; y: number; w: number; h: number; color?: string}) => {
  const frame = useCurrentFrame();
  const d = interpolate(frame, [0, 12], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  return (
    <svg width={886} height={1920} viewBox="0 0 886 1920" style={{position: 'absolute', inset: 0}}>
      <defs>
        <filter id="glowRect" x="-20%" y="-50%" width="140%" height="200%">
          <feGaussianBlur stdDeviation="6" result="b" />
          <feMerge>
            <feMergeNode in="b" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>
      <rect x={x} y={y} width={w} height={h} rx={34} fill="none" stroke={color} strokeWidth={6} pathLength={1} strokeDasharray="1 1" strokeDashoffset={1 - d} filter="url(#glowRect)" />
    </svg>
  );
};

/** A tap: a soft white dot that expands into a fading ring. Rendered from frame 0 of its sequence. */
export const TapRing = ({x, y}: {x: number; y: number}) => {
  const frame = useCurrentFrame();
  const p = interpolate(frame, [0, 12], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  return (
    <svg width={886} height={1920} viewBox="0 0 886 1920" style={{position: 'absolute', inset: 0}}>
      <circle cx={x} cy={y} r={30} fill="rgba(255,255,255,0.35)" opacity={interpolate(frame, [0, 3, 9], [0, 1, 0], clamp)} />
      <circle cx={x} cy={y} r={30 + p * 34} fill="none" stroke={colors.white} strokeWidth={5} opacity={(1 - p) * 0.9} />
    </svg>
  );
};

/** A small padlock drawn for the closing card. */
export const Lock = ({size = 44}: {size?: number}) => {
  const s = useSpring(30, {damping: 12});
  return (
    <svg width={size} height={size} viewBox="-30 -36 60 66" style={{scale: String(s), overflow: 'visible'}}>
      <path d="M -14 -6 V -16 A 14 14 0 0 1 14 -16 V -6" fill="none" stroke={colors.emeraldGlow} strokeWidth={6} />
      <rect x={-22} y={-8} width={44} height={34} rx={7} fill={colors.emeraldGlow} />
    </svg>
  );
};

/** Grandpa Pavel's Even badge where the balance scene left it, fading as the app's own pill shows. */
export const EvenBadge = ({locale}: {locale: Locale}) => {
  const frame = useCurrentFrame();
  const pill = EVEN_PILL[locale];
  return (
    <div style={{position: 'absolute', left: 0, top: 0, transformOrigin: '0 0', translate: `${pill.x}px ${pill.y}px`, scale: String(pill.scale), opacity: interpolate(frame, [8, 14], [1, 0], clamp)}}>
      <div style={{translate: '-50% -50%', fontFamily, fontWeight: 800, fontSize: 54, color: AMBER, background: 'rgba(60,48,20,1)', padding: '14px 38px', borderRadius: 999, whiteSpace: 'nowrap'}}>
        {scaleLabels[locale].even} 🤝
      </div>
    </div>
  );
};
