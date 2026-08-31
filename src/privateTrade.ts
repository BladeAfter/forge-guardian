/**
 * PRIVATE TRADE — direct player ⇄ player trading (no public listing).
 *
 * Every rule lives in the backend: only the two participants can read or touch a
 * trade, assets go into escrow when a side locks its offer, both sides must
 * confirm, and the swap runs in a single atomic/idempotent settlement.
 * The risk engine (anti-multiaccount) is server-side only — the client never
 * receives IP, device or score data.
 */
import { forgeFetch } from './apiClient';

export type PrivateTradeStatus =
  | 'negotiating' | 'offer_locked' | 'ready_for_confirmation'
  | 'security_review' | 'completed' | 'cancelled' | 'expired' | 'blocked';

export type PrivateTradePlayer = {
  id: string;
  telegramId: number | string;
  name: string;
  username?: string | null;
  avatar?: string | null;
  accountDays?: number;
};

export type PrivateTradeItem = {
  id: string;
  itemType: 'hero' | 'pet' | 'item';
  itemCode: string | null;
  quantity: number;
  snapshot: Record<string, unknown> | null;
};

export type PrivateTradeSide = {
  player: PrivateTradePlayer;
  locked: boolean;
  confirmed: boolean;
  fc: number;
  ton: number;
  myth: number;
  items: PrivateTradeItem[];
};

export type PrivateTradeState = {
  ok: boolean;
  id: string;
  code: string;
  status: PrivateTradeStatus;
  mySide: 'initiator' | 'recipient';
  expiresAt: string;
  createdAt: string;
  completedAt: string | null;
  cancelReason: string | null;
  maxItems: number;
  feePercent: number;
  me: PrivateTradeSide;
  partner: PrivateTradeSide;
  balances: { fc: number; ton: number; myth: number };
};

export type PrivateTradeSummary = {
  id: string;
  code: string;
  status: PrivateTradeStatus;
  partner: PrivateTradePlayer;
  mySide: 'initiator' | 'recipient';
  myItems: number;
  theirItems: number;
  expiresAt: string;
  updatedAt: string;
  createdAt: string;
};

export type PrivateTradeList = {
  ok: boolean;
  settings: { enabled: boolean; adminOnly: boolean; maxItems: number; expireHours: number; minAccountDays: number; feePercent: number };
  canTrade: boolean;
  accountDays: number;
  trades: PrivateTradeSummary[];
};

type PrivateTradeAction =
  | { action: 'list' }
  | { action: 'search'; query: string }
  | { action: 'create'; query: string; requestId?: string }
  | { action: 'view'; tradeId: string }
  | { action: 'add-item'; tradeId: string; itemType: 'hero' | 'pet' | 'item'; itemInstanceId?: string; itemCode?: string; quantity?: number }
  | { action: 'remove-item'; tradeId: string; itemId: string }
  | { action: 'currency'; tradeId: string; fc: number; ton: number; myth: number }
  | { action: 'lock'; tradeId: string; locked: boolean; requestId?: string }
  | { action: 'confirm'; tradeId: string; requestId?: string }
  | { action: 'cancel'; tradeId: string; reason?: string };

/** Business codes the player is allowed to read, translated by the UI layer. */
export const PRIVATE_TRADE_ERROR_KEYS: Record<string, string> = {
  PLAYER_NOT_FOUND: 'privateTrade.errPlayerNotFound',
  INVALID_QUERY: 'privateTrade.errInvalidQuery',
  CANNOT_TRADE_WITH_YOURSELF: 'privateTrade.errSelf',
  PLAYER_UNAVAILABLE: 'privateTrade.errUnavailable',
  TRADE_DISABLED: 'privateTrade.errDisabled',
  ACCOUNT_TOO_NEW: 'privateTrade.errAccountNew',
  TRADE_LIMIT_REACHED: 'privateTrade.errTradeLimit',
  TRADE_ALREADY_OPEN: 'privateTrade.errAlreadyOpen',
  TRADE_NOT_FOUND: 'privateTrade.errNotFound',
  TRADE_EXPIRED: 'privateTrade.errExpired',
  TRADE_LOCKED: 'privateTrade.errLocked',
  OFFERS_NOT_LOCKED: 'privateTrade.errNotLocked',
  TRADE_NOT_READY: 'privateTrade.errNotLocked',
  TRADE_UNDER_REVIEW: 'privateTrade.errReview',
  MAX_ITEMS_REACHED: 'privateTrade.errMaxItems',
  ITEM_NOT_TRADABLE: 'privateTrade.errNotTradable',
  ITEM_LOCKED: 'privateTrade.errItemLocked',
  ITEM_ALREADY_IN_TRADE: 'privateTrade.errItemInTrade',
  ITEM_NOT_IN_TRADE: 'privateTrade.errItemNotInTrade',
  INSUFFICIENT_FC: 'privateTrade.errFc',
  INSUFFICIENT_TON: 'privateTrade.errTon',
  INSUFFICIENT_MYTH: 'privateTrade.errMyth',
  PET_ALREADY_OWNED: 'privateTrade.errPetOwned',
  OWNERSHIP_CHANGED: 'privateTrade.errOwnership',
};

export async function privateTradeRequest<T>(initData: string, input: PrivateTradeAction): Promise<T> {
  const response = await forgeFetch('private-trade', { initData, ...input });
  const payload = (await response.json().catch(() => null)) as (T & { error?: string }) | null;
  if (!response.ok || !payload) {
    const raw = String(payload?.error || '');
    if (!PRIVATE_TRADE_ERROR_KEYS[raw]) console.error('[PRIVATE TRADE]', raw);
    throw new Error(raw || 'PRIVATE_TRADE_FAILED');
  }
  return payload;
}

export const fetchPrivateTrades = (initData: string) => privateTradeRequest<PrivateTradeList>(initData, { action: 'list' });
export const searchPrivateTradePlayer = (initData: string, query: string) =>
  privateTradeRequest<{ ok: boolean; player: PrivateTradePlayer }>(initData, { action: 'search', query });
export const createPrivateTrade = (initData: string, query: string) =>
  privateTradeRequest<PrivateTradeState>(initData, { action: 'create', query, requestId: crypto.randomUUID() });
export const fetchPrivateTrade = (initData: string, tradeId: string) =>
  privateTradeRequest<PrivateTradeState>(initData, { action: 'view', tradeId });
export const addPrivateTradeItem = (
  initData: string,
  tradeId: string,
  input: { itemType: 'hero' | 'pet' | 'item'; itemInstanceId?: string; itemCode?: string; quantity?: number },
) => privateTradeRequest<PrivateTradeState>(initData, { action: 'add-item', tradeId, ...input });
export const removePrivateTradeItem = (initData: string, tradeId: string, itemId: string) =>
  privateTradeRequest<PrivateTradeState>(initData, { action: 'remove-item', tradeId, itemId });
export const setPrivateTradeCurrency = (initData: string, tradeId: string, fc: number, ton: number, myth: number) =>
  privateTradeRequest<PrivateTradeState>(initData, { action: 'currency', tradeId, fc, ton, myth });
export const lockPrivateTrade = (initData: string, tradeId: string, locked: boolean) =>
  privateTradeRequest<PrivateTradeState>(initData, { action: 'lock', tradeId, locked, requestId: crypto.randomUUID() });
export const confirmPrivateTrade = (initData: string, tradeId: string) =>
  privateTradeRequest<PrivateTradeState>(initData, { action: 'confirm', tradeId, requestId: crypto.randomUUID() });
export const cancelPrivateTrade = (initData: string, tradeId: string, reason?: string) =>
  privateTradeRequest<PrivateTradeState>(initData, { action: 'cancel', tradeId, reason });

/** True while the side may still edit its offer. */
export const privateTradeEditable = (state: PrivateTradeState) =>
  (state.status === 'negotiating' || state.status === 'offer_locked') && !state.me.locked;

export const privateTradeItemLabel = (item: PrivateTradeItem) => {
  const snap = (item.snapshot || {}) as { name?: string; label?: string; code?: string };
  return String(snap.name || snap.label || item.itemCode || snap.code || '—');
};
export const privateTradeItemImage = (item: PrivateTradeItem) => {
  const snap = (item.snapshot || {}) as { image?: string; imageUrl?: string };
  return snap.image || snap.imageUrl || null;
};
