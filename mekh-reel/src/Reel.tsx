import React from 'react';
import { AbsoluteFill, Audio, Sequence, interpolate, staticFile, useCurrentFrame } from 'remotion';
import { FPS, MUSIC_START_S } from './tokens';
import { EASE, ramp } from './motion';
import { ORDER, SHOTS, TOTAL, WIPE, ShotKey } from './timeline';
import { CASES } from './cases';
import { CaseShot } from './Case';
import { Hook, More, Outro, Tease, Value } from './Scenes';
import { SFX } from './sfx';
import { useSiteFonts } from './ui';

const Wipe: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const f = useCurrentFrame();
  const w = ramp(f, 0, WIPE, EASE.smooth);
  return <AbsoluteFill style={{ clipPath: `inset(${((1 - w) * 100).toFixed(2)}% 0 0 0)` }}>{children}</AbsoluteFill>;
};

const scene = (key: ShotKey): React.ReactNode => {
  const c = CASES.find((x) => x.key === key);
  if (c) return <CaseShot def={c} total={CASES.length} />; // owns its own wipe
  switch (key) {
    case 'hook': return <Hook />;
    case 'tease': return <Tease />;
    case 'more': return <Wipe><More /></Wipe>;
    case 'value': return <Wipe><Value /></Wipe>;
    case 'outro': return <Wipe><Outro /></Wipe>;
  }
  return null;
};

export const MekhReel: React.FC<{ bgm?: boolean }> = ({ bgm = true }) => {
  useSiteFonts();
  return (
    <AbsoluteFill style={{ background: '#081A13' }}>
      {ORDER.map((key, i) => {
        const sh = SHOTS[key];
        // keep the previous shot alive underneath while the next one wipes in
        const dur = sh.dur + (i < ORDER.length - 1 ? WIPE : 0);
        return (
          <Sequence key={key} from={sh.from} durationInFrames={dur} name={key}>
            {scene(key)}
          </Sequence>
        );
      })}

      {SFX.map((p, i) => (
        <Sequence key={i} from={Math.max(0, p.from)} durationInFrames={p.dur ?? 90} name={p.note}>
          <Audio src={staticFile(p.src)} volume={p.volume} />
        </Sequence>
      ))}

      {bgm && (
        <Audio
          src={staticFile('audio/bgm-tech-house.mp3')}
          trimBefore={Math.round(MUSIC_START_S * FPS)}
          volume={(f) =>
            0.6 *
            interpolate(f, [0, 8, TOTAL - 45, TOTAL - 4], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
          }
        />
      )}
    </AbsoluteFill>
  );
};
