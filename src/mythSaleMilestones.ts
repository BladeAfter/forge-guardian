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
  { amount: 500_000, rewards: ['1 Exclusive Pet Egg', '100 Universal Fragments'] },
  { amount: 1_000_000, rewards: ['1 Exclusive Hero Chest', '200 Universal Fragments', '5 PvP Tickets', 'NFT Weapon: Mythblade Ascendant'] },
  { amount: 1_500_000, rewards: ['1 Mythic Chest', '250 Universal Fragments', '8 PvP Tickets'] },
  { amount: 2_000_000, rewards: ['1 Exclusive Hero Chest', '300 Universal Fragments', '10 PvP Tickets', 'NFT Weapon: Myth Reaver'] },
  { amount: 3_000_000, rewards: ['1 Exclusive Pet Egg', '400 Universal Fragments', '12 PvP Tickets'] },
  { amount: 4_000_000, rewards: ['1 Exclusive Hero Chest', '500 Universal Fragments', '15 PvP Tickets', 'NFT Weapon: Scepter of Eternity'] },
  { amount: 5_000_000, rewards: ['1 Exclusive Hero Chest', '650 Universal Fragments', '20 PvP Tickets'] },
  { amount: 6_000_000, rewards: ['1 Exclusive Pet Egg', '800 Universal Fragments', '25 PvP Tickets', 'NFT Weapon: Mythveil Longbow'] },
  { amount: 7_000_000, rewards: ['1 Exclusive Hero Chest', '1000 Universal Fragments', '30 PvP Tickets'] },
  { amount: 8_000_000, rewards: ['1 Exclusive Hero Chest', '1300 Universal Fragments', '35 PvP Tickets', 'NFT Weapon: Mythsong Staff'] },
  { amount: 9_000_000, rewards: ['1 Exclusive Pet Egg', '1600 Universal Fragments', '40 PvP Tickets'] },
  { amount: 10_000_000, rewards: ['1 Exclusive Hero Chest', '2000 Universal Fragments', '50 PvP Tickets', 'NFT Weapon: Godshard of Mythic Seas'] },
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
