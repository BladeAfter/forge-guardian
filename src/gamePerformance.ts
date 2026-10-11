/** Seconds admitted to simulation: never replay a background/stalled interval. */
export function frameDelta(seconds: number) {
  return Number.isFinite(seconds) && seconds > 0 && seconds < .25 ? Math.min(seconds, .05) : 0;
}
export type GameQuality = 'high' | 'balanced' | 'low';
export const qualitySettings = {
  high: { resolution: 1, particles: 70, wake: 6 },
  balanced: { resolution: .9, particles: 35, wake: 4 },
  low: { resolution: .75, particles: 15, wake: 2 },
};
export function qualityMonitor() {
  let quality: GameQuality = 'high', total = 0, samples = 0, slow = 0, fast = 0;
  return {
    get quality() { return quality; },
    sample(seconds: number): GameQuality {
      if (!Number.isFinite(seconds) || seconds <= 0 || seconds >= .25) return quality;
      total += seconds; samples++;
      if (total < 2) return quality;
      const average = total / samples;
      slow = average > .028 ? slow + 1 : 0;
      fast = average < .019 ? fast + 1 : 0;
      if (slow >= 2) { quality = quality === 'high' ? 'balanced' : 'low'; slow = 0; }
      if (fast >= 5) { quality = quality === 'low' ? 'balanced' : 'high'; fast = 0; }
      total = 0; samples = 0;
      return quality;
    },
  };
}
/** Development-only, opt-in instrumentation. Never displays player data. */
export function frameDiagnostics(name: string) {
  const enabled = import.meta.env.DEV && new URLSearchParams(location.search).has('gamePerf');
  let samples = 0, total = 0, peak = 0, logic = 0;
  return (delta: number, updateMs: number, entities: number) => {
    if (!enabled) return;
    samples++; total += delta; peak = Math.max(peak, delta); logic += updateMs;
    if (total < 5) return;
    console.debug('[gamePerf]', { name, fps: samples / total, frameMs: total / samples * 1000, peakMs: peak * 1000, updateMs: logic / samples, entities, loops: 1 });
    samples = 0; total = 0; peak = 0; logic = 0;
  };
}