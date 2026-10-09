import { describe, expect, it } from 'vitest';
import { replaceLegacyCreatureArt, replaceVoyageImage } from './voyageArtReplacement';
import { voyageHeroArt, voyagePetArt } from './voyageArt';

describe('legacy creature art replacement', () => {
  it('replaces old pet and NFT evolution images with new pet art', () => {
    expect(Object.values(voyagePetArt)).toContain(replaceVoyageImage('/assets/game/pets-celestial/solvanthys-ascended.png'));
    expect(Object.values(voyagePetArt)).toContain(replaceVoyageImage('/assets/game/pets-sub-nft/sub-cosmic.png'));
  });
  it('replaces old exclusive heroes with new hero art', () => {
    expect(Object.values(voyageHeroArt)).toContain(replaceVoyageImage('/assets/game/heroes-nft/umbralynn.jpg'));
  });
  it('preserves ownership, prices, attributes and unrelated item art', () => {
    const input = { owner: 'player-1', level: 50, priceTon: 150, miningDailyTon: 0.8, image: '/assets/game/chests/legend-chest.png' };
    expect(replaceLegacyCreatureArt(input)).toEqual(input);
  });
  it('preserves new art paths', () => {
    expect(replaceVoyageImage('/assets/game/new-voyage/pets/tidehorn.png')).toBe('/assets/game/new-voyage/pets/tidehorn.png');
  });
});