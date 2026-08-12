/**
 * Player Market — types shared by the shop panel and the service layer.
 * Every rule (eligibility, fee, minimum price, price band, atomic purchase, TON
 * reservation) is enforced by the backend RPCs; the client only renders what the
 * server returns. Listings are priced in FC or in TON, never in both.
 */
export type MarketItemType = 'hero' | 'pet' | 'item';
export type MarketSort = 'newest' | 'price_low' | 'price_high';
export type MarketCurrency = 'FC' | 'TON';

export type MarketSettings = {
  feePercent: number;
  /** Fee applied to TON sales (may differ from the FC fee). */
  feePercentTon?: number;
  maxActiveListings: number;
  maxPriceFc: number;
  maxPriceTon?: number;
  minPrice: Partial<Record<MarketItemType, number>>;
  minPriceTon?: Partial<Record<MarketItemType, number>>;
  /** Escrow window: how long a sale stays on hold before the seller is paid. */
  settlementHours?: number;
  /** How long an external-wallet payment keeps a listing reserved. */
  reservationMinutes?: number;
};

export type MarketListing = {
  id: string;
  itemType: MarketItemType;
  name: string;
  rarity: string;
  level: number;
  image: string | null;
  priceFc: number;
  /** Price in TON when `currency` is 'TON'. */
  priceTon: number;
  currency: MarketCurrency;
  quantity: number;
  seller: string;
  mine: boolean;
  atk: number;
  hp: number;
  stars: number;
  createdAt: string;
  /** Set while another buyer holds a wallet-payment reservation. */
  status?: 'active' | 'reserved';
  reservedForMe?: boolean;
};

export type MarketBrowse = {
  listings: MarketListing[];
  balanceFc: number;
  /** Internal withdrawable TON balance available to pay for TON listings. */
  availableTon?: number;
  settings: MarketSettings;
  activeCount: number;
};

/** Server-computed safe price band. `source` is 'median' once there are enough settled sales. */
export type MarketPriceRange = {
  min: number;
  max: number;
  recommended: number;
  median: number | null;
  samples: number;
  source: 'config' | 'median';
  itemType: string;
  rarity: string;
  currency?: MarketCurrency;
};


export type MarketSellEligibility = {
  canSell: boolean;
  reason?: string | null;
  accountDays?: number;
  activeDays?: number;
  [key: string]: unknown;
};

export type MarketSellableHero = { id: string; name: string; rarity: string; level: number; image: string | null; stars: number; atk: number; hp: number; priceRange?: MarketPriceRange };
export type MarketSellablePet = { id: string; name: string; rarity: string; level: number; image: string | null; evolution: string | null; tier: number; priceRange?: MarketPriceRange };
export type MarketSellableItem = { code: string; itemType: string; quantity: number; priceRange?: MarketPriceRange };

export type MarketSellable = {
  heroes: MarketSellableHero[];
  pets: MarketSellablePet[];
  items: MarketSellableItem[];
  settings: MarketSettings;
  eligibility?: MarketSellEligibility;
};

/** Live quote for one specific item the player owns (price band + fee + eligibility). */
export type MarketQuote = {
  range: MarketPriceRange;
  settings: MarketSettings;
  eligibility: MarketSellEligibility;
};

export type MarketMyListing = {
  id: string;
  itemType: MarketItemType;
  name: string;
  rarity: string;
  level: number;
  image: string | null;
  priceFc: number;
  status: 'active' | 'sold' | 'cancelled';
  feePercent: number;
  createdAt: string;
  soldAt: string | null;
  cancelledAt: string | null;
};

export type MarketPurchase = { id: string; itemType: MarketItemType; name: string; rarity: string; image: string | null; priceFc: number; seller: string; createdAt: string };

export type MarketMine = { listings: MarketMyListing[]; purchases: MarketPurchase[]; settings: MarketSettings };

export type MarketBuyResult = { ok: boolean; pricePaid: number; feeFc: number; sellerReceived: number; balanceFc: number; itemType: MarketItemType; name: string };
export type MarketCreateResult = { ok: boolean; listingId: string; feePercent: number; sellerReceives: number };

/** Client-side preview of the split. The backend recalculates and is the authority. */
export const marketFeeSplit = (price: number, feePercent: number) => {
  const clean = Number.isFinite(price) && price > 0 ? Math.trunc(price) : 0;
  const percent = Number.isFinite(feePercent) && feePercent >= 0 ? feePercent : 5;
  const fee = Math.round((clean * percent) / 100);
  return { price: clean, fee, receives: clean - fee };
};

/**
 * Marketplace maintenance switch. Single source of truth: the backend
 * (`market_status` RPC) decides both `enabled` and the admin bypass.
 */
export type MarketStatus = {
  enabled: boolean;
  canAccess: boolean;
  adminBypass: boolean;
  maintenanceMessage: string;
  updatedAt: string | null;
};
