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
  const since = Math.max(0, (nowMs - new Date(state.updatedAt).getTime()) / 1000);
  return base + (Number(state.dailyRateTon || 0) * since) / 86400;
}
