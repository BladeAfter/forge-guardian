import { describe, expect, it } from 'vitest';
import { islandArtDiameter } from './oceanPresentation';
import { SEA_ISLANDS, seaIslandsAround, seaLandAt } from './grandLineNavigation';

describe('open sea presentation', () => {
  it('reduces island artwork without shrinking official land or moving docks', () => {
    for (const island of SEA_ISLANDS) {
      expect(islandArtDiameter(island.radius)).toBeLessThan(island.radius * 2.5);
      expect(islandArtDiameter(island.radius) / 2).toBeGreaterThan(island.radius * .7);
      expect(seaLandAt(island.center)).toBe(true);
      expect(seaLandAt(island.dock)).toBe(false);
    }
  });
  it('continues streaming islands beyond the original archipelago', () => {
    const islands = seaIslandsAround({ x: -18000, y: 24000 }, 1);
    expect(islands.length).toBeGreaterThan(0);
    expect(islands.every(island => island.procedural)).toBe(true);
  });
});