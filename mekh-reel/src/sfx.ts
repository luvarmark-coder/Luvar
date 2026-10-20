// Declarative SFX pin table. Every `from` is RELATIVE to the timeline (SHOTS.x.from + offset) — never a bare frame.
// Vocabulary (S1): riser / impact / transition / sparkle, plus real-world foley for the one physical tap.
import { SHOTS } from './timeline';
import { beatF } from './tokens';
import { SWAP } from './Case';
import { CASES } from './cases';

export type Pin = { from: number; src: string; volume: number; dur?: number; note: string };
const s = (f: string) => `audio/sfx/${f}.mp3`;

const casePins = (key: (typeof CASES)[number]['key']): Pin[] => {
  const a = SHOTS[key].from;
  return [
    { from: a - 3, src: s('swoosh-quick'), volume: 0.5, note: `${key}: colour wipe in` },
    { from: a + 8, src: s('transition-soft'), volume: 0.32, dur: 26, note: `${key}: desktop card settles` },
    { from: a + SWAP - 1, src: s('transition-snap'), volume: 0.42, note: `${key}: ДО → СЕЙЧАС on beat 4` },
    { from: a + SWAP + 20, src: s('switch-tap'), volume: 0.3, dur: 12, note: `${key}: proof widget pops (real switch tap)` },
  ];
};

export const SFX: Pin[] = [
  { from: SHOTS.hook.from + beatF(6) - 2, src: s('transition-soft'), volume: 0.4, dur: 28, note: 'hook: "Я начинаю с вашего бизнеса" arrives' },
  // riser plateau (≈1.75s in) ends exactly on the drop (beat 16)
  { from: SHOTS.jbdj.from - 52, src: s('riser-cine'), volume: 0.55, dur: 60, note: 'tease: riser into the drop' },
  { from: SHOTS.jbdj.from - 3, src: s('bass-hit-short'), volume: 0.7, dur: 24, note: 'DROP: the first of two big hits' },
  ...CASES.flatMap((c) => casePins(c.key)),
  { from: SHOTS.more.from - 3, src: s('swoosh-quick'), volume: 0.45, note: 'more: wipe in' },
  { from: SHOTS.more.from + 8, src: s('paper-move-quick'), volume: 0.9, dur: 20, note: 'more: tile 1 deals in' },
  { from: SHOTS.more.from + 8 + 17, src: s('paper-move-quick'), volume: 0.75, dur: 18, note: 'more: tile 3' },
  { from: SHOTS.more.from + 8 + 35, src: s('paper-move-quick'), volume: 0.65, dur: 16, note: 'more: tile 5' },
  { from: SHOTS.more.from + 8 + 46, src: s('paper-move-quick'), volume: 0.55, dur: 14, note: 'more: tile 7' },
  { from: SHOTS.value.from - 3, src: s('swoosh-quick'), volume: 0.45, note: 'value: wipe in' },
  { from: SHOTS.value.from + 8, src: s('transition-soft'), volume: 0.28, dur: 24, note: 'value: line 1' },
  { from: SHOTS.value.from + 32, src: s('transition-soft'), volume: 0.28, dur: 24, note: 'value: line 2' },
  { from: SHOTS.value.from + 56, src: s('transition-soft'), volume: 0.32, dur: 24, note: 'value: line 3' },
  { from: SHOTS.outro.from - 3, src: s('swoosh-quick'), volume: 0.4, note: 'outro: wipe in' },
  { from: SHOTS.outro.from + 4, src: s('riser-cine'), volume: 0.5, dur: 56, note: 'outro: riser, assembling the wordmark' },
  { from: SHOTS.outro.from + 40, src: s('impact-zoom-quick'), volume: 0.7, dur: 30, note: 'outro: wordmark lands (second big hit)' },
  { from: SHOTS.outro.from + 42, src: s('shimmer-sparkle-sweep'), volume: 0.5, dur: 70, note: 'outro: sparkle tail into the CTA' },
];
