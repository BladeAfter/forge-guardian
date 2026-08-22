import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI, useTonWallet } from '@tonconnect/ui-react';
import { toast } from 'sonner';
import { formatTon } from '../economy';
import {
  buyNftHeroWithBalance,
  createNftHeroTonOrder,
  fetchMyNftHeroes,
  fetchNftHeroShop,
  verifyNftHeroPurchases,
  type NftHeroShopItem,
} from '../services';
import { encodeCommentPayload } from '../tonComment';
import { useT } from '../LanguageContext';
import { sendTonPayment } from '../tonPayment';
import { effectiveDailyMining, formatMiningAmount, itemMiningCurrency, miningSymbol, useMiningConfig } from '../miningCurrency';

/**
 * BUY NFT (heroes): store for the 10 unique NFT EXCLUSIVE heroes (1/1 each).
 * Sale data only — price, daily yield (paid through hero TON mining) and status.
 * Every purchase is resolved server-side and atomically: an item can never be
 * sold twice and a double tap can never create two owners.
 */
export function NftHeroShopSection({ telegramInitData }: { telegramInitData: string }) {
  const mining = useMiningConfig();
  const t = useT();
  const queryClient = useQueryClient();
  const [target, setTarget] = useState<NftHeroShopItem | null>(null);
  const [waiting, setWaiting] = useState(false);
  const [tonUI] = useTonConnectUI();
  const wallet = useTonWallet();

  const { data, isLoading, error } = useQuery({
    queryKey: ['nft-hero-shop'],
    queryFn: () => fetchNftHeroShop(telegramInitData),
    staleTime: 15_000,
  });

  const refresh = async () => {
    await Promise.all(
      ['nft-hero-shop', 'nft-heroes-mine', 'player-heroes', 'hero-mining', 'ton-wallet', 'wallet-summary', 'game-state'].map((key) =>
        queryClient.invalidateQueries({ queryKey: [key] }),
      ),
    );
  };

  const purchase = useMutation({
    mutationFn: async (item: NftHeroShopItem) => {
      const key = `${item.id}:${crypto.randomUUID()}`;
      const balance = Number(data?.balanceTon ?? 0);
      // Internal withdrawable TON balance first; otherwise the on-chain flow.
      if (balance >= item.priceTon) return await buyNftHeroWithBalance(telegramInitData, item.id, key);
      if (!wallet) {
        await tonUI.openModal();
        throw new Error('CONNECT_TON_WALLET');
      }
      const order = await createNftHeroTonOrder(telegramInitData, item.id, key);
      await sendTonPayment(order, (tx) => tonUI.sendTransaction(tx));
      setWaiting(true);
      for (let attempt = 1; attempt <= 10; attempt += 1) {
        await new Promise((resolve) => window.setTimeout(resolve, attempt === 1 ? 6000 : 7000));
        try {
          const verification = await verifyNftHeroPurchases(telegramInitData);
          if (verification.completed.length || verification.alreadyDelivered.length) return { status: 'completed' as const };
        } catch (verifyError) {
          console.error('[NFT HERO PURCHASE]', verifyError);
        }
      }
      return { status: 'pending_payment' as const };
    },
    onSuccess: async (result) => {
      setWaiting(false);
      setTarget(null);
      await refresh();
      if (result?.status === 'pending_payment') toast('Pagamento enviado. Assim que a rede confirmar, o herói aparecerá na sua coleção.');
      else toast.success('NFT EXCLUSIVE HERO adquirido! Já disponível em HEROES e NFT EXCLUSIVE.');
    },
    onError: async (purchaseError: unknown) => {
      setWaiting(false);
      await refresh();
      const message = purchaseError instanceof Error ? purchaseError.message : t('common.error');
      toast.error(message === 'CONNECT_TON_WALLET' ? 'Conecte sua carteira TON para comprar.' : message);
    },
  });

  if (isLoading) return <p className="py-24 text-center text-sm text-amber-200">...</p>;
  if (error) return <p className="py-24 text-center text-sm text-rose-300">{error instanceof Error ? error.message : t('common.error')}</p>;

  const items = data?.items ?? [];
  const total = data?.totalSupply ?? items.length;

  return (
    <div className="mt-1 pb-4">
      <section className="forge-nft-card relative overflow-hidden rounded-[1.8rem] border border-amber-200/50 bg-gradient-to-b from-amber-950/40 to-black/85 p-4 text-center">
        <div className="forge-nft-sparkles pointer-events-none absolute inset-0" aria-hidden />
        <p className="relative text-[10px] font-black uppercase tracking-[.28em] text-amber-200">💎 NFT EXCLUSIVE HEROES</p>
        <p className="relative mt-1 text-2xl font-black text-amber-100">{total} Total NFTs</p>
        <p className="relative text-[9px] uppercase tracking-[.22em] text-slate-400">Limited Supply • 1/1 each</p>
        <div className="relative mt-3 grid grid-cols-2 gap-2">
          <div className="rounded-xl border border-amber-200/20 bg-black/45 px-2 py-2">
            <p className="text-[7px] uppercase tracking-[.16em] text-slate-400">{t('nft.available')}</p>
            <p className="text-sm font-black text-emerald-300">{data?.available ?? 0} / {total}</p>
          </div>
          <div className="rounded-xl border border-amber-200/20 bg-black/45 px-2 py-2">
            <p className="text-[7px] uppercase tracking-[.16em] text-slate-400">{t('nft.sold')}</p>
            <p className="text-sm font-black text-amber-100">{data?.sold ?? 0} / {total}</p>
          </div>
        </div>
      </section>

      <div className="mt-3 space-y-3">
        {items.map((item) => {
          const sold = item.status === 'SOLD_OUT';
          return (
            <section
              key={item.id}
              className={`forge-nft-card relative overflow-hidden rounded-[1.6rem] border bg-gradient-to-b from-amber-950/40 to-black/85 p-3 ${sold ? 'border-white/10 opacity-70' : 'border-amber-200/60'}`}
            >
              {!sold ? <div className="forge-nft-sparkles pointer-events-none absolute inset-0" aria-hidden /> : null}
              <div className="relative flex items-start justify-between gap-2">
                <p className="text-[9px] font-black uppercase tracking-[.26em] text-amber-200">💎 NFT EXCLUSIVE</p>
                <p className="text-[10px] font-black text-amber-100">NFT #{String(item.serial).padStart(2, '0')}/{total}</p>
              </div>
              <div className="relative mt-2 flex items-center gap-3">
                {item.image ? (
                  <img src={item.image} alt={item.name} className={`h-20 w-20 shrink-0 rounded-xl object-cover ${sold ? 'grayscale' : 'drop-shadow-[0_0_18px_rgba(251,191,36,.5)]'}`} />
                ) : null}
                <div className="min-w-0 flex-1">
                  <h3 className="truncate text-base font-black text-white">{item.name.toUpperCase()}</h3>
                  <p className="text-[10px] font-bold uppercase tracking-[.14em] text-amber-300/90">Supply 1/1 • Tier {formatTon(item.tierTon)} TON</p>
                  <span className={`mt-1 inline-flex rounded-full border px-2 py-0.5 text-[8px] font-black tracking-[.16em] ${sold ? 'border-white/15 bg-white/5 text-slate-400' : 'border-emerald-300/50 bg-emerald-500/15 text-emerald-200'}`}>
                    {sold ? (item.ownedByMe ? t('nft.ownedByYou') : t('nft.soldOut')) : t('nft.availableTag')}
                  </span>
                </div>
              </div>
              {/* Effective yield rule: a 0/NULL yield NFT shows PRICE alone, full width.
                  Dual mining (MYTH + TON) prints both lines in the same block. */}
              <div className={`relative mt-3 grid gap-2 text-center ${miningRateLines(item.dailyYieldTon, item.dailyYieldMyth).length ? 'grid-cols-2' : 'grid-cols-1'}`}>
                <div className="rounded-xl border border-amber-200/20 bg-black/45 px-1 py-2">
                  <p className="text-[7px] uppercase tracking-[.14em] text-slate-400">{t('nft.price')}</p>
                  <p className="text-[13px] font-black text-amber-100">{formatTon(item.priceTon)} <span className="text-[8px] text-amber-300/80">TON</span></p>
                </div>
                {miningRateLines(item.dailyYieldTon, item.dailyYieldMyth).length ? (
                  <div className="rounded-xl border border-amber-200/20 bg-black/45 px-1 py-2">
                    <p className="text-[7px] uppercase tracking-[.14em] text-slate-400">{t('nft.dailyMining')}</p>
                    {miningRateLines(item.dailyYieldTon, item.dailyYieldMyth).map((line) => (
                      <p key={line.currency} className="text-[13px] font-black text-emerald-300">{formatMiningAmount(line.amount, line.currency)} <span className="text-[8px] text-emerald-200/70">{miningSymbol(line.currency)}</span></p>
                    ))}
                  </div>
                ) : null}
              </div>
              <button
                type="button"
                disabled={sold || purchase.isPending}
                onClick={() => setTarget(item)}
                className={`relative mt-3 w-full rounded-xl px-3 py-2.5 text-[11px] font-black uppercase tracking-[.14em] ${sold ? 'bg-white/5 text-slate-500' : 'bg-gradient-to-b from-amber-300 to-orange-500 text-black'}`}
              >
                {sold ? t('nft.soldOut') : t('nft.buyNft')}
              </button>
            </section>
          );
        })}
      </div>

      {target ? (
        <div className="fixed inset-0 z-[90] flex items-end bg-black/80 p-3" onClick={() => (purchase.isPending ? undefined : setTarget(null))}>
          <div className="forge-nft-card relative w-full overflow-hidden rounded-[1.8rem] border border-amber-200/60 bg-gradient-to-b from-amber-950/60 to-black/95 p-4" onClick={(event) => event.stopPropagation()}>
            <p className="text-[9px] font-black uppercase tracking-[.26em] text-amber-200">{t('nft.confirmPurchase')}</p>
            <h3 className="mt-1 text-lg font-black text-white">{target.name.toUpperCase()}</h3>
            <p className="text-[10px] uppercase tracking-[.14em] text-slate-400">NFT #{String(target.serial).padStart(2, '0')}/{total} • 1/1</p>
            <div className="mt-3 space-y-1 rounded-2xl border border-amber-200/20 bg-black/50 p-3 text-[11px] text-slate-300">
              <p className="flex justify-between"><span>{t('nft.price')}</span><span className="font-black text-amber-100">{formatTon(target.priceTon)} TON</span></p>
              {Number(target.dailyYieldTon || 0) > 0 ? <p className="flex justify-between"><span>{t('nft.dailyMining')}</span><span className="font-black text-emerald-300">{formatMiningAmount(effectiveDailyMining(target.dailyYieldTon, mining, target.dailyYieldMyth), itemMiningCurrency(target.dailyYieldMyth))} {miningSymbol(itemMiningCurrency(target.dailyYieldMyth))}</span></p> : null}
              <p className="flex justify-between"><span>{t('nft.internalBalance')}</span><span className="font-black text-amber-100">{formatTon(data?.balanceTon ?? 0)} TON</span></p>
              <p className="pt-1 text-[9px] text-slate-500">
                {Number(data?.balanceTon ?? 0) >= target.priceTon ? 'Será debitado do seu saldo TON interno.' : 'Pagamento via carteira TON conectada.'}
              </p>
            </div>
            <div className="mt-3 flex gap-2">
              <button type="button" disabled={purchase.isPending} onClick={() => setTarget(null)} className="w-1/3 rounded-xl bg-white/5 px-3 py-2.5 text-[11px] font-black uppercase text-slate-300">
                Cancel
              </button>
              <button
                type="button"
                disabled={purchase.isPending}
                onClick={() => purchase.mutate(target)}
                className="flex-1 rounded-xl bg-gradient-to-b from-amber-300 to-orange-500 px-3 py-2.5 text-[11px] font-black uppercase tracking-[.14em] text-black disabled:opacity-60"
              >
                {purchase.isPending ? (waiting ? 'CONFIRMING PAYMENT...' : 'PROCESSING...') : `BUY FOR ${formatTon(target.priceTon)} TON`}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

/**
 * 💎 NFT EXCLUSIVE (heroes): the player's own 1/1 heroes. The daily TON yield is
 * produced by the existing hero mining system (same ROI cap), so the claim button
 * stays in the HEROES mining bar — here we only show what each NFT produces.
 */
export function NftHeroCollectionSection({ telegramInitData }: { telegramInitData: string }) {
  const mining = useMiningConfig();
  const t = useT();
  const { data, isLoading, error } = useQuery({
    queryKey: ['nft-heroes-mine'],
    queryFn: () => fetchMyNftHeroes(telegramInitData),
    staleTime: 15_000,
  });

  if (isLoading) return <p className="py-24 text-center text-sm text-amber-200">...</p>;
  if (error) return <p className="py-24 text-center text-sm text-rose-300">{error instanceof Error ? error.message : t('common.error')}</p>;

  const items = data?.items ?? [];
  const totalDaily = items.reduce((sum, item) => sum + Number(item.dailyYieldTon || 0), 0);

  if (!items.length) {
    return (
      <div className="py-16 text-center">
        <p className="text-[11px] font-black uppercase tracking-[.24em] text-amber-200">💎 NFT EXCLUSIVE</p>
        <p className="mt-2 text-[11px] text-slate-400">Você ainda não possui heróis NFT EXCLUSIVE.</p>
        <p className="mt-1 text-[10px] text-slate-500">Adquira o seu na aba 🛒 BUY NFT — supply 1/1 e rendimento diário em TON.</p>
      </div>
    );
  }

  return (
    <div className="mt-1 space-y-3 pb-4">
      <section className="rounded-[1.6rem] border border-amber-200/40 bg-gradient-to-b from-amber-950/40 to-black/80 p-3 text-center">
        <p className="text-[9px] font-black uppercase tracking-[.26em] text-amber-200">💎 MY NFT HEROES</p>
        <p className="mt-1 text-xl font-black text-amber-100">{items.length} / {data?.totalSupply ?? 10}</p>
        {totalDaily > 0 ? <p className="text-[9px] uppercase tracking-[.18em] text-emerald-300">{formatTon(totalDaily)} TON / dia via mineração</p> : null}
      </section>

      {items.map((item) => (
        <section key={item.nftId} className="relative overflow-hidden rounded-[1.6rem] border border-amber-200/50 bg-gradient-to-b from-amber-950/35 to-black/85 p-3">
          <div className="flex items-start justify-between gap-2">
            <p className="text-[9px] font-black uppercase tracking-[.24em] text-amber-200">💎 NFT EXCLUSIVE</p>
            <p className="text-[10px] font-black text-amber-100">NFT #{String(item.serial).padStart(2, '0')}</p>
          </div>
          <div className="mt-2 flex items-center gap-3">
            {item.image ? <img src={item.image} alt={item.name} className="h-20 w-20 shrink-0 rounded-xl object-cover drop-shadow-[0_0_18px_rgba(251,191,36,.45)]" /> : null}
            <div className="min-w-0 flex-1">
              <h3 className="truncate text-base font-black text-white">{item.name.toUpperCase()}</h3>
              <p className="text-[10px] font-bold uppercase tracking-[.14em] text-amber-300/90">Lv {item.level} • {item.stars}★</p>
              <p className="text-[10px] text-slate-400">ATK {item.atk} • HP {item.hp}</p>
            </div>
          </div>
          {/* Effective yield rule: hide the mining block (and its footnote) for 0-yield NFTs. */}
          <div className={`mt-3 grid gap-2 text-center ${Number(item.dailyYieldTon || 0) > 0 ? 'grid-cols-2' : 'grid-cols-1'}`}>
            <div className="rounded-xl border border-amber-200/20 bg-black/45 px-1 py-2">
              <p className="text-[7px] uppercase tracking-[.14em] text-slate-400">{t('nft.tier')}</p>
              <p className="text-[13px] font-black text-amber-100">{formatTon(item.tierTon)} <span className="text-[8px] text-amber-300/80">TON</span></p>
            </div>
            {Number(item.dailyYieldTon || 0) > 0 ? (
              <div className="rounded-xl border border-amber-200/20 bg-black/45 px-1 py-2">
                <p className="text-[7px] uppercase tracking-[.14em] text-slate-400">{t('nft.dailyMining')}</p>
                <p className="text-[13px] font-black text-emerald-300">{formatMiningAmount(effectiveDailyMining(item.dailyYieldTon, mining, item.dailyYieldMyth), itemMiningCurrency(item.dailyYieldMyth))} <span className="text-[8px] text-emerald-200/70">{miningSymbol(itemMiningCurrency(item.dailyYieldMyth))}</span></p>
              </div>
            ) : null}
          </div>
          {Number(item.dailyYieldTon || 0) > 0 ? <p className="mt-2 text-center text-[9px] text-slate-500">Rendimento acumulado e coleta na barra de mineração da aba HEROES.</p> : null}
        </section>
      ))}
    </div>
  );
}
