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
  it('repeats a held direction without further pointer-move events and stops on release', async () => {
    vi.mocked(navalCall).mockResolvedValue(state);
    const network = useNavalOcean('signed-test', () => ({ dx: 0, dy: 0, throttle: 0 }));
    const cleanup = hooks.effects[0]?.();
    await vi.advanceTimersByTimeAsync(1);
    network.steer({ dx: 1, dy: 0, throttle: 1 });
    await vi.advanceTimersByTimeAsync(1250);
    const moves = vi.mocked(navalCall).mock.calls.filter(call => (call[2] as { dx: number }).dx === 1);
    expect(moves.length).toBeGreaterThanOrEqual(4);
    network.steer({ dx: 0, dy: 0, throttle: 0 });
    await vi.advanceTimersByTimeAsync(700);
    expect(vi.mocked(navalCall).mock.lastCall?.[2]).toEqual({ dx: 0, dy: 0, throttle: 0 });
    if (typeof cleanup === 'function') cleanup();
  });
  it('refreshes a tap destination without retaining a stale held vector', async () => {
    vi.mocked(navalCall).mockResolvedValue(state);
    let direction = { dx: 0, dy: 0, throttle: 0 };
    const network = useNavalOcean('signed-test', () => direction);
    const cleanup = hooks.effects[0]?.();
    await vi.advanceTimersByTimeAsync(1);
    network.steer({ dx: 1, dy: 0, throttle: 1 });
    direction = { dx: 0, dy: -1, throttle: 1 };
    network.refresh();
    await vi.advanceTimersByTimeAsync(1);
    expect(vi.mocked(navalCall).mock.lastCall?.[2]).toEqual(direction);
    direction = { dx: 0, dy: 0, throttle: 0 };
    await vi.advanceTimersByTimeAsync(700);
    expect(vi.mocked(navalCall).mock.lastCall?.[2]).toEqual(direction);
    if (typeof cleanup === 'function') cleanup();
  });
  it('sends the latest tap immediately after an in-flight idle heartbeat', async () => {
    let resolve: ((value: NavalState) => void) | undefined;
    let direction = { dx: 0, dy: 0, throttle: 0 };
    vi.mocked(navalCall).mockImplementationOnce(() => new Promise(done => { resolve = done; })).mockResolvedValue(state);
    const network = useNavalOcean('signed-test', () => direction);
    const cleanup = hooks.effects[0]?.();
    await vi.advanceTimersByTimeAsync(100);
    direction = { dx: -1, dy: 0, throttle: .5 };
    network.refresh(); network.refresh(); network.refresh();
    resolve?.(state);
    await vi.advanceTimersByTimeAsync(1);
    expect(navalCall).toHaveBeenCalledTimes(2);
    expect(vi.mocked(navalCall).mock.lastCall?.[2]).toEqual(direction);
    if (typeof cleanup === 'function') cleanup();
  });
  it('removes background polling timers and resumes once when visible', async () => {
    vi.mocked(navalCall).mockResolvedValue(state);
    const network = useNavalOcean('signed-test', () => ({ dx: 0, dy: 0, throttle: 0 }));
    const cleanup = hooks.effects[0]?.();
    await vi.advanceTimersByTimeAsync(1);
    const resume = vi.mocked(document.addEventListener).mock.calls.find(call => call[0] === 'visibilitychange')?.[1] as (() => void) | undefined;
    Object.assign(document, { hidden: true }); resume?.();
    await vi.advanceTimersByTimeAsync(10000);
    expect(navalCall).toHaveBeenCalledTimes(1);
    expect(vi.getTimerCount()).toBe(0);
    Object.assign(document, { hidden: false }); resume?.(); resume?.(); network.refresh();
    await vi.advanceTimersByTimeAsync(1);
    expect(navalCall).toHaveBeenCalledTimes(2);
    if (typeof cleanup === 'function') cleanup();
    expect(vi.getTimerCount()).toBe(0);
  });
  it.each(['attack', 'leave'])('preserves %s clicked during a heartbeat and sends it once', async name => {
    let resolve: ((value: NavalState) => void) | undefined;
    vi.mocked(navalCall).mockImplementationOnce(() => new Promise(done => { resolve = done; })).mockResolvedValue(state);
    const network = useNavalOcean('signed-test', () => ({ dx: 0, dy: 0, throttle: 0 }));
    const cleanup = hooks.effects[0]?.();
    const result = network.action(name, { target: 'other-player' });
    expect(navalCall).toHaveBeenCalledTimes(1);
    expect(await network.action(name)).toBe(false);
    resolve?.(state);
    expect(await result).toBe(true);
    expect(navalCall).toHaveBeenNthCalledWith(2, 'signed-test', name, { target: 'other-player' });
    if (typeof cleanup === 'function') cleanup();
  });
  it('does not send a waiting action after leaving the ocean', async () => {
    vi.mocked(navalCall).mockImplementationOnce(() => new Promise(() => {}));
    const network = useNavalOcean('signed-test', () => ({ dx: 0, dy: 0, throttle: 0 }));
    const cleanup = hooks.effects[0]?.();
    const result = network.action('leave');
    if (typeof cleanup === 'function') cleanup();
    expect(await result).toBe(false);
    expect(navalCall).toHaveBeenCalledTimes(1);
  });
  it('does not retry a rejected attack and resumes polling', async () => {
    vi.mocked(navalCall).mockResolvedValue(state).mockRejectedValueOnce(new Error('timeout')).mockRejectedValueOnce(new Error('NAVAL_OUT_OF_RANGE'));
    const network = useNavalOcean('signed-test', () => ({ dx: 0, dy: 0, throttle: 0 }));
    const cleanup = hooks.effects[0]?.();
    expect(await network.action('attack')).toBe(false);
    await vi.advanceTimersByTimeAsync(1);
    expect(vi.mocked(navalCall).mock.calls.filter(call => call[1] === 'attack')).toHaveLength(1);
    expect(vi.mocked(navalCall).mock.lastCall?.[1]).toBe('heartbeat');
    if (typeof cleanup === 'function') cleanup();
  });
});