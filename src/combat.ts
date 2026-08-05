export type HeroRarity = 'common' | 'uncommon' | 'rare' | 'epic' | 'legendary';

export const HERO_RARITY_STATS = {
  common: { baseAtk: 1.875, baseHp: 100, timeReductionMinutes: 48 },
  uncommon: { baseAtk: 1.975, baseHp: 130, timeReductionMinutes: 60 },
  rare: { baseAtk: 2.165, baseHp: 170, timeReductionMinutes: 80 },
  epic: { baseAtk: 2.395, baseHp: 220, timeReductionMinutes: 100 },
  legendary: { baseAtk: 2.68, baseHp: 300, timeReductionMinutes: 120 }
} as const;

export const RARITY_DAMAGE_RESISTANCE: Record<HeroRarity, number> = {
  common: 1, uncommon: .95, rare: .9, epic: .85, legendary: .8
};
export const BASE_BOSS_DURATION_SECONDS = 86_400;
export const MIN_BOSS_DURATION_SECONDS = 14_400;
export const HERO_ATTACK_INTERVAL_SECONDS = 10;
export const HERO_REVIVE_SECONDS = 300;

export type CombatHero = {
  id: string; heroId: string; name: string; image?: string; rarity: HeroRarity | string;
  slot: number; level: number; baseAtk: number; finalAtk: number; baseHp: number;
  maxHp: number; currentHp: number; isAlive: boolean; knockedOutAt: string | null;
  reviveAt: string | null;
};

export type BossCombat = {
  id: string; bossId: string | null; bossName: string; bossLevel: number;
  bossMaxHp: number; bossCurrentHp: number; bossAttack: number;
  bossAttackIntervalSeconds: number; rewardAmount: number;
  status: 'active' | 'defeated' | 'rewarded'; totalDamageDealt: number;
  defeats: number; startedAt: string; lastProcessedAt: string;
  nextHeroAttackAt: string; bossLastAttackAt: string; bossNextAttackAt: string;
  defeatedAt: string | null; rewardClaimedAt: string | null;
  teamChangeAvailableAt: string | null; serverNow: string; heroes: CombatHero[];
  ownedHeroes?: Array<{ id: string; heroKey: string; name: string; image?: string; rarity: HeroRarity; level: number }>;
  petSummary?: { activePet: { name: string; image: string; level: number; rarity: string } | null; bonuses: Record<string, number> };
};

export function normalizeRarity(rarity?: string | null): HeroRarity {
  const value = String(rarity ?? 'common').trim().toLowerCase();
  const aliases: Record<string, HeroRarity> = {
    common: 'common', comum: 'common', uncommon: 'uncommon', incomum: 'uncommon',
    rare: 'rare', raro: 'rare', rara: 'rare', epic: 'epic', 'épico': 'epic', epico: 'epic',
    'épica': 'epic', epica: 'epic', legendary: 'legendary', 'lendário': 'legendary',
    lendario: 'legendary', 'lendária': 'legendary', lendaria: 'legendary'
  };
  return aliases[value] ?? 'common';
}

export const calculateHeroAttack = (baseAtk: number, level: number) =>
  Number((Math.max(0, baseAtk) * (1 + (Math.max(1, level) - 1) * .03)).toFixed(3));
export const calculateHeroMaxHp = (baseHp: number, level: number) =>
  Math.round(Math.max(0, baseHp) * (1 + (Math.max(1, level) - 1) * .05));
export const calculateBossDamageToHero = (attack: number, rarity?: string | null) =>
  Math.max(1, Math.round(Math.max(0, attack) * RARITY_DAMAGE_RESISTANCE[normalizeRarity(rarity)]));
export const calculateTeamDamagePerCycle = (heroes: CombatHero[]) =>
  Number(heroes.filter((hero) => hero.isAlive).reduce((sum, hero) => sum + calculateHeroAttack(hero.baseAtk, hero.level), 0).toFixed(3));
export const calculateRarityEstimatedDuration = (heroes: CombatHero[]) =>
  Math.max(MIN_BOSS_DURATION_SECONDS, BASE_BOSS_DURATION_SECONDS - heroes.reduce((sum, hero) => sum + HERO_RARITY_STATS[normalizeRarity(hero.rarity)].timeReductionMinutes * 60, 0));
export const calculateEstimatedSecondsRemaining = (hp: number, damagePerCycle: number) =>
  damagePerCycle > 0 && Number.isFinite(hp) ? Math.max(0, hp) / (damagePerCycle / HERO_ATTACK_INTERVAL_SECONDS) : null;
export function formatDuration(totalSeconds: number): string {
  if (!Number.isFinite(totalSeconds) || totalSeconds < 0) return '--';
  const seconds = Math.floor(totalSeconds), days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600), minutes = Math.floor((seconds % 3600) / 60), remaining = seconds % 60;
  if (days > 0) return `${days}d ${hours}h ${minutes}m`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  if (minutes > 0) return `${minutes}m ${remaining}s`;
  return `${remaining}s`;
}
export const clampHp = (hp: number, maxHp: number) => Math.min(Math.max(0, Number.isFinite(hp) ? hp : 0), Math.max(0, maxHp));
export const preserveProportionalHp = (currentHp: number, oldMaxHp: number, newMaxHp: number) =>
  clampHp(oldMaxHp > 0 ? Math.round(currentHp / oldMaxHp * newMaxHp) : 0, newMaxHp);
export const nextBossStats = (hp: number, attack: number, reward: number) => ({
  maxHp: Math.min(Number.MAX_SAFE_INTEGER, Math.round(Math.max(1, hp) * 1.08)),
  attack: Math.min(Number.MAX_SAFE_INTEGER, Math.round(Math.max(1, attack) * 1.05)),
  reward: Math.min(Number.MAX_SAFE_INTEGER, Math.round(Math.max(1, reward) * 1.05))
});

export function applyHeroCycle(bossHp:number, heroes:CombatHero[]){
  const damage=calculateTeamDamagePerCycle(heroes); return {damage:Math.min(Math.max(0,bossHp),damage),bossHp:clampHp(bossHp-damage,bossHp)};
}
export function applyBossHit(heroes:CombatHero[],bossAttack:number,targetId:string,at:number){
  return heroes.map(hero=>{if(hero.id!==targetId||!hero.isAlive)return hero;const hp=Math.max(0,hero.currentHp-calculateBossDamageToHero(bossAttack,hero.rarity));return {...hero,currentHp:hp,isAlive:hp>0,knockedOutAt:hp?null:new Date(at).toISOString(),reviveAt:hp?null:new Date(at+HERO_REVIVE_SECONDS*1000).toISOString()}});
}
export function reviveDueHeroes(heroes:CombatHero[],at:number){
  return heroes.map(hero=>!hero.isAlive&&hero.reviveAt&&new Date(hero.reviveAt).getTime()<=at?{...hero,currentHp:hero.maxHp,isAlive:true,knockedOutAt:null,reviveAt:null}:hero);
}
export function grantRewardOnce(keys:Set<string>,combatId:string,amount:number){const key=`boss_reward:${combatId}`;if(keys.has(key))return 0;keys.add(key);return Math.max(0,amount)}
