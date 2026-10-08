/**
 * ⚔️ VETERAN VAULT (V2) — premium pack de 100 TON.
 *
 * Tipagem apenas de exibição. Preço, estoque (fundo de MYTH), entrega dos itens, taxas de mineração
 * em MYTH e o bônus de +10% para quem compra são decididos pelo backend (`veteran_v2_*`) e ajustáveis
 * pelo Admin Bot sem redeploy. Valores exibidos são REFERÊNCIA, nunca promessa de lucro.
 */
export type VeteranV2PendingOrder = {
  orderId: string;
  paymentAddress: string;
  amountNano: string;
  amountTon: number;
  paymentComment: string;
  expiresAt: string;
};

export type VeteranV2Item = { type: 'hero' | 'pet' | 'egg' | 'dragon' | 'weapon'; template: string; instanceId: string | null };

export type VeteranV2State = {
  enabled: boolean;
  salesPaused: boolean;
  packageVersion: string;
  show: boolean;
  popupEnabled: boolean;
  popupFrequency: 'ONCE_PER_SESSION' | 'ONCE_PER_DAY' | 'UNTIL_PURCHASED' | 'DISABLED';
  purchased: boolean;
  eligible: boolean;
  soldOut: boolean;
  priceTon: number;
  amountNano: string;
  availableTon: number;
  boostPercent: number;
  ownerBoostPercent: number;
  mythReward: number;
  legendaryChests: number;
  fragments: number;
  weaponsPerPurchase: number;
  heroDailyMyth: number;
  petDailyMyth: number;
  dragonDailyMyth: number;
  mythReferenceRate: number;
  delivery: Record<string, unknown> | null;
  items: VeteranV2Item[];
  pendingOrder: VeteranV2PendingOrder | null;
};

export type VeteranV2PurchaseResult = {
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
  state?: VeteranV2State;
};

const V2_ERRORS: Record<string, string> = {
  VETERAN_VAULT_DISABLED: 'O Veteran Vault está indisponível neste momento.',
  VETERAN_VAULT_SALES_PAUSED: 'As vendas do Veteran Vault estão pausadas.',
  VETERAN_VAULT_ALREADY_PURCHASED: 'Você já possui o Veteran Vault.',
  VETERAN_VAULT_SOLD_OUT: 'Reservas esgotadas: aguarde o novo financiamento do fundo Veteran.',
  PLAYER_BANNED: 'Conta bloqueada.',
  TON_PAYMENT_ALREADY_SENT: 'O pagamento já foi enviado. Confirme na sua carteira.',
};

export const veteranV2ErrorText = (error: unknown): string => {
  const raw = error instanceof Error ? error.message : String(error ?? '');
  const key = Object.keys(V2_ERRORS).find(code => raw.includes(code));
  return key ? V2_ERRORS[key] : 'Não foi possível concluir a ação do Veteran Vault. Tente novamente.';
};

/** Mineração diária total em MYTH das recompensas do pacote (referência). */
export const veteranV2DailyMyth = (state: VeteranV2State | undefined): number => {
  if (!state) return 0;
  const boost = 1 + Math.max(0, Number(state.boostPercent || 0)) / 100;
  return Math.round((Number(state.heroDailyMyth || 0) + Number(state.petDailyMyth || 0) + Number(state.dragonDailyMyth || 0)) * boost);
};
