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
  name: string;
  username: string | null;
  avatar: string | null;
  trophies: number;
  power: number;
  lastActive: string;
  isMe: boolean;
};

export type ClanMission = { code: string; title: string; target: number; progress: number; rewardPoints: number; completed: boolean };
export type ClanMessage = { id: string; name: string; avatar: string | null; body: string; createdAt: string; isMe: boolean };
export type ClanJoinRequest = { id: string; userId: string; name: string; avatar: string | null; trophies: number };
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
};

const CLAN_ERRORS: Record<string, string> = {
  ALREADY_IN_CLAN: 'clan.error.alreadyInClan',
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
};

/** Maps a backend error code onto a translation key, so every message follows the player's language. */
export const clanErrorKey = (message: string) => CLAN_ERRORS[message] ?? '';

export async function clanRequest<T = ClanDashboard>(initData: string, input: Record<string, unknown> = { action: 'dashboard' }): Promise<T> {
  const response = await forgeFetch('clan', { initData, ...input });
  if (response.status === 404) throw new Error('CLAN_BACKEND_OFFLINE');
  const payload = (await response.json().catch(() => null)) as (T & { error?: string }) | null;
  if (!response.ok || !payload) throw new Error(payload?.error || 'CLAN_UNKNOWN');
  return payload;
}

export const fetchClanDashboard = (initData: string) => clanRequest<ClanDashboard>(initData, { action: 'dashboard' });
export const fetchClanMessages = (initData: string) => clanRequest<{ messages: ClanMessage[] }>(initData, { action: 'chat', chatAction: 'list' });
