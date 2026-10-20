import React from 'react';
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from 'remotion';
import { C, SANS, SERIF, beatF } from './tokens';
import { EASE, mix, ramp } from './motion';
import { Arrow, Chip, Stage, WaIcon, Words, parse } from './ui';
import type { CaseDef } from './cases';
import { WIPE } from './timeline';

// ── layout (px, 1080×1920; Reels UI keeps ~top 220 and bottom ~480 busy, so the story lives in 230–1420) ──
const DESK = { w: 820, h: 512, x: 90, y: 490 };
const PHONE = { w: 210, h: 455, y: 560 };
const PANEL = { x: 60, y: 1070, w: 960, h: 350 };
export const SWAP = beatF(4); // "ДО" → "СЕЙЧАС" lands on beat 4 of the shot
const WIDGET_AT = SWAP + 20;

const shadow = '0 40px 90px rgba(0,0,0,0.38), 0 10px 24px rgba(0,0,0,0.25)';

const Screen: React.FC<{ src: string; style?: React.CSSProperties }> = ({ src, style }) => (
  <Img src={staticFile(src)} style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block', ...style }} />
);

// the desktop sits on the side opposite the phone so the phone overlaps only ~45px of it
const deskLeft = (def: CaseDef) => (def.variant === 'phone' ? 40 : def.phoneSide === 'left' ? 1080 - 60 - DESK.w : 60);

const Desktop: React.FC<{ def: CaseDef; f: number }> = ({ def, f }) => {
  const { variant, cover, second } = def;
  const enter = ramp(f, 4, 34, EASE.out);
  let transform = '';
  let opacity = enter;
  // one camera idea per variant
  if (variant === 'tilt') {
    const ry = mix(-24, -9, ramp(f, 4, 60, EASE.out)) + mix(0, 4, ramp(f, 64, 70, EASE.smooth));
    transform = `perspective(2000px) translateX(${((1 - enter) * 320).toFixed(1)}px) rotateY(${ry.toFixed(2)}deg) rotateX(6deg)`;
  } else if (variant === 'push') {
    const s = mix(1, 1.035, ramp(f, 0, 128, EASE.smooth));
    transform = `translateY(${((1 - enter) * 120).toFixed(1)}px) scale(${s.toFixed(4)})`;
  } else if (variant === 'phone') {
    const s = mix(0.94, 0.9, ramp(f, 10, 100, EASE.smooth));
    transform = `translateY(${((1 - enter) * 120).toFixed(1)}px) translateX(-34px) scale(${s.toFixed(4)})`;
    opacity = enter * mix(1, 0.78, ramp(f, 22, 20, EASE.out));
  } else {
    transform = `translateY(${((1 - enter) * 120).toFixed(1)}px)`;
  }

  // inner content: page "scrolls" to the second screen (scroll) or cross-fades (push), on the swap beat
  const sw = ramp(f, SWAP - 4, 20, EASE.smooth);
  let inner: React.ReactNode;
  if (second && variant === 'scroll') {
    inner = (
      <>
        <div style={{ position: 'absolute', inset: 0, transform: `translateY(${(-sw * 100).toFixed(2)}%)` }}><Screen src={cover} /></div>
        <div style={{ position: 'absolute', inset: 0, transform: `translateY(${((1 - sw) * 100).toFixed(2)}%)` }}><Screen src={second} /></div>
      </>
    );
  } else if (second && variant === 'push') {
    inner = (
      <>
        <Screen src={cover} />
        <div style={{ position: 'absolute', inset: 0, opacity: sw }}><Screen src={second} /></div>
      </>
    );
  } else {
    inner = <Screen src={cover} />;
  }

  return (
    <div
      style={{
        position: 'absolute', left: deskLeft(def), top: DESK.y, width: DESK.w, height: DESK.h,
        borderRadius: 28, overflow: 'hidden', boxShadow: shadow, opacity, transform, transformOrigin: '50% 50%',
        outline: '1px solid rgba(255,255,255,0.14)', background: '#000',
      }}
    >
      {inner}
    </div>
  );
};

const Phone: React.FC<{ def: CaseDef; f: number }> = ({ def, f }) => {
  const big = def.variant === 'phone';
  const enter = ramp(f, big ? 12 : 16, 30, EASE.out);
  const left = def.phoneSide === 'left' ? 36 : 1080 - 36 - PHONE.w;
  const scale = big ? 1.1 : 1;
  const rot = big ? 3 : 0;
  const y = big ? PHONE.y - 100 : PHONE.y;
  return (
    <div
      style={{
        position: 'absolute', left: big ? 1080 - 50 - PHONE.w * scale : left, top: y, width: PHONE.w, height: PHONE.h,
        transform: `translateY(${((1 - enter) * 360).toFixed(1)}px) rotate(${rot}deg) scale(${scale})`,
        transformOrigin: '50% 0%', opacity: Math.min(1, enter * 2),
        borderRadius: 42, background: '#0a0a0a', padding: 8, boxShadow: shadow,
        outline: '1px solid rgba(255,255,255,0.16)',
      }}
    >
      <div style={{ width: '100%', height: '100%', borderRadius: 34, overflow: 'hidden', background: '#000' }}>
        <Screen src={def.mob} />
      </div>
    </div>
  );
};

// ── "proof" widgets: one small, hand-built UI beat that shows the "Now" claim in action ──
const pill: React.CSSProperties = {
  position: 'absolute', display: 'flex', alignItems: 'center', gap: 16, height: 84, padding: '0 34px', borderRadius: 999,
  fontFamily: SANS, fontSize: 36, fontWeight: 600, color: C.fg, background: 'rgba(8,26,19,0.94)',
  border: `1.5px solid ${C.line}`, boxShadow: '0 24px 50px rgba(0,0,0,0.35)', whiteSpace: 'nowrap',
};

const Widget: React.FC<{ def: CaseDef; f: number }> = ({ def, f }) => {
  const p = ramp(f, WIDGET_AT, 18, EASE.overshoot);
  const base: React.CSSProperties = { opacity: Math.min(1, p * 2), transform: `translateY(${((1 - p) * 40).toFixed(1)}px) scale(${mix(0.92, 1, p).toFixed(3)})` };
  const rightAnchored = def.phoneSide === 'left' || def.variant === 'phone';
  const side: React.CSSProperties = def.variant === 'phone' ? { left: 96 } : def.phoneSide === 'left' ? { right: 70 } : { left: 70 };
  const top = DESK.y + DESK.h - 56; // widget bottom ≈ 1030, panel top 1070
  void rightAnchored;

  switch (def.widget) {
    case 'form':
      return (
        <div style={{ ...pill, ...side, top, ...base }}>
          <span style={{ color: C.accent, display: 'flex' }}><Arrow size={40} /></span>
          Все букинги → <b style={{ color: C.accent, fontWeight: 700 }}>одна форма</b>
        </div>
      );
    case 'wa':
      return (
        <div style={{ ...pill, ...side, top, ...base }}>
          <span style={{ display: 'flex', width: 52, height: 52, borderRadius: 26, background: '#25D366', color: '#04130D', alignItems: 'center', justifyContent: 'center' }}><WaIcon size={32} /></span>
          Новая заявка на консультацию
        </div>
      );
    case 'search': {
      const typed = 'омбре намад';
      const n = Math.floor(ramp(f, WIDGET_AT + 2, 22, EASE.linear) * typed.length);
      const hit = ramp(f, WIDGET_AT + 28, 14, EASE.overshoot);
      return (
        <div style={{ ...pill, ...side, top, ...base, gap: 18 }}>
          <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke={C.fg2} strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="6.5" /><path d="m16 16 4 4" /></svg>
          <span style={{ minWidth: 235, color: C.fg }}>{typed.slice(0, n)}<span style={{ color: C.accent }}>{n < typed.length ? '|' : ''}</span></span>
          <span style={{ opacity: hit, transform: `scale(${mix(0.8, 1, hit).toFixed(3)})`, display: 'flex', alignItems: 'center', gap: 10, color: C.onAccent, background: C.accent, borderRadius: 999, padding: '8px 22px', fontWeight: 700 }}>
            Ombre Nomade ✓
          </span>
        </div>
      );
    }
    case 'steps': {
      const steps = ['Собрал', 'Время', 'Забрал'];
      return (
        <div style={{ position: 'absolute', top, display: 'flex', gap: 14, ...side, ...base }}>
          {steps.map((s, i) => {
            const q = ramp(f, WIDGET_AT + i * 8, 14, EASE.overshoot);
            return (
              <div key={s} style={{ ...pill, position: 'static', height: 76, padding: '0 28px', fontSize: 34, gap: 12, opacity: q, transform: `scale(${mix(0.85, 1, q).toFixed(3)})` }}>
                <span style={{ width: 40, height: 40, borderRadius: 20, background: i === 2 ? C.accent : C.surface, color: i === 2 ? C.onAccent : C.accent, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 26, fontWeight: 700 }}>{i + 1}</span>
                {s}
              </div>
            );
          })}
        </div>
      );
    }
    case 'time':
      return (
        <div style={{ ...pill, ...side, top, ...base }}>
          <span style={{ color: C.accent }}>●</span> Как можно скорее · <b style={{ color: C.accent, fontWeight: 700 }}>~10 мин</b>
        </div>
      );
    case 'bubble':
      return (
        <div style={{ ...pill, ...side, top, ...base, background: '#0f3a2a', border: '1.5px solid #1f6a4c', borderRadius: 36, borderBottomLeftRadius: 8, height: 'auto', padding: '18px 30px', gap: 18, whiteSpace: 'normal', maxWidth: 640, fontSize: 32, lineHeight: 1.25 }}>
          <span style={{ display: 'flex', color: '#25D366' }}><WaIcon size={44} /></span>
          Здравствуйте! Хочу записаться: Барбершоп
        </div>
      );
  }
};

// ── bottom panel: ДО → СЕЙЧАС ──
const Panel: React.FC<{ def: CaseDef; f: number }> = ({ def, f }) => {
  const enter = ramp(f, 10, 18, EASE.out);
  const emph = { color: C.accent, fontFamily: SERIF, fontStyle: 'italic' as const, letterSpacing: '-0.01em' };
  const textStyle: React.CSSProperties = { fontFamily: SANS, fontWeight: 400, fontSize: 58, lineHeight: 1.16, letterSpacing: '-0.012em', color: C.fg };
  const beforeOut = ramp(f, SWAP, 10, EASE.exit);
  return (
    <div
      style={{
        position: 'absolute', left: PANEL.x, top: PANEL.y, width: PANEL.w, height: PANEL.h, borderRadius: 40,
        background: 'rgba(8,26,19,0.99)', border: `1.5px solid ${C.line}`, boxShadow: '0 -10px 60px rgba(0,0,0,0.25)',
        opacity: enter, transform: `translateY(${((1 - enter) * 50).toFixed(1)}px)`, padding: 44, boxSizing: 'border-box',
      }}
    >
      {/* ДО */}
      <div style={{ position: 'absolute', left: 44, top: 40, right: 44, opacity: 1 - beforeOut }}>
        <div style={{ opacity: ramp(f, 12, 12, EASE.out), marginBottom: 22 }}><Chip kind="before" /></div>
        <Words
          words={parse(def.before, { color: C.before })}
          start={14} stagger={2} dur={20} dy={30} blur={10}
          exitAt={SWAP} exitDur={10}
          style={{ ...textStyle, color: C.fg2 }}
        />
      </div>
      {/* СЕЙЧАС */}
      <div style={{ position: 'absolute', left: 44, top: 40, right: 44 }}>
        <div style={{ opacity: ramp(f, SWAP + 4, 12, EASE.out), transform: `scale(${mix(0.85, 1, ramp(f, SWAP + 4, 16, EASE.overshoot)).toFixed(3)})`, transformOrigin: '0 50%', marginBottom: 22, display: 'inline-block' }}>
          <Chip kind="now" />
        </div>
        <Words words={parse(def.now, emph)} start={SWAP + 8} stagger={2.2} dur={20} dy={30} blur={10} style={textStyle} />
      </div>
    </div>
  );
};

export const CaseShot: React.FC<{ def: CaseDef; total: number }> = ({ def, total }) => {
  const f = useCurrentFrame();
  const wipe = ramp(f, 0, WIPE, EASE.smooth); // 0 → 1 colour wipe from the bottom edge
  const r = def.room;
  const nameStyle: React.CSSProperties = { fontFamily: SERIF, fontSize: 112, lineHeight: 1, letterSpacing: '-0.03em', color: r.ink };
  return (
    <AbsoluteFill style={{ clipPath: `inset(${((1 - wipe) * 100).toFixed(2)}% 0 0 0)` }}>
      <Stage bg={r.bg} glow={r.glow} glowAt={[0.5, 0.22]}>
        {/* header */}
        <div
          style={{
            position: 'absolute', left: 80, top: 232, fontFamily: SANS, fontSize: 32, fontWeight: 700, letterSpacing: '0.18em',
            color: r.ink, opacity: ramp(f, 6, 14, EASE.out) * 0.82, display: 'flex', gap: 22, alignItems: 'center',
          }}
        >
          <span>ПРОЕКТ {String(def.n).padStart(2, '0')} / {String(total).padStart(2, '0')}</span>
          <span style={{ width: 56, height: 2, background: r.ink2, opacity: 0.6 }} />
        </div>
        <Words words={[{ text: def.name }]} start={6} stagger={0} dur={26} dy={46} blur={16} style={{ position: 'absolute', left: 76, top: 290, ...nameStyle }} />
        <div style={{ position: 'absolute', left: 80, top: 420, fontFamily: SANS, fontSize: 38, color: r.ink2, opacity: ramp(f, 14, 20, EASE.out), transform: `translateY(${((1 - ramp(f, 14, 20, EASE.out)) * 16).toFixed(1)}px)` }}>
          {def.meta}
        </div>

        <Desktop def={def} f={f} />
        <Phone def={def} f={f} />
        <Widget def={def} f={f} />
        <Panel def={def} f={f} />
      </Stage>
    </AbsoluteFill>
  );
};
