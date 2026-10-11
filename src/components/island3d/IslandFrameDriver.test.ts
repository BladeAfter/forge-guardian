import { beforeEach, describe, expect, it, vi } from 'vitest';
const harness = vi.hoisted(() => ({ frame: undefined as undefined | ((state: unknown, delta: number) => void), step: vi.fn(), effects: [] as Array<() => unknown> }));
vi.mock('react', () => ({ useRef: (value: unknown) => ({ current: value }), useEffect: (effect: () => unknown) => harness.effects.push(effect) }));
vi.mock('@react-three/fiber', () => ({ useFrame: (frame: typeof harness.frame) => { harness.frame = frame; } }));
vi.mock('@react-three/rapier', () => ({ useRapier: () => ({ step: harness.step, world: { bodies: { len: () => 2 } } }) }));
import { IslandFrameDriver } from './IslandFrameDriver';
describe('bounded island physics driver', () => {
  beforeEach(() => {
    harness.step.mockClear(); harness.effects = [];
    vi.stubGlobal('document', { hidden: false, addEventListener: vi.fn(), removeEventListener: vi.fn() });
    vi.stubGlobal('window', { addEventListener: vi.fn(), removeEventListener: vi.fn() });
    vi.stubGlobal('location', { search: '' });
  });
  it('keeps 60Hz fixed-step input and drops long catch-up after stalls', () => {
    IslandFrameDriver({ onQuality: vi.fn() });
    const state = { gl: { info: { render: { calls: 2 } } }, setDpr: vi.fn() };
    harness.frame?.(state, 1 / 60);
    harness.frame?.(state, 1 / 60);
    harness.frame?.(state, 1.5);
    expect(harness.step.mock.calls.map(call => call[0])).toEqual([0, 1 / 60, 0]);
  });
  it('does not advance hidden gameplay or replay time on resume', () => {
    IslandFrameDriver({ onQuality: vi.fn() });
    const state = { gl: { info: { render: { calls: 2 } } }, setDpr: vi.fn() };
    document.hidden = true;
    harness.frame?.(state, 20);
    expect(harness.step).not.toHaveBeenCalled();
    document.hidden = false;
    harness.frame?.(state, 20);
    expect(harness.step).toHaveBeenCalledWith(0);
  });
});