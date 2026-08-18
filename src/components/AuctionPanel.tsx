import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { Gavel, Gem, Clock, Flame, Crown, Lock, RefreshCw, ChevronRight, X } from 'lucide-react';
import { useT } from '../LanguageContext';
import { RARITY_COLORS, type HeroRarity } from '../heroCatalog';
import { auctionCountdown, auctionTon, type AuctionBrowse, type AuctionCard, type AuctionMine, type AuctionSellable, type AuctionSellableItem } from '../auction';
import { cancelAuction, createAuction, fetchAuctionBrowse, fetchAuctionMine, fetchAuctionSellable, placeAuctionBid } from '../services';
import { effectiveDailyMining, formatMiningAmount, miningSymbol, useMiningConfig } from '../miningCurrency';

type Props = { telegramInitData: string | null; onOpenWallet?: () => void };

const rarityColor = (rarity: string) => RARITY_COLORS[(rarity as HeroRarity)] ?? '#94a3b8';
const chip = (active: boolean) =>
  `rounded-full border px-2.5 py-1 text-[9px] font-black uppercase tracking-[0.1em] ${active ? 'border-sky-300/70 bg-sky-400/20 text-sky-100' : 'border-white/10 bg-white/[.03] text-slate-300'}`;

/**
 * AUCTION — 100% internal TON. Bidding never opens TonConnect and never touches FC:
 * the backend reserves the player's available TON and releases it when outbid.
 * Every number here comes from the server (min next bid, fee, countdown, reserves).
 */
export function AuctionPanel({ telegramInitData, onOpenWallet }: Props) {
  const mining = useMiningConfig();
  const t = useT();
  const queryClient = useQueryClient();
  const [view, setView] = useState<'browse' | 'mine' | 'sell'>('browse');
  const [itemType, setItemType] = useState<'all' | 'hero' | 'pet' | 'equipment'>('all');
  const [sort, setSort] = useState<'ending' | 'newest' | 'price_low' | 'price_high'>('ending');
  const [bidding, setBidding] = useState<AuctionCard | null>(null);
  const [bidValue, setBidValue] = useState('');
  const [sellItem, setSellItem] = useState<AuctionSellableItem | null>(null);
  const [startBid, setStartBid] = useState('');
  const [duration, setDuration] = useState(24);
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  const enabled = Boolean(telegramInitData);
  const browse = useQuery<AuctionBrowse>({
    queryKey: ['auction-browse', itemType, sort],
    enabled: enabled && view === 'browse',
    refetchInterval: 15000,
    queryFn: () => fetchAuctionBrowse(telegramInitData as string, itemType, sort),
  });
  const mine = useQuery<AuctionMine>({
    queryKey: ['auction-mine'],
    enabled: enabled && view === 'mine',
    refetchInterval: 20000,
    queryFn: () => fetchAuctionMine(telegramInitData as string),
  });
  const sellable = useQuery<AuctionSellable>({
    queryKey: ['auction-sellable'],
    enabled: enabled && view === 'sell',
    queryFn: () => fetchAuctionSellable(telegramInitData as string),
  });

  const settings = browse.data?.settings ?? mine.data?.settings ?? sellable.data?.settings ?? null;
  const availableTon = browse.data?.availableTon ?? mine.data?.availableTon ?? sellable.data?.availableTon ?? 0;
  const reservedTon = browse.data?.reservedTon ?? mine.data?.reservedTon ?? 0;

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ['auction-browse'] });
    void queryClient.invalidateQueries({ queryKey: ['auction-mine'] });
    void queryClient.invalidateQueries({ queryKey: ['auction-sellable'] });
    void queryClient.invalidateQueries({ queryKey: ['ton-wallet'] });
  };

  const bidMutation = useMutation({
    mutationFn: ({ id, amount }: { id: string; amount: number }) =>
      placeAuctionBid(telegramInitData as string, id, amount, `bid:${id}:${amount}:${Date.now()}`),
    onSuccess: () => { toast.success(t('auction.bidPlaced')); setBidding(null); setBidValue(''); invalidate(); },
    onError: (error: Error) => toast.error(error.message),
  });

  const createMutation = useMutation({
    mutationFn: (input: { itemType: string; itemInstanceId: string; startingBidTon: number; durationHours: number }) =>
      createAuction(telegramInitData as string, input),
    onSuccess: () => { toast.success(t('auction.created')); setSellItem(null); setStartBid(''); invalidate(); setView('mine'); },
    onError: (error: Error) => toast.error(error.message),
  });

  const cancelMutation = useMutation({
    mutationFn: (id: string) => cancelAuction(telegramInitData as string, id),
    onSuccess: () => { toast.success(t('auction.cancelled')); invalidate(); },
    onError: (error: Error) => toast.error(error.message),
  });

  const sellOptions = useMemo(() => {
    const data = sellable.data;
    if (!data) return [] as AuctionSellableItem[];
    return [...(data.heroes ?? []), ...(data.pets ?? []), ...(data.equipment ?? [])];
  }, [sellable.data]);

  const feePercent = settings?.feePercent ?? 5;
  const minStart = settings?.minStartingBidTon ?? 0.1;
  const durations = settings?.durations?.length ? settings.durations : [6, 12, 24, 48];
  const startNumber = Number(startBid.replace(',', '.'));
  const receives = Number.isFinite(startNumber) && startNumber > 0
    ? Math.round(startNumber * (1 - feePercent / 100) * 1e6) / 1e6
    : 0;
  const bidNumber = Number(bidValue.replace(',', '.'));
  const bidShort = bidding && Number.isFinite(bidNumber) ? bidNumber > availableTon : false;

  if (settings && settings.enabled === false && !(browse.data?.adminBypass ?? false)) {
    return (
      <div className="mt-6 rounded-2xl border border-sky-300/20 bg-black/30 p-5 text-center">
        <Gavel className="mx-auto h-6 w-6 text-sky-300" />
        <p className="mt-2 text-[11px] font-black uppercase tracking-[0.14em] text-slate-200">{t('auction.disabled')}</p>
      </div>
    );
  }

  return (
    <div>
      {browse.data?.adminBypass && settings?.enabled === false ? (
        <div className="mb-2 rounded-xl border border-fuchsia-400/30 bg-fuchsia-500/10 px-2.5 py-1.5">
          <p className="text-[8px] font-black uppercase tracking-[0.14em] text-fuchsia-200">{t('auction.adminTest')}</p>
        </div>
      ) : null}

      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="flex items-center gap-1.5 text-sm font-black text-white"><Gavel className="h-3.5 w-3.5 text-sky-300" />{t('auction.title')}</p>
          <p className="text-[9px] text-slate-400">{t('auction.subtitle')}</p>
        </div>
        <span className="shrink-0 rounded-full border border-sky-300/40 bg-sky-500/10 px-2 py-1 text-[8px] font-black uppercase tracking-[0.14em] text-sky-200">{t('auction.tonOnly')}</span>
      </div>

      {/* Internal TON wallet strip: the only currency accepted in the auction. */}
      <div className="mt-2 grid grid-cols-2 gap-2">
        <div className="rounded-xl border border-sky-300/20 bg-sky-500/[.06] px-2.5 py-1.5">
          <p className="text-[7px] font-black uppercase tracking-[0.18em] text-slate-400">{t('auction.availableTon')}</p>
          <p className="flex items-center gap-1 text-[13px] font-black text-sky-200"><Gem className="h-3 w-3" />{auctionTon(availableTon)}</p>
        </div>
        <div className="rounded-xl border border-white/10 bg-white/[.03] px-2.5 py-1.5">
          <p className="text-[7px] font-black uppercase tracking-[0.18em] text-slate-400">{t('auction.reservedTon')}</p>
          <p className="flex items-center gap-1 text-[13px] font-black text-slate-200"><Lock className="h-3 w-3" />{auctionTon(reservedTon)}</p>
        </div>
      </div>

      <div className="mt-3 grid grid-cols-3 gap-1.5">
        {([['browse', t('auction.tabBrowse')], ['mine', t('auction.tabMine')], ['sell', t('auction.tabCreate')]] as const).map(([key, label]) => (
          <button
            key={key}
            type="button"
            onClick={() => setView(key)}
            className={`rounded-xl px-1 py-2 text-[9px] font-black uppercase tracking-[.1em] ${view === key ? 'bg-gradient-to-b from-sky-300 to-cyan-500 text-black' : 'border border-white/10 bg-white/[.03] text-slate-300'}`}
          >
            {label}
          </button>
        ))}
      </div>

      {view === 'browse' ? (
        <div className="mt-3">
          <div className="-mx-1 flex gap-1 overflow-x-auto px-1 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            {(['all', 'hero', 'pet', 'equipment'] as const).map((value) => (
              <button key={value} onClick={() => setItemType(value)} className={`${chip(itemType === value)} shrink-0`}>
                {value === 'all' ? t('market.all') : value === 'hero' ? t('market.heroes') : value === 'pet' ? t('market.pets') : t('market.equipment')}
              </button>
            ))}
            <span className="mx-1 w-px shrink-0 bg-white/10" />
            {(['ending', 'price_low', 'price_high', 'newest'] as const).map((value) => (
              <button key={value} onClick={() => setSort(value)} className={`${chip(sort === value)} shrink-0`}>
                {value === 'ending' ? t('auction.endsIn') : value === 'newest' ? t('market.sortNewest') : value === 'price_low' ? t('market.sortPriceLow') : t('market.sortPriceHigh')}
              </button>
            ))}
          </div>

          {settings?.antiSnipeEnabled ? (
            <p className="mt-2 flex items-center gap-1 text-[8px] uppercase tracking-[0.12em] text-slate-500">
              <Flame className="h-3 w-3 text-orange-300" />
              {t('auction.antiSnipe')
                .replace('{window}', String(settings.antiSnipeWindowMinutes ?? 5))
                .replace('{extension}', String(settings.antiSnipeExtensionMinutes ?? 5))}
            </p>
          ) : null}

          {browse.isLoading ? (
            <p className="mt-6 text-center text-[10px] uppercase tracking-[0.2em] text-slate-500">…</p>
          ) : (browse.data?.auctions.length ?? 0) === 0 ? (
            <div className="mt-6 rounded-2xl border border-white/10 bg-black/30 p-5 text-center">
              <p className="text-[10px] uppercase tracking-[0.16em] text-slate-400">{t('auction.empty')}</p>
              <button onClick={() => void browse.refetch()} className="mt-3 rounded-lg border border-sky-300/40 px-3 py-1.5 text-[9px] font-black uppercase tracking-[0.12em] text-sky-200">
                <RefreshCw className="-mt-0.5 mr-1 inline h-3 w-3" />{t('market.retry')}
              </button>
            </div>
          ) : (
            <div className="mt-3 grid grid-cols-2 gap-2">
              {browse.data?.auctions.map((item) => (
                <div key={item.id} className="overflow-hidden rounded-2xl border bg-black/40" style={{ borderColor: `${rarityColor(item.rarity)}55` }}>
                  <div className="relative aspect-square w-full overflow-hidden bg-black/60">
                    {item.image ? <img src={item.image} alt={item.name} className="h-full w-full object-cover object-top" loading="lazy" /> : null}
                    <span className="absolute left-1.5 top-1.5 rounded-full border border-black/40 px-1.5 py-0.5 text-[7px] font-black uppercase tracking-[0.1em] text-black" style={{ background: rarityColor(item.rarity) }}>
                      {item.rarity === 'nft_exclusive' ? 'NFT' : item.rarity}
                    </span>
                    {item.iAmHighest ? (
                      <span className="absolute right-1.5 top-1.5 flex items-center gap-0.5 rounded-full bg-emerald-400 px-1.5 py-0.5 text-[7px] font-black uppercase text-black"><Crown className="h-2.5 w-2.5" />{t('auction.highest')}</span>
                    ) : item.myBidTon ? (
                      <span className="absolute right-1.5 top-1.5 rounded-full bg-rose-500 px-1.5 py-0.5 text-[7px] font-black uppercase text-white">{t('auction.outbid')}</span>
                    ) : null}
                    <span className="absolute bottom-1.5 left-1.5 flex items-center gap-1 rounded-full bg-black/70 px-1.5 py-0.5 text-[8px] font-black text-amber-200">
                      <Clock className="h-2.5 w-2.5" />{auctionCountdown(item.endsAt, now)}
                    </span>
                  </div>
                  <div className="p-2">
                    <p className="truncate text-[11px] font-black text-white">{item.name}</p>
                    <p className="text-[8px] uppercase tracking-[0.1em] text-slate-500">
                      {t('auction.seller')}: {item.seller} · {item.bidCount} {t('auction.bids')}
                    </p>
                    {item.dailyYield > 0 ? (
                      <p className="mt-0.5 text-[8px] font-black uppercase tracking-[0.1em] text-emerald-300">{t('auction.dailyMining')}: {formatMiningAmount(effectiveDailyMining(item.dailyYield, mining), mining.currency)} {miningSymbol(mining.currency)}</p>
                    ) : null}
                    <div className="mt-1.5 rounded-lg border border-sky-300/20 bg-sky-500/[.07] px-2 py-1">
                      <p className="text-[7px] font-black uppercase tracking-[0.14em] text-slate-400">{item.currentBidTon ? t('auction.currentBid') : t('auction.startingBid')}</p>
                      <p className="flex items-center gap-1 text-[13px] font-black text-sky-200"><Gem className="h-3 w-3" />{auctionTon(item.currentBidTon ?? item.startingBidTon)}</p>
                    </div>
                    {item.mine ? (
                      <button
                        type="button"
                        disabled={item.bidCount > 0 || cancelMutation.isPending}
                        onClick={() => cancelMutation.mutate(item.id)}
                        className="mt-1.5 w-full rounded-lg border border-white/15 py-1.5 text-[9px] font-black uppercase tracking-[0.1em] text-slate-300 disabled:opacity-40"
                      >
                        {item.bidCount > 0 ? t('auction.cancelOnlyNoBids') : t('auction.cancelAuction')}
                      </button>
                    ) : (
                      <button
                        type="button"
                        onClick={() => { setBidding(item); setBidValue(auctionTon(item.minNextBidTon)); }}
                        className="mt-1.5 w-full rounded-lg bg-gradient-to-b from-sky-300 to-cyan-500 py-1.5 text-[9px] font-black uppercase tracking-[0.1em] text-black"
                      >
                        {t('auction.placeBid')}
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      ) : null}

      {view === 'mine' ? (
        <div className="mt-3 space-y-3">
          {([['selling', mine.data?.selling ?? []], ['bidding', mine.data?.bidding ?? []]] as const).map(([key, rows]) => (
            <div key={key}>
              <p className="text-[9px] font-black uppercase tracking-[0.16em] text-sky-200">{key === 'selling' ? t('auction.selling') : t('auction.bidding')}</p>
              {rows.length === 0 ? (
                <p className="mt-1 rounded-xl border border-white/10 bg-black/30 px-3 py-3 text-center text-[9px] uppercase tracking-[0.14em] text-slate-500">{t('auction.empty')}</p>
              ) : (
                <div className="mt-1 space-y-1.5">
                  {rows.map((row) => (
                    <div key={row.id} className="flex items-center gap-2 rounded-xl border border-white/10 bg-black/30 p-2">
                      <div className="h-10 w-10 shrink-0 overflow-hidden rounded-lg bg-black/60">
                        {row.image ? <img src={row.image} alt={row.name} className="h-full w-full object-cover object-top" loading="lazy" /> : null}
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[11px] font-black text-white">{row.name}</p>
                        <p className="text-[8px] uppercase tracking-[0.12em] text-slate-500">
                          {t('auction.status')}: {row.status} · {auctionCountdown(row.endsAt, now)}
                        </p>
                      </div>
                      <p className="flex shrink-0 items-center gap-1 text-[12px] font-black text-sky-200">
                        <Gem className="h-3 w-3" />{auctionTon(row.currentBidTon ?? row.myBidTon ?? row.startingBidTon ?? 0)}
                      </p>
                    </div>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      ) : null}

      {view === 'sell' ? (
        <div className="mt-3">
          <p className="text-[9px] font-black uppercase tracking-[0.16em] text-sky-200">{t('auction.selectItem')}</p>
          {sellOptions.length === 0 ? (
            <p className="mt-2 rounded-xl border border-white/10 bg-black/30 px-3 py-4 text-center text-[9px] uppercase tracking-[0.14em] text-slate-500">{t('auction.noEligible')}</p>
          ) : (
            <div className="mt-2 grid grid-cols-3 gap-1.5">
              {sellOptions.map((option) => {
                const active = sellItem?.id === option.id;
                return (
                  <button
                    key={`${option.itemType}:${option.id}`}
                    type="button"
                    disabled={!option.available}
                    onClick={() => { setSellItem(option); setStartBid(String(minStart)); }}
                    className={`overflow-hidden rounded-xl border text-left disabled:opacity-40 ${active ? 'border-sky-300' : 'border-white/10'}`}
                  >
                    <div className="relative aspect-square w-full bg-black/60">
                      {option.image ? <img src={option.image} alt={option.name} className="h-full w-full object-cover object-top" loading="lazy" /> : null}
                      {!option.available ? (
                        <span className="absolute inset-x-0 bottom-0 bg-black/80 py-0.5 text-center text-[7px] font-black uppercase text-rose-300">{t('auction.locked')}</span>
                      ) : null}
                    </div>
                    <p className="truncate px-1 py-1 text-[8px] font-black text-white">{option.name}</p>
                  </button>
                );
              })}
            </div>
          )}

          {sellItem ? (
            <div className="mt-3 rounded-2xl border border-sky-300/25 bg-black/40 p-3">
              <p className="text-[11px] font-black text-white">{sellItem.name}</p>
              <label className="mt-2 block text-[8px] font-black uppercase tracking-[0.16em] text-slate-400">{t('auction.startingBid')} (TON)</label>
              <input
                value={startBid}
                onChange={(event) => setStartBid(event.target.value.replace(/[^0-9.,]/g, ''))}
                inputMode="decimal"
                className="mt-1 w-full rounded-lg border border-white/10 bg-black/60 px-2 py-1.5 text-[13px] font-black text-sky-200 outline-none"
              />
              <p className="mt-1 text-[8px] uppercase tracking-[0.12em] text-slate-500">{t('auction.minNextBid')}: {auctionTon(minStart)} TON</p>

              <p className="mt-2 text-[8px] font-black uppercase tracking-[0.16em] text-slate-400">{t('auction.duration')}</p>
              <div className="mt-1 flex flex-wrap gap-1.5">
                {durations.map((hours) => (
                  <button key={hours} type="button" onClick={() => setDuration(hours)} className={chip(duration === hours)}>
                    {t('auction.hours').replace('{value}', String(hours))}
                  </button>
                ))}
              </div>

              <div className="mt-2 flex items-center justify-between rounded-lg border border-white/10 bg-white/[.02] px-2 py-1.5">
                <p className="text-[8px] font-black uppercase tracking-[0.14em] text-slate-400">{t('auction.feeLabel')} {feePercent}%</p>
                <p className="text-[11px] font-black text-emerald-300">{auctionTon(receives)} TON</p>
              </div>
              <p className="mt-0.5 text-[7px] uppercase tracking-[0.12em] text-slate-500">{t('auction.youReceive')}</p>

              <button
                type="button"
                disabled={createMutation.isPending || !(startNumber >= minStart)}
                onClick={() => createMutation.mutate({ itemType: sellItem.itemType, itemInstanceId: sellItem.id, startingBidTon: startNumber, durationHours: duration })}
                className="mt-3 w-full rounded-xl bg-gradient-to-b from-sky-300 to-cyan-500 py-2 text-[10px] font-black uppercase tracking-[0.14em] text-black disabled:opacity-40"
              >
                {t('auction.create')}
              </button>
            </div>
          ) : null}
        </div>
      ) : null}

      {/* Bid sheet: internal TON only. When the balance is short we send the player to the Wallet. */}
      {bidding ? (
        <div className="fixed inset-0 z-[70] flex items-end justify-center bg-black/80 p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          <div className="w-full max-w-[420px] rounded-2xl border border-sky-300/30 bg-[#090d15] p-4">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="truncate text-[13px] font-black text-white">{bidding.name}</p>
                <p className="text-[8px] uppercase tracking-[0.14em] text-slate-500">{t('auction.minNextBid')}: {auctionTon(bidding.minNextBidTon)} TON</p>
              </div>
              <button onClick={() => setBidding(null)} className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
            </div>

            <label className="mt-3 block text-[8px] font-black uppercase tracking-[0.16em] text-slate-400">{t('auction.yourBid')} (TON)</label>
            <input
              value={bidValue}
              onChange={(event) => setBidValue(event.target.value.replace(/[^0-9.,]/g, ''))}
              inputMode="decimal"
              className="mt-1 w-full rounded-lg border border-white/10 bg-black/60 px-2 py-2 text-[15px] font-black text-sky-200 outline-none"
            />
            <p className="mt-1 text-[8px] uppercase tracking-[0.12em] text-slate-500">{t('auction.availableTon')}: {auctionTon(availableTon)} TON</p>

            {bidShort ? (
              <div className="mt-2 rounded-xl border border-rose-400/40 bg-rose-500/10 p-2.5">
                <p className="text-[9px] font-black uppercase tracking-[0.14em] text-rose-200">{t('auction.insufficientTitle')}</p>
                <p className="mt-0.5 text-[8px] text-slate-300">{t('auction.noFc')}</p>
                <p className="mt-1 text-[8px] uppercase tracking-[0.12em] text-slate-400">
                  {t('auction.required')}: {auctionTon(bidNumber)} TON · {t('auction.available')}: {auctionTon(availableTon)} TON
                </p>
                {onOpenWallet ? (
                  <button onClick={onOpenWallet} className="mt-2 w-full rounded-lg border border-sky-300/50 py-1.5 text-[9px] font-black uppercase tracking-[0.12em] text-sky-200">
                    {t('auction.depositTon')} <ChevronRight className="-mt-0.5 inline h-3 w-3" />
                  </button>
                ) : null}
              </div>
            ) : null}

            <div className="mt-3 grid grid-cols-2 gap-2">
              <button onClick={() => setBidding(null)} className="rounded-xl border border-white/15 py-2 text-[10px] font-black uppercase tracking-[0.12em] text-slate-300">{t('auction.cancel')}</button>
              <button
                disabled={bidMutation.isPending || bidShort || !(bidNumber >= bidding.minNextBidTon)}
                onClick={() => bidMutation.mutate({ id: bidding.id, amount: bidNumber })}
                className="rounded-xl bg-gradient-to-b from-sky-300 to-cyan-500 py-2 text-[10px] font-black uppercase tracking-[0.12em] text-black disabled:opacity-40"
              >
                {t('auction.confirmBid')}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
