import { describe, expect, it } from 'vitest';
import { arenaCrewArt, arenaCrewImage } from './gameAssets';
import { voyageHeroArt } from './voyageArt';
import { replaceVoyageImage } from './voyageArtReplacement';

describe('grounded arena crew cosmetics', () => {
  it('keeps every voyage identity with a separate grounded pose', () => {
    for (const key of Object.keys(arenaCrewArt) as Array<keyof typeof arenaCrewArt>) {
      expect(arenaCrewImage({ image: voyageHeroArt[key], rarity: 'common' })).toBe(arenaCrewArt[key]);
      expect(arenaCrewImage({ image: `https://example.test/assets/game/new-voyage/heroes/${key}.png`, rarity: 'common' })).toBe(arenaCrewArt[key]);
    }
  });
  it('matches the existing identity assigned to legacy hero art', () => {
    const image = '/assets/game/heroes-rare/old-swordsman.png';
    expect(arenaCrewImage({ image, rarity: 'rare' })).toBe(arenaCrewImage({ image: replaceVoyageImage(image), rarity: 'rare' }));
  });
  it('never renders arbitrary or missing catalog images', () => {
    expect(arenaCrewImage({ image: 'https://example.test/airborne.png', rarity: 'epic' })).toBe(arenaCrewArt.tempestcall);
    expect(arenaCrewImage({ rarity: 'unknown' })).toBe(arenaCrewArt.deckblade);
  });
});