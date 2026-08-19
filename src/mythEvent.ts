/**
 * MYTHREON :: SPENDING EVENT (frontend contract only).
 *
 * Promotional 14-day event attached to the MYTH sale. Supply/sold/burned/TON raised always come
 * from the backend sale dashboard (`get_myth_sale_dashboard`); this module only holds the fixed
 * event window and the milestone table used to render progress and rewards.
 */
import type { MythSalePurchaseRow } from './mythSale';

/** Event start (UTC). Duration is fixed at 14 days. */
export const MYTH_EVENT_START = '2026-08-19T00:00:00.000Z';
export const MYTH_EVENT_DAYS = 14;
export const MYTH_EVENT_END = new Date(new Date(MYTH_EVENT_START).getTime() + MYTH_EVENT_DAYS * 86_400_000).toISOString();

export type MythEventMilestone = { amount: number; rewards: string[] };

export const MYTH_EVENT_MILESTONES: MythEventMilestone[] = [
  { amount: 10_000, rewards: ['1 Rare Chest', '5 Universal Fragments'] },
  { amount: 50_000, rewards: ['1 Epic Chest', '10 Universal Fragments', '2 PvP Tickets'] },
  { amount: 100_000, rewards: ['1 Legendary Chest', '25 Universal Fragments', '1 Exclusive Avatar Border'] },
  { amount: 250_000, rewards: ['1 Mythic Chest', '50 Universal Fragments', '1 Premium Title'] },
  { amount: 500_000, rewards: ['1 Exclusive Pet Egg', '100 Universal Fragments', '1 Special Event Badge'] },
  { amount: 1_000_000, rewards: ['1 Exclusive Hero', '1 NFT Weapon', '1 Special Event Frame'] },
];

const DEAD_STATUS = ['pending', 'expired', 'failed', 'cancelled', 'canceled', 'reserved'];

/** MYTH bought by the player inside the event window (settled purchases only). */
export function mythBoughtInEvent(purchases: MythSalePurchaseRow[], now = Date.now()): number {
  const start = new Date(MYTH_EVENT_START).getTime();
  const end = Math.min(new Date(MYTH_EVENT_END).getTime(), Math.max(now, start));
  return purchases.reduce((total, row) => {
    const at = new Date(row.createdAt).getTime();
    if (!Number.isFinite(at) || at < start || at > end) return total;
    if (DEAD_STATUS.includes(String(row.status || '').toLowerCase())) return total;
    return total + (Number(row.mythAmount) || 0);
  }, 0);
}

export type MythEventCountdown = { days: number; hours: number; minutes: number; seconds: number; ended: boolean; started: boolean; progressPercent: number };

export function mythEventCountdown(now = Date.now()): MythEventCountdown {
  const start = new Date(MYTH_EVENT_START).getTime();
  const end = new Date(MYTH_EVENT_END).getTime();
  const ms = Math.max(0, end - now);
  const elapsed = Math.min(Math.max(0, now - start), end - start);
  return {
    days: Math.floor(ms / 86_400_000),
    hours: Math.floor((ms % 86_400_000) / 3_600_000),
    minutes: Math.floor((ms % 3_600_000) / 60_000),
    seconds: Math.floor((ms % 60_000) / 1000),
    ended: ms <= 0,
    started: now >= start,
    progressPercent: Math.round((elapsed / (end - start)) * 1000) / 10,
  };
}

/** Next milestone the player has not reached yet (null when everything is unlocked). */
export function nextMythMilestone(bought: number): MythEventMilestone | null {
  return MYTH_EVENT_MILESTONES.find(m => bought < m.amount) ?? null;
}

/** Percentage towards the next milestone, counting from the previous one. */
export function mythMilestoneProgress(bought: number): number {
  const next = nextMythMilestone(bought);
  if (!next) return 100;
  const index = MYTH_EVENT_MILESTONES.indexOf(next);
  const floor = index > 0 ? MYTH_EVENT_MILESTONES[index - 1].amount : 0;
  const span = Math.max(1, next.amount - floor);
  return Math.min(100, Math.max(0, Math.round(((bought - floor) / span) * 1000) / 10));
}
