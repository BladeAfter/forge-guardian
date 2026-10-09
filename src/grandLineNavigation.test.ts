import { describe, it, expect } from 'vitest';
import { SEA_ISLANDS, SEA_SIZE, sailToward, seaClickTarget, seaDistance } from './grandLineNavigation';

describe('Grand Line navigation', () => {
  it('moves visibly toward a destination without overshooting', () => {
    expect(sailToward({ x: 100, y: 100 }, { x: 400, y: 100 }, 1)).toEqual({ x: 340, y: 100 });
    expect(sailToward({ x: 100, y: 100 }, { x: 110, y: 100 }, 1)).toEqual({ x: 110, y: 100 });
  });
  it('keeps the ship in the world', () => {
    const point = sailToward({ x: 3190, y: 2100 }, { x: 9000, y: 9000 }, 50);
    expect(point.x).toBeLessThanOrEqual(SEA_SIZE.width - 60);
    expect(point.y).toBeLessThanOrEqual(SEA_SIZE.height - 60);
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
});