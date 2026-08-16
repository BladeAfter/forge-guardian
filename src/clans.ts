import { forgeFetch } from './apiClient';

export type ClanRole = 'leader' | 'co-leader' | 'officer' | 'member';
export type ClanJoinType = 'open' | 'approval' | 'closed';

export type ClanEmblem = { shield?: string; background?: string; symbol?: string; border?: string };

export type ClanSummary = {
  id: string;
  name: string;
  tag: string;
  description: string;
  level: number;
  xp: number;
  xpNeeded: number;
  joinType: ClanJoinType;
  minimumTrophies: number;
  memberLimit: number;
  emblem: ClanEmblem;
  clanPoints: number;
  members: number;
  power: number;
  suspended?: boolean;
};

export type ClanMember = {
  userId: string;
  role: ClanRole;
  contribution: number;
  clanPoints?: number;
  name: string;
  username: string | null;
  avatar: string | null;
  trophies: number;
  /** Official player power (same formula used in the collection/profile), computed server-side. */
  power: number;
  heroes?: number;
  accountLevel?: number;
  league?: string;
  lastActive: string | null;
  online?: boolean;
  joinedAt?: string;
  isMe: boolean;
};

/** Compact leader summary; every counter is produced by the backend. */
export type ClanAdminStats = {
  members: number;
  memberLimit: number;
  onlineNow: number;
  active24h: number;
  inactive3d: number;
  inactive7d: number;
  inactive14d: number;
  pendingRequests: number;
};

export type ClanMission = { code: string; title: string; target: number; progress: number; rewardPoints: number; completed: boolean };
export type ClanMessage = { id: string; name: string; avatar: string | null; body: string; createdAt: string; isMe: boolean };
export type ClanJoinRequest = {
  id: string; userId: string; name: string; username?: string | null; avatar: string | null; trophies: number;
  power?: number; heroes?: number; accountLevel?: number; league?: string;
  lastActive?: string | null; online?: boolean; createdAt?: string;
};
export type ClanBoss = {
  id: string; name: string; maxHealth: number; currentHealth: number; status: string; endsAt: string;
  rewardPoints: number; myDamage: number; top: { name: string; avatar: string | null; damage: number }[];
};

export type ClanDashboard = {
  inClan: boolean;
  role?: ClanRole;
  clan?: ClanSummary;
  me?: { contribution: number; clanPoints: number; role: ClanRole };
  members?: ClanMember[];
  requests?: ClanJoinRequest[];
  missions?: ClanMission[];
  boss?: ClanBoss | null;
  ranking?: ClanSummary[];
  recommended?: ClanSummary[];
  createCostFc?: number;
  balance?: number;
  canManageMembers?: boolean;
  onlineThresholdMinutes?: number;
  stats?: ClanAdminStats;
};

/** Friendly "8m / 3h / 2d" label plus a tone bucket used for the activity dot. */
export function activityAge(lastActive?: string | null): { minutes: number | null; short: string; tone: 'online' | 'fresh' | 'warm' | 'stale' | 'cold' } {
  if (!lastActive) return { minutes: null, short: '—', tone: 'cold' };
  const minutes = Math.max(0, Math.floor((Date.now() - new Date(lastActive).getTime()) / 60000));
  const days = Math.floor(minutes / 1440);
  const short = minutes < 60 ? `${Math.max(1, minutes)}m` : minutes < 1440 ? `${Math.floor(minutes / 60)}h` : `${days}d`;
  const tone = minutes < 1440 ? 'fresh' : days < 3 ? 'warm' : days < 7 ? 'stale' : 'cold';
  return { minutes, short, tone };
}

const CLAN_ERRORS: Record<string, string> = {
  ALREADY_IN_CLAN: 'clan.error.alreadyInClan',
  // The applicant (not the manager) joined another clan before the approval.
  TARGET_ALREADY_IN_CLAN: 'clan.error.targetAlreadyInClan',
  NOT_IN_CLAN: 'clan.error.notInClan',
  CLAN_FULL: 'clan.error.full',
  CLAN_CLOSED: 'clan.error.closed',
  CLAN_NOT_FOUND: 'clan.error.notFound',
  CLAN_NAME_TAKEN: 'clan.error.nameTaken',
  CLAN_TAG_TAKEN: 'clan.error.tagTaken',
  INVALID_CLAN_NAME: 'clan.error.invalidName',
  INVALID_CLAN_TAG: 'clan.error.invalidTag',
  INSUFFICIENT_FC: 'clan.error.insufficientFc',
  INSUFFICIENT_CLAN_POINTS: 'clan.error.insufficientPoints',
  TROPHIES_TOO_LOW: 'clan.error.trophies',
  NOT_ALLOWED: 'clan.error.notAllowed',
  CHAT_RATE_LIMIT: 'clan.error.rateLimit',
  CLAN_BOSS_COOLDOWN: 'clan.error.bossCooldown',
  CLAN_BOSS_DEFEATED: 'clan.error.bossDefeated',
  INVALID_JOIN_TYPE: 'clan.error.invalidJoinType',
  PLAYER_NOT_FOUND: 'clan.error.playerNotFound',
  BACKEND_BUSY: 'clan.error.busy',
  CLAN_BACKEND_OFFLINE: 'clan.error.offline',
};


/** Maps a backend error code onto a translation key, so every message follows the player's language. */
export const clanErrorKey = (message: string) => CLAN_ERRORS[message] ?? '';

export type ClanRequestError = Error & { code?: string | null; details?: string | null; hint?: string | null; status?: number };

export async function clanRequest<T = ClanDashboard>(initData: string, input: Record<string, unknown> = { action: 'dashboard' }): Promise<T> {
  const action = String(input.action ?? 'dashboard');
  let response: Awaited<ReturnType<typeof forgeFetch>>;
  try {
    response = await forgeFetch('clan', { initData, ...input });
  } catch (error) {
    console.error('[CLAN REQUEST FAILED]', { action, message: error instanceof Error ? error.message : String(error), code: 'NETWORK', details: null, hint: null });
    const failure = new Error('CLAN_BACKEND_OFFLINE') as ClanRequestError;
    failure.code = 'NETWORK';
    throw failure;
  }
  if (response.status === 404) {
    console.error('[CLAN REQUEST FAILED]', { action, status: 404, message: 'clan route unavailable / no Telegram session', code: 'CLAN_BACKEND_OFFLINE' });
    const failure = new Error('CLAN_BACKEND_OFFLINE') as ClanRequestError;
    failure.code = 'CLAN_BACKEND_OFFLINE';
    failure.status = 404;
    throw failure;
  }
  const payload = (await response.json().catch(() => null)) as (T & { error?: string; code?: string | null; details?: string | null; hint?: string | null }) | null;
  if (!response.ok || !payload || payload.error) {
    // Full Supabase diagnostics stay in the console; the player only sees a friendly toast.
    console.error('[CLAN REQUEST FAILED]', {
      action,
      status: response.status,
      message: payload?.error ?? 'resposta inválida do backend',
      code: payload?.code ?? null,
      details: payload?.details ?? null,
      hint: payload?.hint ?? null,
    });
    const failure = new Error(payload?.error || 'CLAN_UNKNOWN') as ClanRequestError;
    failure.code = payload?.code ?? null;
    failure.details = payload?.details ?? null;
    failure.hint = payload?.hint ?? null;
    failure.status = response.status;
    throw failure;
  }
  return payload;
}


export const fetchClanDashboard = (initData: string) => clanRequest<ClanDashboard>(initData, { action: 'dashboard' });
export const fetchClanMessages = (initData: string) => clanRequest<{ messages: ClanMessage[] }>(initData, { action: 'chat', chatAction: 'list' });
