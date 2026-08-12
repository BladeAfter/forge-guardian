/**
 * MYTHREON :: SPENDING EVENT (independent tracking layer).
 *
 * The backend (`get_spending_event_dashboard`) is the single source of truth for
 * spending points, ranking, totals and estimated rewards. The client only renders.
 * Nothing here touches the Weekly Pool or the Referral Event.
 */
export type SpendingRankRow = {
  position: number;
  userId: string;
  name: string;
  username: string | null;
  avatarUrl: string | null;
  points: number;
  fcSpent: number;
  tonSpent: number;
  estimatedReward: string | null;
};

export type SpendingEventSummary = {
  id: string;
  name: string;
  startsAt: string;
  endsAt: string;
  status: 'scheduled' | 'active' | 'finished' | 'cancelled';
  tonRateFc: number;
  topLimit: number;
};

export type SpendingRewardSlot = { from: number; to: number; label: string };

export type SpendingEventDashboard = {
  event: SpendingEventSummary | null;
  totals: { points: number; fcSpent: number; tonSpent: number; participants: number };
  player: {
    points: number;
    fcSpent: number;
    tonSpent: number;
    position: number | null;
    estimatedReward: string | null;
    nextRank: number | null;
    neededToNext: number | null;
  };
  ranking: SpendingRankRow[];
  rewards: SpendingRewardSlot[];
  serverTime: string;
};

/** 950 · 1.2K · 15.8K · 1.25M · 12.5M — never full giant numbers in the compact UI. */
export function abbreviatePoints(value: number | null | undefined): string {
  const n = Math.max(0, Math.round(Number(value) || 0));
  if (n < 1000) return String(n);
  const units: [number, string][] = [
    [1_000_000_000, 'B'],
    [1_000_000, 'M'],
    [1_000, 'K'],
  ];
  for (const [size, suffix] of units) {
    if (n >= size) {
      const scaled = n / size;
      const text = scaled >= 100 ? scaled.toFixed(0) : scaled.toFixed(scaled >= 10 ? 1 : 2);
      return `${text.replace(/\.0+$/, '').replace(/(\.\d)0$/, '$1')}${suffix}`;
    }
  }
  return String(n);
}

export const fullPoints = (value: number | null | undefined) => Math.round(Number(value) || 0).toLocaleString();

export type SpendingCountdown = { days: number; hours: number; minutes: number; ended: boolean };

/** Countdown always derived from the backend end date. */
export function spendingCountdown(endsAt: string | null | undefined, now = Date.now()): SpendingCountdown {
  const end = endsAt ? new Date(endsAt).getTime() : 0;
  const ms = Math.max(0, end - now);
  return {
    days: Math.floor(ms / 86_400_000),
    hours: Math.floor((ms % 86_400_000) / 3_600_000),
    minutes: Math.floor((ms % 3_600_000) / 60_000),
    ended: ms <= 0,
  };
}

export const countdownLabel = (c: SpendingCountdown) => `${c.days}d ${c.hours}h`;

/** Medal tint for the top three rows; everyone else stays neutral and compact. */
export function rankTone(position: number): string {
  if (position === 1) return 'border-amber-300/60 bg-amber-500/10';
  if (position === 2) return 'border-slate-300/50 bg-slate-400/10';
  if (position === 3) return 'border-orange-400/50 bg-orange-700/10';
  return 'border-white/10 bg-black/55';
}

export const rankMedal = (position: number) => (position === 1 ? '🥇' : position === 2 ? '🥈' : position === 3 ? '🥉' : '');
