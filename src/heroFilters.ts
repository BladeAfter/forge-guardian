import type { PvpHero } from './pvp';

/** Visual-only collection filters. They never mutate ownership, stats or teams. */
export type SortDir = 'default' | 'desc' | 'asc';
export type HeroFilters = { rarity: string; archetype: string; power: SortDir; level: SortDir };

export const DEFAULT_HERO_FILTERS: HeroFilters = { rarity: 'all', archetype: 'all', power: 'default', level: 'default' };

export const HERO_FILTER_RARITIES = ['all', 'common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic', 'ancestral', 'nft_exclusive', 'celestial'] as const;
export const HERO_FILTER_CLASSES = ['all', 'warrior', 'assassin', 'tank', 'mage', 'archer', 'support'] as const;

export const isDefaultHeroFilters = (f: HeroFilters) =>
  f.rarity === 'all' && f.archetype === 'all' && f.power === 'default' && f.level === 'default';

export function applyHeroFilters<T extends Pick<PvpHero, 'rarity' | 'archetype' | 'power' | 'level'>>(heroes: T[], f: HeroFilters): T[] {
  const filtered = heroes.filter(
    (hero) =>
      (f.rarity === 'all' || String(hero.rarity) === f.rarity) &&
      (f.archetype === 'all' || String(hero.archetype) === f.archetype),
  );
  const dir = (d: SortDir) => (d === 'desc' ? -1 : 1);
  if (f.power !== 'default') return [...filtered].sort((a, b) => (Number(a.power ?? 0) - Number(b.power ?? 0)) * dir(f.power));
  if (f.level !== 'default') return [...filtered].sort((a, b) => (Number(a.level ?? 0) - Number(b.level ?? 0)) * dir(f.level));
  return filtered;
}
