import { describe, expect, it } from 'vitest';
import { mascotChestArt, mascotChestImage, mascotChestName } from './gameAssets';
import { replaceLegacyCreatureArt } from './voyageArtReplacement';
import { localizeItemName } from './itemNames';
import { formatEggPrice } from './eggPurchase';

describe('mascot chest presentation', () => {
  it('maps old containers to new art without modifying purchase or reward fields', () => {
    const input = { id: 'egg-id', slug: 'rare-egg', name: 'Ovo raro', quantity: 4, priceFc: 500, rarityRates: { common: 80, rare: 20 }, image: '/assets/game/pet-eggs/rare-egg.webp' };
    expect(replaceLegacyCreatureArt(input)).toEqual({ ...input, image: mascotChestArt.rare });
  });
  it('retains premium and special catalog tiers', () => {
    expect(mascotChestImage('dragon-egg')).toBe(mascotChestArt.legendary);
    expect(mascotChestImage('season-1-mythic-egg')).toBe(mascotChestArt.mythic);
    expect(mascotChestName('ancestral-egg')).toBe('Baú Misterioso Ancestral');
    expect(mascotChestName('common-egg')).toBe('Baú Misterioso Comum');
  });
  it('localizes legacy reward labels and preserves prices', () => {
    expect(localizeItemName('Ovo Raro', 'pt')).toBe('Baú Misterioso Raro');
    expect(localizeItemName('OVO MÍTICO', 'pt')).toBe('BAÚ MISTERIOSO MÍTICO');
    expect(formatEggPrice({ priceFc: 500 })).toBe('500 BERRIES');
    expect(formatEggPrice({ priceTon: 5 })).toBe('5 TON');
  });
});