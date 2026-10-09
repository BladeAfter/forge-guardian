import { createSeasonPassOrder, verifyPassPurchases } from './services';
import { sendTonPayment, type SendTonTransaction } from './tonPayment';

import type { PassTier, SeasonPassDashboard } from './seasonPass';

export type PassPurchaseOutcome = { status: 'completed' | 'already_processed' | string; orderId?: string; tier?: PassTier; priceTon?: number };
export type PassPurchaseVerification = { checked: number; completed: string[]; pending: string[]; results: PassPurchaseOutcome[]; dashboard?: SeasonPassDashboard };

type SendTon = SendTonTransaction;

/**
 * The ONE battle pass purchase pipeline: create order → pay with TonConnect (carrying the order
 * comment so the backend can tie the payment to THIS player) → server confirms on-chain → pass activated.
 * A pass purchase is never a deposit: no TON is converted into BERRIES.
 */
export async function purchaseBattlePass(input: {
  telegramInitData: string | null;
  tier: PassTier;
  sendTransaction: SendTon;
}): Promise<{ orderId: string; tier: PassTier; priceTon: number }> {
  if (!input.telegramInitData) throw new Error('Abra o jogo pelo Telegram para comprar o Passe.');
  const order = await createSeasonPassOrder(input.telegramInitData, input.tier);
  // The wallet receives EXACTLY the amount the backend stored in the intent, once.
  await sendTonPayment(order, (tx) => input.sendTransaction(tx));
  return { orderId: order.id, tier: input.tier, priceTon: order.amountTon };

}

/** Asks the server to reconcile every pending pass payment of this player (idempotent). */
export async function reconcilePendingPassPurchases(telegramInitData: string | null): Promise<PassPurchaseVerification> {
  if (!telegramInitData) return { checked: 0, completed: [], pending: [], results: [] };
  const payload = await verifyPassPurchases(telegramInitData);
  return {
    checked: Number(payload?.checked ?? 0),
    completed: Array.isArray(payload?.completed) ? payload.completed : [],
    pending: Array.isArray(payload?.pending) ? payload.pending : [],
    results: (Array.isArray(payload?.results) ? payload.results : []) as PassPurchaseOutcome[],
    dashboard: payload?.dashboard as SeasonPassDashboard | undefined,
  };
}

/** True when the reconciliation round activated a pass for the first time. */
export const activatedPass = (verification: PassPurchaseVerification): PassPurchaseOutcome | undefined =>
  verification.results.find((outcome) => outcome.status === 'completed');

export const passTierLabel = (tier?: string): string => (tier === 'legendary' ? 'PASSE LENDÁRIO' : 'PASSE AVENTUREIRO');

/** Polls the reconciler right after a payment: the wallet needs a few seconds to land on-chain. */
export async function waitForPassActivation(
  telegramInitData: string | null,
  options: { attempts?: number; delayMs?: number } = {},
): Promise<PassPurchaseVerification> {
  const attempts = options.attempts ?? 8;
  const delayMs = options.delayMs ?? 7000;
  let last: PassPurchaseVerification = { checked: 0, completed: [], pending: [], results: [] };
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    await new Promise((resolve) => window.setTimeout(resolve, attempt === 1 ? 6000 : delayMs));
    try {
      last = await reconcilePendingPassPurchases(telegramInitData);
      if (activatedPass(last)) return last;
    } catch (error) {
      console.error('[Mythic Seas PASS PURCHASE]', error);
    }
  }
  return last;
}
