import { describe, expect, it, vi } from 'vitest';
vi.mock('./apiClient', () => ({ forgeFetch: vi.fn() }));
import { forgeFetch } from './apiClient';
import { DEFAULT_SHIP, SHIP_MODELS, SHIP_SKINS, shipMaxHp, shipStats, navalHeartbeatInput, navalCall } from './naval';
describe('naval presentation', () => {
  it('has six distinct model and skin identifiers', () => { expect(new Set(SHIP_MODELS.map(m => m.id)).size).toBe(6);expect(new Set(SHIP_SKINS.map(s => s.id)).size).toBe(6); });
  it('keeps cosmetic models independent of server stats', () => { expect(shipStats({...DEFAULT_SHIP,model:'legendary',skin:'king'})).toEqual(shipStats(DEFAULT_SHIP)); });
  it('derives hull and progression from server level', () => { expect(shipMaxHp({...DEFAULT_SHIP,level:5})).toBe(1400);expect(shipStats({...DEFAULT_SHIP,level:5}).crew).toBe(4); });
});

describe('naval heartbeat wire contract', () => {
  it.each([NaN, Infinity, -Infinity, null, '1'])('stops malformed movement %s before serialization', value => {
    for (const field of ['dx', 'dy', 'throttle']) expect(navalHeartbeatInput({ dx: 1, dy: 0, throttle: 1, [field]: value })).toEqual({ dx: 0, dy: 0, throttle: 0 });
  });
  it('matches server component bounds and preserves valid diagonal input', () => {
    expect(navalHeartbeatInput({ dx: 1, dy: 1, throttle: .5 })).toEqual({ dx: 1, dy: 1, throttle: .5 });
    expect(navalHeartbeatInput({ dx: 3, dy: -2, throttle: 4 })).toEqual({ dx: 1, dy: -1, throttle: 1 });
    expect(navalHeartbeatInput({})).toEqual({ dx: 0, dy: 0, throttle: 1 });
  });
  it('sends finite stop input and subsequently resumes valid sailing', async () => {
    vi.mocked(forgeFetch).mockResolvedValue({ ok: true, status: 200, json: async () => ({ ship: DEFAULT_SHIP }) });
    await navalCall('signed-test', 'heartbeat', { dx: NaN, dy: 1, throttle: 1 });
    expect(forgeFetch).toHaveBeenLastCalledWith('realm', { initData: 'signed-test', action: 'naval', navalAction: 'heartbeat', input: { dx: 0, dy: 0, throttle: 0 } }, 4000);
    await navalCall('signed-test', 'heartbeat', { dx: 1, dy: 0, throttle: .5 });
    expect(forgeFetch).toHaveBeenLastCalledWith('realm', { initData: 'signed-test', action: 'naval', navalAction: 'heartbeat', input: { dx: 1, dy: 0, throttle: .5 } }, 4000);
  });
  it('preserves non-movement action payloads', async () => {
    vi.mocked(forgeFetch).mockResolvedValue({ ok: true, status: 200, json: async () => ({ ship: DEFAULT_SHIP }) });
    const input = { target: 'other-player' };
    await navalCall('signed-test', 'attack', input);
    expect(forgeFetch).toHaveBeenLastCalledWith('realm', { initData: 'signed-test', action: 'naval', navalAction: 'attack', input }, 12000);
  });
});