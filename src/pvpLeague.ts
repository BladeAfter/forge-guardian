/**
 * MYTHREON :: PVP LEAGUE ARENA (main event slot).
 *
 * The backend (`pvp_league_dashboard`) owns the event score, ranking and prize
 * table. The client only renders it: it never sends score deltas.
 */
export type PvpLeagueRankRow = {
  position: number;
  userId: string;
  name: string;
  username: string | null;
  avatarUrl: string | null;
  score: number;
  wins: number;
  matches: number;
  rewardTon: number;
  isYou: boolean;
};

export type PvpLeagueTier = { label: string; ton: number };

export type PvpLeagueDashboard = {
  status: 'draft' | 'active' | 'finished' | 'cancelled';
  active: boolean;
  event: {
    id: string;
    name: string;
    prizePoolTon: number;
    topLimit: number;
    startedAt: string | null;
    endsAt: string | null;
    durationDays: number;
  };
  participants: number;
  player: {
    score: number;
    position: number | null;
    matches: number;
    wins: number;
    estimatedRewardTon: number;
    league: string | null;
    trophies: number;
    inTop: boolean;
  };
  tiers: PvpLeagueTier[];
  ranking: PvpLeagueRankRow[];
  serverTime: string;
};

/** Countdown from the server end date; the client never decides when the event ends. */
export function leagueCountdown(endsAt: string | null | undefined, now = Date.now()) {
  const ms = Math.max(0, (endsAt ? new Date(endsAt).getTime() : 0) - now);
  return {
    days: Math.floor(ms / 86_400_000),
    hours: Math.floor((ms % 86_400_000) / 3_600_000),
    minutes: Math.floor((ms % 3_600_000) / 60_000),
    ended: ms <= 0,
  };
}

/** Medal used by the ranking rows (top 3 only). */
export const leagueMedal = (position: number) => (position === 1 ? '🥇' : position === 2 ? '🥈' : position === 3 ? '🥉' : '');
