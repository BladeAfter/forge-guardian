import { describe, expect, it } from 'vitest';
import { ISLAND_SHIP, ISLAND_LANDING, islandWalkable, walkIsland } from './islandNavigation';
describe('Island walking', () => {
  it('allows landing on the pier and beach', () => { expect(islandWalkable(ISLAND_SHIP)).toBe(true); expect(islandWalkable(ISLAND_LANDING)).toBe(true); });
  it('moves toward land without overshooting', () => { expect(walkIsland(ISLAND_SHIP, ISLAND_LANDING, 1)).toEqual(ISLAND_LANDING); });
  it('does not allow walking through sea or mountain edges', () => { expect(islandWalkable({ x: 100, y: 950 })).toBe(false); expect(islandWalkable({ x: 768, y: 60 })).toBe(false); });
  it('does not move with negative time', () => { expect(walkIsland(ISLAND_SHIP, ISLAND_LANDING, -1)).toEqual(ISLAND_SHIP); });
});