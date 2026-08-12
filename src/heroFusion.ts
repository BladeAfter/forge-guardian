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

// ------------------------------------------------------------------ rarity fusion (5 heroes -> next rarity)
export const FUSION_RARITIES = ['common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic', 'ancestral'] as const;
export type FusionRarity = (typeof FUSION_RARITIES)[number];

export const RARITY_COLOR: Record<string, string> = {
  common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc', legendary: '#fbbf24',
  mythic: '#fb7185', ancestral: '#f472b6',
};
export const RARITY_LABEL: Record<string, string> = {
  common: 'COMMON', uncommon: 'UNCOMMON', rare: 'RARE', epic: 'EPIC', legendary: 'LEGENDARY',
  mythic: 'MYTHIC', ancestral: 'ANCESTRAL',
};

export type RarityFusionTier = { target: string; cost_fc: number; chance: number; fragments: number };
export type RarityFusionConfig = { enabled: boolean; required_heroes: number; tiers: Record<string, RarityFusionTier> };

export type RarityFusionHero = {
  heroId: string; heroKey: string; name: string; rarity: string; level: number;
  imageUrl: string | null; stars: number; finalAtk: number; finalHp: number; power: number;
  locked: boolean; equipped: boolean; exclusive: boolean;
};

export type RarityFusionHistoryEntry = {
  id: string; sourceRarity: string; targetRarity: string; success: boolean;
  costFc: number; chance: number; rewardHero: string | null; fragments: number; createdAt: string;
};

export type RarityFusionDashboard = {
  config: RarityFusionConfig;
  balance: number;
  fragments: number;
  heroes: RarityFusionHero[];
  counts: Record<string, number>;
  history: RarityFusionHistoryEntry[];
};

export type RarityFusionResult = {
  success: boolean; sourceRarity: string; targetRarity: string;
  costFc: number; chance: number; balance: number; consumed: number;
  fragments: number; fragmentsTotal: number;
  hero: { heroId: string; heroKey: string; name: string; rarity: string; level: number; imageUrl: string | null; finalAtk: number; finalHp: number; power: number } | null;
  dashboard: RarityFusionDashboard;
};

/** A hero can be sacrificed only when it is free: unlocked and not deployed in PvP/Boss teams. */
export const isFusionEligible = (hero: RarityFusionHero, tiers: Record<string, RarityFusionTier>) =>
  !hero.locked && !hero.equipped && Boolean(tiers?.[hero.rarity]);
