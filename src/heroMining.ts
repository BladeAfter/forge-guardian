/**
 * Hero TON mining (client types + formatting helpers).
 *
 * Every value here is produced by the server (`get_hero_mining_state`).
 * The client NEVER computes what can be claimed — it only renders and can
 * optionally tick a visual preview between refetches.
 */
export type HeroMiningClaim = { id: string; amountTon: number; amountMyth?: number; currency?: 'ton' | 'myth'; heroCount: number; ratePerDay: number; createdAt: string };

export type HeroMiningState = {
  enabled: boolean;
  /** Active mining currency (server controlled through the Admin Bot). */
  miningCurrency?: 'ton' | 'myth';
  currencyChangedAt?: string | null;
  /** Daily rate in the ACTIVE currency. */
  dailyRate?: number;
  dailyRateMyth?: number;
  /** Claimable amount in the ACTIVE currency. */
  unclaimed?: number;
  unclaimedMyth?: number;
  lifetimeMyth?: number;
  mythBalance?: number;
  mythPoolAvailable?: number;
  minClaim?: number;
  minClaimMyth?: number;
  dailyRateTon: number;
  unclaimedTon: number;
  lifetimeTon: number;
  /** Total eligible TON the player really invested (deposits + TON purchases). */
  investedTon: number;
  /** TON already returned to the player through hero mining (lifetime, never reset). */
  returnedTon: number;
  /** Remaining ROI capacity: invested - returned - pending unclaimed. */
  remainingTon: number;
  roiLimitReached: boolean;
  hasInvestment: boolean;
  eligibleHeroes: number;
  availableTon: number;
  minClaimTon: number;
  lastClaimAt: string | null;
  updatedAt: string;
  /** rarity -> TON per day (admin editable). */
  rates: Record<string, number>;
  claims: HeroMiningClaim[];
};

export type HeroMiningClaimResult = HeroMiningState & { ok: boolean; currency?: 'ton' | 'myth'; claimedTon: number; claimedMyth?: number; claimId: string };

/** Active currency of the mining state (defaults to TON for legacy payloads). */
export function miningStateCurrency(state: HeroMiningState | undefined): 'ton' | 'myth' {
  return state?.miningCurrency === 'myth' ? 'myth' : 'ton';
}

/** Daily rate in the active currency. */
export function miningStateRate(state: HeroMiningState | undefined): number {
  if (!state) return 0;
  return Number(state.dailyRate ?? state.dailyRateTon ?? 0);
}

/** Daily rate of a single hero, taken from the server rate table. */
export function heroDailyRate(rates: Record<string, number> | undefined, rarity: string | null | undefined): number {
  if (!rates) return 0;
  if (!isMiningRarity(rarity)) return 0;
  return Number(rates[String(rarity ?? '').toLowerCase()] ?? 0);
}

/** Compact TON formatting: mining values are small, so keep the significant digits. */
export function formatMiningTon(value: number, digits = 4): string {
  const amount = Number(value || 0);
  if (amount === 0) return '0';
  if (amount < 0.0001) return amount.toFixed(6).replace(/0+$/, '').replace(/\.$/, '');
  return amount.toFixed(digits).replace(/0+$/, '').replace(/\.$/, '');
}

/**
 * Visual-only projection between server refetches: the server timestamp plus the
 * elapsed local seconds at the server rate. Claim always uses the server value.
 */
export function projectUnclaimed(state: HeroMiningState | undefined, nowMs: number): number {
  const currency = miningStateCurrency(state);
  const base = Number((currency === 'myth' ? state?.unclaimedMyth : state?.unclaimedTon) ?? state?.unclaimed ?? 0);
  if (!state || !state.enabled) return base;
  const since = Math.max(0, (nowMs - new Date(state.updatedAt).getTime()) / 1000);
  const produced = (miningStateRate(state) * since) / 86400;
  if (currency === 'myth') {
    // MYTH accrual has no ROI cap: it is limited by the MYTH mining pool at claim time.
    return base + produced;
  }
  // No eligible TON invested (or ROI cap reached): heroes generate nothing.
  const room = Math.max(0, Number(state.remainingTon ?? 0));
  if (room <= 0) return base;
  return base + Math.min(produced, room);
}

/** Mining only runs for players with remaining ROI capacity. */
export function miningActive(state: HeroMiningState | undefined): boolean {
  if (!state) return false;
  if (!state.enabled) return false;
  // MYTH mode ignores the TON ROI cap (that cap only limits TON payouts).
  if (miningStateCurrency(state) === 'myth') return miningStateRate(state) > 0;
  return Number(state.investedTon || 0) > 0 && Number(state.remainingTon || 0) > 0;
}

/** Rarities allowed to mine TON (mirrors the server gate `hero_mining_rarity_eligible`). */
export const MINING_ELIGIBLE_RARITIES = ['rare', 'epic', 'legendary', 'mythic', 'ancestral', 'nft_exclusive'] as const;

/** Common/Uncommon never mine. NFT Exclusive sits above the ladder and always passes. */
export function isMiningRarity(rarity: string | null | undefined): boolean {
  return (MINING_ELIGIBLE_RARITIES as readonly string[]).includes(String(rarity ?? '').toLowerCase());
}
