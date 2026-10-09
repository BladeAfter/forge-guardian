/**
 * Mythic Seas :: MYTH TOKEN SALE (frontend contract only).
 *
 * Every number here is produced by the backend (`get_myth_sale_dashboard` / `myth_sale_stats`).
 * The client never computes price, supply, availability or the payment method — it only renders
 * what the database decided and forwards a TonConnect transfer when the backend asks for one.
 */
export type MythSaleStats = {
  symbol: string;
  name: string;
  saleStatus: 'active' | 'paused' | 'finished' | string;
  mythPerTon: number;
  minPurchase: number;
  intentMinutes: number;
  initialSupply: number;
  saleAllocation: number;
  effectiveSupply: number;
  sold: number;
  burned: number;
  reserved: number;
  available: number;
  tonRaised: number;
  burnedPercent: number;
  soldPercent: number;
  lastSaleAt: string | null;
  serverTime: string;
};

export type MythSalePurchaseRow = {
  id: string;
  mythAmount: number;
  amountTon: number;
  method: 'INTERNAL' | 'TONCONNECT' | string;
  status: string;
  createdAt: string;
};

export type MythBurnRow = { id: string; amount: number; reason: string | null; createdAt: string };

/** Pending TonConnect checkout: supply stays reserved by the backend until it expires. */
export type MythSaleIntent = {
  id: string;
  mythAmount: number;
  amountTon: number;
  amountNano: string;
  paymentAddress: string;
  paymentComment: string;
  expiresAt: string;
};

export type MythSaleDashboard = {
  stats: MythSaleStats;
  /** `mythPurchasedTotal` = compras diretas + MYTH recebido nos pacotes premium (35 / 100 TON). */
  player: { mythBalance: number; internalTon: number; mythPurchasedTotal?: number };
  purchases: MythSalePurchaseRow[];
  pendingIntent: MythSaleIntent | null;
  burns: MythBurnRow[];
};

/** Backend answer for a purchase attempt: internal settlement or a TonConnect intent. */
export type MythSalePurchaseResult =
  | { ok: true; method: 'INTERNAL'; duplicate?: boolean; transactionId: string; mythAmount: number; amountTon: number; stats: MythSaleStats }
  | ({ ok: true; method: 'TONCONNECT'; duplicate?: boolean; paymentId: string; stats: MythSaleStats } & MythSaleIntent);

/** 100,000,000 · 20.5K — compact display for supply cards, never used in any calculation. */
export function abbreviateMyth(value: number | null | undefined): string {
  const n = Math.max(0, Number(value) || 0);
  if (n >= 1_000_000) return `${trim(n / 1_000_000)}M`;
  if (n >= 1_000) return `${trim(n / 1_000)}K`;
  return trim(n);
}

const trim = (n: number) => String(Math.round(n * 100) / 100);

export const mythFull = (value: number | null | undefined) => Math.round(Number(value) || 0).toLocaleString();

/** TON cost preview (display only): the charged amount is always the server's `amountNano`. */
export const mythCostTon = (mythAmount: number, mythPerTon: number) =>
  mythPerTon > 0 ? Math.ceil((mythAmount / mythPerTon) * 1e9) / 1e9 : 0;

export type MythIntentCountdown = { minutes: number; seconds: number; expired: boolean };

export function mythIntentCountdown(expiresAt: string | null | undefined, now = Date.now()): MythIntentCountdown {
  const end = expiresAt ? new Date(expiresAt).getTime() : 0;
  const ms = Math.max(0, end - now);
  return { minutes: Math.floor(ms / 60_000), seconds: Math.floor((ms % 60_000) / 1000), expired: ms <= 0 };
}
