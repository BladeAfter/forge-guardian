/**
 * ⚔️ MYTHIC VANGUARD PACK — pacote premium de 50 TON.
 *
 * Tipagem de exibição apenas. Preço, elegibilidade, estoque de heróis MYTHIC sem dono, entrega
 * atômica dos itens, o passe oficial de 20 TON incluído e o bônus de +1% na mineração de TON da
 * conta são decididos pelo backend (`vanguard_pack_*`) e ajustáveis pelo Admin Bot sem redeploy.
 *
 * REGRAS CENTRAIS:
 * - Teto de raridade MYTHIC: este pack NUNCA entrega nada Celestial.
 * - O Herói Mythic e o Pet NFT chegam com a mineração "A SER REVELADA" (`MINING TO BE REVEALED`).
 *   O servidor nunca inventa taxa e nunca gera mineração retroativa.
 */
export type VanguardPackItem = {
  type: string;
  template: string | null;
  rarity: string | null;
  instanceId: string | null;
  pendingReveal: boolean;
  revealedTon: number | null;
  revealedMyth: number | null;
  revealedAt: string | null;
};

export type VanguardPackPendingOrder = {
  orderId: string;
  paymentAddress: string;
  amountNano: string;
  amountTon: number;
  paymentComment: string;
  expiresAt: string;
};

export type VanguardPackState = {
  enabled: boolean;
  salesPaused: boolean;
  packageVersion: string;
  show: boolean;
  popupEnabled: boolean;
  popupFrequency: string;
  purchased: boolean;
  eligible: boolean;
  soldOut: boolean;
  heroRarity: string;
  /** Heróis MYTHIC ainda sem dono (estoque real do pacote). */
  mythicAvailable: number;
  nftPetsAvailable: number;
  priceTon: number;
  amountNano: string;
  availableTon: number;
  fcReward: number;
  legendaryChests: number;
  mythicChests: number;
  nftWeapons: number;
  legendaryArmors: number;
  randomItems: number;
  passTier: string;
  passIncluded: boolean;
  maxRewardRarity: string;
  accountBonusPercent: number;
  ownerBonusPercent: number;
  bonusPolicy: string;
  bonusSources: { source: string; percent: number }[];
  miningRevealPending: boolean;
  delivery: Record<string, unknown> | null;
  items: VanguardPackItem[];
  pendingOrder: VanguardPackPendingOrder | null;
  /** Metadados da oferta (janela, estoque, limite e popup) — sempre calculados no servidor. */
  offerId?: string;
  popupPriority?: number;
  purchaseLimit?: number;
  stockTotal?: number | null;
  stockRemaining?: number;
  soldOutVisible?: boolean;
  windowOpen?: boolean;
  paymentPending?: boolean;
  processing?: boolean;
  sold?: number;
};

export type VanguardPackPurchaseResult = {
  status: 'completed' | 'payment_required' | 'already_processed';
  method?: string;
  purchaseId?: string;
  orderId?: string;
  paymentAddress?: string;
  amountNano?: string;
  amountTon?: number;
  paymentComment?: string;
  expiresAt?: string;
  priceTon?: number;
  delivery?: Record<string, unknown> | null;
  state?: VanguardPackState;
};

const VP_ERRORS: Record<string, string> = {
  VANGUARD_PACK_DISABLED: 'O Mythic Vanguard Pack está indisponível agora.',
  VANGUARD_PACK_SALES_PAUSED: 'As vendas do Mythic Vanguard Pack estão pausadas.',
  VANGUARD_PACK_OUTSIDE_WINDOW: 'A janela do Mythic Vanguard Pack está fechada.',
  VANGUARD_PACK_ALREADY_PURCHASED: 'Você já possui o Mythic Vanguard Pack.',
  VANGUARD_PACK_SOLD_OUT: 'O estoque do Mythic Vanguard Pack esgotou.',
  VANGUARD_MYTHIC_HERO_SOLD_OUT: 'Não há mais Heróis Mythic disponíveis para este pacote.',
  VANGUARD_NFT_PET_UNAVAILABLE: 'Não há mais Pets NFT disponíveis para este pacote.',
  VANGUARD_CELESTIAL_FORBIDDEN: 'Recompensa inválida detectada e bloqueada. Nada foi cobrado.',
  INVALID_PAYMENT_AMOUNT: 'Valor pago abaixo do preço do pacote.',
  TX_ALREADY_USED: 'Esta transação já foi utilizada.',
  PLAYER_BANNED: 'Conta suspensa.',
};

export const vanguardPackErrorText = (error: unknown): string => {
  const raw = error instanceof Error ? error.message : String(error ?? '');
  const key = Object.keys(VP_ERRORS).find(code => raw.includes(code));
  return key ? VP_ERRORS[key] : 'Não foi possível concluir a ação do Mythic Vanguard Pack. Tente novamente.';
};
