import { formatTon } from './economy';
import type { PetDashboard, PetHatchResult } from './pets';
import { createEggTonOrder, verifyEggPurchases } from './services';
import { encodeCommentPayload } from './tonComment';
import type { TonPaymentIntent } from './wallet';

/** Where the purchase started. The pipeline below is identical for both screens. */
export type EggPurchaseSource = 'pet_shop' | 'wallet';

export type EggPurchaseOutcome = {
  status: 'completed' | 'already_processed' | string;
  orderId?: string;
  eggId?: string;
  eggName?: string;
  priceTon?: number;
  result?: PetHatchResult;
  dashboard?: PetDashboard;
};

export type EggPurchaseVerification = {
  checked: number;
  /** Orders delivered in this round (payment confirmed + creature saved). */
  completed: string[];
  /** Orders whose creature had already been delivered before — never delivered twice. */
  alreadyDelivered: string[];
  /** Orders still genuinely waiting for the TON transfer to appear on-chain. */
  pending: string[];
  results: EggPurchaseOutcome[];
};

/**
 * The ONE egg price formatter. An egg is priced in FC *or* in TON — never both, never twice.
 * When neither price exists the egg is not for sale and we show its availability label instead.
 */
export function formatEggPrice(egg: { priceFc?: number | null; priceTon?: number | null; availabilityLabel?: string | null }): string {
  if (egg.priceFc) return `${new Intl.NumberFormat('pt-BR').format(egg.priceFc)} FC`;
  if (egg.priceTon) return `${formatTon(egg.priceTon)} TON`;
  return egg.availabilityLabel || 'Evento exclusivo';
}

type SendTon = (tx: { validUntil: number; messages: Array<{ address: string; amount: string; payload?: string }> }) => Promise<unknown>;

/**
 * The ONE premium egg purchase pipeline (pet shop and wallet both use it):
 * create order → pay with TonConnect (carrying the order comment) → backend confirms on-chain → egg hatches.
 * A premium egg purchase is never a deposit: no FC is credited.
 */
export async function purchasePremiumEgg(input: {
  telegramInitData: string | null;
  eggId: string;
  source: EggPurchaseSource;
  sendTransaction: SendTon;
}): Promise<TonPaymentIntent> {
  if (!input.telegramInitData) throw new Error('Abra o jogo pelo Telegram para comprar.');
  const order = await createEggTonOrder(input.telegramInitData, input.eggId, `${input.source}:${crypto.randomUUID()}`);
  await input.sendTransaction({
    validUntil: Math.floor(Date.now() / 1000) + 300,
    // The comment ties this exact payment to this exact order (no value-only guessing).
    messages: [{ address: order.paymentAddress, amount: order.amountNano, payload: encodeCommentPayload(order.paymentComment) }],
  });
  return order;
}

/** Checks the blockchain and finishes every pending/paid egg purchase of this player, exactly once. */
export async function reconcilePendingEggPurchases(telegramInitData: string | null): Promise<EggPurchaseVerification> {
  if (!telegramInitData) return { checked: 0, completed: [], alreadyDelivered: [], pending: [], results: [] };
  const payload = await verifyEggPurchases(telegramInitData) as Record<string, unknown> & { checked?: number };
  return {
    checked: Number(payload.checked ?? 0),
    completed: Array.isArray(payload.completed) ? payload.completed : [],
    alreadyDelivered: Array.isArray((payload as any).alreadyDelivered) ? (payload as any).alreadyDelivered : [],
    pending: Array.isArray(payload.pending) ? payload.pending : [],
    results: (Array.isArray(payload.results) ? payload.results : []) as unknown as EggPurchaseOutcome[],
  };
}

/** First purchase that produced a pet in this reconciliation round. */
export const hatchedPurchase = (verification: EggPurchaseVerification): EggPurchaseOutcome | undefined =>
  verification.results.find((outcome) => Boolean(outcome.result));

/** Human status for the wallet history (never a permanent "PENDING"). */
export const eggPurchaseStatusLabel = (status: string): string =>
  ({
    pending: 'PENDING PAYMENT',
    // Payment found on-chain, creature not delivered yet: COMPLETED is reserved for delivered purchases.
    paid: 'PAYMENT CONFIRMED',
    confirmed: 'PAYMENT CONFIRMED',
    delivered: 'COMPLETED',
    expired: 'FAILED',
    cancelled: 'FAILED',
  } as Record<string, string>)[status] ?? status.toUpperCase();

/** The exact message for the "já paguei" recovery button, derived from the reconciled state. */
export function eggRecoveryMessage(verification: EggPurchaseVerification): { tone: 'success' | 'info'; text: string } {
  if (verification.completed.length) return { tone: 'success', text: 'Pagamento confirmado! Abrindo seu ovo...' };
  if (verification.alreadyDelivered.length) return { tone: 'info', text: 'Compra já concluída.' };
  if (verification.pending.length) return { tone: 'info', text: 'Pagamento ainda não localizado na blockchain. Tente novamente em instantes.' };
  return { tone: 'info', text: 'Nenhuma compra de ovo pendente.' };
}

/**
 * Polls the reconciler right after a payment: the wallet takes a few seconds to land on-chain.
 * Returns as soon as a pet is delivered, otherwise the last verification state.
 */
export async function waitForEggPurchase(
  telegramInitData: string | null,
  options: { attempts?: number; delayMs?: number; onAttempt?: (attempt: number) => void } = {},
): Promise<EggPurchaseVerification> {
  const attempts = options.attempts ?? 8;
  const delayMs = options.delayMs ?? 7000;
  let last: EggPurchaseVerification = { checked: 0, completed: [], alreadyDelivered: [], pending: [], results: [] };
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    options.onAttempt?.(attempt);
    await new Promise((resolve) => window.setTimeout(resolve, attempt === 1 ? 6000 : delayMs));
    try {
      last = await reconcilePendingEggPurchases(telegramInitData);
      if (hatchedPurchase(last)) return last;
    } catch (error) {
      console.error('[FORGE EGG PURCHASE]', error);
    }
  }
  return last;
}
