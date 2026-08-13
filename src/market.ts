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
  /** Escrow window for FC sales: how long a sale stays on hold before the seller is paid. */
  settlementHours?: number;
  /** Escrow window for TON sales. 0 = instant settlement after payment confirmation. */
  settlementHoursTon?: number;
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

/** Why an owned asset cannot be listed right now (server-computed). */
export type MarketLockReason =
  | 'listed' | 'locked' | 'not_tradable' | 'exclusive'
  | 'pvp_team' | 'global_boss_team' | 'clan_boss_team'
  | 'active_pet' | 'equipped';

export type MarketSellableBase = { locks?: MarketLockReason[]; available?: boolean };
export type MarketSellableHero = MarketSellableBase & { id: string; name: string; rarity: string; level: number; image: string | null; stars: number; atk: number; hp: number; priceRange?: MarketPriceRange };
export type MarketSellablePet = MarketSellableBase & { id: string; name: string; rarity: string; level: number; image: string | null; evolution: string | null; tier: number; priceRange?: MarketPriceRange };
export type MarketSellableItem = MarketSellableBase & { code: string; itemType: string; quantity: number; priceRange?: MarketPriceRange };

export type MarketSellable = {
  heroes: MarketSellableHero[];
  pets: MarketSellablePet[];
  items: MarketSellableItem[];
  balanceFc?: number;
  /** Withdrawable TON balance (same value the main HUD shows). */
  availableTon?: number;
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
  priceTon: number;
  currency: MarketCurrency;
  status: 'active' | 'reserved' | 'sold' | 'cancelled';
  feePercent: number;
  createdAt: string;
  soldAt: string | null;
  cancelledAt: string | null;
};

export type MarketPurchase = { id: string; itemType: MarketItemType; name: string; rarity: string; image: string | null; priceFc: number; priceTon: number; currency: MarketCurrency; seller: string; createdAt: string };

export type MarketMine = { listings: MarketMyListing[]; purchases: MarketPurchase[]; settings: MarketSettings };

export type MarketBuyResult = { ok: boolean; currency: MarketCurrency; pricePaid: number; feeFc: number; sellerReceived: number; balanceFc: number; availableTon?: number; itemType: MarketItemType; name: string };
export type MarketCreateResult = { ok: boolean; listingId: string; currency: MarketCurrency; feePercent: number; sellerReceives: number };

/**
 * External-wallet TON payment. The listing is reserved for this buyer until
 * `expiresAt`; the backend confirms the transfer on-chain and then delivers the item.
 */
export type MarketPaymentIntent = {
  paymentId: string;
  listingId: string;
  paymentAddress: string;
  amountNano: string;
  amountTon: number;
  paymentComment: string;
  expiresAt: string;
};
export type MarketPaymentStatus = {
  paymentId: string;
  status: 'pending' | 'confirmed' | 'expired' | 'cancelled';
  amountTon: number;
  expiresAt: string;
  listingId: string;
};

/** Client-side preview of the split. The backend recalculates and is the authority. */
export const marketFeeSplit = (price: number, feePercent: number, currency: MarketCurrency = 'FC') => {
  const clean = Number.isFinite(price) && price > 0 ? (currency === 'TON' ? Math.round(price * 1000) / 1000 : Math.trunc(price)) : 0;
  const percent = Number.isFinite(feePercent) && feePercent >= 0 ? feePercent : 5;
  const rawFee = (clean * percent) / 100;
  const fee = currency === 'TON' ? Math.round(rawFee * 1000) / 1000 : Math.round(rawFee);
  const receives = currency === 'TON' ? Math.round((clean - fee) * 1000) / 1000 : clean - fee;
  return { price: clean, fee, receives };
};

/** Display helper: FC uses thousands separators, TON keeps up to 3 decimals. */
export const marketPriceLabel = (listing: { currency: MarketCurrency; priceFc: number; priceTon: number }) =>
  listing.currency === 'TON'
    ? `${Number(listing.priceTon ?? 0).toLocaleString('en-US', { maximumFractionDigits: 3 })} TON`
    : `${Number(listing.priceFc ?? 0).toLocaleString('en-US')} FC`;


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
