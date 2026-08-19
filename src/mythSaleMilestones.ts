/**
 * MYTH SALE MILESTONES (presentation contract only).
 *
 * Restores the original chest/reward ladder shown under the MYTH SALE tab.
 * Totals come from the backend sale dashboard (`get_myth_sale_dashboard`);
 * the SPENDING EVENT ranking is completely independent from this file.
 */
import type { MythSalePurchaseRow } from './mythSale';

export type MythSaleMilestone = { amount: number; rewards: string[] };

export const MYTH_SALE_MILESTONES: MythSaleMilestone[] = [
  { amount: 10_000, rewards: ['1 Rare Chest', '5 Universal Fragments'] },
  { amount: 50_000, rewards: ['1 Epic Chest', '10 Universal Fragments', '2 PvP Tickets'] },
  { amount: 100_000, rewards: ['1 Legendary Chest', '25 Universal Fragments', '1 Exclusive Avatar Border'] },
  { amount: 250_000, rewards: ['1 Mythic Chest', '50 Universal Fragments', '1 Premium Title'] },
  { amount: 500_000, rewards: ['1 Exclusive Pet Egg', '100 Universal Fragments', '1 Special Event Badge'] },
  { amount: 1_000_000, rewards: ['1 Exclusive Hero', '1 NFT Weapon', '1 Special Event Frame'] },
];

const DEAD_STATUS = ['pending', 'expired', 'failed', 'cancelled', 'canceled', 'reserved'];

/** Total MYTH bought by the player (settled purchases only). */
export function mythBoughtTotal(purchases: MythSalePurchaseRow[]): number {
  return purchases.reduce((total, row) => {
    if (DEAD_STATUS.includes(String(row.status || '').toLowerCase())) return total;
    return total + (Number(row.mythAmount) || 0);
  }, 0);
}

/** Next milestone the player has not reached yet (null when everything is unlocked). */
export function nextMythMilestone(bought: number): MythSaleMilestone | null {
  return MYTH_SALE_MILESTONES.find(m => bought < m.amount) ?? null;
}

/** Percentage towards the next milestone, counting from the previous one. */
export function mythMilestoneProgress(bought: number): number {
  const next = nextMythMilestone(bought);
  if (!next) return 100;
  const index = MYTH_SALE_MILESTONES.indexOf(next);
  const floor = index > 0 ? MYTH_SALE_MILESTONES[index - 1].amount : 0;
  const span = Math.max(1, next.amount - floor);
  return Math.min(100, Math.max(0, Math.round(((bought - floor) / span) * 1000) / 10));
}
