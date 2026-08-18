/**
 * MYTHREON :: INTERNAL MYTH STAKING (frontend contract only).
 *
 * This is Mythreon ecosystem staking, NOT TON on-chain / validator staking:
 * MYTH only moves between the available balance and a staking position, and every reward is paid
 * from a reserve of the existing supply. APR, locks, limits and the on/off switch come from the
 * backend (Admin Bot) — the client never computes rewards nor decides whether staking is open.
 */
export type MythStakingPlan = { code: string; label: string; lockDays: number; aprPercent: number };

export type MythStakingSettings = {
  enabled: boolean;
  claimsEnabled: boolean;
  newStakesPaused: boolean;
  minStake: number;
  maxStake: number;
  bestApr: number | null;
  rewardPoolTotal: number;
  rewardPoolAvailable: number;
  rewardPoolDistributed: number;
};

export type MythStakingPosition = {
  id: string;
  planCode: string;
  planLabel: string;
  amount: number;
  aprPercent: number;
  lockDays: number;
  claimable: number;
  claimed: number;
  stakedAt: string;
  unlockAt: string | null;
  unlocked: boolean;
};

export type MythStakingDashboard = {
  settings: MythStakingSettings;
  plans: MythStakingPlan[];
  player: { available: number; staked: number; totalOwned: number; claimable: number };
  positions: MythStakingPosition[];
  totals: { totalStaked: number; stakers: number };
  serverTime: string;
};

/** 125,000 MYTH — display only, never used in any server-side calculation. */
export const formatMyth = (value: number | null | undefined) =>
  Number(value ?? 0).toLocaleString('en-US', { maximumFractionDigits: 4 });

/** APR is never hardcoded: until the Admin configures it we simply show a dash. */
export const formatApr = (apr: number | null | undefined) =>
  apr && apr > 0 ? `${Number(apr).toLocaleString('en-US', { maximumFractionDigits: 2 })}%` : '--%';

export const formatUnlockDate = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleDateString('pt-BR') : null;

export const mythStakingErrorLabel = (message: string): string => {
  const key = (message || '').replace(/^.*::/, '').trim();
  const map: Record<string, string> = {
    MYTH_STAKING_DISABLED: 'Staking is being prepared for a future Mythreon update.',
    MYTH_STAKING_PAUSED: 'New stakes are paused right now.',
    MYTH_STAKING_CLAIMS_DISABLED: 'Reward claims are temporarily disabled.',
    MYTH_STAKING_PLAN_INVALID: 'This staking plan is not active.',
    MYTH_STAKING_INVALID_AMOUNT: 'Enter a valid MYTH amount.',
    MYTH_STAKING_MIN_AMOUNT: 'Amount below the minimum stake.',
    MYTH_STAKING_MAX_AMOUNT: 'Amount above the maximum stake.',
    MYTH_STAKING_INSUFFICIENT: 'Not enough available MYTH.',
    MYTH_STAKING_LOCKED: 'This position is still locked.',
    MYTH_STAKING_NOTHING_TO_CLAIM: 'No rewards to claim yet.',
    MYTH_STAKING_POSITION_NOT_FOUND: 'Staking position not found.',
  };
  return map[key] ?? key ?? 'Staking action failed.';
};
