import { forgeFetch } from './apiClient';
export type OceanOdds = { kind: 'material' | 'equipment' | 'mascot' | 'ton'; weight: number; amount?: number };
export type OceanChest = { id: string; region: string; rarity: string; x: number; y: number; expiresAt: string; odds: OceanOdds[] };
export type OceanReward = { kind: OceanOdds['kind']; amount?: number; material?: string; itemId?: string; name?: string; rarity?: string; image?: string; paymentStatus?: string };
export type OceanChestState = { poolTon?: number; emission: string; collectRadius: number; odds: OceanOdds[]; alternativeOdds?: OceanOdds[]; chests: OceanChest[]; history: { chest_id: string; reward: OceanReward; payment_status: string; created_at: string }[]; equipmentQuotes: { id: string; name: string; materials: Record<string, number> }[]; reward?: OceanReward };
export const formatOceanTon = (amount: number, locale = 'pt-BR') => new Intl.NumberFormat(locale, { minimumFractionDigits: 3, maximumFractionDigits: 9 }).format(amount);
export function nearestOceanChest(chests: OceanChest[], position: { x: number; y: number }, radius: number): OceanChest | null {
  return chests.filter(c => Date.parse(c.expiresAt) > Date.now()).sort((a,b) => Math.hypot(a.x-position.x,a.y-position.y)-Math.hypot(b.x-position.x,b.y-position.y)).find(c => Math.hypot(c.x-position.x,c.y-position.y)<=radius) ?? null;
}
export async function oceanChestCall(initData: string, oceanAction = 'state', id?: string): Promise<OceanChestState> {
  const response = await forgeFetch('realm', { initData, action: 'ocean-chests', oceanAction, id }, 12_000);
  const data = await response.json() as OceanChestState & { error?: string };
  if (!response.ok || data.error || !Array.isArray(data.chests)) throw new Error(data.error ?? 'OCEAN_UNAVAILABLE');
  return data;
}