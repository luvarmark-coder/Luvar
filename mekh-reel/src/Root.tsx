import React from 'react';
import { Composition } from 'remotion';
import { MekhReel } from './Reel';
import { FPS, H, W } from './tokens';
import { TOTAL } from './timeline';

export const Root: React.FC = () => (
  <Composition id="MekhReel" component={MekhReel} durationInFrames={TOTAL} fps={FPS} width={W} height={H} defaultProps={{ bgm: true }} />
);
