import { formatTon } from './economy';
/**
 * Mythic Seas :: Special Events (independent layer, never mixed with the weekly Community Pool).
 *
 * The backend (`get_special_events_dashboard`) is the only source of truth for
 * valid referrals, ranking and prize estimation. The client just renders it.
 */
export type EventDistributionSlice = { from: number; to: number; ton?: number; totalTon?: number };

export type SpecialEventRankRow = {
  position: number;
  userId: string;
  name: string;
  username: string | null;
  avatarUrl: string | null;
  validReferrals: number;
  estimatedRewardTon: number;
  isYou: boolean;
};

export type SpecialEventSummary = {
  id: string;
  eventKey: string;
  name: string;
  type: string;
  startsAt: string;
  endsAt: string;
  status: 'scheduled' | 'active' | 'finished' | 'cancelled';
  prizePoolTon: number;
  distributionMode: 'fixed' | 'proportional';
  minDailyQuests: number;
  topLimit: number;
  distribution: EventDistributionSlice[];
};

export type SpecialEventsDashboard = {
  event: SpecialEventSummary | null;
  nextEvent: { name: string; startsAt: string; endsAt: string; prizePoolTon: number; type: string } | null;
  ranking: SpecialEventRankRow[];
  participantCount: number;
  totalValidReferrals: number;
  player: { validReferrals: number; position: number | null; estimatedRewardTon: number; lifetimeReferrals: number };
  serverTime: string;
};

export type EventCountdown = { days: number; hours: number; minutes: number; seconds: number; ended: boolean };

/** Countdown derived from the backend end date; the client never decides when an event ends. */
export function eventCountdown(endsAt: string | null | undefined, now = Date.now()): EventCountdown {
  const end = endsAt ? new Date(endsAt).getTime() : 0;
  const ms = Math.max(0, end - now);
  return {
    days: Math.floor(ms / 86_400_000),
    hours: Math.floor((ms % 86_400_000) / 3_600_000),
    minutes: Math.floor((ms % 3_600_000) / 60_000),
    seconds: Math.floor((ms % 60_000) / 1000),
    ended: ms <= 0,
  };
}

export const formatEventTon = (value: number) => `${formatTon(value)} TON`;

/** Human readable prize table used by the "how it works" sheet. */
export function describeDistribution(event: SpecialEventSummary | null): { label: string; value: string }[] {
  if (!event) return [];
  if (event.distributionMode === 'proportional') return [{ label: 'TOP ' + event.topLimit, value: 'Proportional' }];
  return (event.distribution || []).map((slice) => ({
    label: slice.from === slice.to ? `#${slice.from}` : `#${slice.from}–#${slice.to}`,
    value: formatEventTon(slice.ton ?? slice.totalTon ?? 0) + (slice.ton === undefined ? ' total' : ''),
  }));
}
