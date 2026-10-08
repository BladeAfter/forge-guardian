/**
 * MYTHREON AUCTION — negociação 100% em TON interno.
 * Não existe BERRIES, não existe seleção de moeda e nenhum lance abre TonConnect:
 * o jogador precisa ter TON no saldo interno (Wallet → DEPOSIT TON BALANCE) antes de dar lance.
 * Todas as regras (reserva, liberação ao ser superado, taxa, anti-snipe, encerramento)
 * são calculadas e aplicadas pelo backend — o cliente apenas exibe.
 */
export type AuctionItemType = 'hero' | 'pet' | 'equipment';
export type AuctionSort = 'ending' | 'newest' | 'price_low' | 'price_high';

export type AuctionSettings = {
  enabled: boolean;
  feePercent: number;
  minStartingBidTon: number;
  minIncrementTon: number;
  antiSnipeEnabled: boolean;
  antiSnipeWindowMinutes: number;
  antiSnipeExtensionMinutes: number;
  durations: number[];
  currency: 'TON';
};

export type AuctionCard = {
  id: string;
  itemType: AuctionItemType;
  name: string;
  rarity: string;
  level: number;
  image: string | null;
  serial: string | number | null;
  stars: number;
  atk: number;
  hp: number;
  /** Só é exibido no card quando > 0 (DAILY MINING / DAILY YIELD). */
  dailyYield: number;
  seller: string;
  startingBidTon: number;
  currentBidTon: number | null;
  minNextBidTon: number;
  bidCount: number;
  endsAt: string;
  mine: boolean;
  iAmHighest: boolean;
  myBidTon: number | null;
};

export type AuctionBrowse = {
  auctions: AuctionCard[];
  availableTon: number;
  reservedTon: number;
  settings: AuctionSettings;
  canCreate: boolean;
  adminBypass: boolean;
};

export type AuctionSellableItem = {
  id: string;
  itemType: AuctionItemType;
  name: string;
  rarity: string;
  level: number;
  image: string | null;
  stars?: number;
  atk?: number;
  hp?: number;
  slot?: string;
  dailyYield?: number;
  available: boolean;
};

export type AuctionSellable = {
  heroes: AuctionSellableItem[];
  pets: AuctionSellableItem[];
  equipment: AuctionSellableItem[];
  availableTon: number;
  settings: AuctionSettings;
};

export type AuctionMineEntry = {
  id: string;
  name: string;
  rarity: string;
  image: string | null;
  itemType: AuctionItemType;
  currentBidTon: number | null;
  startingBidTon?: number;
  bidCount?: number;
  myBidTon?: number;
  endsAt: string;
  status: string;
  finalPriceTon?: number | null;
  netTon?: number | null;
};

export type AuctionMine = {
  selling: AuctionMineEntry[];
  bidding: AuctionMineEntry[];
  availableTon: number;
  reservedTon: number;
  settings: AuctionSettings;
};

/** Heróis Mythic+ e qualquer NFT Exclusive são AUCTION ONLY (espelho da regra do backend). Lendários são livres no mercado. */
export const AUCTION_ONLY_RARITIES = ['nft_exclusive', 'divine', 'celestial'];
export const AUCTION_ONLY_HERO_RARITIES = ['mythic', 'ancestral'];
export const isAuctionOnlyItem = (itemType: string, rarity?: string | null) => {
  const rar = String(rarity ?? '').toLowerCase();
  return AUCTION_ONLY_RARITIES.includes(rar)
    || (String(itemType).toLowerCase() === 'hero' && AUCTION_ONLY_HERO_RARITIES.includes(rar));
};

/** Exibição: TON com até 9 casas, sem zeros à direita. */
export const auctionTon = (value: number | string | null | undefined) => {
  const amount = Number(value);
  if (!Number.isFinite(amount)) return '0';
  const text = amount.toFixed(9).replace(/0+$/, '').replace(/\.$/, '');
  return text === '-0' ? '0' : text;
};

/** Contagem regressiva no formato 01h 42m (ou 12m 30s no fim). */
export function auctionCountdown(endsAt: string, now: number = Date.now()) {
  const diff = new Date(endsAt).getTime() - now;
  if (!Number.isFinite(diff) || diff <= 0) return '00m 00s';
  const total = Math.floor(diff / 1000);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  if (hours > 0) return `${String(hours).padStart(2, '0')}h ${String(minutes).padStart(2, '0')}m`;
  return `${String(minutes).padStart(2, '0')}m ${String(seconds).padStart(2, '0')}s`;
}
