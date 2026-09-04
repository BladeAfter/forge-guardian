/**
 * 👑 CELESTIAL SOVEREIGN PACK — pacote ultra premium de 150 TON.
 *
 * Tipagem de exibição apenas. Preço, elegibilidade, estoque de Celestiais sem dono, entrega atômica
 * e o bônus permanente de mineração TON da conta vêm do backend (`sovereign_pack_*`) e são ajustáveis
 * pelo Admin Bot sem redeploy. Herói Celestial e Pet NFT chegam com mineração "A SER REVELADA":
 * o servidor nunca inventa taxa e nunca gera mineração retroativa.
 */
export type SovereignPackItem = {
  type: string;
  template: string | null;
  instanceId: string | null;
  pendingReveal: boolean;
  revealedTon: number | null;
  revealedMyth: number | null;
  revealedAt: string | null;
};

export type SovereignPackPendingOrder = {
  orderId: string;
  paymentAddress: string;
  amountNano: string;
  amountTon: number;
  paymentComment: string;
  expiresAt: string;
};

export type SovereignPackState = {
  enabled: boolean;
  salesPaused: boolean;
  packageVersion: string;
  show: boolean;
  popupEnabled: boolean;
  popupFrequency: string;
  purchased: boolean;
  eligible: boolean;
  soldOut: boolean;
  celestialAvailable: number;
  nftPetsAvailable: number;
  priceTon: number;
  amountNano: string;
  availableTon: number;
  fcReward: number;
  legendaryChests: number;
  mythicChests: number;
  nftWeapons: number;
  mythicArmors: number;
  celestialArmors: number;
  randomItems: number;
  accountBonusPercent: number;
  ownerBonusPercent: number;
  miningRevealPending: boolean;
  delivery: Record<string, unknown> | null;
  items: SovereignPackItem[];
  pendingOrder: SovereignPackPendingOrder | null;
  offerId?: string;
  popupPriority?: number;
  purchaseLimit?: number;
  startAt?: string | null;
  endsAt?: string | null;
  stockTotal?: number | null;
  stockRemaining?: number;
  soldOutVisible?: boolean;
  windowOpen?: boolean;
  purchasedCount?: number;
  paymentPending?: boolean;
  pendingOrderId?: string | null;
  processing?: boolean;
  sold?: number;
};

export type SovereignPackPurchaseResult = {
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
  state?: SovereignPackState;
};

const SP_ERRORS: Record<string, string> = {
  SOVEREIGN_PACK_DISABLED: 'O Celestial Sovereign Pack está indisponível neste momento.',
  SOVEREIGN_PACK_SALES_PAUSED: 'As vendas do Celestial Sovereign Pack estão pausadas.',
  SOVEREIGN_PACK_ALREADY_PURCHASED: 'Você já possui o Celestial Sovereign Pack.',
  SOVEREIGN_PACK_SOLD_OUT: 'Não há mais unidades do Celestial Sovereign Pack.',
  CELESTIAL_HERO_SOLD_OUT: 'Não há mais Heróis Celestiais sem dono disponíveis.',
  SOVEREIGN_PACK_NFT_PET_UNAVAILABLE: 'Nenhuma unidade de Pet NFT disponível agora. Tente novamente em instantes.',
  SOVEREIGN_PACK_OUTSIDE_WINDOW: 'A oferta do Celestial Sovereign Pack não está aberta agora.',
  PLAYER_BANNED: 'Conta bloqueada.',
  TON_PAYMENT_ALREADY_SENT: 'O pagamento já foi enviado. Confirme na sua carteira.',
};

export const sovereignPackErrorText = (error: unknown): string => {
  const raw = error instanceof Error ? error.message : String(error ?? '');
  const key = Object.keys(SP_ERRORS).find(code => raw.includes(code));
  return key ? SP_ERRORS[key] : 'Não foi possível concluir a ação do Celestial Sovereign Pack. Tente novamente.';
};
