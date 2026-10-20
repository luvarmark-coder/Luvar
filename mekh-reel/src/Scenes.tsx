import React from 'react';
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from 'remotion';
import { C, SANS, SERIF, beatF } from './tokens';
import { EASE, mix, ramp } from './motion';
import { Arrow, Chip, Stage, WaIcon, Words, parse } from './ui';
import { SHOTS } from './timeline';

const emph: React.CSSProperties = { color: C.accent, fontStyle: 'italic' };
const eyebrow: React.CSSProperties = {
  position: 'absolute', left: 80, fontFamily: SANS, fontSize: 30, fontWeight: 700, letterSpacing: '0.18em', color: C.fg3,
};

const Drift: React.FC<{ dur: number; children: React.ReactNode }> = ({ dur, children }) => {
  const f = useCurrentFrame();
  return <AbsoluteFill style={{ transform: `scale(${mix(1, 1.03, ramp(f, 0, dur, EASE.smooth)).toFixed(4)})`, transformOrigin: '50% 45%' }}>{children}</AbsoluteFill>;
};

// ───────────── 0–12 beats: hook (low energy, music intro) ─────────────
export const Hook: React.FC = () => {
  const f = useCurrentFrame();
  const B6 = beatF(6);
  const dimA = ramp(f, B6 - 2, 14, EASE.smooth);
  return (
    <Stage bg={C.bg} glow="rgba(94,227,172,0.16)" glowAt={[0.5, 0.42]}>
      <Drift dur={SHOTS.hook.dur}>
        {/* frame 0 is never empty: brand eyebrow + hairline are already on screen */}
        <div style={{ ...eyebrow, top: 236, display: 'flex', alignItems: 'center', gap: 18 }}>
          <span style={{ width: 16, height: 16, borderRadius: 8, background: C.accent }} />
          MEKH · ДУБАЙ ⇄ ДУШАНБЕ
        </div>
        <div style={{ position: 'absolute', left: 80, right: 80, top: 300, height: 2, background: C.line, transform: `scaleX(${ramp(f, 0, 26, EASE.snappy).toFixed(3)})`, transformOrigin: '0 50%' }} />

        <div style={{ position: 'absolute', left: 80, right: 80, top: 470, opacity: mix(1, 0.32, dimA) }}>
          <Words
            words={'Большинство начинает сайт с дизайна.'.split(' ').map((text) => ({ text }))}
            start={3} stagger={4} dur={24} dy={50} blur={16}
            style={{ fontFamily: SERIF, fontSize: 112, lineHeight: 1.06, letterSpacing: '-0.03em', color: C.fg2 }}
          />
        </div>
        <div style={{ position: 'absolute', left: 80, right: 80, top: 980 }}>
          <Words
            words={parse('Я начинаю с *вашего бизнеса.*', emph)}
            start={B6} stagger={5} dur={26} dy={56} blur={18}
            style={{ fontFamily: SERIF, fontSize: 132, lineHeight: 1.04, letterSpacing: '-0.035em', color: C.fg }}
          />
        </div>
      </Drift>
    </Stage>
  );
};

// ───────────── 12–16 beats: tease (riser into the drop) ─────────────
export const Tease: React.FC = () => {
  const f = useCurrentFrame();
  const chips = ramp(f, 26, 16, EASE.overshoot);
  return (
    <Stage bg={C.bg} glow="rgba(94,227,172,0.20)" glowAt={[0.5, 0.5]}>
      <div style={{ position: 'absolute', left: 80, right: 80, top: 560 }}>
        <Words words={[{ text: 'Шесть' }, { text: 'работ.', style: emph }]} start={0} stagger={5} dur={22} dy={50} blur={16}
          style={{ fontFamily: SERIF, fontSize: 168, lineHeight: 1.02, letterSpacing: '-0.04em', color: C.fg }} />
        <div style={{ marginTop: 34 }}>
          <Words words={'Что было — и что стало.'.split(' ').map((text) => ({ text }))} start={12} stagger={3} dur={20} dy={30} blur={10}
            style={{ fontFamily: SANS, fontSize: 60, color: C.fg2, letterSpacing: '-0.01em' }} />
        </div>
        <div style={{ marginTop: 56, display: 'flex', alignItems: 'center', gap: 22, opacity: chips, transform: `scale(${mix(0.9, 1, chips).toFixed(3)})`, transformOrigin: '0 50%' }}>
          <Chip kind="before" />
          <span style={{ color: C.fg3, display: 'flex' }}><Arrow size={48} /></span>
          <Chip kind="now" />
        </div>
      </div>
    </Stage>
  );
};

// ───────────── 64–70 beats: more work (accelerating deal-in grid, names stay readable) ─────────────
type Tile = { name: string; type: string; thumb?: string };
const TILES: Tile[] = [
  { name: 'Rome Residence', type: 'жилой комплекс', thumb: 'rome-thumb' },
  { name: 'Huseynzoda Avenue', type: 'жилой квартал', thumb: 'huseynzoda-thumb' },
  { name: 'LUMIÈRE', type: 'салон красоты', thumb: 'lumiere-thumb' },
  { name: 'NOIR Estate', type: 'недвижимость', thumb: 'noir-thumb' },
  { name: 'APEX Drive', type: 'аренда авто', thumb: 'apex-thumb' },
  { name: 'MAQSAD', type: 'брендинг', thumb: 'maqsad-thumb' },
  { name: 'Menu Engine', type: 'меню + WhatsApp', thumb: 'menu-thumb' },
  { name: 'MATRIX', type: 'по реальным фото', thumb: 'matrix-thumb' },
];
// each tile arrives faster than the last (R2): gaps 9,8,7,6,5,4,3,3 frames
const GAPS = [0, 9, 8, 7, 6, 5, 4, 3, 3];
const TILE_START = GAPS.reduce<number[]>((a, g, i) => [...a, (i ? a[i - 1] : 8) + g], []);

export const More: React.FC = () => {
  const f = useCurrentFrame();
  const CW = 300, GAP = 30, X0 = 60, Y0 = 500, PITCH = 292;
  const cell = (i: number) => ({ x: X0 + (i % 3) * (CW + GAP), y: Y0 + Math.floor(i / 3) * PITCH });
  return (
    <Stage bg={C.bg} glow="rgba(94,227,172,0.12)" glowAt={[0.5, 0.2]}>
      <div style={{ ...eyebrow, top: 232 }}>ПОРТФОЛИО</div>
      <div style={{ position: 'absolute', left: 80, right: 80, top: 282 }}>
        <Words words={parse('И ещё *8 проектов*', emph)} start={0} stagger={4} dur={22} dy={44} blur={14}
          style={{ fontFamily: SERIF, fontSize: 104, lineHeight: 1.02, letterSpacing: '-0.03em', color: C.fg }} />
      </div>
      {[...TILES, null].map((t, i) => {
        const p = ramp(f, TILE_START[i], 20, EASE.out);
        const { x, y } = cell(i);
        return (
          <div key={i} style={{ position: 'absolute', left: x, top: y, width: CW, opacity: p, transform: `translate(${((1 - p) * 90).toFixed(1)}px, ${((1 - p) * 230).toFixed(1)}px) scale(${mix(0.9, 1, p).toFixed(3)})`, filter: p >= 0.999 ? undefined : `blur(${((1 - p) * 8).toFixed(1)}px)` }}>
            {t ? (
              <>
                <div style={{ width: CW, height: 187, borderRadius: 18, overflow: 'hidden', boxShadow: '0 18px 40px rgba(0,0,0,0.4)', outline: '1px solid rgba(255,255,255,0.12)' }}>
                  <Img src={staticFile(`site/assets/img/work/${t.thumb}.webp`)} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                </div>
                <div style={{ marginTop: 12, fontFamily: SANS, fontSize: 34, fontWeight: 600, color: C.fg, whiteSpace: 'nowrap', letterSpacing: '-0.01em' }}>{t.name}</div>
                <div style={{ fontFamily: SANS, fontSize: 32, color: C.fg3, whiteSpace: 'nowrap' }}>{t.type}</div>
              </>
            ) : (
              <div style={{ width: CW, height: 187 + 12 + 40 + 38, borderRadius: 18, background: C.accent, color: C.onAccent, padding: 24, boxSizing: 'border-box', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
                <div style={{ fontFamily: SANS, fontSize: 30, fontWeight: 700, letterSpacing: '0.16em' }}>NEURON</div>
                <div style={{ fontFamily: SERIF, fontSize: 34, lineHeight: 1.05, letterSpacing: '-0.02em' }}>AI-автоматизация</div>
              </div>
            )}
          </div>
        );
      })}
    </Stage>
  );
};

// ───────────── 70–78 beats: what the business gets ─────────────
const VALUES = ['Заявки — сразу *в WhatsApp*', 'Заказ — *без очереди*', 'Сайт — *на языке ваших клиентов*'];
export const Value: React.FC = () => {
  const f = useCurrentFrame();
  const starts = [6, 30, 54];
  return (
    <Stage bg={C.bg} glow="rgba(94,227,172,0.14)" glowAt={[0.5, 0.3]}>
      <div style={{ ...eyebrow, top: 232, opacity: ramp(f, 0, 14, EASE.out) }}>ЧТО ЭТО ДАЁТ БИЗНЕСУ</div>
      {VALUES.map((v, i) => {
        const y = 400 + i * 330;
        const line = ramp(f, starts[i] - 4, 24, EASE.snappy);
        return (
          <div key={i}>
            <div style={{ position: 'absolute', left: 80, right: 80, top: y, height: 2, background: C.line, transform: `scaleX(${line.toFixed(3)})`, transformOrigin: '0 50%' }} />
            <div style={{ position: 'absolute', left: 80, top: y + 34, fontFamily: SANS, fontSize: 34, fontWeight: 700, letterSpacing: '0.16em', color: C.accent, opacity: ramp(f, starts[i], 14, EASE.out) }}>0{i + 1}</div>
            <div style={{ position: 'absolute', left: 80, right: 80, top: y + 92 }}>
              <Words words={parse(v, emph)} start={starts[i]} stagger={4} dur={24} dy={44} blur={14}
                style={{ fontFamily: SERIF, fontSize: 96, lineHeight: 1.04, letterSpacing: '-0.03em', color: C.fg }} />
            </div>
          </div>
        );
      })}
      <div style={{ position: 'absolute', left: 80, top: 400 + 2 * 330 + 92 + 232, fontFamily: SANS, fontSize: 40, letterSpacing: '0.2em', color: C.fg3, opacity: ramp(f, 82, 18, EASE.out) }}>
        RU · EN · TJ · AR
      </div>
    </Stage>
  );
};

// ───────────── 78–86 beats: outro lockup, sign-off hold ≥1s ─────────────
export const Outro: React.FC = () => {
  const f = useCurrentFrame();
  const word = 'mekh.dev'.split('');
  const cta = ramp(f, 62, 22, EASE.overshoot);
  const pulse = 1 + 0.012 * Math.sin((Math.max(0, f - 84) / 29) * Math.PI * 2);
  return (
    <Stage bg={C.bg} glow="rgba(94,227,172,0.24)" glowAt={[0.5, 0.42]}>
      <div style={{ position: 'absolute', left: 0, right: 0, top: 620, display: 'flex', justifyContent: 'center', fontFamily: SERIF, fontSize: 220, letterSpacing: '-0.04em', color: C.fg, lineHeight: 1 }}>
        {word.map((ch, i) => {
          const p = ramp(f, 4 + i * 3.2, 20, EASE.out);
          return (
            <span key={i} style={{ display: 'inline-block', opacity: p, transform: `translateX(${((1 - p) * 26).toFixed(1)}px)`, filter: p >= 0.999 ? undefined : `blur(${((1 - p) * 8).toFixed(1)}px)`, color: ch === '.' ? C.accent : C.fg }}>{ch}</span>
          );
        })}
      </div>
      <div style={{ position: 'absolute', left: 80, right: 80, top: 880, textAlign: 'center', opacity: ramp(f, 38, 20, EASE.out), transform: `translateY(${((1 - ramp(f, 38, 20, EASE.out)) * 20).toFixed(1)}px)`, fontFamily: SANS, fontSize: 58, color: C.fg2, letterSpacing: '-0.01em' }}>
        Сайты и AI-автоматизация
      </div>
      <div style={{ position: 'absolute', left: 80, right: 80, top: 962, textAlign: 'center', opacity: ramp(f, 46, 20, EASE.out), fontFamily: SANS, fontSize: 40, color: C.fg3, letterSpacing: '0.14em' }}>
        ДУБАЙ ⇄ ДУШАНБЕ
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, top: 1110, display: 'flex', justifyContent: 'center', opacity: Math.min(1, cta * 2), transform: `translateY(${((1 - cta) * 40).toFixed(1)}px) scale(${(mix(0.92, 1, cta) * pulse).toFixed(4)})` }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 20, height: 112, padding: '0 56px', borderRadius: 999, background: C.accent, color: C.onAccent, fontFamily: SANS, fontSize: 50, fontWeight: 700, letterSpacing: '-0.01em', boxShadow: '0 0 90px rgba(94,227,172,0.35)' }}>
          <WaIcon size={52} />
          Напишите в WhatsApp
        </div>
      </div>
    </Stage>
  );
};
