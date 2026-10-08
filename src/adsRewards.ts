import { forgeFetch } from './apiClient';

/**
 * REWARDS tab — AdsGram rewarded ads that pay real TON.
 *
 * Every rule lives in the backend: reward per ad, daily limit and the 21:00
 * (America/Sao_Paulo) reset. The client only shows an ad and reports completion.
 */
export type AdRewardsState = {
  enabled: boolean;
  blockId: string | null;
  rewardTon: number;
  dailyLimit: number;
  adsCompleted: number;
  remaining: number;
  earnedTon: number;
  maxTon: number;
  period: string;
  resetsAt: string;
  lastAdAt: string | null;
};

export type AdRewardClaim = {
  granted: boolean;
  reason?: string;
  rewardTon?: number;
  balanceTon?: number;
  ads: AdRewardsState;
};

const AD_ERRORS: Record<string, string> = {
  AD_REWARD_DAILY_LIMIT: 'adRewards.errorLimit',
  AD_REWARDS_DISABLED: 'adRewards.errorDisabled',
  NO_PENDING_VIEW: 'adRewards.errorNoView',
  ALREADY_REWARDED: 'adRewards.errorAlready',
};

/** Maps a backend code to an i18n key so the modal can translate it. */
export const adRewardErrorKey = (raw: string) => AD_ERRORS[raw] ?? 'adRewards.errorGeneric';

async function adsRequest<T>(telegramInitData: string, action: 'state' | 'begin' | 'reward', extra: Record<string, unknown> = {}): Promise<T> {
  const response = await forgeFetch('ads', { initData: telegramInitData, action, ...extra });
  const payload = (await response.json().catch(() => null)) as (T & { error?: string }) | null;
  if (!response.ok || !payload) throw new Error(payload?.error || 'AD_REWARD_FAILED');
  return payload;
}

export const fetchAdRewards = (initData: string) => adsRequest<{ ads: AdRewardsState }>(initData, 'state');
/** Opens a server-side view (limit checked there). No TON is granted here. */
export const beginAdReward = (initData: string) => adsRequest<{ viewId: string; blockId: string | null; ads: AdRewardsState }>(initData, 'begin');
/** Called ONLY after AdsGram confirms a valid completion. The server credits the TON. */
export const claimAdReward = (initData: string, viewId: string) => adsRequest<AdRewardClaim>(initData, 'reward', { viewId });
