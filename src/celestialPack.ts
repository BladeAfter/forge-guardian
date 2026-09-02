/**
 * 💫 CELESTIAL MYSTERY PACK — pacote premium de 100 TON.
 *
 * Tipagem de exibição apenas. Preço, elegibilidade, estoque de heróis Celestiais sem dono,
 * entrega atômica dos itens e o bônus permanente de mineração TON da conta são decididos pelo
 * backend (`celestial_pack_*`) e ajustáveis pelo Admin Bot sem redeploy.
 *
 * REGRA CENTRAL: o Herói Celestial e o Pet NFT são entregues com a mineração
 * "A SER REVELADA" (`MINING TO BE REVEALED`). O servidor nunca inventa uma taxa e nunca
 * gera mineração retroativa: a acumulação começa no instante da revelação feita pelo admin.
 */
export type CelestialPackItem = {
  type: 'hero' | 'nft_pet' | 'nft_weapon' | 'armor' | 'random_item';
  template: string | null;
  instanceId: string | null;
  pendingReveal: boolean;
  revealedTon: number | null;
  revealedMyth: number | null;
  revealedAt: string | null;
};

export type CelestialPackPendingOrder = {
  orderId: string;
  paymentAddress: string;
  amountNano: string;
  amountTon: number;
  paymentComment: string;
  expiresAt: string;
};

export type CelestialPackState = {
  enabled: boolean;
  salesPaused: boolean;
  packageVersion: string;
  show: boolean;
  popupEnabled: boolean;
  popupFrequency: string;
  purchased: boolean;
  eligible: boolean;
  soldOut: boolean;
  /** Heróis Celestiais ainda sem dono (estoque real do pacote). */
  celestialAvailable: number;
  priceTon: number;
  amountNano: string;
  availableTon: number;
  fcReward: number;
  legendaryChests: number;
  nftWeapons: number;
  armors: number;
  randomItems: number;
  accountBonusPercent: number;
  ownerBonusPercent: number;
  miningRevealPending: boolean;
  delivery: Record<string, unknown> | null;
  items: CelestialPackItem[];
  pendingOrder: CelestialPackPendingOrder | null;
};

export type CelestialPackPurchaseResult = {
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
  state?: CelestialPackState;
};

const CP_ERRORS: Record<string, string> = {
  CELESTIAL_PACK_DISABLED: 'O Celestial Mystery Pack está indisponível neste momento.',
  CELESTIAL_PACK_SALES_PAUSED: 'As vendas do Celestial Mystery Pack estão pausadas.',
  CELESTIAL_PACK_ALREADY_PURCHASED: 'Você já possui o Celestial Mystery Pack.',
  CELESTIAL_PACK_SOLD_OUT: 'Não há mais Heróis Celestiais sem dono disponíveis.',
  CELESTIAL_HERO_SOLD_OUT: 'Não há mais Heróis Celestiais sem dono disponíveis.',
  CELESTIAL_PACK_NFT_PET_UNAVAILABLE: 'Nenhuma unidade de Pet NFT disponível agora. Tente novamente em instantes.',
  PLAYER_BANNED: 'Conta bloqueada.',
  TON_PAYMENT_ALREADY_SENT: 'O pagamento já foi enviado. Confirme na sua carteira.',
};

export const celestialPackErrorText = (error: unknown): string => {
  const raw = error instanceof Error ? error.message : String(error ?? '');
  const key = Object.keys(CP_ERRORS).find(code => raw.includes(code));
  return key ? CP_ERRORS[key] : 'Não foi possível concluir a ação do Celestial Mystery Pack. Tente novamente.';
};
