import { useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { X, Store, Swords, Tag, Info, ChevronDown, ChevronLeft, ChevronRight, ShoppingCart, RefreshCw } from 'lucide-react';
import altarImage from '../assets/recruit-altar.jpg';
import { useT } from '../LanguageContext';
import { formatCurrency } from '../utils';
import { RARITY_COLORS, type HeroRarity, type ShopHero } from '../heroCatalog';
import { useMarketBrowse, useMarketMine, useMarketRealtime, useMarketSellable, useMarketStatus } from '../hooks';
import { buyMarketListing, cancelMarketListing, createMarketListing } from '../services';
import { marketFeeSplit, type MarketItemType, type MarketSort } from '../market';

type Props = {
  telegramInitData: string | null;
  fcBalance: number;
  summonOdds: Array<{ rarity: HeroRarity; chance: number }>;
  recruitPrice: (count: number) => number;
  shopResults: ShopHero[];
  onRecruit: (count: 1 | 5 | 10) => void;
  onClose: () => void;
};

const RARITY_FILTERS = ['all', 'common', 'uncommon', 'rare', 'epic', 'legendary'] as const;
const rarityColor = (rarity: string) => RARITY_COLORS[(rarity as HeroRarity)] ?? '#94a3b8';

/** Marketplace is FC-only by design: there is no TON/crypto path in this screen. */
export function HeroShopPanel({ telegramInitData, fcBalance, summonOdds, recruitPrice, shopResults, onRecruit, onClose }: Props) {
  const t = useT();
  const queryClient = useQueryClient();
  const [tab, setTab] = useState<'recruit' | 'market'>('recruit');
  const [marketTab, setMarketTab] = useState<'browse' | 'mine' | 'sell'>('browse');
  const [itemType, setItemType] = useState<MarketItemType | 'all'>('all');
  const [rarity, setRarity] = useState<string>('all');
  const [sort, setSort] = useState<MarketSort>('newest');
  const [sellKind, setSellKind] = useState<MarketItemType>('hero');
  const [selected, setSelected] = useState<{ id?: string; code?: string; name: string } | null>(null);
  const [price, setPrice] = useState('');
  const [sortOpen, setSortOpen] = useState(false);
  const [page, setPage] = useState(1);

  // Maintenance switch and the admin bypass are decided by the backend only.
  const status = useMarketStatus(telegramInitData, tab === 'market');
  const marketAccess = status.data?.canAccess ?? false;
  const marketOpen = tab === 'market' && marketAccess;
  useMarketRealtime(marketOpen);
  const browse = useMarketBrowse(telegramInitData, marketOpen && marketTab === 'browse', itemType, rarity, sort);
  const mine = useMarketMine(telegramInitData, marketOpen && marketTab === 'mine');
  const sellable = useMarketSellable(telegramInitData, marketOpen && marketTab === 'sell');

  const settings = browse.data?.settings ?? mine.data?.settings ?? sellable.data?.settings;
  const feePercent = Number(settings?.feePercent ?? 5);
  const minPrice = Number(settings?.minPrice?.[sellKind] ?? 5000);
  const split = useMemo(() => marketFeeSplit(Number(price) || 0, feePercent), [price, feePercent]);

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
    ]);
  };

  const buyMutation = useMutation({
    mutationFn: (listingId: string) => buyMarketListing(telegramInitData ?? '', listingId),
    onSuccess: async (result) => { toast.success(`${result.name} · -${formatCurrency(result.pricePaid)} FC`); await refreshAll(); },
    onError: (error) => toast.error(error instanceof Error ? error.message : t('market.loadError')),
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
      priceFc: Math.trunc(Number(price) || 0),
    }),
    onSuccess: async (result) => {
      toast.success(`${t('market.youReceive')}: ${formatCurrency(result.sellerReceives)} FC`);
      setSelected(null); setPrice(''); setMarketTab('mine');
      await refreshAll();
    },
    onError: (error) => toast.error(error instanceof Error ? error.message : t('market.loadError')),
  });

  const chipClass = (active: boolean) =>
    `rounded-full border px-2.5 py-1 text-[9px] font-black uppercase tracking-[0.12em] transition ${active ? 'border-amber-300/70 bg-amber-400/20 text-amber-200' : 'border-white/10 bg-white/[.03] text-slate-400'}`;

  type SellOption = { id?: string; code?: string; name: string; rarity: string; level: number; image: string | null; detail: string };
  const sellOptions: SellOption[] = sellKind === 'hero'
    ? (sellable.data?.heroes ?? []).map((hero) => ({ id: hero.id, name: hero.name, rarity: hero.rarity, level: hero.level, image: hero.image, detail: `ATK ${formatCurrency(hero.atk)} · HP ${formatCurrency(hero.hp)}` }))
    : sellKind === 'pet'
      ? (sellable.data?.pets ?? []).map((pet) => ({ id: pet.id, name: pet.name, rarity: pet.rarity, level: pet.level, image: pet.image, detail: String(pet.evolution ?? '').toUpperCase() }))
      : (sellable.data?.items ?? []).map((item) => ({ code: item.code, name: item.code.replace(/_/g, ' ').toUpperCase(), rarity: 'rare', level: 1, image: null, detail: `x${item.quantity}` }));


  return (
    <div className="fullscreen-page flex items-center justify-center p-3">
      <div className="flex max-h-[92dvh] w-full max-w-[450px] flex-col overflow-hidden rounded-[2rem] border border-amber-300/25 bg-[#090d15] shadow-2xl">
        <div className="flex items-center justify-between px-4 pt-4">
          <div>
            <p className="text-[9px] uppercase tracking-[0.3em] text-amber-300">MYTHREON</p>
            <h2 className="text-lg font-black leading-tight text-white">{t('shop')}</h2>
          </div>
          <div className="flex items-center gap-2">
            <span className="rounded-full border border-amber-300/25 bg-black/40 px-2.5 py-1 text-[10px] font-black text-amber-300">{formatCurrency(fcBalance)} FC</span>
            <button onClick={onClose} className="grid h-9 w-9 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
          </div>
        </div>

        <div className="mt-3 grid grid-cols-2 gap-2 px-4">
          <button onClick={() => setTab('recruit')} className={`flex items-center justify-center gap-1 rounded-xl border px-2 py-2 text-[10px] font-black uppercase tracking-[0.16em] ${tab === 'recruit' ? 'border-amber-300/60 bg-amber-400/15 text-amber-200' : 'border-white/10 bg-white/[.03] text-slate-400'}`}>
            <Swords className="h-3.5 w-3.5" />{t('market.tabRecruit')}
          </button>
          <button onClick={() => setTab('market')} className={`flex items-center justify-center gap-1 rounded-xl border px-2 py-2 text-[10px] font-black uppercase tracking-[0.16em] ${tab === 'market' ? 'border-amber-300/60 bg-amber-400/15 text-amber-200' : 'border-white/10 bg-white/[.03] text-slate-400'}`}>
            <Store className="h-3.5 w-3.5" />{t('market.tabMarket')}
          </button>
        </div>

        <div className="mt-3 flex-1 overflow-y-auto px-4 pb-4">
          {tab === 'recruit' ? (
            <div>
              <div className="rounded-2xl border border-amber-300/20 bg-black/30 p-3 text-center">
                <p className="text-[13px] font-black tracking-[0.06em] text-amber-300">{t('market.recruitTitle')}</p>
                <p className="mt-0.5 text-[8px] uppercase tracking-[0.2em] text-slate-400">{t('market.recruitSubtitle')}</p>
                <div className="mt-3 rounded-xl border border-white/10 bg-white/[.02] p-2">
                  <p className="text-[9px] font-black uppercase tracking-[0.2em] text-slate-300">{t('market.summonOdds')}</p>
                  <div className="mt-1.5 grid grid-cols-5 gap-1">
                    {summonOdds.slice().reverse().map((entry) => (
                      <div key={entry.rarity} className="text-center">
                        <p className="truncate text-[7px] font-bold uppercase" style={{ color: RARITY_COLORS[entry.rarity] }}>{t(entry.rarity)}</p>
                        <p className="text-[12px] font-black text-white">{entry.chance}%</p>
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
                  <button key={count} onClick={() => onRecruit(count)} className="rounded-2xl border border-amber-300/25 bg-gradient-to-b from-white/[.06] to-black/40 px-1 py-3 text-center active:scale-95">
                    <span className="block text-xl font-black text-white">{count}×</span>
                    <span className="mt-0.5 block text-[8px] font-black text-amber-300">{formatCurrency(recruitPrice(count))} FC</span>
                  </button>
                ))}
              </div>

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
                        <img src={hero.image} alt={hero.name} className="aspect-square w-full object-cover" />
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
                  <button onClick={() => setTab('recruit')} className="rounded-lg border border-white/15 px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.12em] text-slate-300">
                    {t('market.tabRecruit')}
                  </button>
                </div>
              </div>
            </div>
          ) : (
            <div>
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
                      <p className="text-[11px] text-rose-200">{browse.error instanceof Error ? browse.error.message : t('market.loadError')}</p>
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
                            {listing.image ? (
                              <img src={listing.image} alt={listing.name} className="h-16 w-16 shrink-0 rounded-xl border-2 object-cover" style={{ borderColor: rarityColor(listing.rarity) }} />
                            ) : (
                              <div className="grid h-16 w-16 shrink-0 place-items-center rounded-xl border-2 bg-white/[.03]" style={{ borderColor: rarityColor(listing.rarity) }}><Tag className="h-5 w-5 text-slate-500" /></div>
                            )}
                            <div className="min-w-0 flex-1">
                              <p className="truncate text-[11px] font-black" style={{ color: rarityColor(listing.rarity) }}>{listing.name}</p>
                              <p className="truncate text-[8px] font-bold uppercase tracking-[0.08em] text-slate-400">
                                {t(listing.rarity)} · Lv. {listing.level}
                              </p>
                              {listing.itemType === 'hero' ? (
                                <p className="truncate text-[8px] text-slate-300">ATK {formatCurrency(listing.atk)} · HP {formatCurrency(listing.hp)}</p>
                              ) : null}
                              <p className="truncate text-[7px] uppercase tracking-[0.14em] text-slate-500">
                                {listing.itemType === 'hero' ? t('market.heroes') : listing.itemType === 'pet' ? t('market.pets') : t('market.equipment')}
                              </p>
                              <p className="truncate text-[8px] text-slate-500">{t('market.seller')} <span className="text-slate-300">{listing.seller}</span></p>
                            </div>
                            <div className="flex w-[86px] shrink-0 flex-col items-end gap-1">
                              <p className="text-right text-[11px] font-black leading-tight text-amber-300">{formatCurrency(listing.priceFc)} FC</p>
                              {listing.mine ? (
                                <span className="w-full rounded-lg border border-white/10 py-1 text-center text-[8px] font-black text-slate-400">{t('market.own')}</span>
                              ) : (
                                <button
                                  disabled={buyMutation.isPending}
                                  onClick={() => buyMutation.mutate(listing.id)}
                                  className="w-full rounded-lg border border-amber-300/50 bg-amber-400/15 py-1.5 text-[9px] font-black uppercase tracking-[0.12em] text-amber-200 disabled:opacity-50"
                                >{t('market.buy')}</button>
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
                      <p className="text-[11px] text-rose-200">{mine.error instanceof Error ? mine.error.message : t('market.loadError')}</p>
                      <button onClick={() => void mine.refetch()} className="mt-2 rounded-lg border border-amber-300/40 px-3 py-1.5 text-[10px] font-black text-amber-200">{t('market.retry')}</button>
                    </div>
                  ) : null}
                  {(mine.data?.listings ?? []).length ? mine.data!.listings.map((listing) => (
                    <div key={listing.id} className="flex items-center gap-2 rounded-2xl border border-white/10 bg-white/[.03] p-2">
                      {listing.image ? <img src={listing.image} alt={listing.name} className="h-10 w-10 rounded-lg object-cover" /> : <div className="grid h-10 w-10 place-items-center rounded-lg bg-black/40"><Tag className="h-4 w-4 text-slate-500" /></div>}
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[11px] font-black text-white">{listing.name}</p>
                        <p className="text-[9px] font-black text-amber-300">{formatCurrency(listing.priceFc)} FC</p>
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
                        <p className="truncate text-[10px] font-black text-white">{purchase.name}</p>
                        <p className="truncate text-[8px] text-slate-500">{t('market.seller')}: {purchase.seller}</p>
                      </div>
                      <p className="text-[10px] font-black text-amber-300">{formatCurrency(purchase.priceFc)} FC</p>
                    </div>
                  )) : <p className="text-center text-[10px] text-slate-500">{t('market.noPurchases')}</p>}
                </div>
              ) : null}

              {marketTab === 'sell' ? (
                <div className="mt-3">
                  <p className="text-[9px] uppercase tracking-[0.2em] text-slate-400">{t('market.chooseCategory')}</p>
                  <div className="mt-1.5 grid grid-cols-3 gap-1.5">
                    {(['hero', 'pet', 'item'] as const).map((value) => (
                      <button key={value} onClick={() => { setSellKind(value); setSelected(null); }} className={`rounded-lg border px-1 py-1.5 text-[9px] font-black uppercase ${sellKind === value ? 'border-amber-300/60 bg-amber-400/15 text-amber-200' : 'border-white/10 bg-white/[.03] text-slate-400'}`}>
                        {value === 'hero' ? t('market.heroes') : value === 'pet' ? t('market.pets') : t('market.equipment')}
                      </button>
                    ))}
                  </div>

                  <p className="mt-3 text-[9px] uppercase tracking-[0.2em] text-slate-400">{t('market.chooseItem')}</p>
                  {sellable.isLoading ? <p className="mt-3 text-center text-[11px] text-slate-400">{t('market.loading')}</p> : null}
                  {!sellable.isLoading && !sellOptions.length ? <p className="mt-3 text-center text-[10px] text-slate-500">{t('market.nothingToSell')}</p> : null}
                  <div className="mt-2 grid grid-cols-3 gap-1.5">
                    {sellOptions.map((option) => {
                      const active = selected?.id === option.id && selected?.code === option.code;
                      return (
                        <button
                          key={option.id ?? option.code}
                          onClick={() => setSelected({ id: option.id, code: option.code, name: option.name })}
                          className={`overflow-hidden rounded-xl border bg-black/40 text-left ${active ? 'border-amber-300' : 'border-white/10'}`}
                        >
                          {option.image ? <img src={option.image} alt={option.name} className="aspect-square w-full object-cover" /> : <div className="grid aspect-square w-full place-items-center bg-white/[.03]"><Tag className="h-5 w-5 text-slate-500" /></div>}
                          <div className="p-1">
                            <p className="truncate text-[8px] font-black text-white">{option.name}</p>
                            <p className="truncate text-[7px]" style={{ color: rarityColor(option.rarity) }}>{option.detail}</p>
                          </div>
                        </button>
                      );
                    })}
                  </div>

                  {selected ? (
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
                              <span className="font-black text-sky-200">{formatCurrency(bandMin)} – {formatCurrency(bandMax)} FC</span>
                            </div>
                            <div className="mt-1 flex items-center justify-between text-[9px]">
                              <span className="uppercase tracking-[0.14em] text-slate-400">{t('market.recommended')}</span>
                              <button onClick={() => setPrice(String(bandRecommended))} className="rounded-md border border-emerald-400/40 bg-emerald-400/10 px-1.5 py-0.5 text-[9px] font-black text-emerald-200">
                                {formatCurrency(bandRecommended)} FC · {t('market.useRecommended')}
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

                      <p className="mt-2 text-[9px] uppercase tracking-[0.2em] text-slate-400">{t('market.enterPrice')}</p>
                      <input
                        value={price}
                        onChange={(event) => { setPrice(event.target.value.replace(/[^0-9]/g, '').slice(0, 12)); setConfirming(false); }}
                        inputMode="numeric"
                        placeholder={String(bandRecommended || minPrice)}
                        className="mt-1 w-full rounded-xl border border-white/10 bg-black/50 px-3 py-2 text-sm font-black text-amber-200 outline-none"
                      />
                      <p className="mt-1 text-[8px] text-slate-500">{t('market.minPrice', { value: formatCurrency(bandMin) })}</p>
                      {outOfBand ? (
                        <p className="mt-1 text-[8px] font-bold text-rose-300">
                          {t('market.outOfBand', { min: formatCurrency(bandMin), max: formatCurrency(bandMax) })}
                        </p>
                      ) : null}
                      <div className="mt-2 flex items-center justify-between text-[10px]">
                        <span className="text-slate-400">{t('market.fee')}</span>
                        <span className="font-black text-rose-300">{feePercent}% · {formatCurrency(split.fee)} FC</span>
                      </div>
                      <div className="flex items-center justify-between text-[10px]">
                        <span className="text-slate-400">{t('market.youReceive')}</span>
                        <span className="font-black text-emerald-300">{formatCurrency(split.receives)} FC</span>
                      </div>
                      <div className="mt-1 flex items-center justify-between text-[10px]">
                        <span className="text-slate-400">{t('market.holdTitle')}</span>
                        <span className="font-black text-amber-200">{settlementHours}h</span>
                      </div>

                      {confirming ? (
                        <div className="mt-3 rounded-xl border border-amber-300/40 bg-amber-400/[.08] p-2.5">
                          <p className="text-[10px] font-black uppercase tracking-[0.14em] text-amber-200">{t('market.confirmSaleTitle')}</p>
                          <p className="mt-1 text-[9px] leading-relaxed text-slate-300">
                            {t('market.confirmSaleBody', {
                              name: selected.name,
                              price: formatCurrency(split.price),
                              receives: formatCurrency(split.receives),
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
                          disabled={listMutation.isPending || split.price < bandMin || split.price > bandMax}
                          onClick={() => setConfirming(true)}
                          className="mt-3 w-full rounded-xl border border-amber-300/50 bg-gradient-to-b from-amber-400/25 to-orange-600/10 py-2 text-[10px] font-black uppercase tracking-[0.18em] text-amber-100 disabled:opacity-40"
                        >{t('market.list')}</button>
                      )}
                    </div>
                  ) : null}


                  {settings ? (
                    <p className="mt-3 text-center text-[8px] uppercase tracking-[0.16em] text-slate-500">
                      {t('market.activeLimit', { count: browse.data?.activeCount ?? (mine.data?.listings ?? []).filter((item) => item.status === 'active').length, max: settings.maxActiveListings })}
                    </p>
                  ) : null}
                </div>
              ) : null}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
