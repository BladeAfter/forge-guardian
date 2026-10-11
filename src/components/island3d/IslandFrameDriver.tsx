import { useEffect, useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import { useRapier } from '@react-three/rapier';
import { frameDelta, frameDiagnostics, qualityMonitor, qualitySettings, type GameQuality } from '../../gamePerformance';

/** Uses R3F's single loop; Rapier remains fixed-step, with bounded catch-up. */
export function IslandFrameDriver({ onQuality }: { onQuality: (quality: GameQuality) => void }) {
  const { step, world } = useRapier();
  const monitor = useRef(qualityMonitor()), diagnose = useRef(frameDiagnostics('island'));
  const resume = useRef(true), quality = useRef<GameQuality>('high');
  useEffect(() => {
    const reset = () => { resume.current = true; };
    document.addEventListener('visibilitychange', reset); window.addEventListener('pageshow', reset);
    return () => { document.removeEventListener('visibilitychange', reset); window.removeEventListener('pageshow', reset); };
  }, []);
  useFrame(({ gl, setDpr }, rawDelta) => {
    if (document.hidden) { resume.current = true; return; }
    const start = performance.now();
    const dt = resume.current ? 0 : frameDelta(rawDelta); resume.current = false;
    step(dt);
    const next = monitor.current.sample(rawDelta);
    if (next !== quality.current) { quality.current = next; setDpr(qualitySettings[next].resolution); onQuality(next); }
    diagnose.current(rawDelta, performance.now() - start, gl.info.render.calls + world.bodies.len());
  }, -50);
  return null;
}