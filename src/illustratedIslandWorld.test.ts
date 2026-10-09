import { describe, expect, it } from 'vitest';
import { clearEncounterPoint, islandObstacles, mapPoint, obstacleAt } from './illustratedIslandWorld';

describe('illustrated island obstacles', () => {
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