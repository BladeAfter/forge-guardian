import { encodeCommentPayload } from './tonComment';

/** Exactly the shape TonConnect expects. Amounts are ALWAYS integer nanoton strings. */
export type TonTransactionRequest = {
  validUntil: number;
  messages: Array<{ address: string; amount: string; payload?: string }>;
};
export type SendTonTransaction = (tx: TonTransactionRequest) => Promise<unknown>;

/** A payment intent created by the backend. The amount here is the ONLY source of truth. */
export type TonPaymentOrder = {
  paymentAddress: string;
  paymentComment: string;
  /** Integer nanoton string produced by the server (never recalculated on the client). */
  amountNano: string;
};

/** Payments already handed to the wallet in this session, keyed by the intent comment. */
const sentPayments = new Set<string>();
/** Payments currently open in the wallet, so a second tap can never fire a second transfer. */
const inFlightPayments = new Set<string>();

const NANO_PATTERN = /^[0-9]+$/;

/** Financial values never travel as floats: the nanoton string is validated as a positive integer. */
export function assertNanoAmount(amountNano: string): bigint {
  const raw = String(amountNano ?? '').trim();
  if (!NANO_PATTERN.test(raw)) throw new Error('TON_PAYMENT_AMOUNT_INVALID');
  const value = BigInt(raw);
  if (value <= 0n) throw new Error('TON_PAYMENT_AMOUNT_INVALID');
  return value;
}

/**
 * The ONE gateway between the game and the player's wallet.
 *
 * Guarantees, for every TON purchase in Mythic Seas (pass, NFTs, eggs, equipment, deposits):
 * - the transfer amount is the exact `amountNano` the backend stored in the payment intent;
 * - the payload carries exactly ONE outgoing message, and its total is compared with the expected
 *   amount before the wallet is opened (mismatch => TON_PAYMENT_AMOUNT_MISMATCH, wallet stays closed);
 * - the same intent can never be sent twice (double tap, retry, re-render): a 5 TON product can
 *   never turn into a 10 TON transfer.
 */
export async function sendTonPayment(order: TonPaymentOrder, sendTransaction: SendTonTransaction): Promise<void> {
  const comment = String(order.paymentComment ?? '').trim();
  const address = String(order.paymentAddress ?? '').trim();
  if (!comment || !address) throw new Error('TON_PAYMENT_INTENT_INVALID');

  const expected = assertNanoAmount(order.amountNano);
  if (inFlightPayments.has(comment) || sentPayments.has(comment)) throw new Error('TON_PAYMENT_ALREADY_SENT');
  inFlightPayments.add(comment);

  try {
    const messages = [{ address, amount: expected.toString(), payload: encodeCommentPayload(comment) }];
    const total = messages.reduce((sum, message) => sum + BigInt(message.amount), 0n);
    if (messages.length !== 1 || total !== expected) {
      console.error('[TON_PAYMENT_AMOUNT_MISMATCH]', { comment, expected: expected.toString(), total: total.toString(), messages: messages.length });
      throw new Error('TON_PAYMENT_AMOUNT_MISMATCH');
    }
    await sendTransaction({ validUntil: Math.floor(Date.now() / 1000) + 300, messages });
    sentPayments.add(comment);
  } finally {
    inFlightPayments.delete(comment);
  }
}

/** Human amount for confirmation screens — display only, never used to build the payload. */
export const nanoToTon = (amountNano: string): number => Number(assertNanoAmount(amountNano)) / 1e9;
