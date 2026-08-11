import { useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { X, Store, Swords, Tag, Info, ChevronDown, ChevronLeft, ChevronRight, ShoppingCart, RefreshCw } from 'lucide-react';
import altarImage from '../assets/recruit-altar.jpg';
import { useT } from '../LanguageContext';
import { formatCurrency } from '../utils';
import { RARITY_COLORS, type HeroRarity, type ShopHero } from '../heroCatalog';
import { useMarketBrowse, useMarketMine, useMarketRealtime, useMarketSellable } from '../hooks';
import { buyMarketListing, cancelMarketListing, createMarketListing } from '../services';
import { marketFeeSplit, type MarketItemType, type MarketSort } from '../market';

type Props = {
  telegramInitData: string | null;
  fcBalance: number | null;
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

  const marketUnderMaintenance = true;
  const marketOpen = tab === 'market' && !marketUnderMaintenance;
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
            <span className="rounded-full border border-amber-300/25 bg-black/40 px-2.5 py-1 text-[10px] font-black text-amber-300">{fcBalance === null ? '---' : formatCurrency(fcBalance)} FC</span>
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

          ) : (
            <div className="flex flex-1 flex-col items-center justify-center text-center">
              <div className="rounded-2xl border border-amber-300/20 bg-amber-400/10 p-6">
                <Store className="mx-auto h-10 w-10 text-amber-300 opacity-60" />
                <p className="mt-3 text-sm font-black uppercase tracking-[0.12em] text-amber-200">{t('market.maintenance')}</p>
                <p className="mt-1 text-[10px] text-slate-400">{t('market.maintenanceMessage')}</p>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
