import { describe, expect, it } from 'vitest';
import { canFuse, pickMaterials, starRow, type FusionHero } from './heroFusion';

const hero = (over: Partial<FusionHero>): FusionHero => ({
  heroId: 'a', heroKey: 'forge_swordsman', name: 'Espadachim', rarity: 'rare', level: 12, imageUrl: null,
  archetype: 'warrior', stars: 1, locked: false, finalAtk: 96, finalHp: 1235, power: 1427, maxLevel: 20,
  inTeam: false, duplicates: 2,
  next: { stars: 2, costFc: 15000, duplicatesRequired: 1, bonusPercent: 5, maxLevel: 25, finalAtk: 101, finalHp: 1297 },
  ...over,
});

describe('hero fusion rules', () => {
  it('renders the star row', () => expect(starRow(2, 5)).toBe('★★☆☆☆'));

  it('only picks unlocked idle duplicates of the same hero_key', () => {
    const main = hero({ heroId: 'main' });
    const pool = [
      main,
      hero({ heroId: 'dupe-locked', locked: true }),
      hero({ heroId: 'dupe-team', inTeam: true }),
      hero({ heroId: 'other', heroKey: 'rune_smith' }),
      hero({ heroId: 'dupe-ok', stars: 0, level: 3 }),
    ];
    expect(pickMaterials(main, pool)).toEqual(['dupe-ok']);
  });

  it('blocks fusion without copies or FC', () => {
    expect(canFuse(hero({}), 20000)).toBe(true);
    expect(canFuse(hero({ duplicates: 0 }), 20000)).toBe(false);
    expect(canFuse(hero({}), 1000)).toBe(false);
    expect(canFuse(hero({ next: null }), 999999)).toBe(false);
  });
});
