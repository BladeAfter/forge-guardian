/**
 * 👑 MYTHREON FOUNDER PACK — 25 TON, new players only.
 *
 * Everything here is display-only typing: price, eligibility window, reward contents, payment method
 * and delivery are owned by the backend (`founder_pack_*` RPCs) and can be re-tuned by the Admin Bot
 * without a redeploy. The client never computes eligibility or credits a single reward.
 */
export type FounderPackPendingOrder = {
  orderId: string;
  paymentAddress: string;
  amountNano: string;
  amountTon: number;
  paymentComment: string;
  expiresAt: string;
};

export type FounderPackState = {
  enabled: boolean;
  /** Server decides visibility: the card only exists for eligible new accounts (or admin test mode). */
  show: boolean;
  testMode: boolean;
  eligible: boolean;
  purchased: boolean;
  priceTon: number;
  amountNano: string;
  eligibilityDays: number;
  eligibleUntil: string | null;
  accountCreatedAt: string;
  availableTon: number;
  mythAmount: number;
  fragments: number;
  passTier: string;
  /** Popup diário controlado pelo servidor (Admin Bot). */
  popupEnabled: boolean;
  popupFrequency: string;
  /** Quando falso, a oferta vale para todos os jogadores dentro da janela. */
  requireNewAccount: boolean;
  startAt: string | null;
  endsAt: string | null;
  /** MYTH MINING dos itens Founder (sem TON mining, sem bônus Veteran). */
  heroDailyMyth: number;
  petDailyMyth: number;
  legendaryChests: number;
  weaponCode: string | null;
  pendingOrder: FounderPackPendingOrder | null;
};

export type FounderPackPurchaseResult = {
  status: 'completed' | 'payment_required';
  method: 'internal_ton' | 'ton_connect';
  purchaseId?: string;
  orderId?: string;
  priceTon?: number;
  amountTon?: number;
  amountNano?: string;
  paymentAddress?: string;
  paymentComment?: string;
  expiresAt?: string;
  duplicate?: boolean;
  delivery?: Record<string, unknown> | null;
  state?: FounderPackState;
};

export type FounderEntitlement = { code: string; label: string; equipped: boolean; grantedAt: string };

/** Remaining eligibility window as a compact `Xd HH:MM:SS` countdown (display only). */
export function founderCountdown(eligibleUntil: string | null | undefined, now = Date.now()): string {
  if (!eligibleUntil) return '--';
  const remaining = new Date(eligibleUntil).getTime() - now;
  if (!Number.isFinite(remaining) || remaining <= 0) return '00:00:00';
  const total = Math.floor(remaining / 1000);
  const days = Math.floor(total / 86400);
  const pad = (value: number) => String(value).padStart(2, '0');
  const clock = `${pad(Math.floor((total % 86400) / 3600))}:${pad(Math.floor((total % 3600) / 60))}:${pad(total % 60)}`;
  return days > 0 ? `${days}d ${clock}` : clock;
}

const FOUNDER_ERRORS: Record<string, string> = {
  FOUNDER_PACK_DISABLED: 'O Founder Pack está indisponível neste momento.',
  FOUNDER_PACK_NOT_ELIGIBLE: 'O Founder Pack é exclusivo para contas novas dentro da janela de lançamento.',
  FOUNDER_PACK_ALREADY_PURCHASED: 'Você já garantiu o Founder Pack nesta conta.',
  FOUNDER_FRAME_NOT_OWNED: 'Você ainda não possui a moldura de Fundador.',
  PLAYER_BANNED: 'Conta bloqueada.',
  TON_PAYMENT_ALREADY_SENT: 'O pagamento já foi enviado para a sua carteira. Confirme na carteira.',
};

export const founderErrorText = (error: unknown): string => {
  const raw = error instanceof Error ? error.message : String(error ?? '');
  const key = Object.keys(FOUNDER_ERRORS).find(code => raw.includes(code));
  return key ? FOUNDER_ERRORS[key] : 'Não foi possível concluir a compra do Founder Pack. Tente novamente.';
};
