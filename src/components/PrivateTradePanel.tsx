import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { ArrowLeftRight, Check, Lock, LockOpen, Search, ShieldAlert, Trash2, UserRound, X } from 'lucide-react';
import { useT } from '../LanguageContext';
import { getInventoryItemVisual } from '../inventoryVisuals';
import {
  PRIVATE_TRADE_ERROR_KEYS, addPrivateTradeItem, cancelPrivateTrade, confirmPrivateTrade, createPrivateTrade,
  fetchPrivateTrade, fetchPrivateTradeAssets, fetchPrivateTrades, lockPrivateTrade, privateTradeEditable,
  privateTradeItemImage, privateTradeItemLabel, removePrivateTradeItem, searchPrivateTradePlayer,
  setPrivateTradeCurrency,
  type PrivateTradeAssets, type PrivateTradeItem, type PrivateTradeList, type PrivateTradeSide,
  type PrivateTradeState, type PrivateTradeStatus,
} from '../privateTrade';

type Props = { telegramInitData: string | null };

const STATUS_KEY: Record<PrivateTradeStatus, string> = {
  negotiating: 'privateTrade.statusNegotiating',
  offer_locked: 'privateTrade.statusOfferLocked',
  ready_for_confirmation: 'privateTrade.statusReady',
  security_review: 'privateTrade.statusReview',
  completed: 'privateTrade.statusCompleted',
  cancelled: 'privateTrade.statusCancelled',
  expired: 'privateTrade.statusExpired',
  blocked: 'privateTrade.statusBlocked',
};

type PickerRow = {
  id: string; name: string; image: string | null; qty: number;
  rarity?: string | null; nft?: boolean; veteran?: boolean; level?: number;
};

const RARITY_BORDER: Record<string, string> = {
  common: 'border-slate-500/40', uncommon: 'border-emerald-400/40', rare: 'border-sky-400/50',
  epic: 'border-violet-400/50', legendary: 'border-amber-400/60', mythic: 'border-fuchsia-400/60',
  ancestral: 'border-rose-400/60', nft_exclusive: 'border-fuchsia-400/70',
};
const RARITY_TEXT: Record<string, string> = {
  common: 'text-slate-400', uncommon: 'text-emerald-300', rare: 'text-sky-300',
  epic: 'text-violet-300', legendary: 'text-amber-300', mythic: 'text-fuchsia-300',
  ancestral: 'text-rose-300', nft_exclusive: 'text-fuchsia-300',
};

/** Real artwork for stackable items (chests, fragments, keys, equipment). */
const itemArt = (image: string | null, code: string, itemType: string, category: string) => {
  if (image && (image.startsWith('http') || image.startsWith('/'))) return image;
  const visual = getInventoryItemVisual({
    itemId: code.replace(/^(equip|pfrag|food):/, ''),
    itemType,
    category: (category as never) ?? 'other',
    quantity: 1,
    image,
  } as never);
  return visual.image;
};

/**
 * PRIVATE TRADE — the whole flow is server-authoritative. This panel only renders
 * what `private_trade_*` returns: it never computes ownership, escrow or risk.
 * Risk/anti-multiaccount data stays on the server (admin only).
 */
export function PrivateTradePanel({ telegramInitData }: Props) {
  const t = useT();
  const queryClient = useQueryClient();
  const enabled = Boolean(telegramInitData);
  const [query, setQuery] = useState('');
  const [openTradeId, setOpenTradeId] = useState<string | null>(null);
  const [picker, setPicker] = useState<'hero' | 'pet' | 'item' | null>(null);
  const [fc, setFc] = useState('');
  const [ton, setTon] = useState('');
  const [myth, setMyth] = useState('');

  const errorText = (error: Error) => {
    const key = PRIVATE_TRADE_ERROR_KEYS[error.message];
    return key ? t(key) : t('privateTrade.errGeneric');
  };

  const list = useQuery<PrivateTradeList>({
    queryKey: ['private-trades'],
    enabled,
    refetchInterval: 20000,
    queryFn: () => fetchPrivateTrades(telegramInitData as string),
  });

  const trade = useQuery<PrivateTradeState>({
    queryKey: ['private-trade', openTradeId],
    enabled: enabled && Boolean(openTradeId),
    refetchInterval: 5000,
    queryFn: () => fetchPrivateTrade(telegramInitData as string, openTradeId as string),
  });

  // NFT / legendary / mythic instances come from the private-trade specific list.
  const sellable = useQuery<PrivateTradeAssets>({
    queryKey: ['private-trade-assets'],
    enabled: enabled && Boolean(picker),
    queryFn: () => fetchPrivateTradeAssets(telegramInitData as string),
  });

  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: ['private-trades'] });
    void queryClient.invalidateQueries({ queryKey: ['private-trade'] });
    void queryClient.invalidateQueries({ queryKey: ['private-trade-assets'] });
    void queryClient.invalidateQueries({ queryKey: ['market-sellable'] });
    void queryClient.invalidateQueries({ queryKey: ['ton-wallet'] });
    void queryClient.invalidateQueries({ queryKey: ['game-state'] });
  };

  const startMutation = useMutation({
    mutationFn: async () => {
      await searchPrivateTradePlayer(telegramInitData as string, query.trim());
      return createPrivateTrade(telegramInitData as string, query.trim());
    },
    onSuccess: (state) => { setOpenTradeId(state.id); setQuery(''); refresh(); },
    onError: (error: Error) => toast.error(errorText(error)),
  });

  const mutate = <T,>(fn: (initData: string) => Promise<T>, done?: () => void) =>
    fn(telegramInitData as string)
      .then(() => { done?.(); refresh(); })
      .catch((error: Error) => toast.error(errorText(error)));

  const state = trade.data ?? null;
  const editable = state ? privateTradeEditable(state) : false;

  const currencyDirty = useMemo(() => {
    if (!state) return false;
    return Number(fc || 0) !== state.me.fc || Number(ton || 0) !== state.me.ton || Number(myth || 0) !== state.me.myth;
  }, [state, fc, ton, myth]);

  const openTrade = (id: string) => {
    setOpenTradeId(id);
    setFc(''); setTon(''); setMyth('');
  };

  // -------------------------------------------------- list view
  if (!openTradeId || !state) {
    const gate = list.data;
    return (
      <div className="space-y-3">
        <header className="rounded-2xl border border-amber-300/25 bg-gradient-to-br from-amber-500/10 via-black/40 to-black/60 p-3">
          <div className="flex items-center gap-2">
            <ArrowLeftRight className="h-4 w-4 text-amber-200" />
            <h2 className="text-[13px] font-black uppercase tracking-[0.14em] text-amber-100">{t('privateTrade.title')}</h2>
          </div>
          <p className="mt-1 text-[10px] text-slate-300">{t('privateTrade.subtitle')}</p>
        </header>

        {gate && !gate.canTrade ? (
          <div className="rounded-2xl border border-white/10 bg-black/40 p-3 text-[11px] text-slate-300">
            {gate.settings.enabled
              ? t('privateTrade.gateAccountDays').replace('{days}', String(gate.settings.minAccountDays))
              : t('privateTrade.gateDisabled')}
          </div>
        ) : (
          <div className="rounded-2xl border border-white/10 bg-black/40 p-3">
            <label className="text-[9px] font-black uppercase tracking-[0.12em] text-slate-400">{t('privateTrade.searchLabel')}</label>
            <div className="mt-2 flex gap-2">
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder={t('privateTrade.searchPlaceholder')}
                className="min-w-0 flex-1 rounded-xl border border-white/10 bg-black/50 px-3 py-2 text-[12px] text-slate-100 outline-none focus:border-amber-300/50"
              />
              <button
                type="button"
                disabled={query.trim().length < 2 || startMutation.isPending}
                onClick={() => startMutation.mutate()}
                className="flex items-center gap-1 rounded-xl border border-amber-300/40 bg-amber-400/20 px-3 py-2 text-[10px] font-black uppercase tracking-[0.1em] text-amber-100 disabled:opacity-40"
              >
                <Search className="h-3.5 w-3.5" />{t('privateTrade.startTrade')}
              </button>
            </div>
          </div>
        )}

        <section className="space-y-2">
          <h3 className="text-[10px] font-black uppercase tracking-[0.12em] text-slate-400">{t('privateTrade.open')}</h3>
          {(gate?.trades ?? []).length === 0 ? (
            <p className="rounded-2xl border border-white/10 bg-black/30 p-3 text-[11px] text-slate-400">{t('privateTrade.none')}</p>
          ) : (
            (gate?.trades ?? []).map((row) => (
              <button
                key={row.id}
                type="button"
                onClick={() => openTrade(row.id)}
                className="flex w-full items-center gap-3 rounded-2xl border border-white/10 bg-black/40 p-3 text-left"
              >
                <span className="flex h-9 w-9 items-center justify-center rounded-full border border-white/10 bg-white/5">
                  {row.partner?.avatar
                    ? <img src={row.partner.avatar} alt="" className="h-full w-full rounded-full object-cover" />
                    : <UserRound className="h-4 w-4 text-slate-300" />}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[12px] font-bold text-slate-100">{row.partner?.name ?? '—'}</span>
                  <span className="block text-[9px] uppercase tracking-[0.1em] text-slate-400">
                    {t(STATUS_KEY[row.status])} · {row.myItems} ⇄ {row.theirItems}
                  </span>
                </span>
                <span className="font-mono text-[9px] text-slate-500">{row.code}</span>
              </button>
            ))
          )}
        </section>
      </div>
    );
  }

  // -------------------------------------------------- trade view
  const closed = ['completed', 'cancelled', 'expired', 'blocked'].includes(state.status);
  const sideBlock = (side: PrivateTradeSide, mine: boolean) => (
    <div className={`rounded-2xl border p-3 ${mine ? 'border-amber-300/30 bg-amber-500/[.06]' : 'border-white/10 bg-black/40'}`}>
      <div className="flex items-center justify-between">
        <span className="text-[9px] font-black uppercase tracking-[0.12em] text-slate-300">
          {mine ? t('privateTrade.myOffer') : t('privateTrade.theirOffer')}
        </span>
        <span className="flex items-center gap-1 text-[9px] uppercase tracking-[0.1em]">
          {side.locked && <span className="flex items-center gap-1 text-amber-200"><Lock className="h-3 w-3" />{t('privateTrade.locked')}</span>}
          {side.confirmed && <span className="flex items-center gap-1 text-emerald-300"><Check className="h-3 w-3" />{t('privateTrade.confirmed')}</span>}
        </span>
      </div>
      <p className="mt-1 truncate text-[11px] font-bold text-slate-100">{side.player?.name ?? '—'}</p>

      <div className="mt-2 space-y-1">
        {side.items.length === 0 && <p className="text-[10px] text-slate-500">—</p>}
        {side.items.map((item: PrivateTradeItem) => (
          <div key={item.id} className="flex items-center gap-2 rounded-xl border border-white/10 bg-black/40 px-2 py-1.5">
            {privateTradeItemImage(item)
              ? <img src={privateTradeItemImage(item) as string} alt="" className="h-7 w-7 rounded-lg object-cover" />
              : <span className="h-7 w-7 rounded-lg bg-white/5" />}
            <span className="min-w-0 flex-1 truncate text-[11px] text-slate-200">{privateTradeItemLabel(item)}</span>
            {item.quantity > 1 && <span className="text-[10px] font-bold text-slate-400">x{item.quantity}</span>}
            {mine && editable && (
              <button type="button" onClick={() => void mutate((init) => removePrivateTradeItem(init, state.id, item.id))}>
                <Trash2 className="h-3.5 w-3.5 text-rose-300" />
              </button>
            )}
          </div>
        ))}
      </div>

      <div className="mt-2 grid grid-cols-3 gap-1 text-center text-[10px]">
        <span className="rounded-lg border border-white/10 bg-black/40 px-1 py-1 text-amber-200">{side.fc.toLocaleString('en-US')} BERRIES</span>
        <span className="rounded-lg border border-white/10 bg-black/40 px-1 py-1 text-sky-200">{side.ton} TON</span>
        <span className="rounded-lg border border-white/10 bg-black/40 px-1 py-1 text-fuchsia-200">{side.myth} MYTH</span>
      </div>
    </div>
  );

  return (
    <div className="space-y-3">
      <header className="flex items-center justify-between rounded-2xl border border-white/10 bg-black/40 p-3">
        <button type="button" onClick={() => setOpenTradeId(null)} className="text-[10px] font-black uppercase tracking-[0.1em] text-slate-300">
          ← {t('privateTrade.back')}
        </button>
        <span className="text-[9px] font-black uppercase tracking-[0.12em] text-amber-200">{t(STATUS_KEY[state.status])}</span>
      </header>

      {state.status === 'security_review' && (
        <p className="flex items-start gap-2 rounded-2xl border border-amber-300/30 bg-amber-500/10 p-3 text-[11px] text-amber-100">
          <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" />{t('privateTrade.reviewNotice')}
        </p>
      )}
      {state.status === 'blocked' && (
        <p className="rounded-2xl border border-rose-400/30 bg-rose-500/10 p-3 text-[11px] text-rose-100">{t('privateTrade.blockedNotice')}</p>
      )}
      {state.status === 'completed' && (
        <p className="rounded-2xl border border-emerald-400/30 bg-emerald-500/10 p-3 text-[11px] text-emerald-100">{t('privateTrade.completedNotice')}</p>
      )}

      {sideBlock(state.me, true)}
      {sideBlock(state.partner, false)}

      {editable && (
        <>
          <div className="grid grid-cols-3 gap-2">
            {(['hero', 'pet', 'item'] as const).map((kind) => (
              <button
                key={kind}
                type="button"
                onClick={() => setPicker(kind)}
                className="rounded-xl border border-white/10 bg-black/40 px-2 py-2 text-[9px] font-black uppercase tracking-[0.1em] text-slate-200"
              >
                + {kind === 'hero' ? t('market.heroes') : kind === 'pet' ? t('market.pets') : t('market.itemLabel')}
              </button>
            ))}
          </div>

          <div className="rounded-2xl border border-white/10 bg-black/40 p-3">
            <span className="text-[9px] font-black uppercase tracking-[0.12em] text-slate-400">{t('privateTrade.currencies')}</span>
            <div className="mt-2 grid grid-cols-3 gap-2">
              <input inputMode="decimal" value={fc} onChange={(e) => setFc(e.target.value)} placeholder={`BERRIES · ${state.balances.fc}`}
                className="min-w-0 rounded-xl border border-white/10 bg-black/50 px-2 py-2 text-[11px] text-slate-100 outline-none" />
              <input inputMode="decimal" value={ton} onChange={(e) => setTon(e.target.value)} placeholder={`TON · ${state.balances.ton}`}
                className="min-w-0 rounded-xl border border-white/10 bg-black/50 px-2 py-2 text-[11px] text-slate-100 outline-none" />
              <input inputMode="decimal" value={myth} onChange={(e) => setMyth(e.target.value)} placeholder={`MYTH · ${state.balances.myth}`}
                className="min-w-0 rounded-xl border border-white/10 bg-black/50 px-2 py-2 text-[11px] text-slate-100 outline-none" />
            </div>
            <button
              type="button"
              disabled={!currencyDirty}
              onClick={() => void mutate((init) => setPrivateTradeCurrency(init, state.id, Number(fc || 0), Number(ton || 0), Number(myth || 0)))}
              className="mt-2 w-full rounded-xl border border-white/15 bg-white/5 px-3 py-2 text-[10px] font-black uppercase tracking-[0.1em] text-slate-100 disabled:opacity-40"
            >
              {t('privateTrade.save')}
            </button>
          </div>
        </>
      )}

      {!closed && (
        <div className="space-y-2">
          <button
            type="button"
            onClick={() => void mutate((init) => lockPrivateTrade(init, state.id, !state.me.locked))}
            className="flex w-full items-center justify-center gap-2 rounded-xl border border-amber-300/40 bg-amber-400/15 px-3 py-2.5 text-[11px] font-black uppercase tracking-[0.1em] text-amber-100"
          >
            {state.me.locked ? <LockOpen className="h-4 w-4" /> : <Lock className="h-4 w-4" />}
            {state.me.locked ? t('privateTrade.unlockOffer') : t('privateTrade.lockOffer')}
          </button>

          {state.status === 'ready_for_confirmation' && (
            <>
              <p className="text-center text-[10px] uppercase tracking-[0.1em] text-slate-400">{t('privateTrade.finalReview')}</p>
              <button
                type="button"
                disabled={state.me.confirmed}
                onClick={() => void mutate((init) => confirmPrivateTrade(init, state.id))}
                className="w-full rounded-xl border border-emerald-300/40 bg-emerald-400/20 px-3 py-2.5 text-[11px] font-black uppercase tracking-[0.1em] text-emerald-100 disabled:opacity-50"
              >
                {state.me.confirmed ? t('privateTrade.waitingPartner') : t('privateTrade.confirm')}
              </button>
            </>
          )}

          {state.status !== 'security_review' && (
            <button
              type="button"
              onClick={() => void mutate((init) => cancelPrivateTrade(init, state.id))}
              className="flex w-full items-center justify-center gap-2 rounded-xl border border-rose-400/30 bg-rose-500/10 px-3 py-2 text-[10px] font-black uppercase tracking-[0.1em] text-rose-200"
            >
              <X className="h-3.5 w-3.5" />{t('privateTrade.cancel')}
            </button>
          )}
        </div>
      )}

      {picker && (
        <div className="fixed inset-0 z-[80] flex items-end bg-black/80 p-3" onClick={() => setPicker(null)}>
          <div className="max-h-[70vh] w-full overflow-y-auto rounded-2xl border border-white/10 bg-[#0b0e14] p-3" onClick={(e) => e.stopPropagation()}>
            <div className="mb-2 flex items-center justify-between">
              <span className="text-[10px] font-black uppercase tracking-[0.12em] text-slate-300">{t('privateTrade.chooseItem')}</span>
              <button type="button" onClick={() => setPicker(null)}><X className="h-4 w-4 text-slate-400" /></button>
            </div>
            {(() => {
              const data = sellable.data;
              const rows: PickerRow[] = picker === 'hero'
                ? (data?.heroes ?? []).filter((h) => h.available !== false).map((h) => ({
                    id: h.id, name: h.name, image: h.image, qty: 1, rarity: h.rarity, nft: h.nft, veteran: h.veteranLine, level: h.level,
                  }))
                : picker === 'pet'
                  ? (data?.pets ?? []).filter((p) => p.available !== false).map((p) => ({
                      id: p.id, name: p.name, image: p.image, qty: 1, rarity: p.rarity, nft: p.nft, veteran: p.veteranLine, level: p.level,
                    }))
                  : (data?.items ?? []).filter((i) => i.available !== false).map((i) => ({
                      id: i.code,
                      name: i.name ?? i.code,
                      image: itemArt(i.image, i.code, i.itemType, i.category),
                      qty: i.quantity,
                      rarity: i.rarity,
                      nft: i.nft,
                    }));
              if (rows.length === 0) return <p className="p-2 text-[11px] text-slate-400">{t('privateTrade.noItems')}</p>;
              return rows.map((row) => (
                <button
                  key={row.id}
                  type="button"
                  onClick={() => {
                    setPicker(null);
                    void mutate((init) => addPrivateTradeItem(init, state.id, picker === 'item'
                      ? { itemType: 'item', itemCode: row.id, quantity: 1 }
                      : { itemType: picker, itemInstanceId: row.id }));
                  }}
                  className="flex w-full items-center gap-2 border-b border-white/5 px-1 py-2 text-left"
                >
                  {row.image
                    ? <img src={row.image} alt="" loading="lazy" className={`h-10 w-10 rounded-lg border object-cover ${RARITY_BORDER[String(row.rarity ?? '').toLowerCase()] ?? 'border-white/10'}`} />
                    : <span className="h-10 w-10 rounded-lg bg-white/5" />}
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[11px] font-bold text-slate-100">{row.name}</span>
                    <span className="flex flex-wrap items-center gap-1">
                      {row.rarity && (
                        <span className={`text-[9px] font-black uppercase tracking-[0.1em] ${RARITY_TEXT[String(row.rarity).toLowerCase()] ?? 'text-slate-400'}`}>
                          {String(row.rarity)}
                        </span>
                      )}
                      {typeof row.level === 'number' && <span className="text-[9px] text-slate-500">Lv {row.level}</span>}
                      {row.veteran && <span className="rounded bg-amber-400/20 px-1 text-[8px] font-black uppercase text-amber-200">VETERAN</span>}
                      {row.nft && !row.veteran && <span className="rounded bg-fuchsia-400/20 px-1 text-[8px] font-black uppercase text-fuchsia-200">NFT</span>}
                    </span>
                  </span>
                  {row.qty > 1 && <span className="text-[10px] text-slate-400">x{row.qty}</span>}
                </button>
              ));
            })()}
          </div>
        </div>
      )}
    </div>
  );
}
