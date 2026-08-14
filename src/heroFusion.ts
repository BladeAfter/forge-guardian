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
  /** Universal fragments that replace the required copies for this same step. */
  fragmentsRequired?: number;
  bonusPercent: number;
  maxLevel: number;
  finalAtk: number;
  finalHp: number;
};

/** Per-instance usage status returned by the backend (single source of truth). */
export type HeroUsage = {
  manuallyLocked: boolean;
  pvpAttack: boolean;
  pvpDefense: boolean;
  globalBoss: boolean;
  clanBoss: boolean;
  tower: boolean;
  marketplace: boolean;
  /** NFT Exclusive is only a category: it blocks marketplace + fusion, never gameplay. */
  isNft?: boolean;
  notTradeable?: boolean;
  /** True only when the instance is really busy in an activity right now. */
  inUse?: boolean;
  canFuse: boolean;
  reason: HeroLockReason | null;
};

export type HeroLockReason = 'MANUAL' | 'PVP_ATTACK' | 'PVP_DEFENSE' | 'BOSS' | 'TOWER' | 'MARKET' | 'NFT';

export const HERO_LOCK_LABEL: Record<HeroLockReason, string> = {
  MANUAL: '🔒 MANUALLY LOCKED',
  PVP_ATTACK: '🔒 PVP ATTACK',
  PVP_DEFENSE: '🔒 PVP DEFENSE',
  BOSS: '🔒 GLOBAL BOSS',
  TOWER: '🔒 TOWER',
  MARKET: '🔒 MARKET',
  NFT: '💎 NFT EXCLUSIVE',
};

/**
 * Central helper: a hero instance is free for fusion only when nothing is using it right now.
 * NFT Exclusive heroes stay fully playable (PvP, Boss, Tower, Equipment); they are just
 * unique (no fusion) and never tradeable on the player market.
 */
export const getHeroUsageStatus = (hero: { usage?: HeroUsage | null; locked?: boolean; inTeam?: boolean; equipped?: boolean; isNft?: boolean }): HeroUsage => {
  if (hero.usage) return { ...hero.usage, inUse: hero.usage.inUse ?? (hero.usage.manuallyLocked || hero.usage.pvpAttack || hero.usage.pvpDefense || hero.usage.globalBoss || hero.usage.tower || hero.usage.marketplace) };
  const manuallyLocked = Boolean(hero.locked);
  const busy = Boolean(hero.inTeam || hero.equipped);
  return {
    manuallyLocked, pvpAttack: busy, pvpDefense: false, globalBoss: false, clanBoss: false,
    tower: false, marketplace: false, isNft: Boolean(hero.isNft), notTradeable: Boolean(hero.isNft),
    inUse: manuallyLocked || busy,
    canFuse: !manuallyLocked && !busy && !hero.isNft,
    reason: manuallyLocked ? 'MANUAL' : busy ? 'PVP_ATTACK' : null,
  };
};


export const heroLockLabel = (reason: HeroLockReason | null | undefined) => (reason ? HERO_LOCK_LABEL[reason] ?? '🔒 IN USE' : null);

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
  usage?: HeroUsage | null;
  lockReason?: HeroLockReason | null;
  isNft?: boolean;
  /** Server-computed daily TON mining rate for this hero instance (0 = not eligible). */
  miningDailyTon?: number;
  duplicates: number;

  next: FusionNext | null;
};

export type FusionDashboard = {
  config: FusionConfig; balance: number; heroes: FusionHero[];
  /** Universal fragments owned and the cost of paying one fusion step with them. */
  universalFragments?: number; fragmentsPerFusion?: number;
  /** Normal hero fragments (summon currency) and its server config. */
  fragments?: number; summonConfig?: { fragments_per_hero?: number; rates?: Record<string, number> } | null;
};

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
  usedFragments?: boolean;
  fragmentsSpent?: number;
  universalFragments?: number;
  dashboard: FusionDashboard;
};

export const starRow = (stars: number, max = 5) => '★'.repeat(Math.max(0, stars)) + '☆'.repeat(Math.max(0, max - stars));

/** Available materials for the next ascension of a hero (duplicates that are unlocked and idle). */
export const pickMaterials = (hero: FusionHero, pool: FusionHero[]): string[] =>
  // Send every valid candidate: the backend re-validates and consumes only the
  // exact amount required for the current star step (1★→2★ = 1, 2★→3★ = 2, ...).
  pool
    .filter((h) => h.heroKey === hero.heroKey && h.heroId !== hero.heroId && getHeroUsageStatus(h).canFuse)
    .sort((a, b) => a.stars - b.stars || a.level - b.level)
    .map((h) => h.heroId);


export const canFuse = (hero: FusionHero, balance: number) =>
  Boolean(hero.next) && hero.duplicates >= (hero.next?.duplicatesRequired ?? 0) && balance >= (hero.next?.costFc ?? 0);

/**
 * Option 2: pay the SAME step with universal fragments instead of hero copies.
 * NFT exclusive heroes never enter the star fusion system.
 */
export const canFuseWithFragments = (hero: FusionHero, balance: number, universalFragments: number, fragmentsPerFusion: number) =>
  Boolean(hero.next) && !hero.isNft && fragmentsPerFusion > 0
  && universalFragments >= fragmentsPerFusion && balance >= (hero.next?.costFc ?? 0);

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
  usage?: HeroUsage | null; lockReason?: HeroLockReason | null;
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
  getHeroUsageStatus(hero).canFuse && Boolean(tiers?.[hero.rarity]);
