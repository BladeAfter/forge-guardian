import { petBuffShortLabel } from './petLabels';

export type PetBonusEntry = { key: string; value: number };

/** Base revive delay used by the backend for knocked out boss heroes (seconds). */
export const BASE_REVIVE_SECONDS = 300;

/** Bonuses that actually change the Boss fight, in display priority order. */
export const BOSS_BONUS_KEYS = [
  'revive_speed_percent',
  'boss_damage_percent',
  'boss_damage_reduction_percent',
  'team_hp_percent',
  'hp_percent',
  'hp_bonus',
  'reward_percent',
] as const;

/**
 * Single source of truth for the active pet bonuses shown/applied anywhere.
 * The backend (`get_pet_bonuses`) already returns the active pet buffs; here we
 * only pick the ones relevant to a screen and format them for compact cards.
 */
export function activePetBonuses(bonuses?: Record<string, number> | null, keys: readonly string[] = BOSS_BONUS_KEYS): PetBonusEntry[] {
  if (!bonuses) return [];
  return keys
    .map((key) => ({ key, value: Number(bonuses[key] ?? 0) }))
    .filter((entry) => Number.isFinite(entry.value) && entry.value > 0);
}

export const petBonusValue = (bonuses: Record<string, number> | null | undefined, key: string) => {
  const value = Number(bonuses?.[key] ?? 0);
  return Number.isFinite(value) && value > 0 ? value : 0;
};

export const formatPetBonus = (entry: PetBonusEntry) => `${petBuffShortLabel(entry.key)} +${entry.value}%`;

/** Display helper only — the backend is the authority for the real timer. */
export const effectiveReviveSeconds = (reviveSpeedPercent: number, base = BASE_REVIVE_SECONDS) =>
  Math.max(30, Math.round(base / (1 + Math.max(0, reviveSpeedPercent) / 100)));
