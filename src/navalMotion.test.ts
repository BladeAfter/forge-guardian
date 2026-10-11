import { describe, expect, it } from 'vitest';
import { approachApprovedPose, updateApprovedFleet } from './navalMotion';
import { DEFAULT_SHIP, type NavalShip } from './naval';

describe('approved ship motion', () => {
  it('continues moving between updates without passing the approved location', () => {
    const approved = { x: 110, y: 40, heading: Math.PI / 2 };
    const first = approachApprovedPose({ x: 10, y: 40 }, 0, approved, .016);
    const second = approachApprovedPose(first.position, first.heading, approved, .016);
    expect(first.position.x).toBeGreaterThan(10);
    expect(second.position.x).toBeGreaterThan(first.position.x);
    expect(second.position.x).toBeLessThan(110);
    expect(second.position.y).toBe(40);
  });
  it('does not invent movement when the approved ship is stationary', () => {
    expect(approachApprovedPose({ x: 10, y: 40 }, 0, { x: 10, y: 40, heading: 0 }, .05).position).toEqual({ x: 10, y: 40 });
  });
  it('limits a delayed approved update to the ship presentation speed', () => {
    const next = approachApprovedPose({ x: 0, y: 0 }, 0, { x: 250, y: 0, heading: 0 }, .016, 122);
    expect(next.position.x).toBeGreaterThan(0);
    expect(next.position.x).toBeLessThanOrEqual(122 * .016);
  });
  it('interpolates confirmed players and removes those no longer returned', () => {
    const cache = new Map<string, NavalShip>();
    const ship = { ...DEFAULT_SHIP, user_id: 'real-player', x: 0, y: 0 };
    updateApprovedFleet(cache, [ship], .016);
    updateApprovedFleet(cache, [{ ...ship, x: 120 }], .016);
    expect(cache.get(ship.user_id)?.x).toBeGreaterThan(0);
    expect(cache.get(ship.user_id)?.x).toBeLessThan(120);
    updateApprovedFleet(cache, [], .016);
    expect(cache.size).toBe(0);
  });
});