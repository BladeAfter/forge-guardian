/**
 * Friendly PT-BR presentation for every pet bonus key. The database stores raw
 * keys (`boss_damage_percent`); the player must never see them.
 */
export const PET_BUFF_LABELS: Record<string, string> = {
  boss_damage_percent: 'Dano contra o Chefe',
  boss_damage_reduction_percent: 'Redução de dano do Chefe',
  team_hp_percent: 'HP da equipe',
  team_attack_percent: 'Ataque da equipe',
  defense_percent: 'Defesa',
  pvp_attack_percent: 'Ataque na Arena',
  pvp_defense_percent: 'Defesa na Arena',
  pvp_speed_percent: 'Velocidade na Arena',
  critical_chance_percent: 'Chance de crítico',
  critical_damage_percent: 'Dano crítico',
  farm_fc_percent: 'Ganho de Forge Coins',
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

export const petBuffLabel = (key?: string | null) =>
  (key && PET_BUFF_LABELS[key]) ||
  (key ? key.replace(/_percent$/, '').replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase()) : 'Bônus passivo');

export const PET_RARITY_LABELS: Record<string, string> = {
  common: 'COMUM',
  uncommon: 'INCOMUM',
  rare: 'RARO',
  epic: 'ÉPICO',
  legendary: 'LENDÁRIO',
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
