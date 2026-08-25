/**
 * Hero TON mining (client types + formatting helpers).
 *
 * Every value here is produced by the server (`get_hero_mining_state`).
 * The client NEVER computes what can be claimed — it only renders and can
 * optionally tick a visual preview between refetches.
 */
export type HeroMiningClaim = { id: string; amountTon: number; amountMyth?: number; currency?: 'ton' | 'myth'; heroCount: number; ratePerDay: number; createdAt: string };

export type TonMiningAccess = 'LEGACY_GRANTED' | 'PASS_GRANTED' | 'MANUAL_GRANTED' | 'LOCKED_PASS_REQUIRED';

export type HeroMiningState = {
  enabled: boolean;
  /** Server authorization for NFT mining (Pass gate). Never decided on the client. */
  miningAccess?: TonMiningAccess;
  accessLocked?: boolean;
  passGate?: { enabled: boolean; cutoffAt: string; priceTon: number };
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

/**
 * Currency shown as the "main" one (defaults to TON for legacy payloads).
 * Mining is per-NFT now: a player can accrue TON (already sold NFTs) and MYTH
 * (NFTs that carry a MYTH rate) at the same time.
 */
export function miningStateCurrency(state: HeroMiningState | undefined): 'ton' | 'myth' {
  if (Number(state?.dailyRateMyth ?? 0) > 0 && !(Number(state?.dailyRateTon ?? 0) > 0)) return 'myth';
  return 'ton';
}

/** TON daily rate (units frozen in TON). */
export function miningStateRate(state: HeroMiningState | undefined): number {
  if (!state) return 0;
  return Number(state.dailyRateTon ?? state.dailyRate ?? 0);
}

/** MYTH daily rate (units frozen in MYTH). */
export function miningStateMythRate(state: HeroMiningState | undefined): number {
  return Number(state?.dailyRateMyth ?? 0);
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
  const base = Number(state?.unclaimedTon ?? state?.unclaimed ?? 0);
  if (!state || !state.enabled) return base;
  const since = Math.max(0, (nowMs - new Date(state.updatedAt).getTime()) / 1000);
  const produced = (miningStateRate(state) * since) / 86400;
  // No eligible TON invested (or ROI cap reached): TON units generate nothing.
  const room = Math.max(0, Number(state.remainingTon ?? 0));
  if (room <= 0) return base;
  return base + Math.min(produced, room);
}

/** MYTH accrual has no ROI cap: it is limited by the MYTH mining pool at claim time. */
export function projectUnclaimedMyth(state: HeroMiningState | undefined, nowMs: number): number {
  const base = Number(state?.unclaimedMyth ?? 0);
  if (!state || !state.enabled) return base;
  const since = Math.max(0, (nowMs - new Date(state.updatedAt).getTime()) / 1000);
  return base + (miningStateMythRate(state) * since) / 86400;
}

/** Mining runs when any unit produces: TON needs ROI room, MYTH only a rate. */
export function miningActive(state: HeroMiningState | undefined): boolean {
  if (!state) return false;
  if (!state.enabled) return false;
  if (miningStateMythRate(state) > 0) return true;
  return Number(state.investedTon || 0) > 0 && Number(state.remainingTon || 0) > 0;
}


/** Rarities allowed to mine TON (mirrors the server gate `hero_mining_rarity_eligible`). */
export const MINING_ELIGIBLE_RARITIES = ['rare', 'epic', 'legendary', 'mythic', 'ancestral', 'nft_exclusive'] as const;

/** Common/Uncommon never mine. NFT Exclusive sits above the ladder and always passes. */
export function isMiningRarity(rarity: string | null | undefined): boolean {
  return (MINING_ELIGIBLE_RARITIES as readonly string[]).includes(String(rarity ?? '').toLowerCase());
}
