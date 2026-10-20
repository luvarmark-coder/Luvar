// The single source of truth for timing. Everything (shots, SFX pins) derives from this, in BEATS.
import { beatF } from './tokens';

export const WIPE = 12; // frames the incoming shot overlaps the previous one (colour wipe)

const spec = [
  ['hook', 0, 12],
  ['tease', 12, 16],
  ['jbdj', 16, 24],
  ['velour', 24, 32],
  ['bil', 32, 40],
  ['romashka', 40, 48],
  ['coffeemoose', 48, 56],
  ['tandis', 56, 64],
  ['more', 64, 70],
  ['value', 70, 78],
  ['outro', 78, 86],
] as const;

export type ShotKey = (typeof spec)[number][0];

export const SHOTS = Object.fromEntries(
  spec.map(([key, a, b]) => [key, { key, beat: a, beats: b - a, from: beatF(a), dur: beatF(b) - beatF(a) }]),
) as Record<ShotKey, { key: ShotKey; beat: number; beats: number; from: number; dur: number }>;

export const ORDER = spec.map((s) => s[0]) as ShotKey[];
export const TOTAL = beatF(86);
