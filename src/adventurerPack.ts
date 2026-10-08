/**
 * 🏆 LEGENDARY ADVENTURER PACK — pacote premium de 30 TON.
 *
 * Tipagem de exibição apenas. Preço, elegibilidade, estoque de heróis LEGENDARY sem dono, entrega
 * atômica dos itens, o passe oficial de 5 TON incluído (tier `adventurer`) e o bônus de +0,5% na
 * mineração de TON da conta são decididos pelo backend (`adventurer_pack_*`) e ajustáveis pelo
 * Admin Bot sem redeploy.
 *
 * REGRAS CENTRAIS:
 * - Teto de raridade LEGENDARY: este pack NUNCA garante nada Celestial ou Mythic.
 * - O Herói Legendary chega com a mineração "A SER REVELADA" (`MINING TO BE REVEALED`). O servidor
 *   nunca inventa taxa e nunca gera mineração retroativa: ela começa a contar na revelação.
 * - O preço de 30 TON já inclui o passe: nenhum custo extra é cobrado do jogador.
 */
export type AdventurerPackItem = {
  type: string;
  template: string | null;
  rarity: string | null;
  instanceId: string | null;
  pendingReveal: boolean;
  revealedTon: number | null;
  revealedMyth: number | null;
  revealedAt: string | null;
};

export type AdventurerPackPendingOrder = {
  orderId: string;
  paymentAddress: string;
  amountNano: string;
  amountTon: number;
  paymentComment: string;
  expiresAt: string;
};

export type AdventurerPackState = {
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
  /** Heróis LEGENDARY ainda sem dono (estoque real do pacote). */
  legendaryAvailable: number;
  priceTon: number;
  amountNano: string;
  availableTon: number;
  fcReward: number;
  legendaryChests: number;
  nftWeapons: number;
  legendaryArmors: number;
  universalFragments: number;
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
  items: AdventurerPackItem[];
  pendingOrder: AdventurerPackPendingOrder | null;
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

export type AdventurerPackPurchaseResult = {
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
  state?: AdventurerPackState;
};

const AP_ERRORS: Record<string, string> = {
  ADVENTURER_PACK_DISABLED: 'O Legendary Adventurer Pack está indisponível agora.',
  ADVENTURER_PACK_SALES_PAUSED: 'As vendas do Legendary Adventurer Pack estão pausadas.',
  ADVENTURER_PACK_OUTSIDE_WINDOW: 'A janela do Legendary Adventurer Pack está fechada.',
  ADVENTURER_PACK_ALREADY_PURCHASED: 'Você já possui o Legendary Adventurer Pack.',
  ADVENTURER_PACK_SOLD_OUT: 'O estoque do Legendary Adventurer Pack esgotou.',
  ADVENTURER_LEGENDARY_HERO_SOLD_OUT: 'Não há mais Heróis Lendários disponíveis para este pacote.',
  ADVENTURER_TIER_VIOLATION: 'Recompensa acima do teto LEGENDARY foi bloqueada. Nada foi cobrado.',
  INVALID_PAYMENT_AMOUNT: 'Valor pago abaixo do preço do pacote.',
  TX_ALREADY_USED: 'Esta transação já foi utilizada.',
  PLAYER_BANNED: 'Conta suspensa.',
};

export const adventurerPackErrorText = (error: unknown): string => {
  const raw = error instanceof Error ? error.message : String(error ?? '');
  const key = Object.keys(AP_ERRORS).find(code => raw.includes(code));
  return key ? AP_ERRORS[key] : 'Não foi possível concluir a ação do Legendary Adventurer Pack. Tente novamente.';
};
