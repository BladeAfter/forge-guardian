import { forgeFetch } from './apiClient';

/**
 * MISSION: ADD #Mythreon TO YOUR TELEGRAM NAME.
 * The client never sends (nor is trusted with) the display name: it only asks the
 * backend to VERIFY & CLAIM. The server reads the real Telegram profile and pays once.
 */
export type NameMissionState = {
  enabled: boolean;
  hashtag: string;
  rewardFc: number;
  claimed: boolean;
  claimedAt?: string | null;
  verifiedName?: string | null;
  rewardReceived?: number;
};

export type NameMissionVerify = NameMissionState & {
  status?: 'claimed' | 'already_claimed' | 'not_verified';
  verified: boolean;
  reason?: string;
  stale?: boolean;
  source?: 'bot_api' | 'init_data';
  displayName?: string;
  creditedFc?: number;
  balance?: number;
};

async function request<T>(initData: string, action: 'state' | 'verify'): Promise<T> {
  const response = await forgeFetch('namemission', { initData, action });
  if (response.status === 404) throw new Error('BACKEND_OFFLINE');
  const payload = (await response.json().catch(() => null)) as (T & { error?: string }) | null;
  if (!response.ok || !payload) throw new Error(payload?.error || 'NAME_MISSION_ERROR');
  return payload;
}

export const fetchNameMission = (initData: string) => request<NameMissionState>(initData, 'state');
export const verifyNameMission = (initData: string) => request<NameMissionVerify>(initData, 'verify');
