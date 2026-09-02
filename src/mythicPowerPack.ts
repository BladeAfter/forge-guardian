/**
 * ⚡ 20 TON MYTHIC PACK (MYTHIC POWER PACK) — tipagem de exibição apenas.
 *
 * Preço, recompensas, bônus de primeira compra (+10.000 MYTH e 1 Celestial Key, uma única vez por
 * conta), pagamento (saldo interno integral OU TonConnect integral, nunca combinado), validação
 * on-chain, idempotência e entrega atômica vivem 100% no backend (`mythic_power_pack_*`) e são
 * ajustáveis pelo Admin Bot sem redeploy. Compras ilimitadas: o bônus só vale na primeira.
 */
export type MythicPowerPackPendingOrder = {
  orderId: string;
  paymentAddress: string;
  amountNano: string;
  amountTon: number;
  paymentComment: string;
  expiresAt: string;
};

export type MythicPowerPackHistoryEntry = {
  purchaseId: string;
  createdAt: string;
  deliveredAt: string | null;
  priceTon: number;
  method: string;
  status: string;
  firstPurchaseBonus: boolean;
  txHash: string | null;
  delivery: Record<string, unknown> | null;
};

export type MythicPowerPackState = {
  offerId: string;
  enabled: boolean;
  salesPaused: boolean;
  packageVersion: string;
  show: boolean;
  popupEnabled: boolean;
  popupFrequency: string;
  popupPriority: number;
  windowOpen: boolean;
  priceTon: number;
  amountNano: string;
  availableTon: number;
  mythReward: number;
  firstBonusMyth: number;
  firstBonusKey: string;
  firstPurchaseAvailable: boolean;
  purchasedCount: number;
  mythicEggs: number;
  voidChests: number;
  equipmentChests: number;
  universalFragments: number;
  pvpTickets: number;
  eternityKeys: number;
  voidKeys: number;
  petFood: number;
  heroXp: number;
  paymentPending: boolean;
  pendingOrderId: string | null;
  processing: boolean;
  delivery: Record<string, unknown> | null;
  pendingOrder: MythicPowerPackPendingOrder | null;
  history: MythicPowerPackHistoryEntry[];
};

export type MythicPowerPackPurchaseResult = {
  status: 'completed' | 'payment_required';
  method?: 'internal_ton' | 'ton_connect';
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
  state?: MythicPowerPackState;
};

const MPP_ERRORS: Record<string, string> = {
  MYTHIC_POWER_PACK_DISABLED: 'O 20 TON MYTHIC PACK está indisponível neste momento.',
  MYTHIC_POWER_PACK_SALES_PAUSED: 'As vendas do 20 TON MYTHIC PACK estão pausadas.',
  MYTHIC_POWER_PACK_OUTSIDE_WINDOW: 'A oferta do 20 TON MYTHIC PACK não está aberta agora.',
  MYTHIC_POWER_PACK_ORDER_NOT_FOUND: 'Pedido não encontrado.',
  MYTHIC_POWER_PACK_NOT_PAID: 'O pagamento ainda não foi confirmado.',
  INVALID_PAYMENT_AMOUNT: 'Valor pago abaixo do preço do pacote.',
  TX_ALREADY_USED: 'Esta transação já foi utilizada.',
  PLAYER_BANNED: 'Conta bloqueada.',
  TON_PAYMENT_ALREADY_SENT: 'O pagamento já foi enviado. Confirme na sua carteira.',
};

export const mythicPowerPackErrorText = (error: unknown): string => {
  const raw = error instanceof Error ? error.message : String(error ?? '');
  const key = Object.keys(MPP_ERRORS).find(code => raw.includes(code));
  return key ? MPP_ERRORS[key] : 'Não foi possível concluir a ação do 20 TON MYTHIC PACK. Tente novamente.';
};
