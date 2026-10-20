// easing primitives — copied from video-shotcraft demos/_fixtures/Polish.tsx (bezier / EASE / ramp)
// ───────────────────────── 缓动 ─────────────────────────

export const clamp01 = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x);

// cubic-bezier(x1,y1,x2,y2) → (t)=>number，与 CSS 同义；Newton-Raphson 求解，失败退二分。
// x1/x2 须在 [0,1]；y 可越界（做预备/过冲）。输入 t 自动钳到 [0,1]。
export const bezier = (x1: number, y1: number, x2: number, y2: number) => {
  if (x1 === y1 && x2 === y2) return (t: number) => clamp01(t);
  const ax = 1 - 3 * x2 + 3 * x1, bx = 3 * x2 - 6 * x1, cx = 3 * x1;
  const ay = 1 - 3 * y2 + 3 * y1, by = 3 * y2 - 6 * y1, cy = 3 * y1;
  const sx = (u: number) => ((ax * u + bx) * u + cx) * u;
  const sy = (u: number) => ((ay * u + by) * u + cy) * u;
  const dx = (u: number) => (3 * ax * u + 2 * bx) * u + cx;
  const solve = (x: number) => {
    let u = x;
    for (let i = 0; i < 8; i++) {
      const err = sx(u) - x;
      if (Math.abs(err) < 1e-7) return u;
      const d = dx(u);
      if (Math.abs(d) < 1e-6) break;
      u -= err / d;
    }
    let lo = 0, hi = 1;
    u = x;
    for (let i = 0; i < 40; i++) {
      const v = sx(u);
      if (Math.abs(v - x) < 1e-7) break;
      if (v < x) lo = u; else hi = u;
      u = (lo + hi) / 2;
    }
    return u;
  };
  return (t: number) => (t <= 0 ? 0 : t >= 1 ? 1 : sy(solve(t)));
};

// 命名缓动预设（入场 snappy / 换位 smooth / 出场 exit / 预备 anticip / 过冲 overshoot）
export const EASE = {
  snappy: bezier(0.16, 1, 0.3, 1), // 强 ease-out（≈ expo-out）：入场、急推落定
  out: bezier(0.22, 1, 0.36, 1), // 柔一点的 ease-out（≈ quint-out）：次要元素入场、跟随
  smooth: bezier(0.65, 0, 0.35, 1), // 对称 in-out：换位、相机平移
  swift: bezier(0.4, 0, 0.2, 1), // 不对称 in-out（起步稍快、落点很软）：通用位移
  exit: bezier(0.7, 0, 0.84, 0), // 强 ease-in（≈ quart-in）：出场、甩出画外
  anticip: bezier(0.5, -0.32, 0.25, 1), // 先反向回拉 ~5% 再冲出：大动作前的预备
  overshoot: bezier(0.34, 1.45, 0.64, 1), // 冲过头 ~8% 再回落：弹出、落座
  linear: (t: number) => clamp01(t),
};

// 分段进度：frame 在 [start, start+dur] 内归一化 → 缓动，越界钳位（所有动效的时间轴原语）
export const ramp = (frame: number, start: number, dur: number, ease: (t: number) => number = EASE.snappy) =>
  ease(clamp01((frame - start) / Math.max(1e-6, dur)));


export const mix = (a: number, b: number, t: number) => a + (b - a) * t;
