import { clanRequest } from './clans';

/**
 * Clan Boss (Abyssal Warlord) — a fully independent system.
 * It never reads global boss state: HP, cycles, cooldown, damage, ranking and
 * rewards all live in the clan-scoped backend tables.
 */
export type ClanBossRankRow = {
  userId: string;
  name: string;
  username: string | null;
  avatar: string | null;
  damage: number;
  attacks: number;
  isMe: boolean;
};

export type ClanBossHistoryRow = {
  cycle: number;
  status: 'defeated' | 'expired' | string;
  maxHp: number;
  totalDamage: number;
  clanXp: number;
  finishedAt: string | null;
  topName: string | null;
};

export type ClanBossState = {
  inClan: boolean;
  bossName?: string;
  clan?: { id: string; name: string; tag: string; level: number; emblem: Record<string, string> };
  boss?: {
    id: string;
    key: string;
    name: string;
    cycle: number;
    level: number;
    maxHp: number;
    currentHp: number;
    status: 'active' | 'defeated' | 'expired' | string;
    startsAt: string;
    endsAt: string;
    clanDamage: number;
    attacks: number;
    participants: number;
    minDamageForRewards: number;
    clanXpReward: number;
    cooldownSeconds: number;
  };
  me?: {
    damage: number;
    attacks: number;
    rank: number | null;
    nextAttackAt: string | null;
    canAttack: boolean;
    eligibleForRewards: boolean;
    power: number;
  };
  ranking?: ClanBossRankRow[];
  rewards?: Record<string, unknown>;
  history?: ClanBossHistoryRow[];
  serverTime: string;
};

export type ClanBossStrike = {
  status: string;
  damage: number;
  critical: boolean;
  currentHp: number;
  maxHp: number;
  defeated: boolean;
  nextAttackAt: string;
  /**
   * Optional presentation-only fields. The battle backend currently returns the
   * player strike; when it also reports the boss retaliation these are used to
   * animate it. Never synthesized on the client.
   */
  eventId?: string;
  bossAttack?: { damage?: number; teamDamage?: number } | null;
  teamDamage?: number | null;
  heroesDefeated?: string[] | null;
  heroesRevived?: string[] | null;
};


export const fetchClanBoss = (initData: string) => clanRequest<ClanBossState>(initData, { action: 'boss-state' });

export const strikeClanBoss = (initData: string, instanceId: string | null) =>
  clanRequest<ClanBossStrike>(initData, { action: 'boss-strike', instanceId });

/** Compact number formatting used across the clan boss screen (13.2K, 1.05M). */
export function abbreviateDamage(value: number | null | undefined): string {
  const n = Math.max(0, Math.round(Number(value) || 0));
  if (n < 1000) return String(n);
  const units: [number, string][] = [[1_000_000_000, 'B'], [1_000_000, 'M'], [1_000, 'K']];
  for (const [size, suffix] of units) {
    if (n >= size) {
      const scaled = n / size;
      return `${(scaled >= 100 ? scaled.toFixed(0) : scaled.toFixed(scaled >= 10 ? 1 : 2)).replace(/\.0+$/, '')}${suffix}`;
    }
  }
  return String(n);
}

/** "18h 42m" / "42m 10s" countdown, always derived from the server clock. */
export function countdownLabel(target: string | null | undefined, now: number): string {
  if (!target) return '--';
  const ms = new Date(target).getTime() - now;
  if (!Number.isFinite(ms) || ms <= 0) return '00m 00s';
  const total = Math.floor(ms / 1000);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  if (hours > 0) return `${hours}h ${String(minutes).padStart(2, '0')}m`;
  return `${String(minutes).padStart(2, '0')}m ${String(seconds).padStart(2, '0')}s`;
}
