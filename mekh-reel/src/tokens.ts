// Design tokens lifted from mehroj-dev.netlify.app (assets/css/site.css) — the reel speaks the site's own language.
export const C = {
  bg: '#081A13',
  bgAlt: '#0C2219',
  surface: '#112B21',
  fg: '#EEECE1',
  fg2: '#B4C2B9',
  fg3: '#8FA59A',
  accent: '#5EE3AC', // "now"
  onAccent: '#04130D',
  before: '#E8A84A', // "before"
  line: '#22463A',
};

export const SERIF = '"Mehr Display", Georgia, serif';
export const SANS = '"Mehr Sans", system-ui, sans-serif';

export const W = 1080;
export const H = 1920;
export const FPS = 30;

// BGM: bgm-tech-house.mp3 — 124 BPM, beat grid fitted by least squares (residual ±19ms), first beat at 1.483s.
// Video frame 0 == music bar 3 (t=7.289s) so the kick drop (music bar 7) lands on video beat 16.
export const BPM = 124;
export const BEAT_S = 60 / BPM;
export const MUSIC_T0 = 1.483;
export const MUSIC_START_S = MUSIC_T0 + 12 * BEAT_S;
export const beatF = (n: number) => Math.round(n * BEAT_S * FPS);
