/**
 * Player Market (FC only) — types shared by the shop panel and the service layer.
 * Every rule (eligibility, fee, minimum price, atomic purchase) is enforced by the
 * backend RPCs; the client only renders what the server returns.
 */
export type MarketItemType = 'hero' | 'pet' | 'item';
export type MarketSort = 'newest' | 'price_low' | 'price_high';

export type MarketSettings = {
  feePercent: number;
  maxActiveListings: number;
  maxPriceFc: number;
  minPrice: Partial<Record<MarketItemType, number>>;
};

export type MarketListing = {
  id: string;
  itemType: MarketItemType;
  name: string;
  rarity: string;
  level: number;
  image: string | null;
  priceFc: number;
  quantity: number;
  seller: string;
  mine: boolean;
  atk: number;
  hp: number;
  stars: number;
  createdAt: string;
};

export type MarketBrowse = {
  listings: MarketListing[];
  balanceFc: number;
  settings: MarketSettings;
  activeCount: number;
};

export type MarketSellableHero = { id: string; name: string; rarity: string; level: number; image: string | null; stars: number; atk: number; hp: number };
export type MarketSellablePet = { id: string; name: string; rarity: string; level: number; image: string | null; evolution: string | null; tier: number };
export type MarketSellableItem = { code: string; itemType: string; quantity: number };

export type MarketSellable = {
  heroes: MarketSellableHero[];
  pets: MarketSellablePet[];
  items: MarketSellableItem[];
  settings: MarketSettings;
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
