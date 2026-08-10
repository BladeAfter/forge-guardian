/** Hero ascension (fusion) contracts. Every rule lives on the server; the client only renders previews. */
export type FusionConfig = {
  max_stars: number;
  bonus_percent: Record<string, number>;
  cost_fc: Record<string, number>;
  duplicates: Record<string, number>;
  level_cap: Record<string, number>;
};

export type FusionNext = {
  stars: number;
  costFc: number;
  duplicatesRequired: number;
  bonusPercent: number;
  maxLevel: number;
  finalAtk: number;
  finalHp: number;
};

export type FusionHero = {
  heroId: string;
  heroKey: string;
  name: string;
  rarity: string;
  level: number;
  imageUrl: string | null;
  archetype: string;
  stars: number;
  locked: boolean;
  finalAtk: number;
  finalHp: number;
  power: number;
  maxLevel: number;
  inTeam: boolean;
  duplicates: number;
  next: FusionNext | null;
};

export type FusionDashboard = { config: FusionConfig; balance: number; heroes: FusionHero[] };

export type FusionResult = {
  heroId: string;
  name: string;
  fromStars: number;
  toStars: number;
  atkBefore: number;
  atkAfter: number;
  hpBefore: number;
  hpAfter: number;
  bonusPercent: number;
  maxLevel: number;
  costFc: number;
  consumed: number;
  balance: number;
  dashboard: FusionDashboard;
};

export const starRow = (stars: number, max = 5) => '★'.repeat(Math.max(0, stars)) + '☆'.repeat(Math.max(0, max - stars));

/** Available materials for the next ascension of a hero (duplicates that are unlocked and idle). */
export const pickMaterials = (hero: FusionHero, pool: FusionHero[]): string[] => {
  const needed = hero.next?.duplicatesRequired ?? 0;
  return pool
    .filter((h) => h.heroKey === hero.heroKey && h.heroId !== hero.heroId && !h.locked && !h.inTeam)
    .sort((a, b) => a.stars - b.stars || a.level - b.level)
    .slice(0, needed)
    .map((h) => h.heroId);
};

export const canFuse = (hero: FusionHero, balance: number) =>
  Boolean(hero.next) && hero.duplicates >= (hero.next?.duplicatesRequired ?? 0) && balance >= (hero.next?.costFc ?? 0);
