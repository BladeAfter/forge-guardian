import { describe, expect, it } from 'vitest';
import { frameDelta, qualityMonitor, qualitySettings } from './gamePerformance';
describe('Telegram frame timing', () => {
  it('preserves two minutes of simulation time at 30, 60 and 120Hz', () => {
    for (const fps of [30, 60, 120]) {
      let elapsed = 0;
      for (let i = 0; i < fps * 120; i++) elapsed += frameDelta(1 / fps);
      expect(elapsed).toBeCloseTo(120, 6);
    }
  });
  it('does not replay a long stalled/background frame', () => {
    expect(frameDelta(1.5)).toBe(0);
    expect(frameDelta(30)).toBe(0);
    expect(frameDelta(.1)).toBe(.05);
  });
  it('reduces secondary effects after sustained slow frames, not one stall', () => {
    const monitor = qualityMonitor();
    monitor.sample(1.5); expect(monitor.quality).toBe('high');
    for (let i = 0; i < 160; i++) monitor.sample(.04);
    expect(monitor.quality).not.toBe('high');
    expect(qualitySettings.low.particles).toBe(15);
  });
});