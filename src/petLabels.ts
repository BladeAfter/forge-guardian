import { VETERAN_LINE_LABEL, isVeteranLine } from './veteranLine';

/**
 * Friendly PT-BR presentation for every pet bonus key. The database stores raw
 * keys (`boss_damage_percent`); the player must never see them.
 */
export const PET_BUFF_LABELS: Record<string, string> = {
  boss_damage_percent: 'Dano contra o Chefe',
  boss_damage_reduction_percent: 'Redução de dano do Chefe',
  team_hp_percent: 'HP da equipe',
  hp_percent: 'HP da equipe',
  hp_bonus: 'HP da equipe',
  team_attack_percent: 'Ataque da equipe',
  defense_percent: 'Defesa',
  pvp_attack_percent: 'Ataque na Arena',
  pvp_defense_percent: 'Defesa na Arena',
  pvp_speed_percent: 'Velocidade na Arena',
  critical_chance_percent: 'Chance de crítico',
  critical_damage_percent: 'Dano crítico',
  farm_fc_percent: 'Ganho de BERRIES',
  offline_production_percent: 'Produção offline',
  mission_reward_percent: 'Recompensa de missões',
  mission_progress_percent: 'Progresso de missões',
  reward_percent: 'Recompensas gerais',
  random_reward_percent: 'Recompensas surpresa',
  drop_chance_percent: 'Chance de itens raros',
  egg_luck_percent: 'Sorte em ovos',
  hero_xp_percent: 'XP dos heróis',
  account_xp_percent: 'XP da conta',
  pet_xp_percent: 'XP dos pets',
  revive_speed_percent: 'Velocidade de reanimação',
};

/** Compact labels for mobile cards (Boss/Pets) — internal keys never change. */
export const PET_BUFF_SHORT_LABELS: Record<string, string> = {
  boss_damage_percent: 'Dano no Chefe',
  boss_damage_reduction_percent: 'Red. de dano',
  team_hp_percent: 'HP da equipe',
  team_attack_percent: 'Ataque',
  defense_percent: 'Defesa',
  pvp_attack_percent: 'Atk Arena',
  pvp_defense_percent: 'Def Arena',
  pvp_speed_percent: 'Vel. Arena',
  critical_chance_percent: 'Chance Crít.',
  critical_damage_percent: 'Dano Crít.',
  farm_fc_percent: 'Ganho BERRIES',
  offline_production_percent: 'Prod. offline',
  mission_reward_percent: 'Rec. missões',
  mission_progress_percent: 'Prog. missões',
  reward_percent: 'Recompensas',
  random_reward_percent: 'Rec. surpresa',
  drop_chance_percent: 'Itens raros',
  egg_luck_percent: 'Sorte em ovos',
  hero_xp_percent: 'XP heróis',
  account_xp_percent: 'XP conta',
  pet_xp_percent: 'XP pets',
  revive_speed_percent: 'Vel. Revive',
};

export const petBuffShortLabel = (key?: string | null) =>
  (key && PET_BUFF_SHORT_LABELS[key]) || petBuffLabel(key);

export const petBuffLabel = (key?: string | null) =>
  (key && PET_BUFF_LABELS[key]) ||
  (key ? key.replace(/_percent$/, '').replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase()) : 'Bônus passivo');

export const PET_RARITY_LABELS: Record<string, string> = {
  common: 'COMUM',
  uncommon: 'INCOMUM',
  rare: 'RARO',
  epic: 'ÉPICO',
  legendary: 'LENDÁRIO',
  mythic: 'MÍTICO',
  ancestral: 'ANCESTRAL',
  exclusive: 'EXCLUSIVO',
  nft_exclusive: 'NFT EXCLUSIVE',
  celestial: 'CELESTIAL',
  veteran: VETERAN_LINE_LABEL,
};

export const petRarityLabel = (rarity?: string | null) => PET_RARITY_LABELS[String(rarity ?? '')] ?? 'COMUM';

export const PET_STAGE_LABELS: Record<string, string> = {
  baby: 'Filhote',
  young: 'Jovem',
  adult: 'Adulto',
  ancestral: 'Ancestral',
};

export const petStageLabel = (stage?: string | null) => PET_STAGE_LABELS[String(stage ?? '')] ?? 'Filhote';

export const PET_FOOD_ICONS: Record<string, string> = {
  ration: '🥣',
  food: '🍖',
  meat: '🥩',
  fruit: '🍎',
  rare: '✨',
};

/**
 * NFT EXCLUSIVE is a category ABOVE every normal rarity. The database may still
 * carry a legacy `rarity` (often `common`) on NFT pets, so the UI must never
 * trust it: any NFT marker wins and the normal rarity badge is hidden.
 */
export type NftPetLike = {
  rarity?: string | null;
  isNft?: boolean | null;
  nft?: unknown;
  nftSerial?: number | null;
  specialCategory?: string | null;
  special_category?: string | null;
  specialType?: string | null;
  special_type?: string | null;
  exclusiveBadge?: string | null;
  /** Founder Pack / Veteran Vault line: superior premium tier, never mythic. */
  veteranLine?: boolean | null;
  veteran_line?: boolean | null;
  premiumSource?: string | null;
  premium_source?: string | null;
};

const NFT_TOKEN = /nft/i;

export function isNftExclusivePet(pet?: NftPetLike | null): boolean {
  if (!pet) return false;
  if (pet.isNft === true) return true;
  if (pet.nft) return true;
  if (typeof pet.nftSerial === 'number' && pet.nftSerial > 0) return true;
  const markers = [pet.rarity, pet.specialCategory, pet.special_category, pet.specialType, pet.special_type, pet.exclusiveBadge];
  return markers.some((value) => typeof value === 'string' && NFT_TOKEN.test(value));
}

/** Rarity key used ONLY for presentation (colors, badges). Stats stay untouched. */
export const petDisplayRarity = (pet?: NftPetLike | null): string =>
  isVeteranLine(pet) ? 'veteran' : isNftExclusivePet(pet) ? 'nft_exclusive' : String(pet?.rarity ?? 'common');

/** The single rarity badge text for a pet. NFT/Veteran pets never show COMUM/MÍTICO/etc. */
export const petDisplayRarityLabel = (pet?: NftPetLike | null): string =>
  isVeteranLine(pet)
    ? VETERAN_LINE_LABEL
    : isNftExclusivePet(pet)
      ? PET_RARITY_LABELS.nft_exclusive
      : petRarityLabel(pet?.rarity ?? null);

