import { describe, expect, it } from 'vitest';
import { oceanChestArt, oceanChestImage } from './gameAssets';
import { boss } from './locales/boss';

describe('ocean chest presentation', () => {
  it('shares three distinct dedicated ocean sprites across cosmetic region tiers', () => {
    expect(new Set(Object.values(oceanChestArt)).size).toBe(3);
    expect(oceanChestImage('common')).toBe(oceanChestArt.common);
    expect(oceanChestImage('epic')).toBe(oceanChestArt.rare);
    expect(oceanChestImage('mythic')).toBe(oceanChestArt.legendary);
    expect(oceanChestImage('unknown')).toBe(oceanChestArt.common);
  });
  it('uses the server top count in every supplied reward label', () => {
    for (const bundle of Object.values(boss)) {
      expect(bundle['boss.topRanked']).toContain('{count}');
    }
  });
});