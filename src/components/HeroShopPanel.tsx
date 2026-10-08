import { useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { petDisplayRarity } from '../petLabels';
import { useTonConnectUI, useTonWallet } from '@tonconnect/ui-react';
import { toast } from 'sonner';
import { ArrowLeftRight, X, Store, Swords, Tag, Info, ChevronDown, ChevronLeft, ChevronRight, ShoppingCart, RefreshCw, Wallet, Lock, Gem, Gavel } from 'lucide-react';
import altarImage from '../assets/recruit-altar.jpg';
import { useT } from '../LanguageContext';
import { formatCurrency } from '../utils';
import { RARITY_COLORS, type HeroRarity, type ShopHero } from '../heroCatalog';
import { useMarketBrowse, useMarketMine, useMarketQuote, useMarketRealtime, useMarketSellable, useMarketStatus, useMythUtility } from '../hooks';
import { MythBalanceHint, MythPayButton } from './MythPayButton';
import {
  buyMarketListing,
  cancelMarketListing,
  createMarketListing,
  createMarketPaymentIntent,
  waitForMarketPayment,
} from '../services';
import { MARKET_SELL_CATEGORIES, marketFeeSplit, marketKindForCategory, marketMinPriceTon, marketPriceLabel, type MarketCurrency, type MarketItemType, type MarketLockReason, type MarketSellCategory, type MarketSort } from '../market';
import { getInventoryItemVisual } from '../inventoryVisuals';
import { encodeCommentPayload } from '../tonComment';
import { NftHeroCollectionSection, NftHeroShopSection } from './NftHeroShopSection';
import { PrivateTradePanel } from './PrivateTradePanel';
import { AuctionPanel } from './AuctionPanel';
import { ItemDetailsModal } from './ItemDetailsModal';
import { sendTonPayment } from '../tonPayment';
import { RouletteOverlay } from './RouletteOverlay';
import rouletteWheel from '../assets/roulette/wheel.png';


type Props = {
  telegramInitData: string | null;
  fcBalance: number;
  /** Same withdrawable TON balance shown in the main HUD. */
  tonBalance?: number;
  summonOdds: Array<{ rarity: HeroRarity; chance: number }>;
  recruitPrice: (count: number) => number;
  shopResults: ShopHero[];
  onRecruit: (count: 1 | 5 | 10, payWith?: 'FC' | 'MYTH') => void;
  onClose: () => void;
  /** Which access point opened the panel: hero recruitment or the Player Market. */
  mode?: 'recruit' | 'market';
};

const RARITY_FILTERS = ['all', 'common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic', 'ancestral'] as const;
const rarityColor = (rarity: string) => RARITY_COLORS[(rarity as HeroRarity)] ?? '#94a3b8';
const tonAmount = (value: number) => Number(value ?? 0).toLocaleString('en-US', { maximumFractionDigits: 3 });

/**
 * Marketplace with two currencies: FC (game coin) and TON. TON purchases spend the
 * internal withdrawable TON balance first; when it is not enough the backend reserves
 * the listing and the buyer pays from the connected wallet.
 */
export function HeroShopPanel({ telegramInitData, fcBalance, tonBalance = 0, summonOdds, recruitPrice, shopResults, onRecruit, onClose, mode = 'recruit' }: Props) {
  const t = useT();
  const queryClient = useQueryClient();
  const [tonUI] = useTonConnectUI();
  const wallet = useTonWallet();
  // Access point only: the panel now opens either the Recruit view or the Player Market
  // view (moved to the Village). The market system itself is untouched.
  const tab: 'recruit' | 'market' = mode;
  // MYTH is offered as an EXTRA recruitment payment when the backend enables it.
  const mythUtility = useMythUtility(telegramInitData, mode === 'recruit');
  // Tapping a listing opens the read-only premium preview (real backend attributes).
  const [detailsId, setDetailsId] = useState<string | null>(null);
  // Hero shop sub-tabs: RECRUIT, 💎 NFT EXCLUSIVE and 🛒 BUY NFT (same structure as pets).
  const [heroTab, setHeroTab] = useState<'recruit' | 'nft' | 'buy-nft'>('recruit');
  // 🎡 Global Mystery Roulette lives inside the hero shop (fullscreen overlay).
  const [rouletteOpen, setRouletteOpen] = useState(false);

  // Trading floor: the classic Market (FC/TON) or the Auction (internal TON only).
  const [section, setSection] = useState<'market' | 'auction' | 'private'>('market');
  const [marketTab, setMarketTab] = useState<'browse' | 'mine' | 'sell'>('browse');
  const [itemType, setItemType] = useState<MarketItemType | 'all'>('all');
  const [rarity, setRarity] = useState<string>('all');
  const [sort, setSort] = useState<MarketSort>('newest');
  const [currencyFilter, setCurrencyFilter] = useState<MarketCurrency | 'all'>('all');
  const [sellCategory, setSellCategory] = useState<MarketSellCategory>('hero');
  const sellKind: MarketItemType = marketKindForCategory(sellCategory);
  const [quantity, setQuantity] = useState(1);
  const [sellCurrency, setSellCurrency] = useState<MarketCurrency>('FC');
  const [selected, setSelected] = useState<{ id?: string; code?: string; name: string; rarity?: string; max?: number; stackable?: boolean; minPriceTon?: number } | null>(null);
  const [price, setPrice] = useState('');
  const [sortOpen, setSortOpen] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [page, setPage] = useState(1);
  const [payingId, setPayingId] = useState<string | null>(null);
  const [tonPrompt, setTonPrompt] = useState<{ id: string; price: number; name: string } | null>(null);

  // Maintenance switch and the admin bypass are decided by the backend only.
  const status = useMarketStatus(telegramInitData, tab === 'market');
  const marketAccess = status.data?.canAccess ?? false;
  const marketOpen = tab === 'market' && marketAccess;
  useMarketRealtime(marketOpen);
  const browse = useMarketBrowse(telegramInitData, marketOpen && marketTab === 'browse', itemType, rarity, sort, currencyFilter);
  const mine = useMarketMine(telegramInitData, marketOpen && marketTab === 'mine');
  const sellable = useMarketSellable(telegramInitData, marketOpen && marketTab === 'sell');

  const settings = browse.data?.settings ?? mine.data?.settings ?? sellable.data?.settings;
  const isTonSale = sellCurrency === 'TON';
  const feePercent = Number((isTonSale ? settings?.feePercentTon : settings?.feePercent) ?? settings?.feePercent ?? 5);
  // TON minimum is the hard backend rule (0.10 TON, 10 TON for Legendary+ heroes).
  const minPriceTonForSelection = Number(selected?.minPriceTon ?? marketMinPriceTon(sellKind, selected?.rarity));
  const minPrice = isTonSale ? minPriceTonForSelection : Number(settings?.minPrice?.[sellKind] ?? 5000);
  const maxQuantity = Math.max(1, Number(selected?.max ?? 1));
  const isStackable = sellKind === 'item' && selected?.stackable !== false && maxQuantity > 1;
  const listedQuantity = Math.min(Math.max(1, Math.trunc(quantity) || 1), maxQuantity);
  // TON sales settle instantly (no hold); FC sales keep the configured anti-fraud hold.
  const settlementHours = Number(settings?.settlementHours ?? 72);
  const tonSettlementHours = Number(settings?.settlementHoursTon ?? 0);
  // FC and TON sales both settle the moment the purchase is confirmed (no hold).
  const instantSettlement = isTonSale ? tonSettlementHours <= 0 : true;
  const availableTon = Number(browse.data?.availableTon ?? sellable.data?.availableTon ?? tonBalance ?? 0);
  // Header chip: prefer the live server value, fall back to the HUD balance.
  const tonWalletBalance = Number(sellable.data?.availableTon ?? browse.data?.availableTon ?? tonBalance ?? 0);

  // Selling is the only action locked for young accounts: browsing and buying stay open.
  const eligibility = sellable.data?.eligibility;
  const canSell = eligibility ? eligibility.canSell !== false : true;

  // Live price band for the selected item — the backend is the single source of truth.
  const quote = useMarketQuote(telegramInitData, marketOpen && marketTab === 'sell' && !!selected, {
    itemType: sellKind,
    itemInstanceId: sellKind === 'item' ? undefined : selected?.id,
    itemCode: sellKind === 'item' ? selected?.code : undefined,
  });
  const band = quote.data?.range ?? null;
  const bandActive = !isTonSale && band?.currency !== 'TON';
  const bandMin = bandActive ? Math.max(Number(band?.min ?? minPrice), minPrice) : minPrice;
  const bandMax = bandActive
    ? Number(band?.max ?? settings?.maxPriceFc ?? 50_000_000)
    : Number(settings?.maxPriceTon ?? 100_000);
  const bandRecommended = bandActive ? Number(band?.recommended ?? bandMin) : bandMin;
  const priceValue = Number(price) || 0;
  const outOfBand = priceValue > 0 && (priceValue < bandMin || priceValue > bandMax);
  const split = useMemo(() => marketFeeSplit(priceValue, feePercent, sellCurrency), [priceValue, feePercent, sellCurrency]);
  const priceUnit = isTonSale ? 'TON' : 'FC';
  const amountLabel = (value: number) => (isTonSale ? tonAmount(value) : formatCurrency(value));

  const sortLabel = (value: MarketSort) =>
    value === 'newest' ? t('market.sortNewest') : value === 'price_low' ? t('market.sortPriceLow') : t('market.sortPriceHigh');

  const PAGE_SIZE = 8;
  const listings = browse.data?.listings ?? [];
  const totalPages = Math.max(1, Math.ceil(listings.length / PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const pageListings = listings.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE);
  const pageNumbers = Array.from({ length: Math.min(5, totalPages) }, (_, index) => {
    const start = Math.max(1, Math.min(currentPage - 2, totalPages - 4));
    return start + index;
  }).filter((value) => value >= 1 && value <= totalPages);


  const refreshAll = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ['market-browse'] }),
      queryClient.invalidateQueries({ queryKey: ['market-mine'] }),
      queryClient.invalidateQueries({ queryKey: ['market-sellable'] }),
      queryClient.invalidateQueries({ queryKey: ['game-state'] }),
      queryClient.invalidateQueries({ queryKey: ['player-heroes'] }),
      queryClient.invalidateQueries({ queryKey: ['pet-dashboard'] }),
      queryClient.invalidateQueries({ queryKey: ['player-inventory'] }),
      queryClient.invalidateQueries({ queryKey: ['wallet-summary'] }),
      queryClient.invalidateQueries({ queryKey: ['ton-wallet'] }),
      // Escrow: listed items leave the collection/backpack immediately, everywhere they are shown.
      queryClient.invalidateQueries({ queryKey: ['hero-mining'] }),
      queryClient.invalidateQueries({ queryKey: ['hero-equipment'] }),
      queryClient.invalidateQueries({ queryKey: ['hero-fusion'] }),
      queryClient.invalidateQueries({ queryKey: ['pvp-dashboard'] }),
      queryClient.invalidateQueries({ queryKey: ['boss-combat'] }),
      queryClient.invalidateQueries({ queryKey: ['tower-dashboard'] }),
      queryClient.invalidateQueries({ queryKey: ['breeding'] }),
      queryClient.invalidateQueries({ queryKey: ['expeditions'] }),
    ]);
  };

  /**
   * External wallet payment. Always charges the FULL listing price: the internal TON
   * balance is never debited nor combined with the wallet payment. The backend reserves
   * the listing (payment intent) and only delivers after confirming the transfer on-chain.
   */
  const payWithWallet = async (listingId: string) => {
    if (!wallet) { await tonUI.openModal(); throw new Error(t('market.connectWallet')); }
    const address = String(wallet.account?.address ?? '');
    const intent = await createMarketPaymentIntent(telegramInitData ?? '', listingId, address);
    await sendTonPayment(intent, (tx) => tonUI.sendTransaction(tx));

    toast.message(t('market.paymentSent', { minutes: 10 }));
    const result = await waitForMarketPayment(telegramInitData ?? '', intent.paymentId);
    if (result?.status === 'confirmed') toast.success(t('market.paymentConfirmed'));
    else toast.message(t('market.paymentPending'));
  };

  /**
   * One purchase = exactly one payment method.
   * internal TON balance >= price  -> INTERNAL_TON
   * otherwise                      -> EXTERNAL_TON_WALLET (full price, internal untouched)
   */
  const startPurchase = (listingId: string) => {
    // Double-click guard: one BUY tap can never open two purchase intents.
    if (buyMutation.isPending || payingId) return;
    const listing = listings.find((item) => item.id === listingId);
    if (listing?.currency === 'TON' && Number(listing.priceTon) > availableTon) {
      setTonPrompt({ id: listingId, price: Number(listing.priceTon), name: listing.name });
      return;
    }
    buyMutation.mutate(listingId);
  };

  const buyMutation = useMutation({
    mutationFn: async (listingId: string) => {
      const listing = listings.find((item) => item.id === listingId);
      if (listing?.currency === 'TON' && Number(listing.priceTon) > availableTon) {
        setPayingId(listingId);
        await payWithWallet(listingId);
        return null;
      }
      return await buyMarketListing(telegramInitData ?? '', listingId);
    },

    onSuccess: async (result) => {
      if (result) {
        const paid = result.currency === 'TON' ? `${tonAmount(result.pricePaid)} TON` : `${formatCurrency(result.pricePaid)} FC`;
        toast.success(`${t('market.purchaseCompleted')} · ${result.name} · -${paid}`, {
          description: t('market.purchaseCompletedBody', { name: String(result.name ?? '') }),
        });
      }
      setPayingId(null);
      setTonPrompt(null);
      await refreshAll();
    },
    onError: (error) => { setPayingId(null); setTonPrompt(null); toast.error(error instanceof Error ? error.message : t('market.loadError')); },
  });
  const cancelMutation = useMutation({
    mutationFn: (listingId: string) => cancelMarketListing(telegramInitData ?? '', listingId),
    onSuccess: async () => { toast.success(t('market.statusCancelled')); await refreshAll(); },
    onError: (error) => toast.error(error instanceof Error ? error.message : t('market.loadError')),
  });
  const listMutation = useMutation({
    mutationFn: () => createMarketListing(telegramInitData ?? '', {
      itemType: sellKind,
      itemInstanceId: sellKind === 'item' ? undefined : selected?.id,
      itemCode: sellKind === 'item' ? selected?.code : undefined,
      currency: sellCurrency,
      priceFc: isTonSale ? undefined : Math.trunc(priceValue),
      priceTon: isTonSale ? Math.round(priceValue * 1000) / 1000 : undefined,
      quantity: sellKind === 'item' ? listedQuantity : 1,
    }),
    onSuccess: async (result) => {
      toast.success(t('market.listingCreated'));
      setSelected(null); setPrice(''); setQuantity(1); setConfirming(false); setMarketTab('mine');
      await refreshAll();
    },
    onError: (error) => toast.error(error instanceof Error ? error.message : t('market.loadError')),
  });

  const chipClass = (active: boolean) =>
    `rounded-full border px-2.5 py-1 text-[9px] font-black uppercase tracking-[0.12em] transition ${active ? 'border-amber-300/70 bg-amber-400/20 text-amber-200' : 'border-white/10 bg-white/[.03] text-slate-400'}`;

  type SellOption = { id?: string; code?: string; name: string; rarity: string; level: number; image: string | null; detail: string; locks: MarketLockReason[]; available: boolean; quantity: number; stackable: boolean; minPriceTon: number };
  const lockLabel = (lock: MarketLockReason) =>
    lock === 'pvp_team' ? t('market.lockPvp')
      : lock === 'global_boss_team' ? t('market.lockGlobalBoss')
      : lock === 'clan_boss_team' ? t('market.lockClanBoss')
      : lock === 'active_pet' ? t('market.lockActivePet')
      : lock === 'equipped' ? t('market.lockEquipped')
      : lock === 'listed' ? t('market.lockListed')
      : lock === 'exclusive' ? t('market.lockExclusive')
      : t('market.lockNotTradable');
  const normalize = (locks: MarketLockReason[] | undefined, available: boolean | undefined) => {
    const list = Array.from(new Set(locks ?? []));
    return { locks: list, available: available ?? list.length === 0 };
  };
  const sellOptions: SellOption[] = sellCategory === 'hero'
    ? (sellable.data?.heroes ?? []).map((hero) => ({ id: hero.id, name: hero.name, rarity: hero.rarity, level: hero.level, image: hero.image, detail: `ATK ${formatCurrency(hero.atk)} · HP ${formatCurrency(hero.hp)}`, quantity: 1, stackable: false, minPriceTon: Number(hero.minPriceTon ?? marketMinPriceTon('hero', hero.rarity)), ...normalize(hero.locks, hero.available) }))
    : sellCategory === 'pet'
      ? (sellable.data?.pets ?? []).map((pet) => ({ id: pet.id, name: pet.name, rarity: petDisplayRarity(pet), level: pet.level, image: pet.image, detail: String(pet.evolution ?? '').toUpperCase(), quantity: 1, stackable: false, minPriceTon: Number(pet.minPriceTon ?? marketMinPriceTon('pet', pet.rarity)), ...normalize(pet.locks, pet.available) }))
      : (sellable.data?.items ?? [])
        .filter((item) => (item.category ?? 'other') === sellCategory)
        .map((item) => {
          // Art comes from the SAME shared map the inventory uses, so nothing renders broken.
          const visual = getInventoryItemVisual({
            itemId: item.code.includes(':') ? item.code.split(':')[0] : item.code,
            itemType: item.itemType, category: (item.category ?? 'other') as never,
            image: item.image ?? null, rarity: item.rarity ?? null, quantity: item.quantity,
          } as never);
          return {
            code: item.code,
            name: item.name ?? item.code.replace(/_/g, ' ').toUpperCase(),
            rarity: item.rarity ?? 'rare',
            level: 1,
            image: item.image ?? visual.image,
            detail: `x${item.quantity}`,
            quantity: Math.max(1, Number(item.quantity ?? 1)),
            stackable: item.stackable !== false,
            minPriceTon: Number(item.minPriceTon ?? marketMinPriceTon('item', item.rarity)),
            ...normalize(item.locks, item.available),
          };
        });
  const freeOptions = sellOptions.filter((option) => option.available);
  const selectedOption = sellOptions.find((option) => option.id === selected?.id && option.code === selected?.code) ?? null;

  return (
    <>
    <div className={`fullscreen-page flex items-center justify-center p-3 ${rouletteOpen ? 'hidden' : ''}`}>


      <div className="relative flex max-h-[92dvh] w-full max-w-[450px] flex-col overflow-hidden rounded-[2rem] border border-amber-300/25 bg-[#090d15] shadow-2xl">
        <div className="flex items-center justify-between px-4 pt-4">
          <div>
            <p className="text-[9px] uppercase tracking-[0.3em] text-amber-300">MYTHREON</p>
            <h2 className="text-lg font-black leading-tight text-white">{tab === 'market' ? t('market.tabMarket') : t('shop')}</h2>
          </div>
          <div className="flex items-center gap-2">
            <span className="rounded-full border border-amber-300/25 bg-black/40 px-2.5 py-1 text-[10px] font-black text-amber-300">{formatCurrency(fcBalance)} FC</span>
            <span className="flex items-center gap-1 rounded-full border border-sky-300/30 bg-black/40 px-2.5 py-1 text-[10px] font-black text-sky-300">
              <Gem className="h-3 w-3" />{tonAmount(tonWalletBalance)} TON
            </span>
            <button onClick={onClose} className="grid h-9 w-9 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
          </div>
        </div>


        {tab === 'recruit' ? (
          <div className="mt-3 grid grid-cols-3 gap-1.5 px-4">
            {([
              ['recruit', t('shop.tabRecruit')],
              ['nft', t('shop.tabNft')],
              ['buy-nft', t('shop.tabBuyNft')],
            ] as const).map(([key, label]) => (
              <button
                key={key}
                type="button"
                onClick={() => setHeroTab(key)}
                className={`rounded-xl px-1 py-2 text-[9px] font-black uppercase tracking-[.12em] ${heroTab === key ? 'bg-gradient-to-b from-amber-300 to-orange-500 text-black' : 'border border-white/10 bg-white/[.03] text-slate-300'}`}
              >
                {label}
              </button>
            ))}
          </div>
        ) : null}

        <div className="mt-3 flex-1 overflow-y-auto px-4 pb-4">
          {tab === 'recruit' && heroTab === 'nft' ? (
            telegramInitData ? <NftHeroCollectionSection telegramInitData={telegramInitData} /> : null
          ) : tab === 'recruit' && heroTab === 'buy-nft' ? (
            telegramInitData ? <NftHeroShopSection telegramInitData={telegramInitData} /> : null
          ) : tab === 'recruit' ? (
            <div>

              {/* 🎡 GLOBAL MYSTERY ROULETTE — entrada premium. Nada do ciclo global é exposto aqui. */}
              <button
                type="button"
                onClick={() => setRouletteOpen(true)}
                className="mb-3 flex w-full items-center gap-3 overflow-hidden rounded-2xl border border-amber-300/30 bg-[radial-gradient(circle_at_top_left,rgba(251,191,36,0.18),rgba(0,0,0,0.6))] p-3 text-left"
              >
                <img src={rouletteWheel} alt="" className="h-14 w-14 shrink-0 object-contain drop-shadow-[0_0_12px_rgba(251,191,36,0.5)]" />
                <span className="min-w-0 flex-1">
                  <span className="block text-[12px] font-black uppercase tracking-[0.12em] text-amber-300">Global Mystery Roulette</span>
                  <span className="block text-[9px] uppercase tracking-[0.18em] text-slate-400">Gire e receba recompensas reais</span>
                </span>
                <ChevronRight className="h-4 w-4 shrink-0 text-amber-300" />
              </button>



              <div className="rounded-2xl border border-amber-300/20 bg-black/30 p-3 text-center">
                <p className="text-[13px] font-black tracking-[0.06em] text-amber-300">{t('market.recruitTitle')}</p>
                <p className="mt-0.5 text-[8px] uppercase tracking-[0.2em] text-slate-400">{t('market.recruitSubtitle')}</p>
                <div className="mt-3 rounded-xl border border-white/10 bg-white/[.02] p-2">
                  <p className="text-[9px] font-black uppercase tracking-[0.2em] text-slate-300">{t('market.summonOdds')}</p>
                  <div className="mt-1.5 grid grid-cols-3 gap-x-1 gap-y-1.5 sm:grid-cols-6">
                    {summonOdds.filter((entry) => entry.rarity !== 'ancestral').map((entry) => (
                      <div key={entry.rarity} className="min-w-0 text-center">
                        <p className="truncate text-[6.5px] font-bold uppercase leading-tight tracking-tight" style={{ color: RARITY_COLORS[entry.rarity] }}>{t(entry.rarity)}</p>
                        <p className="text-[11px] font-black leading-tight text-white">{entry.chance}%</p>
                      </div>
                    ))}
                  </div>
                </div>
              </div>

              <div className="relative mt-3 overflow-hidden rounded-2xl border border-amber-300/20">
                <img src={altarImage} alt={t('market.recruitTitle')} width={1024} height={768} loading="lazy" className="h-[190px] w-full object-cover" />
                <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-[#090d15] via-transparent to-transparent" />
              </div>

              <div className="mt-3 grid grid-cols-3 gap-2">
                {([1, 5, 10] as const).map((count) => (
                  <div key={count} className="flex flex-col gap-1.5">
                    <button onClick={() => onRecruit(count, 'FC')} className="rounded-2xl border border-amber-300/25 bg-gradient-to-b from-white/[.06] to-black/40 px-1 py-3 text-center active:scale-95">
                      <span className="block text-xl font-black text-white">{count}×</span>
                      <span className="mt-0.5 block text-[8px] font-black text-amber-300">{formatCurrency(recruitPrice(count))} FC</span>
                    </button>
                    {/* Extra payment option: MYTH (price + burn are decided by the backend). */}
                    <MythPayButton state={mythUtility.data} feature="HERO_RECRUIT" fc={recruitPrice(count)} onPay={() => onRecruit(count, 'MYTH')} />
                  </div>
                ))}
              </div>
              <MythBalanceHint state={mythUtility.data} />


              <div className="mt-3 flex items-start gap-2 rounded-2xl border border-sky-400/20 bg-sky-400/[.06] p-2.5">
                <Info className="mt-0.5 h-3.5 w-3.5 shrink-0 text-sky-300" />
                <p className="text-[9px] leading-relaxed text-slate-300">{t('market.recruitHint')}</p>
              </div>

              {shopResults.length ? (
                <div className="mt-3">
                  <p className="text-[9px] uppercase tracking-[0.2em] text-slate-400">{t('latestHeroes')}</p>
                  <div className="mt-1.5 grid grid-cols-5 gap-1.5">
                    {shopResults.map((hero, index) => (
                      <div key={`${hero.id}-${index}`} className="overflow-hidden rounded-lg border bg-black/50" style={{ borderColor: `${RARITY_COLORS[hero.rarity]}99` }}>
                        <img src={hero.image} alt={hero.name} className="aspect-square w-full object-cover object-top" />
                        <p className="truncate px-1 py-0.5 text-center text-[7px] font-bold" style={{ color: RARITY_COLORS[hero.rarity] }}>{t(hero.rarity)}</p>
                      </div>
                    ))}
                  </div>
                </div>
              ) : null}
            </div>

          ) : !marketAccess ? (
            <div className="flex flex-1 flex-col items-center justify-center py-10 text-center">
              <div className="rounded-2xl border border-amber-300/20 bg-amber-400/10 p-6">
                <Store className="mx-auto h-10 w-10 text-amber-300 opacity-60" />
                <p className="mt-3 text-[10px] uppercase tracking-[0.25em] text-slate-400">{t('market.title')}</p>
                <p className="mt-1 text-sm font-black uppercase tracking-[0.12em] text-amber-200">🛠 {t('market.maintenance')}</p>
                <p className="mt-2 text-[10px] leading-relaxed text-slate-300">{status.data?.maintenanceMessage ?? t('market.maintenanceMessage')}</p>
                <div className="mt-4 flex justify-center gap-2">
                  <button onClick={() => void status.refetch()} className="rounded-lg border border-amber-300/40 px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.12em] text-amber-200">
                    <RefreshCw className="-mt-0.5 mr-1 inline h-3 w-3" />{t('market.retry')}
                  </button>
                  <button onClick={onClose} className="rounded-lg border border-white/15 px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.12em] text-slate-300">
                    {t('close')}
                  </button>

                </div>
              </div>
            </div>
          ) : (
            <div>
              {/* MARKET ↔ AUCTION switch. The auction is a separate trading floor: internal TON only. */}
              <div className="mb-3 grid grid-cols-3 gap-1.5 rounded-2xl border border-white/10 bg-black/40 p-1">
                {([['market', t('market.tabMarket')], ['auction', t('auction.tab')], ['private', t('privateTrade.tab')]] as const).map(([key, label]) => (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setSection(key)}
                    className={`rounded-xl px-1 py-2 text-[10px] font-black uppercase tracking-[.12em] ${section === key
                      ? key === 'auction' ? 'bg-gradient-to-b from-sky-300 to-cyan-500 text-black'
                        : key === 'private' ? 'bg-gradient-to-b from-fuchsia-300 to-purple-500 text-black'
                        : 'bg-gradient-to-b from-amber-300 to-orange-500 text-black'
                      : 'text-slate-300'}`}
                  >
                    {key === 'auction' ? <Gavel className="-mt-0.5 mr-1 inline h-3 w-3" />
                      : key === 'private' ? <ArrowLeftRight className="-mt-0.5 mr-1 inline h-3 w-3" />
                      : <Store className="-mt-0.5 mr-1 inline h-3 w-3" />}{label}
                  </button>
                ))}
              </div>

              {section === 'private' ? <PrivateTradePanel telegramInitData={telegramInitData} />
                : section === 'auction' ? <AuctionPanel telegramInitData={telegramInitData} /> : (<>

              {status.data && !status.data.enabled ? (
                <div className="mb-2 flex items-center gap-2 rounded-xl border border-fuchsia-400/30 bg-fuchsia-500/10 px-2.5 py-1.5">
                  <span className="text-[10px]">🧪</span>
                  <p className="text-[8px] font-black uppercase tracking-[0.14em] text-fuchsia-200">
                    {t('market.adminTestMode')} · <span className="font-bold normal-case tracking-normal text-slate-300">{t('market.adminTestModeHint')}</span>
                  </p>
                </div>
              ) : null}

              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="text-sm font-black text-white">{t('market.title')}</p>
                  <p className="text-[9px] text-slate-400">{t('market.subtitle')}</p>
                </div>
                <button
                  onClick={() => setMarketTab(marketTab === 'mine' ? 'browse' : 'mine')}
                  className={`shrink-0 rounded-full border px-2.5 py-1 text-[9px] font-black uppercase tracking-[0.1em] ${marketTab === 'mine' ? 'border-amber-300/70 bg-amber-400/20 text-amber-200' : 'border-white/10 bg-white/[.03] text-slate-300'}`}
                >
                  {t('market.myListings')} <ChevronRight className="-mt-0.5 inline h-3 w-3" />
                </button>
              </div>

              {marketTab === 'browse' ? (
                <div className="mt-3">
                  <div className="-mx-1 flex gap-1 overflow-x-auto px-1 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                    {(['all', 'hero', 'pet', 'item'] as const).map((value) => (
                      <button key={value} onClick={() => { setItemType(value); setPage(1); }} className={`${chipClass(itemType === value)} shrink-0`}>
                        {value === 'all' ? t('market.all') : value === 'hero' ? t('market.heroes') : value === 'pet' ? t('market.pets') : t('market.equipment')}
                      </button>
                    ))}
                  </div>
                  <div className="-mx-1 mt-1 flex gap-1 overflow-x-auto px-1 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                    {RARITY_FILTERS.map((value) => (
                      <button
                        key={value}
                        onClick={() => { setRarity(value); setPage(1); }}
                        className={`${chipClass(rarity === value)} shrink-0`}
                        style={value === 'all' ? undefined : { color: rarityColor(value), borderColor: `${rarityColor(value)}${rarity === value ? 'cc' : '55'}` }}
                      >
                        {value === 'all' ? t('market.all') : t(value)}
                      </button>
                    ))}
                  </div>

                  <div className="-mx-1 mt-1 flex gap-1 overflow-x-auto px-1 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                    {(['all', 'FC', 'TON'] as const).map((value) => (
                      <button key={value} onClick={() => { setCurrencyFilter(value); setPage(1); }} className={`${chipClass(currencyFilter === value)} shrink-0`}>
                        {value === 'all' ? t('market.all') : value}
                      </button>
                    ))}
                    {availableTon > 0 ? (
                      <span className="shrink-0 rounded-full border border-sky-300/40 bg-sky-400/10 px-2.5 py-1 text-[9px] font-black text-sky-200">{tonAmount(availableTon)} TON</span>
                    ) : null}
                  </div>

                  <div className="relative mt-2 flex items-center gap-2">
                    <button
                      onClick={() => setSortOpen((open) => !open)}
                      className="flex min-w-0 flex-1 items-center justify-between gap-1 rounded-xl border border-white/12 bg-white/[.03] px-2.5 py-2 text-[9px] font-black uppercase tracking-[0.1em] text-slate-200"
                    >
                      <span className="truncate">{sortLabel(sort)}</span>
                      <ChevronDown className="h-3.5 w-3.5 shrink-0 text-amber-300" />
                    </button>
                    <button
                      onClick={() => setMarketTab('sell')}
                      className="flex shrink-0 items-center gap-1 rounded-xl border border-amber-300/50 bg-gradient-to-b from-amber-400/25 to-orange-600/10 px-3 py-2 text-[9px] font-black uppercase tracking-[0.12em] text-amber-100"
                    >
                      <ShoppingCart className="h-3.5 w-3.5" />{t('market.sellItem')}
                    </button>
                    {sortOpen ? (
                      <div className="absolute left-0 top-full z-20 mt-1 w-[62%] overflow-hidden rounded-xl border border-amber-300/30 bg-[#0b1220] shadow-2xl">
                        {(['newest', 'price_low', 'price_high'] as const).map((value) => (
                          <button
                            key={value}
                            onClick={() => { setSort(value); setSortOpen(false); setPage(1); }}
                            className={`block w-full px-3 py-2 text-left text-[9px] font-black uppercase tracking-[0.1em] ${sort === value ? 'bg-amber-400/15 text-amber-200' : 'text-slate-300'}`}
                          >
                            {sortLabel(value)}
                          </button>
                        ))}
                      </div>
                    ) : null}
                  </div>

                  {browse.isError ? (
                    <div className="mt-4 rounded-2xl border border-rose-400/30 bg-rose-500/10 p-4 text-center">
                      <p className="text-[11px] text-rose-200">{t('market.loadError')}</p>
                      <button onClick={() => void browse.refetch()} className="mt-2 rounded-lg border border-amber-300/40 px-3 py-1.5 text-[10px] font-black text-amber-200">{t('market.retry')}</button>
                    </div>
                  ) : browse.isLoading ? (
                    <div className="mt-3 space-y-2">
                      {[0, 1, 2].map((key) => (
                        <div key={key} className="flex animate-pulse items-center gap-2 rounded-2xl border border-white/10 bg-white/[.03] p-2">
                          <div className="h-14 w-14 shrink-0 rounded-xl bg-white/10" />
                          <div className="flex-1 space-y-1.5">
                            <div className="h-2.5 w-2/3 rounded bg-white/10" />
                            <div className="h-2 w-1/3 rounded bg-white/10" />
                            <div className="h-2 w-1/2 rounded bg-white/10" />
                          </div>
                          <div className="h-7 w-14 shrink-0 rounded-lg bg-white/10" />
                        </div>
                      ))}
                    </div>
                  ) : !listings.length ? (
                    <p className="mt-6 text-center text-[11px] text-slate-400">{t('market.empty')}</p>
                  ) : (
                    <>
                      <div className="mt-3 space-y-2">
                        {pageListings.map((listing) => (
                          <div key={listing.id} className="flex items-center gap-2 rounded-2xl border border-white/10 bg-black/40 p-2">
                            <button type="button" onClick={() => setDetailsId(listing.id)} className="shrink-0 active:scale-95" aria-label={`Ver detalhes de ${listing.name}`}>
                              {listing.image ? (
                                <img src={listing.image} alt={listing.name} loading="lazy" className="h-16 w-16 rounded-xl border-2 object-cover" style={{ borderColor: rarityColor(listing.rarity) }} />
                              ) : (
                                <div className="grid h-16 w-16 place-items-center rounded-xl border-2 bg-white/[.03]" style={{ borderColor: rarityColor(listing.rarity) }}><Tag className="h-5 w-5 text-slate-500" /></div>
                              )}
                            </button>
                            <button type="button" onClick={() => setDetailsId(listing.id)} className="min-w-0 flex-1 text-left">
                              <p className="truncate text-[11px] font-black" style={{ color: rarityColor(listing.rarity) }}>{listing.name}</p>
                              <p className="truncate text-[8px] font-bold uppercase tracking-[0.08em] text-slate-400">
                                {t(listing.rarity)} · Lv. {listing.level}
                              </p>
                              {listing.itemType === 'hero' ? (
                                <p className="truncate text-[8px] text-slate-300">ATK {formatCurrency(listing.atk)} · HP {formatCurrency(listing.hp)}</p>
                              ) : null}
                              <p className="truncate text-[7px] uppercase tracking-[0.14em] text-slate-500">
                                {listing.itemType === 'hero' ? t('market.heroes') : listing.itemType === 'pet' ? t('market.pets') : t('market.itemLabel')}
                                {Number(listing.quantity ?? 1) > 1 ? ` · x${listing.quantity}` : ''}
                              </p>
                              <p className="truncate text-[8px] text-slate-500">{t('market.seller')} <span className="text-slate-300">{listing.seller}</span></p>
                              <p className="mt-0.5 flex items-center gap-1 text-[7px] font-black uppercase tracking-[0.14em] text-amber-300/80"><Info className="h-2.5 w-2.5" />Ver atributos</p>
                            </button>
                            <div className="flex w-[86px] shrink-0 flex-col items-end gap-1">
                              <p className={`text-right text-[11px] font-black leading-tight ${listing.currency === 'TON' ? 'text-sky-300' : 'text-amber-300'}`}>{marketPriceLabel(listing)}</p>
                              {listing.mine ? (
                                <span className="w-full rounded-lg border border-white/10 py-1 text-center text-[8px] font-black text-slate-400">{t('market.own')}</span>
                              ) : (
                                <button
                                  disabled={buyMutation.isPending || (listing.status === 'reserved' && !listing.reservedForMe)}
                                  onClick={() => startPurchase(listing.id)}
                                  className={`w-full rounded-lg border py-1.5 text-[9px] font-black uppercase tracking-[0.12em] disabled:opacity-50 ${listing.currency === 'TON' ? 'border-sky-300/50 bg-sky-400/15 text-sky-200' : 'border-amber-300/50 bg-amber-400/15 text-amber-200'}`}
                                >
                                  {listing.status === 'reserved' && !listing.reservedForMe
                                    ? t('market.reserved')
                                    : payingId === listing.id
                                      ? t('market.paying')
                                      : listing.currency === 'TON'
                                        ? Number(listing.priceTon) > availableTon
                                          ? <><Wallet className="-mt-0.5 mr-1 inline h-3 w-3" />{t('market.payWallet')}</>
                                          : <span className="text-[8px] leading-tight">{t('market.payTonBalance')}</span>
                                        : t('market.buy')}
                                </button>
                              )}
                            </div>
                          </div>
                        ))}
                      </div>

                      <div className="mt-3 flex items-center justify-between gap-2">
                        <div className="flex items-center gap-1">
                          <button onClick={() => setPage(Math.max(1, currentPage - 1))} disabled={currentPage <= 1} className="grid h-7 w-7 place-items-center rounded-lg border border-white/12 text-slate-300 disabled:opacity-30"><ChevronLeft className="h-3.5 w-3.5" /></button>
                          {pageNumbers.map((value) => (
                            <button key={value} onClick={() => setPage(value)} className={`h-7 min-w-7 rounded-lg border px-1.5 text-[9px] font-black ${value === currentPage ? 'border-amber-300/70 bg-amber-400/20 text-amber-200' : 'border-white/12 text-slate-400'}`}>{value}</button>
                          ))}
                          <button onClick={() => setPage(Math.min(totalPages, currentPage + 1))} disabled={currentPage >= totalPages} className="grid h-7 w-7 place-items-center rounded-lg border border-white/12 text-slate-300 disabled:opacity-30"><ChevronRight className="h-3.5 w-3.5" /></button>

                        </div>
                        <button onClick={() => void browse.refetch()} className="flex items-center gap-1 text-[9px] font-black uppercase tracking-[0.1em] text-slate-400">
                          <RefreshCw className={`h-3.5 w-3.5 ${browse.isFetching ? 'animate-spin' : ''}`} />{t('market.refresh')}
                        </button>
                      </div>
                    </>
                  )}
                </div>
              ) : null}


              {marketTab !== 'browse' ? (
                <button onClick={() => setMarketTab('browse')} className="mt-3 rounded-lg border border-white/12 px-2.5 py-1 text-[9px] font-black uppercase tracking-[0.1em] text-slate-300">
                  <ChevronLeft className="-mt-0.5 inline h-3 w-3" />{t('market.back')}
                </button>
              ) : null}

              {marketTab === 'mine' ? (
                <div className="mt-3 space-y-3">

                  {mine.isLoading ? <p className="text-center text-[11px] text-slate-400">{t('market.loading')}</p> : null}
                  {mine.isError ? (
                    <div className="rounded-2xl border border-rose-400/30 bg-rose-500/10 p-4 text-center">
                      <p className="text-[11px] text-rose-200">{t('market.loadError')}</p>
                      <button onClick={() => void mine.refetch()} className="mt-2 rounded-lg border border-amber-300/40 px-3 py-1.5 text-[10px] font-black text-amber-200">{t('market.retry')}</button>
                    </div>
                  ) : null}
                  {(mine.data?.listings ?? []).length ? mine.data!.listings.map((listing) => (
                    <div key={listing.id} className="flex items-center gap-2 rounded-2xl border border-white/10 bg-white/[.03] p-2">
                      {listing.image ? <img src={listing.image} alt={listing.name} className="h-10 w-10 rounded-lg object-cover" /> : <div className="grid h-10 w-10 place-items-center rounded-lg bg-black/40"><Tag className="h-4 w-4 text-slate-500" /></div>}
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[11px] font-black text-white">
                          {listing.name}{Number(listing.quantity ?? 1) > 1 ? <span className="ml-1 text-amber-200">x{listing.quantity}</span> : null}
                        </p>
                        <p className={`text-[9px] font-black ${listing.currency === 'TON' ? 'text-sky-300' : 'text-amber-300'}`}>{marketPriceLabel(listing)}</p>
                      </div>
                      <span className={`rounded-full px-2 py-0.5 text-[8px] font-black ${listing.status === 'active' ? 'bg-emerald-400/15 text-emerald-300' : listing.status === 'sold' ? 'bg-sky-400/15 text-sky-300' : 'bg-white/10 text-slate-400'}`}>
                        {listing.status === 'active' ? t('market.statusActive') : listing.status === 'sold' ? t('market.statusSold') : t('market.statusCancelled')}
                      </span>
                      {listing.status === 'active' ? (
                        <button disabled={cancelMutation.isPending} onClick={() => cancelMutation.mutate(listing.id)} className="rounded-lg border border-rose-400/40 px-2 py-1 text-[8px] font-black text-rose-200 disabled:opacity-50">{t('market.cancel')}</button>
                      ) : null}
                    </div>
                  )) : mine.isLoading ? null : <p className="text-center text-[11px] text-slate-400">{t('market.noListings')}</p>}

                  <p className="pt-2 text-[9px] uppercase tracking-[0.2em] text-slate-400">{t('market.myPurchases')}</p>
                  {(mine.data?.purchases ?? []).length ? mine.data!.purchases.map((purchase) => (
                    <div key={purchase.id} className="flex items-center gap-2 rounded-2xl border border-white/10 bg-black/30 p-2">
                      {purchase.image ? <img src={purchase.image} alt={purchase.name} className="h-9 w-9 rounded-lg object-cover" /> : <div className="grid h-9 w-9 place-items-center rounded-lg bg-black/40"><Tag className="h-4 w-4 text-slate-500" /></div>}
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[10px] font-black text-white">
                          {purchase.name}{Number(purchase.quantity ?? 1) > 1 ? <span className="ml-1 text-amber-200">x{purchase.quantity}</span> : null}
                        </p>
                        <p className="truncate text-[8px] text-slate-500">{t('market.seller')}: {purchase.seller}</p>
                      </div>
                      <p className={`text-[10px] font-black ${purchase.currency === 'TON' ? 'text-sky-300' : 'text-amber-300'}`}>{marketPriceLabel(purchase)}</p>
                    </div>
                  )) : <p className="text-center text-[10px] text-slate-500">{t('market.noPurchases')}</p>}
                </div>
              ) : null}

              {marketTab === 'sell' ? (
                <div className="mt-3">
                  <p className="text-[9px] uppercase tracking-[0.2em] text-slate-400">{t('market.chooseCategory')}</p>
                  <div className="mt-1.5 -mx-1 flex gap-1.5 overflow-x-auto px-1 pb-1">
                    {MARKET_SELL_CATEGORIES.map((value) => (
                      <button
                        key={value}
                        onClick={() => { setSellCategory(value); setSelected(null); setQuantity(1); }}
                        className={`shrink-0 rounded-lg border px-2.5 py-1.5 text-[9px] font-black uppercase tracking-[0.1em] ${sellCategory === value ? 'border-amber-300/60 bg-amber-400/15 text-amber-200' : 'border-white/10 bg-white/[.03] text-slate-400'}`}
                      >
                        {value === 'hero' ? t('market.heroes')
                          : value === 'pet' ? t('market.pets')
                          : value === 'equipment' ? t('market.equipment')
                          : value === 'fragments' ? t('market.fragments')
                          : value === 'food' ? t('market.petFood')
                          : t('market.chests')}
                      </button>
                    ))}
                  </div>

                  <p className="mt-3 text-[9px] uppercase tracking-[0.2em] text-slate-400">{t('market.chooseCurrency')}</p>
                  <div className="mt-1.5 grid grid-cols-2 gap-1.5">
                    {(['FC', 'TON'] as const).map((value) => (
                      <button
                        key={value}
                        onClick={() => { setSellCurrency(value); setPrice(''); setConfirming(false); }}
                        className={`rounded-lg border px-1 py-1.5 text-[9px] font-black uppercase ${sellCurrency === value ? (value === 'TON' ? 'border-sky-300/60 bg-sky-400/15 text-sky-200' : 'border-amber-300/60 bg-amber-400/15 text-amber-200') : 'border-white/10 bg-white/[.03] text-slate-400'}`}
                      >{value}</button>
                    ))}
                  </div>
                  {sellCurrency === 'TON' ? (
                    <p className="mt-1.5 text-[8px] leading-relaxed text-sky-200/80">{t('market.tonSaleHint')}</p>
                  ) : null}

                  {!canSell ? (
                    <div className="mt-3 flex items-start gap-2 rounded-2xl border border-amber-300/30 bg-amber-400/10 p-2.5">
                      <Lock className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-300" />
                      <p className="text-[9px] leading-relaxed text-amber-100">{t('market.sellLocked')}</p>
                    </div>
                  ) : null}

                  <p className="mt-3 text-[9px] uppercase tracking-[0.2em] text-slate-400">{t('market.chooseItem')}</p>
                  {sellable.isLoading ? <p className="mt-3 text-center text-[11px] text-slate-400">{t('market.loading')}</p> : null}
                  {!sellable.isLoading && !sellOptions.length ? <p className="mt-3 text-center text-[10px] text-slate-500">{t('market.nothingOwned')}</p> : null}
                  {!sellable.isLoading && sellOptions.length > 0 && freeOptions.length === 0 ? <p className="mt-2 text-center text-[9px] leading-relaxed text-amber-200/80">{t('market.lockedHint')}</p> : null}
                  <div className="mt-2 grid grid-cols-3 gap-1.5">
                    {sellOptions.map((option) => {
                      const active = selected?.id === option.id && selected?.code === option.code;
                      const locked = !option.available;
                      return (
                        <button
                          key={option.id ?? option.code}
                          disabled={locked}
                          title={locked ? option.locks.map(lockLabel).join(' · ') : undefined}
                          onClick={() => { if (locked) return; setSelected({ id: option.id, code: option.code, name: option.name, rarity: option.rarity, max: option.quantity, stackable: option.stackable, minPriceTon: option.minPriceTon }); setQuantity(1); setPrice(''); setConfirming(false); }}
                          className={`relative overflow-hidden rounded-xl border bg-black/40 text-left transition ${active ? 'border-amber-300 ring-2 ring-amber-300/50 scale-[1.02]' : locked ? 'border-rose-400/30' : 'border-white/10'}`}
                        >
                          <div className={locked ? 'opacity-45' : ''}>
                            {option.image ? <img src={option.image} alt={option.name} className="aspect-square w-full object-cover object-top" /> : <div className="grid aspect-square w-full place-items-center bg-white/[.03]"><Tag className="h-5 w-5 text-slate-500" /></div>}
                          </div>
                          {option.stackable && option.quantity > 1 ? (
                            <span className="absolute bottom-8 right-1 rounded bg-black/80 px-1 text-[7px] font-black text-amber-200">x{option.quantity}</span>
                          ) : null}
                          {active && !locked ? (
                            <span className="absolute right-1 top-1 rounded-md bg-amber-300 px-1 py-0.5 text-[6.5px] font-black uppercase tracking-tight text-black">✓ {t('market.selectedBadge')}</span>
                          ) : null}
                          {locked ? (
                            <div className="absolute inset-x-0 top-0 space-y-0.5 bg-gradient-to-b from-black/85 to-transparent p-1">
                              {option.locks.slice(0, 3).map((lock) => (
                                <p key={lock} className="flex items-center gap-0.5 text-[6.5px] font-black uppercase leading-tight tracking-tight text-rose-200">
                                  <Lock className="h-2 w-2 shrink-0" />{lockLabel(lock)}
                                </p>
                              ))}
                            </div>
                          ) : null}

                          <div className="p-1">
                            <p className="truncate text-[8px] font-black text-white">{option.name}</p>
                            <p className="truncate text-[7px]" style={{ color: rarityColor(option.rarity) }}>{option.detail}</p>
                            <p className={`truncate text-[6.5px] font-black uppercase tracking-tight ${locked ? 'text-rose-300' : 'text-emerald-300'}`}>
                              {locked ? t('market.inUse') : t('market.available')}
                            </p>
                          </div>
                        </button>
                      );
                    })}
                  </div>



                  {settings ? (
                    <p className="mt-3 text-center text-[8px] uppercase tracking-[0.16em] text-slate-500">
                      {t('market.activeLimit', { count: browse.data?.activeCount ?? (mine.data?.listings ?? []).filter((item) => item.status === 'active').length, max: settings.maxActiveListings })}
                    </p>
                  ) : null}
                </div>
              ) : null}
              </>)}
            </div>
          )}
        </div>

        {selected ? (
          <div className="absolute inset-0 z-40 flex items-end bg-black/75" onClick={() => { setSelected(null); setConfirming(false); }}>
            <div onClick={(event) => event.stopPropagation()} className="max-h-[88%] w-full overflow-y-auto rounded-t-[1.75rem] border-t border-amber-300/30 bg-[#0b1220] p-3 pb-5">
              <div className="mb-1 flex items-center justify-between">
                <p className="text-[10px] font-black uppercase tracking-[0.16em] text-amber-200">{t('market.sellSheetTitle')}</p>
                <button onClick={() => { setSelected(null); setConfirming(false); }} className="grid h-8 w-8 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
              </div>
                    <div className="mt-3 rounded-2xl border border-amber-300/25 bg-black/40 p-3">
                      <p className="text-[11px] font-black text-white">{selected.name}</p>

                      {/* Safe price band + recommendation — computed by the backend (median of recent settled sales). */}
                      <div className="mt-2 rounded-xl border border-sky-400/20 bg-sky-400/[.06] p-2">
                        {quote.isLoading ? (
                          <p className="text-[9px] text-slate-400">{t('market.loading')}</p>
                        ) : (
                          <>
                            <div className="flex items-center justify-between text-[9px]">
                              <span className="uppercase tracking-[0.14em] text-slate-400">{t('market.priceBand')}</span>
                              <span className="font-black text-sky-200">{amountLabel(bandMin)} – {amountLabel(bandMax)} {priceUnit}</span>
                            </div>
                            <div className="mt-1 flex items-center justify-between text-[9px]">
                              <span className="uppercase tracking-[0.14em] text-slate-400">{t('market.recommended')}</span>
                              <button onClick={() => setPrice(String(bandRecommended))} className="rounded-md border border-emerald-400/40 bg-emerald-400/10 px-1.5 py-0.5 text-[9px] font-black text-emerald-200">
                                {amountLabel(bandRecommended)} {priceUnit} · {t('market.useRecommended')}
                              </button>
                            </div>
                            <p className="mt-1 text-[8px] leading-relaxed text-slate-500">
                              {band?.source === 'median'
                                ? t('market.bandMedian', { value: formatCurrency(Number(band?.median ?? 0)), count: Number(band?.samples ?? 0) })
                                : t('market.bandConfig')}
                            </p>
                          </>
                        )}
                      </div>

                      {isStackable ? (
                        <div className="mt-2 rounded-xl border border-white/10 bg-black/40 p-2">
                          <p className="text-[9px] uppercase tracking-[0.2em] text-slate-400">{t('market.quantity')}</p>
                          <div className="mt-1 flex items-center gap-2">
                            <button
                              onClick={() => { setQuantity((value) => Math.max(1, value - 1)); setConfirming(false); }}
                              className="grid h-8 w-8 place-items-center rounded-lg border border-white/15 text-sm font-black text-slate-200"
                            >−</button>
                            <input
                              value={String(listedQuantity)}
                              onChange={(event) => { setQuantity(Math.min(maxQuantity, Math.max(1, Number(event.target.value.replace(/[^0-9]/g, '')) || 1))); setConfirming(false); }}
                              inputMode="numeric"
                              className="w-full rounded-lg border border-white/10 bg-black/50 px-3 py-1.5 text-center text-sm font-black text-amber-200 outline-none"
                            />
                            <button
                              onClick={() => { setQuantity((value) => Math.min(maxQuantity, value + 1)); setConfirming(false); }}
                              className="grid h-8 w-8 place-items-center rounded-lg border border-white/15 text-sm font-black text-slate-200"
                            >+</button>
                            <button
                              onClick={() => { setQuantity(maxQuantity); setConfirming(false); }}
                              className="shrink-0 rounded-lg border border-amber-300/40 bg-amber-400/10 px-2 py-1.5 text-[8px] font-black uppercase text-amber-200"
                            >MAX</button>
                          </div>
                          <p className="mt-1 text-[8px] text-slate-500">{t('market.quantityHint', { max: maxQuantity })}</p>
                        </div>
                      ) : null}

                      <p className="mt-2 text-[9px] uppercase tracking-[0.2em] text-slate-400">{t('market.enterPrice')}</p>
                      <input
                        value={price}
                        onChange={(event) => { setPrice(event.target.value.replace(isTonSale ? /[^0-9.]/g : /[^0-9]/g, '').slice(0, 12)); setConfirming(false); }}
                        inputMode="decimal"
                        placeholder={String(bandRecommended || minPrice)}
                        className="mt-1 w-full rounded-xl border border-white/10 bg-black/50 px-3 py-2 text-sm font-black text-amber-200 outline-none"
                      />
                      <p className="mt-1 text-[8px] text-slate-500">{t('market.minPrice', { value: `${amountLabel(bandMin)} ${priceUnit}` })}</p>
                      {isTonSale ? (
                        <p className="text-[8px] font-bold text-sky-200/80">{t('market.minTonHint', { value: tonAmount(minPriceTonForSelection) })}</p>
                      ) : null}
                      {outOfBand ? (
                        <p className="mt-1 text-[8px] font-bold text-rose-300">
                          {t('market.outOfBand', { min: `${amountLabel(bandMin)} ${priceUnit}`, max: `${amountLabel(bandMax)} ${priceUnit}` })}
                        </p>
                      ) : null}
                      <div className="mt-2 flex items-center justify-between text-[10px]">
                        <span className="text-slate-400">{t('market.fee')}</span>
                        <span className="font-black text-rose-300">{feePercent}% · {amountLabel(split.fee)} {priceUnit}</span>
                      </div>
                      <div className="flex items-center justify-between text-[10px]">
                        <span className="text-slate-400">{t('market.estimatedReceive')}</span>
                        <span className="font-black text-emerald-300">{amountLabel(split.receives)} {priceUnit}</span>
                      </div>
                      <div className="mt-1 flex items-start justify-between gap-2 text-[10px]">
                        <span className="text-slate-400">{instantSettlement ? t('market.settlementTitle') : t('market.holdTitle')}</span>
                        <span className={`text-right font-black ${instantSettlement ? 'text-emerald-300' : 'text-amber-200'}`}>
                          {instantSettlement ? t('market.settlementInstant') : `${settlementHours}h`}
                        </span>
                      </div>

                      {confirming ? (
                        <div className="mt-3 rounded-xl border border-amber-300/40 bg-amber-400/[.08] p-2.5">
                          <p className="text-[10px] font-black uppercase tracking-[0.14em] text-amber-200">{t('market.confirmSaleTitle')}</p>
                          {selectedOption ? (
                            <div className="mt-1.5 space-y-0.5 rounded-lg border border-white/10 bg-black/40 p-2 text-[9px]">
                              <div className="flex items-center justify-between"><span className="text-slate-400">{t(sellKind === 'hero' ? 'market.heroes' : sellKind === 'pet' ? 'market.pets' : 'market.itemLabel')}</span><strong className="text-white">{selectedOption.name}</strong></div>
                              <div className="flex items-center justify-between"><span className="text-slate-400">{t('heroes.rarityLabel')}</span><strong style={{ color: rarityColor(selectedOption.rarity) }}>{String(selectedOption.rarity).replace(/_/g, ' ').toUpperCase()}</strong></div>
                              <div className="flex items-center justify-between"><span className="text-slate-400">{t('shop.level')}</span><strong className="text-white">{selectedOption.level}</strong></div>
                              <div className="flex items-center justify-between"><span className="text-slate-400">{selectedOption.detail}</span><strong className={isTonSale ? 'text-sky-300' : 'text-amber-300'}>{amountLabel(split.price)} {priceUnit}</strong></div>
                            </div>
                          ) : null}
                          <p className="mt-1 text-[9px] leading-relaxed text-slate-300">
                            {t(!instantSettlement ? 'market.confirmSaleBody' : isTonSale ? 'market.confirmSaleBodyTon' : 'market.confirmSaleBodyInstant', {
                              name: selected.name,
                              price: `${amountLabel(split.price)} ${priceUnit}`,
                              receives: `${amountLabel(split.receives)} ${priceUnit}`,
                              hours: settlementHours,
                            })}
                          </p>
                          <div className="mt-2 grid grid-cols-2 gap-2">
                            <button
                              disabled={listMutation.isPending}
                              onClick={() => listMutation.mutate()}
                              className="rounded-lg border border-emerald-400/50 bg-emerald-400/15 py-2 text-[9px] font-black uppercase tracking-[0.14em] text-emerald-200 disabled:opacity-40"
                            >{t('market.confirm')}</button>
                            <button
                              onClick={() => setConfirming(false)}
                              className="rounded-lg border border-white/15 py-2 text-[9px] font-black uppercase tracking-[0.14em] text-slate-300"
                            >{t('market.cancel')}</button>
                          </div>
                        </div>
                      ) : (
                        <button
                          disabled={listMutation.isPending || !canSell || split.price < bandMin || split.price > bandMax}
                          onClick={() => setConfirming(true)}
                          className="mt-3 w-full rounded-xl border border-amber-300/50 bg-gradient-to-b from-amber-400/25 to-orange-600/10 py-2 text-[10px] font-black uppercase tracking-[0.18em] text-amber-100 disabled:opacity-40"
                        >{t('market.list')}</button>
                      )}
                    </div>
            </div>
          </div>
        ) : null}

        {tonPrompt ? (
          <div className="absolute inset-0 z-30 grid place-items-center bg-black/80 p-4">
            <div className="w-full max-w-[330px] rounded-2xl border border-sky-300/35 bg-[#0b1220] p-4">
              <p className="text-[11px] font-black uppercase tracking-[0.16em] text-sky-200">
                {wallet ? t('market.insufficientTonTitle') : t('market.walletRequiredTitle')}
              </p>
              {wallet ? null : (
                <p className="mt-2 text-[9px] leading-relaxed text-slate-300">{t('market.walletRequiredText')}</p>
              )}
              <div className="mt-3 space-y-1.5 rounded-xl border border-white/10 bg-black/40 p-2.5 text-[10px]">
                <div className="flex items-center justify-between"><span className="text-slate-400">{t('market.priceLabel')}</span><strong className="text-sky-300">{tonAmount(tonPrompt.price)} TON</strong></div>
                <div className="flex items-center justify-between"><span className="text-slate-400">{t('market.availableLabel')}</span><strong className="text-slate-200">{tonAmount(availableTon)} TON</strong></div>
              </div>
              <p className="mt-2 text-[8px] leading-relaxed text-slate-500">{t('market.noSplitPayment')}</p>
              <div className="mt-3 grid gap-2">
                {wallet ? (
                  <button
                    disabled={buyMutation.isPending}
                    onClick={() => buyMutation.mutate(tonPrompt.id)}
                    className="rounded-xl border border-sky-300/50 bg-sky-400/15 py-2 text-[9px] font-black uppercase tracking-[0.14em] text-sky-100 disabled:opacity-40"
                  >
                    <Wallet className="-mt-0.5 mr-1 inline h-3 w-3" />
                    {t('market.payFullWallet', { amount: tonAmount(tonPrompt.price) })}
                  </button>
                ) : (
                  <button
                    onClick={() => { void tonUI.openModal(); }}
                    className="rounded-xl border border-sky-300/50 bg-sky-400/15 py-2 text-[9px] font-black uppercase tracking-[0.14em] text-sky-100"
                  >{t('market.connectWalletCta')}</button>
                )}
                <button
                  disabled={buyMutation.isPending}
                  onClick={() => setTonPrompt(null)}
                  className="rounded-xl border border-white/15 py-2 text-[9px] font-black uppercase tracking-[0.14em] text-slate-300 disabled:opacity-40"
                >{t('market.cancel')}</button>
              </div>
            </div>
          </div>
        ) : null}

        {/* Premium read-only preview. Purchase flow, prices and fees stay unchanged. */}
        {detailsId ? (
          <ItemDetailsModal
            telegramInitData={telegramInitData}
            source="market"
            id={detailsId}
            onClose={() => setDetailsId(null)}
            onBuy={(id) => { setDetailsId(null); startPurchase(id); }}
            buyLabel={t('market.buy')}
            buyDisabled={buyMutation.isPending}
          />
        ) : null}

      </div>
    </div>


      {/* Fullscreen exclusive mode: portals to body, shop above stays display:none. */}
      {rouletteOpen ? (
        <RouletteOverlay telegramInitData={telegramInitData} onClose={() => setRouletteOpen(false)} />
      ) : null}
    </>
  );
}

