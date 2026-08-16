import { useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI, useTonWallet } from '@tonconnect/ui-react';
import { ChevronLeft, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { formatTon } from '../economy';
import {
  buyNftEquipmentWithBalance,
  createNftEquipmentTonOrder,
  fetchArsenal,
  fetchNftEquipmentShop,
  verifyNftEquipmentPurchases,
  type ArsenalItem,
  type NftEquipShopItem,
} from '../services';
import { encodeCommentPayload } from '../tonComment';
import { useT } from '../LanguageContext';
import { sendTonPayment } from '../tonPayment';

const RARITY: Record<string, string> = {
  common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc',
  legendary: '#fbbf24', mythic: '#fb7185', ancestral: '#f472b6', nft_exclusive: '#fde68a',
};

const SLOTS = ['all', 'weapon', 'armor', 'ring'] as const;
type SlotFilter = (typeof SLOTS)[number];
const SLOT_GLYPH: Record<string, string> = { weapon: '⚔', armor: '🛡', ring: '💍' };

type Tab = 'mine' | 'nft' | 'shop';

/** Compact slot filter row shared by the three Arsenal tabs. */
function SlotFilters({ value, onChange }: { value: SlotFilter; onChange: (slot: SlotFilter) => void }) {
  const t = useT();
  return (
    <div className="-mx-1 mb-3 flex gap-1.5 overflow-x-auto px-1 pb-1">
      {SLOTS.map((slot) => (
        <button
          key={slot}
          type="button"
          onClick={() => onChange(slot)}
          className={`shrink-0 rounded-lg border px-2.5 py-1 text-[9px] font-black uppercase tracking-[.12em] ${value === slot ? 'border-amber-300/60 bg-amber-300/15 text-amber-200' : 'border-white/12 bg-black/50 text-slate-400'}`}
        >
          {slot === 'all' ? t('arsenal.slot.all') : `${SLOT_GLYPH[slot]} ${t(`arsenal.slot.${slot}`)}`}
        </button>
      ))}
    </div>
  );
}

function ItemCard({ item }: { item: ArsenalItem }) {
  const t = useT();
  const accent = RARITY[String(item.rarity)] ?? '#94a3b8';
  return (
    <article
      className={`relative overflow-hidden rounded-2xl border bg-black/55 p-2 ${item.isNft ? 'nft-hero-card border-amber-200/60' : ''}`}
      style={{ borderColor: item.isNft ? undefined : accent }}
    >
      {item.isNft ? (
        <div className="mb-1 flex items-center justify-between">
          <span className="nft-hero-badge text-[7px]">💎 NFT EXCLUSIVE</span>
          {item.serial ? <span className="text-[8px] font-black text-amber-100">#{String(item.serial).padStart(3, '0')}</span> : null}
        </div>
      ) : null}
      <div className="flex gap-2">
        <div className="grid h-16 w-16 shrink-0 place-items-center overflow-hidden rounded-xl border border-white/10 bg-black/60">
          {item.image
            ? <img src={item.image} alt={item.name} loading="lazy" className={`h-full w-full object-contain p-0.5 ${item.isNft ? 'drop-shadow-[0_0_12px_rgba(251,191,36,.55)]' : ''}`} />
            : <span className="text-lg opacity-50">{SLOT_GLYPH[item.slot] ?? '⚔'}</span>}
        </div>
        <div className="min-w-0 flex-1">
          <p className={`truncate text-[11px] font-black uppercase ${item.isNft ? 'nft-hero-name' : 'text-white'}`}>{item.name}</p>
          <p className="text-[8px] font-black uppercase tracking-[.12em]" style={{ color: accent }}>
            {item.isNft ? 'NFT EXCLUSIVE' : (item.rarity ? t(`rarity.${item.rarity}`) : '')} · {SLOT_GLYPH[item.slot]} {t(`arsenal.slot.${item.slot}`)}
          </p>
          <p className="text-[9px] font-bold text-emerald-300">ATK +{item.bonusAttack} · DEF +{item.bonusDefense} · HP +{item.bonusHp}</p>
          <p className="text-[8px] font-black uppercase tracking-[.1em] text-slate-400">
            {item.slot === 'weapon' && item.heroClass ? t('arsenal.classOnly', { class: item.heroClass.toUpperCase() }) : t('arsenal.anyClass')}
          </p>
          <p className={`truncate text-[8px] font-black uppercase tracking-[.1em] ${item.equippedHeroId ? 'text-amber-300' : item.listed ? 'text-rose-300' : 'text-emerald-300'}`}>
            {item.equippedHeroId
              ? `🔒 ${t('arsenal.equippedOn', { hero: item.equippedHeroName ?? '' })}`
              : item.listed ? `🔒 ${t('arsenal.listed')}` : t('arsenal.available')}
          </p>
        </div>
      </div>
    </article>
  );
}

function ShopCard({ item, total, onBuy, disabled }: { item: NftEquipShopItem; total: number; onBuy: () => void; disabled: boolean }) {
  const t = useT();
  const sold = item.status === 'SOLD_OUT';
  return (
    <section className={`forge-nft-card relative overflow-hidden rounded-[1.6rem] border bg-gradient-to-b from-amber-950/40 to-black/85 p-3 ${sold ? 'border-white/10 opacity-70' : 'border-amber-200/60'}`}>
      {!sold ? <div className="forge-nft-sparkles pointer-events-none absolute inset-0" aria-hidden /> : null}
      <div className="relative flex items-start justify-between gap-2">
        <p className="text-[9px] font-black uppercase tracking-[.26em] text-amber-200">💎 NFT EXCLUSIVE</p>
        <p className="text-[10px] font-black text-amber-100">NFT #{String(item.serial).padStart(2, '0')}/{total}</p>
      </div>
      <div className="relative mt-2 flex items-center gap-3">
        {item.image ? (
          <img src={item.image} alt={item.name} loading="lazy" className={`h-20 w-20 shrink-0 rounded-xl object-contain ${sold ? 'grayscale' : 'drop-shadow-[0_0_18px_rgba(251,191,36,.5)]'}`} />
        ) : null}
        <div className="min-w-0 flex-1">
          <h3 className="truncate text-base font-black text-white">{item.name.toUpperCase()}</h3>
          <p className="text-[10px] font-bold uppercase tracking-[.14em] text-amber-300/90">
            {SLOT_GLYPH[item.slot]} {t(`arsenal.slot.${item.slot}`)} · Supply 1/1
          </p>
          <p className="text-[9px] font-black uppercase tracking-[.12em] text-slate-300">
            {item.slot === 'weapon' && item.heroClass ? t('arsenal.classOnly', { class: item.heroClass.toUpperCase() }) : t('arsenal.anyClass')}
          </p>
          <span className={`mt-1 inline-flex rounded-full border px-2 py-0.5 text-[8px] font-black tracking-[.16em] ${sold ? 'border-white/15 bg-white/5 text-slate-400' : 'border-emerald-300/50 bg-emerald-500/15 text-emerald-200'}`}>
            {sold ? (item.ownedByMe ? t('nft.ownedByYou') : t('nft.soldOut')) : t('nft.availableTag')}
          </span>
        </div>
      </div>
      <div className="relative mt-3 grid grid-cols-2 gap-2 text-center">
        <div className="rounded-xl border border-amber-200/20 bg-black/45 px-1 py-2">
          <p className="text-[7px] uppercase tracking-[.14em] text-slate-400">{t('nft.price')}</p>
          <p className="text-[13px] font-black text-amber-100">{formatTon(item.priceTon)} <span className="text-[8px] text-amber-300/80">TON</span></p>
        </div>
        <div className="rounded-xl border border-amber-200/20 bg-black/45 px-1 py-2">
          <p className="text-[7px] uppercase tracking-[.14em] text-slate-400">POWER</p>
          <p className="text-[13px] font-black text-emerald-300">{item.power}</p>
        </div>
      </div>
      <p className="relative mt-2 text-center text-[9px] font-bold text-slate-300">
        ATK +{item.bonusAttack} · DEF +{item.bonusDefense} · HP +{item.bonusHp}
      </p>
      <button
        type="button"
        disabled={sold || disabled}
        onClick={onBuy}
        className={`relative mt-3 w-full rounded-xl px-3 py-2.5 text-[11px] font-black uppercase tracking-[.14em] ${sold ? 'bg-white/5 text-slate-500' : 'bg-gradient-to-b from-amber-300 to-orange-500 text-black'}`}
      >
        {sold ? t('nft.soldOut') : t('nft.buyNft')}
      </button>
    </section>
  );
}

/**
 * MYTHREON ARSENAL — sub-screen of HEROES → INVENTORY. Read-only view over the
 * server state: the collection, the player's NFT 1/1 pieces and the primary NFT
 * store. Equipping still happens in the hero details slots.
 */
export function ArsenalPanel({ telegramInitData, onBack }: { telegramInitData: string; onBack: () => void }) {
  const t = useT();
  const queryClient = useQueryClient();
  const [tab, setTab] = useState<Tab>('mine');
  const [slot, setSlot] = useState<SlotFilter>('all');
  const [target, setTarget] = useState<NftEquipShopItem | null>(null);
  const [waiting, setWaiting] = useState(false);
  const [tonUI] = useTonConnectUI();
  const wallet = useTonWallet();

  const arsenal = useQuery({ queryKey: ['arsenal'], queryFn: () => fetchArsenal(telegramInitData), staleTime: 15_000 });
  const shop = useQuery({ queryKey: ['nft-equip-shop'], queryFn: () => fetchNftEquipmentShop(telegramInitData), staleTime: 15_000, enabled: tab === 'shop' });

  const refresh = () => Promise.all(
    ['arsenal', 'nft-equip-shop', 'player-inventory', 'player-heroes', 'hero-equipment', 'ton-wallet', 'wallet-summary', 'game-state', 'market-sellable'].map((key) =>
      queryClient.invalidateQueries({ queryKey: [key] }),
    ),
  );

  const purchase = useMutation({
    mutationFn: async (item: NftEquipShopItem) => {
      const key = `${item.id}:${crypto.randomUUID()}`;
      const balance = Number(shop.data?.balanceTon ?? 0);
      // Internal withdrawable TON balance first; otherwise the on-chain flow.
      if (balance >= item.priceTon) return await buyNftEquipmentWithBalance(telegramInitData, item.id, key);
      if (!wallet) {
        await tonUI.openModal();
        throw new Error('CONNECT_TON_WALLET');
      }
      const order = await createNftEquipmentTonOrder(telegramInitData, item.id, key);
      await sendTonPayment(order, (tx) => tonUI.sendTransaction(tx));
      setWaiting(true);
      for (let attempt = 1; attempt <= 10; attempt += 1) {
        await new Promise((resolve) => window.setTimeout(resolve, attempt === 1 ? 6000 : 7000));
        try {
          const verification = await verifyNftEquipmentPurchases(telegramInitData);
          if (verification.completed.length || verification.alreadyDelivered.length) return { status: 'completed' as const };
        } catch (verifyError) {
          console.error('[NFT EQUIP PURCHASE]', verifyError);
        }
      }
      return { status: 'pending_payment' as const };
    },
    onSuccess: async (result) => {
      setWaiting(false);
      setTarget(null);
      await refresh();
      if (result?.status === 'pending_payment') toast(t('arsenal.shopSubtitle'));
      else { toast.success('NFT EXCLUSIVE EQUIPMENT'); setTab('nft'); }
    },
    onError: async (purchaseError: unknown) => {
      setWaiting(false);
      await refresh();
      const message = purchaseError instanceof Error ? purchaseError.message : t('common.error');
      toast.error(message === 'CONNECT_TON_WALLET' ? 'Conecte sua carteira TON para comprar.' : message);
    },
  });

  const items = arsenal.data?.items ?? [];
  const visible = useMemo(() => {
    const scoped = tab === 'nft' ? items.filter((item) => item.isNft) : items;
    return slot === 'all' ? scoped : scoped.filter((item) => item.slot === slot);
  }, [items, slot, tab]);
  const shopItems = useMemo(() => {
    const list = shop.data?.items ?? [];
    return slot === 'all' ? list : list.filter((item) => item.slot === slot);
  }, [shop.data, slot]);
  const total = shop.data?.totalSupply ?? shopItems.length;

  return (
    <section className="rounded-2xl border border-amber-300/20 bg-black/45 p-3">
      <header className="mb-3 flex items-center gap-2">
        <button
          type="button"
          onClick={onBack}
          className="flex items-center gap-1 rounded-xl border border-white/12 bg-black/60 px-2 py-1.5 text-[9px] font-black uppercase tracking-[.12em] text-slate-300"
        >
          <ChevronLeft size={12} /> {t('arsenal.back')}
        </button>
        <p className="flex-1 truncate text-right text-[11px] font-black uppercase tracking-[.2em] text-amber-200">⚔ {t('arsenal.title')}</p>
      </header>

      <nav className="-mx-1 mb-3 flex gap-1.5 overflow-x-auto px-1 pb-1">
        {(['mine', 'nft', 'shop'] as Tab[]).map((key) => (
          <button
            key={key}
            type="button"
            onClick={() => setTab(key)}
            className={`shrink-0 rounded-xl border px-3 py-1.5 text-[9px] font-black uppercase tracking-[.12em] ${tab === key ? 'border-amber-300/60 bg-amber-300/15 text-amber-200' : 'border-white/12 bg-black/50 text-slate-400'}`}
          >
            {key === 'nft' ? '💎 ' : key === 'shop' ? '🛒 ' : ''}{t(`arsenal.tab.${key}`)}
          </button>
        ))}
      </nav>

      <SlotFilters value={slot} onChange={setSlot} />

      {tab === 'shop' ? (
        shop.isLoading ? (
          <p className="grid place-items-center py-16"><Loader2 className="animate-spin text-amber-300" /></p>
        ) : shop.error ? (
          <p className="py-16 text-center text-sm text-rose-300">{shop.error instanceof Error ? shop.error.message : t('common.error')}</p>
        ) : (
          <div className="space-y-3 pb-2">
            <section className="rounded-[1.6rem] border border-amber-200/40 bg-gradient-to-b from-amber-950/40 to-black/80 p-3 text-center">
              <p className="text-[9px] font-black uppercase tracking-[.24em] text-amber-200">💎 {t('arsenal.shopHeader')}</p>
              <p className="mt-1 text-xl font-black text-amber-100">{shop.data?.available ?? 0} / {total}</p>
              <p className="text-[9px] uppercase tracking-[.18em] text-slate-400">{t('arsenal.shopSubtitle')}</p>
            </section>
            {shopItems.map((item) => (
              <ShopCard key={item.id} item={item} total={total} disabled={purchase.isPending} onBuy={() => setTarget(item)} />
            ))}
          </div>
        )
      ) : arsenal.isLoading ? (
        <p className="grid place-items-center py-16"><Loader2 className="animate-spin text-amber-300" /></p>
      ) : arsenal.error ? (
        <p className="py-16 text-center text-sm text-rose-300">{arsenal.error instanceof Error ? arsenal.error.message : t('common.error')}</p>
      ) : visible.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-[11px] text-slate-400">{tab === 'nft' ? t('arsenal.nftEmpty') : t('arsenal.empty')}</p>
          {tab === 'nft' ? <p className="mt-1 text-[10px] text-slate-500">{t('arsenal.nftEmptyHint')}</p> : null}
        </div>
      ) : (
        <>
          <p className="mb-2 text-[9px] font-black uppercase tracking-[.16em] text-slate-400">{t('arsenal.count', { count: visible.length })}</p>
          <div className="space-y-2">{visible.map((item) => <ItemCard key={item.instanceId} item={item} />)}</div>
          <p className="mt-3 text-center text-[9px] text-slate-500">{t('arsenal.equipHint')}</p>
        </>
      )}

      {/* Portal: the HEROES tab slider uses a CSS transform, which would trap a
          `fixed` overlay inside it and push the dialog off-screen. */}
      {target ? createPortal(
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="arsenal-purchase-title"
          className="fixed left-0 top-0 z-[99999] grid h-[100dvh] w-screen place-items-center overflow-y-auto overscroll-contain bg-black/80 px-3 py-6 [isolation:isolate]"
          style={{ paddingTop: 'max(1.5rem, env(safe-area-inset-top))', paddingBottom: 'max(1.5rem, env(safe-area-inset-bottom))' }}
          onClick={() => (purchase.isPending ? undefined : setTarget(null))}
        >
          <div className="forge-nft-card relative z-[1] mx-auto max-h-full w-full max-w-[420px] overflow-y-auto rounded-[1.8rem] border border-amber-200/60 bg-gradient-to-b from-amber-950/60 to-black/95 p-4 shadow-2xl" onClick={(event) => event.stopPropagation()}>
            <p className="text-[9px] font-black uppercase tracking-[.26em] text-amber-200">{t('nft.confirmPurchase')}</p>
            <h3 id="arsenal-purchase-title" className="mt-1 text-lg font-black text-white">{target.name.toUpperCase()}</h3>
            <p className="text-[10px] uppercase tracking-[.14em] text-slate-400">NFT #{String(target.serial).padStart(2, '0')}/{total} • 1/1</p>
            <div className="mt-3 space-y-1 rounded-2xl border border-amber-200/20 bg-black/50 p-3 text-[11px] text-slate-300">
              <p className="flex justify-between"><span>{t('nft.price')}</span><span className="font-black text-amber-100">{formatTon(target.priceTon)} TON</span></p>
              <p className="flex justify-between"><span>ATK / DEF / HP</span><span className="font-black text-emerald-300">+{target.bonusAttack} / +{target.bonusDefense} / +{target.bonusHp}</span></p>
              <p className="flex justify-between"><span>{t('nft.internalBalance')}</span><span className="font-black text-amber-100">{formatTon(shop.data?.balanceTon ?? 0)} TON</span></p>
              {target.slot === 'weapon' && target.heroClass ? (
                <p className="pt-1 text-[9px] font-black uppercase tracking-[.12em] text-amber-300">{t('arsenal.classOnly', { class: target.heroClass.toUpperCase() })}</p>
              ) : null}
            </div>
            <div className="mt-3 flex gap-2">
              <button type="button" disabled={purchase.isPending} onClick={() => setTarget(null)} className="w-1/3 rounded-xl bg-white/5 px-3 py-2.5 text-[11px] font-black uppercase text-slate-300">
                {t('inventory.cancel')}
              </button>
              <button
                type="button"
                disabled={purchase.isPending}
                onClick={() => purchase.mutate(target)}
                className="flex-1 rounded-xl bg-gradient-to-b from-amber-300 to-orange-500 px-3 py-2.5 text-[11px] font-black uppercase tracking-[.14em] text-black disabled:opacity-60"
              >
                {purchase.isPending ? (waiting ? 'CONFIRMING PAYMENT...' : 'PROCESSING...') : `${t('nft.buyNft')} · ${formatTon(target.priceTon)} TON`}
              </button>
            </div>
          </div>
        </div>,
        document.body,
      ) : null}
    </section>
  );
}
