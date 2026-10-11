import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
const hooks = vi.hoisted(() => ({ effects: [] as Array<() => void | (() => void)> }));
vi.mock('react', () => ({
  useRef: (value: unknown) => ({ current: value }),
  useState: (value: unknown) => [value, vi.fn()],
  useEffect: (effect: () => void | (() => void)) => hooks.effects.push(effect),
}));
vi.mock('./naval', () => ({ navalCall: vi.fn() }));
import { navalCall, type NavalState } from './naval';
import { useNavalOcean } from './useNavalOcean';
const state = { ship: { x: 1700, y: 1340 }, others: [] } as unknown as NavalState;
describe('mobile naval input scheduling', () => {
  beforeEach(() => {
    vi.useFakeTimers(); vi.clearAllMocks(); hooks.effects = [];
    vi.stubGlobal('document', { hidden: false, addEventListener: vi.fn(), removeEventListener: vi.fn() });
    vi.stubGlobal('window', { addEventListener: vi.fn(), removeEventListener: vi.fn() });
  });
  afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });
  it('drains drag and release immediately after a slow heartbeat', async () => {
    let resolve: ((value: NavalState) => void) | undefined;
    vi.mocked(navalCall).mockImplementationOnce(() => new Promise(done => { resolve = done; })).mockResolvedValue(state);
    const network = useNavalOcean('signed-test', () => ({ dx: 0, dy: 0, throttle: 0 }));
    const cleanup = hooks.effects[0]?.();
    await vi.advanceTimersByTimeAsync(400);
    network.steer({ dx: 1, dy: 0, throttle: 1 });
    network.steer({ dx: 0, dy: 0, throttle: 0 });
    expect(navalCall).toHaveBeenCalledTimes(1);
    resolve?.(state);
    await vi.advanceTimersByTimeAsync(1);
    expect(navalCall).toHaveBeenNthCalledWith(2, 'signed-test', 'heartbeat', { dx: 1, dy: 0, throttle: 1 });
    await vi.advanceTimersByTimeAsync(1);
    expect(navalCall).toHaveBeenNthCalledWith(3, 'signed-test', 'heartbeat', { dx: 0, dy: 0, throttle: 0 });
    if (typeof cleanup === 'function') cleanup();
  });
  it('does not send unauthenticated preview movement', async () => {
    const network = useNavalOcean('', () => ({ dx: 1, dy: 0, throttle: 1 }));
    const cleanup = hooks.effects[0]?.();
    network.steer({ dx: 1, dy: 0, throttle: 1 });
    await vi.advanceTimersByTimeAsync(1000);
    expect(navalCall).not.toHaveBeenCalled();
    if (typeof cleanup === 'function') cleanup();
  });
});