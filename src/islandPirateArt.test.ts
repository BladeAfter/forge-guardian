import { describe, expect, it } from 'vitest';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { islandPirateArt, pirateEncounterArt } from './islandPirateArt';

describe('unique island pirate identities', () => {
  it('gives all twenty NPCs distinct images without shared image contents', () => {
    const hashes: string[] = [];
    for (let island = 0; island < 5; island++) for (let pirate = 0; pirate < 4; pirate++) {
      const art = pirateEncounterArt(`islandCombat.enemy.${island}.${pirate}`);
      expect(art).not.toBeNull();
      hashes.push(createHash('sha256').update(readFileSync(`src/assets/island-pirates/npc-${island}-${pirate}.png`)).digest('hex'));
    }
    expect(Object.keys(islandPirateArt)).toHaveLength(20);
    expect(new Set(Object.values(islandPirateArt).map(art => art.image)).size).toBe(20);
    expect(new Set(hashes).size).toBe(20);
  });
  it('never lends a known pirate image to an unknown identity', () => {
    expect(pirateEncounterArt('islandCombat.enemy.99.0')).toBeNull();
  });
});