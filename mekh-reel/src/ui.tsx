import React from 'react';
import { AbsoluteFill, continueRender, delayRender, staticFile, useCurrentFrame } from 'remotion';
import { C, SANS, SERIF } from './tokens';
import { EASE, ramp } from './motion';

// ───────── fonts: the site's own Mehr Display / Mehr Sans (Tajik Cyrillic) ─────────
export const useSiteFonts = () => {
  const [handle] = React.useState(() => delayRender('mehr fonts'));
  React.useEffect(() => {
    const faces = [
      new FontFace('Mehr Display', `url(${staticFile('site/assets/fonts/MehrDisplay-Regular.woff2')})`, { weight: '400' }),
      new FontFace('Mehr Sans', `url(${staticFile('site/assets/fonts/MehrSans-400.woff2')})`, { weight: '100 900' }),
    ];
    Promise.all(faces.map((f) => f.load()))
      .then((l) => l.forEach((f) => document.fonts.add(f)))
      .catch(() => undefined)
      .finally(() => continueRender(handle));
  }, [handle]);
};

// ───────── blur-slide word reveal (shot card: blur-slide) ─────────
// opacity / translateY / blur share ONE progress p and ONE easing — that is the whole trick.
export type Word = {
  text: string;
  style?: React.CSSProperties;
};

export const Words: React.FC<{
  words: Word[];
  start: number;
  stagger?: number;
  dur?: number;
  dy?: number;
  blur?: number;
  gap?: string;
  /** frame at which the whole line exits (blur-slide in reverse), optional */
  exitAt?: number;
  exitDur?: number;
  style?: React.CSSProperties;
}> = ({ words, start, stagger = 4, dur = 22, dy = 40, blur = 14, gap = '0.26em', exitAt, exitDur = 10, style }) => {
  const frame = useCurrentFrame();
  const out = exitAt === undefined ? 0 : ramp(frame, exitAt, exitDur, EASE.exit);
  return (
    <div
      style={{
        display: 'flex',
        flexWrap: 'wrap',
        alignItems: 'baseline',
        columnGap: gap,
        rowGap: '0.12em',
        opacity: 1 - out,
        transform: `translateY(${(-out * 24).toFixed(2)}px)`,
        filter: out > 0.001 ? `blur(${(out * 10).toFixed(2)}px)` : undefined,
        ...style,
      }}
    >
      {words.map((w, i) => {
        const p = ramp(frame, start + i * stagger, dur, EASE.out);
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              opacity: p,
              transform: `translateY(${((1 - p) * dy).toFixed(2)}px)`,
              filter: p >= 0.999 ? undefined : `blur(${((1 - p) * blur).toFixed(2)}px)`,
              ...w.style,
            }}
          >
            {w.text}
          </span>
        );
      })}
    </div>
  );
};

/** "plain plain *emph* plain" → Word[]; *…* marks the accent word(s). */
export const parse = (s: string, emph: React.CSSProperties): Word[] => {
  const out: Word[] = [];
  let on = false;
  for (const tok of s.split(' ')) {
    let t = tok;
    const starts = t.startsWith('*');
    const ends = t.endsWith('*') && t.length > 1;
    if (starts) { on = true; t = t.slice(1); }
    if (ends) t = t.slice(0, -1);
    out.push({ text: t, style: on ? emph : undefined });
    if (ends) on = false;
  }
  return out;
};

// ───────── stage: flat room colour + soft light + static grain (deterministic) ─────────
const GRAIN =
  "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' seed='7'/><feColorMatrix values='0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 .55 0'/></filter><rect width='100%' height='100%' filter='url(%23n)'/></svg>\")";

export const Stage: React.FC<{
  bg: string;
  glow?: string;
  glowAt?: [number, number];
  grain?: number;
  children?: React.ReactNode;
}> = ({ bg, glow, glowAt = [0.5, 0.28], grain = 0.07, children }) => (
  <AbsoluteFill style={{ background: bg, overflow: 'hidden' }}>
    {glow && (
      <AbsoluteFill
        style={{
          background: `radial-gradient(ellipse 85% 55% at ${glowAt[0] * 100}% ${glowAt[1] * 100}%, ${glow}, transparent 70%)`,
        }}
      />
    )}
    {children}
    <AbsoluteFill style={{ backgroundImage: GRAIN, opacity: grain, mixBlendMode: 'overlay', pointerEvents: 'none' }} />
  </AbsoluteFill>
);

// ───────── small shared pieces ─────────
export const Chip: React.FC<{ kind: 'before' | 'now'; scale?: number }> = ({ kind, scale = 1 }) => {
  const isNow = kind === 'now';
  return (
    <div
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 12,
        height: 56 * scale,
        padding: `0 ${26 * scale}px`,
        borderRadius: 999,
        fontFamily: SANS,
        fontWeight: 700,
        fontSize: 30 * scale,
        letterSpacing: '0.16em',
        background: isNow ? C.accent : 'transparent',
        color: isNow ? C.onAccent : C.before,
        border: isNow ? 'none' : `2px solid ${C.before}`,
      }}
    >
      {isNow ? 'СЕЙЧАС' : 'ДО'}
    </div>
  );
};

export const WaIcon: React.FC<{ size?: number; color?: string }> = ({ size = 36, color = 'currentColor' }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
    <path d="M20 11.6a8 8 0 0 1-11.7 7.1L4 20l1.4-4.1A8 8 0 1 1 20 11.6z" />
    <path d="M9 9.3c.2 2.7 2.4 4.9 5.2 5.4" />
  </svg>
);

export const Arrow: React.FC<{ size?: number; color?: string }> = ({ size = 36, color = 'currentColor' }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
    <path d="M5 12h14M13 6l6 6-6 6" />
  </svg>
);
