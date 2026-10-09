/**
 * ⚔️ Mythic Seas VETERAN VAULT — premium pack for veteran players with a 45-day reward cycle.
 *
 * Display-only typing. Eligibility, price, cycle day, matured rewards, TON/MYTH credits, pool coverage
 * and completion are decided by the backend (`veteran_vault_*` RPCs) and tuned by the Admin Bot without
 * a redeploy. Reward values shown in the UI are REFERENCE values, never a promise of profit.
 */
export type VeteranVaultPendingOrder = {
  orderId: string;
  paymentAddress: string;
  amountNano: string;
  amountTon: number;
  paymentComment: string;
  expiresAt: string;
};

export type VeteranVaultClaimable = {
  day: number;
  ton: number;
  myth: number;
  finalReady: boolean;
  hasRewards: boolean;
  nextDay: number | null;
  nextRewardAt: string | null;
};

export type VeteranVaultCycle = {
  purchaseId: string;
  vaultVersion: string;
  cycleStartAt: string;
  cycleEndAt: string;
  cycleDays: number;
  day: number;
  completed: boolean;
  tonEarned: number;
  mythEarned: number;
  tonBudget: number;
  referenceValueTon: number;
  claimable: VeteranVaultClaimable | null;
};

export type VeteranVaultState = {
  enabled: boolean;
  salesPaused: boolean;
  /** Server-side visibility: veterans inside the offer, or anyone with an active cycle. */
  show: boolean;
  testMode: boolean;
  eligible: boolean;
  veteran: boolean;
  poolFunded: boolean;
  soldOut: boolean;
  accountAgeDays: number;
  minAccountAgeDays: number;
  vaultVersion: string;
  priceTon: number;
  amountNano: string;
  availableTon: number;
  cycleDays: number;
  initialMyth: number;
  fragments: number;
  passTier: string;
  tonRewardBudget: number;
  mythRewardBudget: number;
  targetReferenceTon: number;
  rewardSchedule: { ton?: Record<string, number>; mythBonus?: Record<string, number> } | null;
  finalReward: Record<string, unknown> | null;
  purchased: boolean;
  vault: VeteranVaultCycle | null;
  pendingOrder: VeteranVaultPendingOrder | null;
};

export type VeteranVaultPurchaseResult = {
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
  state?: VeteranVaultState;
};

export type VeteranVaultClaimResult = {
  ok: true;
  nothingToClaim?: boolean;
  tonClaimed?: number;
  mythClaimed?: number;
  finalReward?: Record<string, unknown> | null;
  day?: number;
  state?: VeteranVaultState;
};

/** Countdown to the next matured reward (display only). */
export function veteranCountdown(nextRewardAt: string | null | undefined, now = Date.now()): string {
  if (!nextRewardAt) return '--';
  const remaining = new Date(nextRewardAt).getTime() - now;
  if (!Number.isFinite(remaining) || remaining <= 0) return '00h 00m';
  const total = Math.floor(remaining / 1000);
  const pad = (value: number) => String(value).padStart(2, '0');
  const days = Math.floor(total / 86400);
  const hours = Math.floor((total % 86400) / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  return days > 0 ? `${days}d ${pad(hours)}h ${pad(minutes)}m` : `${pad(hours)}h ${pad(minutes)}m`;
}

const VETERAN_ERRORS: Record<string, string> = {
  VETERAN_VAULT_DISABLED: 'O Veteran Vault está indisponível neste momento.',
  VETERAN_VAULT_SALES_PAUSED: 'As vendas do Veteran Vault estão pausadas.',
  VETERAN_VAULT_NOT_ELIGIBLE: 'O Veteran Vault é exclusivo para jogadores antigos do Mythic Seas.',
  VETERAN_VAULT_ALREADY_PURCHASED: 'Você já possui o Veteran Vault desta temporada.',
  VETERAN_VAULT_SOLD_OUT: 'Reservas esgotadas: aguarde o novo financiamento do Veteran Reward Pool.',
  VETERAN_VAULT_NOT_ACTIVE: 'Você ainda não possui um ciclo Veteran ativo.',
  PLAYER_BANNED: 'Conta bloqueada.',
  TON_PAYMENT_ALREADY_SENT: 'O pagamento já foi enviado para a sua carteira. Confirme na carteira.',
};

export const veteranErrorText = (error: unknown): string => {
  const raw = error instanceof Error ? error.message : String(error ?? '');
  const key = Object.keys(VETERAN_ERRORS).find(code => raw.includes(code));
  return key ? VETERAN_ERRORS[key] : 'Não foi possível concluir a ação do Veteran Vault. Tente novamente.';
};
