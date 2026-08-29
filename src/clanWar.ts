import { forgeFetch } from './apiClient';
import type { PvpHero } from './pvp';

/** Fortress sector codes (server-owned, see clan_war_sector_def). */
export type ClanWarSectorCode = 'OUTER_GATE' | 'NORTH_TOWER' | 'SOUTH_TOWER' | 'INNER_KEEP' | 'CLAN_THRONE';

export type ClanWarConfig = {
  enabled: boolean;
  rosterSize: number;
  attacksPerPlayer: number;
  preparationHours: number;
  battleHours: number;
  seasonWeeks: number;
  matchmaking: boolean;
  baseRating: number;
  pointsWin: number;
  pointsPerfect: number;
  pointsUpsetMax: number;
  pointsLoss: number;
  defenderMaxDefeats: number;
  conqueredPercent: number;
  sectorBonusPercent: number;
  tonSeasonPrize: boolean;
};

export type ClanWarSeason = { id: string; code: string; name: string; starts_at: string; ends_at: string; status: string; ton_prize_enabled: boolean; ton_prize_ton: number } | null;

export type ClanWarSide = { id: string; name: string; tag: string; emblem: Record<string, string> | null; rating: number; league: string };

export type ClanWarDefender = { userId: string; name: string; avatarUrl: string | null; power: number; defeats: number; beaten: boolean };

export type ClanWarSector = {
  code: ClanWarSectorCode;
  order: number;
  bonus: string | null;
  required: number;
  requires: ClanWarSectorCode[];
  conquered: boolean;
  defenders: ClanWarDefender[];
};

export type ClanWarRosterEntry = {
  userId: string;
  name: string;
  avatarUrl: string | null;
  sector: ClanWarSectorCode;
  points: number;
  attacksLeft: number;
  wins: number;
  losses: number;
  defeatsTaken: number;
  defenseSet: boolean;
  isMe: boolean;
};

export type ClanWarFeedEntry = { id: string; sector: ClanWarSectorCode; result: 'win' | 'loss'; points: number; perfect: boolean; attacker: string; defender: string; mine: boolean; createdAt: string };

export type ClanWarMe = {
  inRoster: boolean;
  sector: ClanWarSectorCode;
  attacksLeft: number;
  attacksTotal: number;
  points: number;
  wins: number;
  losses: number;
  defense: { heroIds: string[]; petId: string | null; power: number; team: PvpHero[] } | null;
};

export type ClanWarState = {
  warId: string;
  status: 'searching' | 'preparation' | 'battle' | 'finished' | 'cancelled';
  preparationEndsAt: string | null;
  battleEndsAt: string | null;
  scoreYou: number;
  scoreEnemy: number;
  yourClan: ClanWarSide | null;
  enemyClan: ClanWarSide | null;
  me: ClanWarMe | null;
  attackTeam: PvpHero[];
  sectors: ClanWarSector[];
  roster: ClanWarRosterEntry[];
  feed: ClanWarFeedEntry[];
};

export type ClanWarRankEntry = { clanId: string; name: string; tag: string; emblem: Record<string, string> | null; rating: number; league: string; wins: number; losses: number; points: number };

export type ClanWarDashboard = {
  config: ClanWarConfig;
  inClan: boolean;
  role: string | null;
  canManage: boolean;
  season: ClanWarSeason;
  war: ClanWarState | null;
  lastWar?: { warId: string; scoreYou: number; scoreEnemy: number; result: 'win' | 'loss' | 'draw'; reward: Record<string, unknown> | null } | null;
  ranking: ClanWarRankEntry[];
};

export type ClanWarAttackResult = {
  status: 'ok';
  win: boolean;
  points: number;
  perfect: boolean;
  sectorConquered: boolean;
  battleLog: Array<{ turn: number; side: string; attackerId: string; targetId: string; damage: number; remainingHp: number }>;
  attackerState: PvpHero[];
  defenderState: PvpHero[];
};

/** Human labels come from i18n; this is only the fallback ordering/naming helper. */
export const CLAN_WAR_SECTOR_LABEL: Record<ClanWarSectorCode, string> = {
  OUTER_GATE: 'Outer Gate',
  NORTH_TOWER: 'North Tower',
  SOUTH_TOWER: 'South Tower',
  INNER_KEEP: 'Inner Keep',
  CLAN_THRONE: 'Clan Throne',
};

export type ClanWarRosterCandidate = {
  userId: string;
  name: string;
  avatarUrl: string | null;
  role: string;
  power: number;
  inRoster: boolean;
  /** Already fought in this war: cannot be removed from the roster anymore. */
  locked: boolean;
};

export type ClanWarRosterPicker = {
  rosterSize: number;
  warId: string | null;
  status: string | null;
  editable: boolean;
  selected: string[];
  members: ClanWarRosterCandidate[];
};

export const CLAN_WAR_ERRORS: Record<string, string> = {
  NOT_IN_CLAN: 'clan.error.notInClan',
  CLAN_WAR_DISABLED: 'clanwar.error.disabled',
  CLAN_WAR_NOT_ACTIVE: 'clanwar.error.notActive',
  CLAN_WAR_NOT_IN_BATTLE: 'clanwar.error.notInBattle',
  CLAN_WAR_NOT_IN_ROSTER: 'clanwar.error.notInRoster',
  CLAN_WAR_NO_ATTACKS: 'clanwar.error.noAttacks',
  CLAN_WAR_INVALID_TARGET: 'clanwar.error.invalidTarget',
  CLAN_WAR_SECTOR_LOCKED: 'clanwar.error.sectorLocked',
  CLAN_WAR_NO_ATTACK_TEAM: 'clanwar.error.noAttackTeam',
  CLAN_WAR_ALREADY_QUEUED: 'clanwar.error.alreadyQueued',
  CLAN_WAR_NOT_ALLOWED: 'clan.error.notAllowed',
  CLAN_WAR_ROSTER_LOCKED: 'clanwar.error.rosterLocked',
  CLAN_WAR_ROSTER_EMPTY: 'clanwar.error.rosterEmpty',
  CLAN_WAR_ROSTER_TOO_LARGE: 'clanwar.error.rosterTooLarge',
  INVALID_TEAM: 'clanwar.error.invalidTeam',
};

export const clanWarErrorKey = (message: string) => CLAN_WAR_ERRORS[message] ?? '';


/** All clan-war traffic goes through the game-api `clan-war` route; the RPCs own every rule. */
export async function clanWarRequest<T>(initData: string, input: Record<string, unknown> = { action: 'dashboard' }): Promise<T> {
  const response = await forgeFetch('clan-war', { initData, ...input });
  const payload = (await response.json().catch(() => null)) as (T & { error?: string }) | null;
  if (!response.ok || !payload || (payload as { error?: string }).error) {
    const message = (payload as { error?: string } | null)?.error || 'CLAN_WAR_BACKEND_OFFLINE';
    console.error('[CLAN WAR REQUEST FAILED]', { action: input.action, status: response.status, message });
    throw new Error(message);
  }
  return payload;
}

export const fetchClanWarDashboard = (initData: string) => clanWarRequest<ClanWarDashboard>(initData, { action: 'dashboard' });
export const joinClanWar = (initData: string) => clanWarRequest<ClanWarDashboard>(initData, { action: 'join' });
export const leaveClanWarQueue = (initData: string) => clanWarRequest<{ status: string }>(initData, { action: 'leave-queue' });
export const setClanWarDefense = (initData: string, heroIds: string[], petId?: string | null) =>
  clanWarRequest<{ status: string; power: number }>(initData, { action: 'defense', heroIds, petId: petId ?? null });
export const attackClanWarDefender = (initData: string, defender: string, clientKey: string) =>
  clanWarRequest<ClanWarAttackResult>(initData, { action: 'attack', defender, clientKey });
export const fetchClanWarRosterPicker = (initData: string) =>
  clanWarRequest<ClanWarRosterPicker>(initData, { action: 'roster-candidates' });
export const setClanWarRoster = (initData: string, userIds: string[]) =>
  clanWarRequest<{ status: string; selected: number; rosterSize: number }>(initData, { action: 'set-roster', userIds });
