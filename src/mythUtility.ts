/**
 * MYTHREON :: MYTH TOKEN UTILITY (frontend contract only).
 *
 * MYTH is an ALTERNATIVE payment method: FC and TON keep working exactly as before.
 * The client never decides prices — it only mirrors the backend formula to render a preview.
 * Reference: 1 TON = 20,000 MYTH = 100,000 FC (1 MYTH = 5 FC), minus the utility discount.
 *
 * Hard rules owned by the backend:
 * - only the AVAILABLE MYTH balance can pay (staked MYTH is untouchable);
 * - every MYTH spent is BURNED (it lowers the effective supply, it is never recycled);
 * - materials (hero copies, fragments, XP, level, tickets) are always still required.
 */

export type MythFeatureCode =
  | 'FOOD_PURCHASE'
  | 'EGG_PURCHASE'
  | 'HERO_FUSE'
  | 'HERO_UPGRADE'
  | 'PET_UPGRADE'
  | 'PASS_LEVELS'
  | 'PASS_PURCHASE'
  | 'TOWER_ENTRY'
  | 'HERO_RECRUIT';

export type MythFeatureConfig = {
  label: string;
  enabled: boolean;
  pricingMode: 'AUTO_FC' | 'AUTO_TON' | 'CUSTOM';
  customMyth: number | null;
};

export type MythUtilityState = {
  enabled: boolean;
  mythPerTon: number;
  fcPerTon: number;
  mythPerFc: number;
  discountPercent: number;
  onchainBurnEnabled: boolean;
  features: Partial<Record<MythFeatureCode, MythFeatureConfig>>;
  /** Spendable MYTH (staked MYTH is excluded on purpose). */
  balance: number;
  available: number;
  staked: number;
  totalOwned: number;
  mySpentMyth: number;
  burned: number;
  utilityBurned: number;
  effectiveSupply: number;
  originalSupply: number;
  burnedPercent: number;
};

/** True when MYTH may be offered for this feature at all. */
export const mythFeatureEnabled = (state: MythUtilityState | null | undefined, feature: MythFeatureCode) =>
  !!state?.enabled && !!state.features?.[feature]?.enabled;

/**
 * Mirrors `myth_utility_price` (ceil + discount). Returns null when MYTH is not offered.
 * The server recomputes this on every charge — the UI value is a preview only.
 */
export function mythPrice(
  state: MythUtilityState | null | undefined,
  feature: MythFeatureCode,
  { fc = 0, ton = 0 }: { fc?: number; ton?: number },
): number | null {
  if (!mythFeatureEnabled(state, feature)) return null;
  const cfg = state!.features[feature]!;
  if (cfg.pricingMode === 'CUSTOM') {
    const custom = Number(cfg.customMyth ?? 0);
    return custom > 0 ? Math.ceil(custom) : null;
  }
  const mythPerTon = Number(state!.mythPerTon) || 0;
  const fcPerTon = Number(state!.fcPerTon) || 0;
  const discount = Number(state!.discountPercent) || 0;
  let base = 0;
  if (cfg.pricingMode === 'AUTO_TON') {
    if (!(ton > 0) || !mythPerTon) return null;
    base = ton * mythPerTon;
  } else {
    if (!(fc > 0) || !fcPerTon || !mythPerTon) return null;
    base = (fc / fcPerTon) * mythPerTon;
  }
  const value = Math.ceil((base * (100 - discount)) / 100);
  return value > 0 ? value : null;
}

export const formatMyth = (value: number) => Math.round(Number(value) || 0).toLocaleString('pt-BR');

/** Discount label used on every MYTH payment button. */
export const mythDiscountLabel = (state: MythUtilityState | null | undefined) =>
  state && Number(state.discountPercent) > 0 ? `-${Math.round(Number(state.discountPercent))}%` : '';
