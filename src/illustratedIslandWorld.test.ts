import { describe, expect, it } from 'vitest';
import { clearEncounterPoint, islandObstacles, islandWalkable, mapPoint, obstacleAt, safeIslandStep } from './illustratedIslandWorld';

describe('illustrated island obstacles', () => {
  it('blocks water and pier edges on every island', () => {
    for (let index = 0; index < 5; index++) {
      for (const point of [{ x: 3, z: 48 }, { x: 20, z: 34 }, { x: 0, z: 54 }, { x: 92, z: 0 }, { x: 0, z: -62 }]) expect(islandWalkable(index, point)).toBe(false);
      for (const z of [29, 30, 40, 48, 52]) expect(islandWalkable(index, { x: 0, z })).toBe(true);
      const stopped = safeIslandStep(index, { x: 0, z: 48 }, { x: 20, z: 48 });
      expect(stopped.x).toBeLessThanOrEqual(1.4);
      expect(islandWalkable(index, stopped)).toBe(true);
    }
  });
  it('allows automatic landing and boarding, not manual deck escape', () => {
    const route = [{ x: 5.3, z: 48 }, { x: 4.1, z: 48 }, { x: 0, z: 48 }, { x: 0, z: 29 }];
    for (let index = 0; index < 5; index++) for (let i = 1; i < route.length; i++) {
      expect(safeIslandStep(index, route[i - 1], route[i], true)).toEqual(route[i]);
      expect(safeIslandStep(index, route[i], route[i - 1], true)).toEqual(route[i - 1]);
    }
    expect(islandWalkable(1, route[0])).toBe(false);
  });
  it('sweeps airborne moves and recovers invalid positions', () => {
    const point = safeIslandStep(1, { x: 0, z: 40 }, { x: 7, z: 49 }, true);
    expect(point).not.toEqual({ x: 7, z: 49 });
    expect(islandWalkable(1, point, true)).toBe(true);
    expect(safeIslandStep(1, { x: 100, z: 100 }, { x: 101, z: 101 })).toEqual({ x: 0, z: 29 });
    expect(safeIslandStep(1, { x: 0, z: 29 }, { x: NaN, z: 10 })).toEqual({ x: 0, z: 29 });
  });
  it('maps the illustrated pier and beach onto the harbor coordinates', () => {
    expect(mapPoint(.5, .9)).toEqual({ x: 0, z: 48 });
    expect(mapPoint(.5, .75)).toEqual({ x: 0, z: 30 });
  });
  it('blocks the visible shore palms instead of the central path', () => {
    expect(obstacleAt(1, 14.4, 19.2)?.id).toBe('shore-palms-east');
    for (const z of [29, 24, 18, 12]) expect(obstacleAt(1, 0, z)).toBeUndefined();
  });
  it('keeps each islands trees, rocks and houses solid', () => {
    for (let index = 0; index < 5; index++) for (const o of islandObstacles(index)) expect(obstacleAt(index, o.x, o.z)).toBeDefined();
  });
  it('keeps encounters accessible without changing their official identities', () => {
    const point = clearEncounterPoint(1, { x: 14.4, z: 19.2 });
    expect(obstacleAt(1, point.x, point.z, 1.2)).toBeUndefined();
    expect(clearEncounterPoint(1, { x: 0, z: 29 })).toEqual({ x: 0, z: 29 });
  });
});