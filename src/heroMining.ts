/**
 * Hero TON mining (client types + formatting helpers).
 *
 * Every value here is produced by the server (`get_hero_mining_state`).
 * The client NEVER computes what can be claimed — it only renders and can
 * optionally tick a visual preview between refetches.
 */
export type HeroMiningClaim = { id: string; amountTon: number; heroCount: number; ratePerDay: number; createdAt: string };

export type HeroMiningState = {
  enabled: boolean;
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

export type HeroMiningClaimResult = HeroMiningState & { ok: boolean; claimedTon: number; claimId: string };

/** Daily rate of a single hero, taken from the server rate table. */
export function heroDailyRate(rates: Record<string, number> | undefined, rarity: string | null | undefined): number {
  if (!rates) return 0;
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
  if (!state || !state.enabled) return Number(state?.unclaimedTon ?? 0);
  const base = Number(state.unclaimedTon || 0);
  // No eligible TON invested (or ROI cap reached): heroes generate nothing.
  const room = Math.max(0, Number(state.remainingTon ?? 0));
  if (room <= 0) return base;
  const since = Math.max(0, (nowMs - new Date(state.updatedAt).getTime()) / 1000);
  const produced = (Number(state.dailyRateTon || 0) * since) / 86400;
  return base + Math.min(produced, room);
}

/** Mining only runs for players with remaining ROI capacity. */
export function miningActive(state: HeroMiningState | undefined): boolean {
  if (!state) return false;
  return state.enabled && Number(state.investedTon || 0) > 0 && Number(state.remainingTon || 0) > 0;
}
