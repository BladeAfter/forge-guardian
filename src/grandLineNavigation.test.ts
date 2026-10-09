import { describe, it, expect } from 'vitest';
import { SEA_ISLANDS, SEA_CHUNK, seaIslandsAround, seaRegion, advanceSailing, sailToward, seaClickTarget, seaDistance } from './grandLineNavigation';

describe('Grand Line navigation', () => {
  it('moves visibly toward a destination without overshooting', () => {
    expect(sailToward({ x: 100, y: 100 }, { x: 400, y: 100 }, 1)).toEqual({ x: 340, y: 100 });
    expect(sailToward({ x: 100, y: 100 }, { x: 110, y: 100 }, 1)).toEqual({ x: 110, y: 100 });
  });
  it('continues beyond the original world without clamping', () => {
    const point = sailToward({ x: 3190, y: 2100 }, { x: 9000, y: 9000 }, 50);
    expect(point).toEqual({ x: 9000, y: 9000 });
    expect(sailToward({ x: 0, y: 0 }, { x: -5000, y: -5000 }, 50)).toEqual({ x: -5000, y: -5000 });
  });
  it('uses physical island terrain to route to its dock', () => {
    for (const island of SEA_ISLANDS) {
      expect(seaClickTarget(island.center)).toEqual(island.dock);
      expect(seaDistance(island.center, island.dock)).toBeGreaterThan(island.radius * .7);
    }
    expect(seaClickTarget({ x: 1800, y: 1200 })).toEqual({ x: 1800, y: 1200 });
  });
  it('does not move for negative time or stationary targets', () => {
    expect(sailToward({ x: 100, y: 100 }, { x: 300, y: 100 }, -1)).toEqual({ x: 100, y: 100 });
    expect(sailToward({ x: 100, y: 100 }, { x: 100, y: 100 }, 1)).toEqual({ x: 100, y: 100 });
  });
  it('streams a bounded, deterministic neighborhood at distant coordinates', () => {
    const position = { x: 1000000, y: -800000 };
    const islands = seaIslandsAround(position);
    expect(islands).toEqual(seaIslandsAround(position));
    expect(islands.length).toBeLessThanOrEqual(25);
    expect(islands.length).toBeGreaterThan(0);
    expect(islands.map(i => i.id)).not.toEqual(seaIslandsAround({ x: position.x + SEA_CHUNK * 5, y: position.y }).map(i => i.id));
    for (const island of islands) expect(seaClickTarget(island.center)).toEqual(island.dock);
    expect(seaRegion(0, 0)).toBeNull();
  });
  it('accelerates and brakes without teleporting or overshooting at rest', () => {
    const motion = { velocity: { x: 0, y: 0 }, heading: 0 };
    let position = { x: -500, y: -500 };
    const next = advanceSailing(position, { x: -200, y: -500 }, motion, .05, 122);
    expect(next.x).toBeGreaterThan(position.x);
    expect(next.x - position.x).toBeLessThan(122 * .05);
    position = next;
    const speed = Math.hypot(motion.velocity.x, motion.velocity.y);
    for (let i = 0; i < 100; i++) position = advanceSailing(position, position, motion, .05, 0);
    expect(Math.hypot(motion.velocity.x, motion.velocity.y)).toBeLessThan(speed * .001);
  });
});