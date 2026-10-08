import { useEffect, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { Crown, Sparkles, X } from 'lucide-react';
import { toast } from 'sonner';
import { useSovereignPack } from '../hooks';
import { startSovereignPackPurchase, trackOfferImpression, verifySovereignPackPurchases } from '../services';
import { sendTonPayment } from '../tonPayment';
import { sovereignPackErrorText } from '../sovereignPack';
import { formatTon } from '../economy';
import { useT } from '../LanguageContext';
import packArt from '../assets/celestial-sovereign-pack.jpg';

const int = (value: number) => Math.round(Number(value || 0)).toLocaleString('pt-BR');

/**
 * 👑 CELESTIAL SOVEREIGN PACK (150 TON) — card permanente em OFERTAS PREMIUM e popup diário.
 *
 * Preço, janela, estoque, limite, entrega atômica e o bônus permanente de mineração TON da conta são
 * decididos pelo servidor. Herói Celestial e Pet NFT Celestial chegam com mineração "A REVELAR":
 * nada é prometido antes da compra e não existe mineração retroativa.
 */
export function SovereignPackCard({ telegramInitData, popupMode = false, onPopupClose }: {
  telegramInitData: string;
  popupMode?: boolean;
  onPopupClose?: () => void;
}) {
  const t = useT();
  const client = useQueryClient();
  const [tonConnectUI] = useTonConnectUI();
  const { data: state } = useSovereignPack(telegramInitData, Boolean(telegramInitData));
  const [open, setOpen] = useState(popupMode);
  const [confirming, setConfirming] = useState(false);

  const refreshAll = () => Promise.all(
    ['sovereign-pack', 'premium-offers', 'game-state', 'ton-wallet', 'wallet-summary', 'player-inventory', 'player-heroes', 'pet-dashboard', 'hero-mining', 'arsenal', 'telegram-profile']
      .map(key => client.invalidateQueries({ queryKey: [key] })),
  );

  const reconcile = async () => {
    try {
      const result = await verifySovereignPackPurchases(telegramInitData);
      if (result.confirmed.length) toast.success('Celestial Sovereign Pack entregue!');
      await refreshAll();
    } catch { /* tentado novamente na próxima montagem */ }
  };

  const ensureWallet = async (): Promise<string> => {
    const current = tonConnectUI.account?.address;
    if (current) return current;
    const linked = new Promise<string>((resolve, reject) => {
      const unsubscribe = tonConnectUI.onStatusChange(wallet => {
        if (wallet?.account?.address) { unsubscribe(); resolve(wallet.account.address); }
      });
      window.setTimeout(() => { unsubscribe(); reject(new Error('Conecte uma carteira TON para continuar.')); }, 120_000);
    });
    await tonConnectUI.openModal();
    return linked;
  };

  const buy = useMutation({
    mutationFn: async () => {
      const payWithInternal = (state?.availableTon ?? 0) >= (state?.priceTon ?? 0);
      const walletAddress = payWithInternal ? undefined : await ensureWallet();
      const order = await startSovereignPackPurchase(telegramInitData, crypto.randomUUID(), walletAddress);
      if (order.status === 'payment_required') {
        await sendTonPayment(
          { paymentAddress: String(order.paymentAddress), paymentComment: String(order.paymentComment), amountNano: String(order.amountNano) },
          tx => tonConnectUI.sendTransaction(tx),
        );
      }
      return order;
    },
    onSuccess: async order => {
      setConfirming(false);
      void trackOfferImpression(telegramInitData, 'CELESTIAL_SOVEREIGN_PACK', 'purchased').catch(() => {});
      await refreshAll();
      if (order.status === 'completed') { close(); toast.success('Celestial Sovereign Pack garantido! Recompensas entregues.'); }
      else { toast.success('Pagamento enviado. Confirmando na blockchain…'); window.setTimeout(() => { void reconcile(); }, 6_000); }
    },
    onError: error => { setConfirming(false); toast.error(sovereignPackErrorText(error)); },
  });

  useEffect(() => { if (state?.pendingOrder) void reconcile(); }, [state?.pendingOrder?.orderId]);
  const close = () => { setOpen(false); setConfirming(false); onPopupClose?.(); };

  if (!state || (!popupMode && !state.show && !state.purchased)) return null;

  const payWithInternal = state.availableTon >= state.priceTon;
  const stock = Number(state.stockRemaining ?? state.celestialAvailable ?? 0);
  const soldOut = Boolean(state.soldOut) || stock <= 0;
  const paymentPending = Boolean(state.paymentPending);
  const processing = Boolean(state.processing);

  if (state.purchased) {
    if (popupMode) return null;
    return (
      <div className="relative w-full overflow-hidden rounded-3xl border border-amber-200/40 bg-forge-black/80 p-4 shadow-card">
        <img src={packArt} alt="Mythreon Celestial Sovereign Pack" loading="lazy" width={1024} height={640} className="absolute inset-0 h-full w-full object-cover opacity-25" />
        <div className="relative">
          <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-amber-200">
            <Crown className="h-3 w-3" /> {t('svp.title')}
          </p>
          <div className="mt-1 flex items-center gap-2">
            <h3 className="text-base font-semibold text-white">{t('svp.title')}</h3>
            <span className="rounded-full bg-emerald-500/20 px-2 py-0.5 text-[9px] font-black tracking-[0.16em] text-emerald-200">{t('svp.owned')}</span>
          </div>
          <div className="mt-3 grid grid-cols-3 gap-2 text-center">
            <div className="rounded-2xl bg-white/5 p-2">
              <p className="text-[10px] uppercase tracking-widest text-slate-400">Bônus TON</p>
              <p className="text-sm font-semibold text-amber-200">+{formatTon(state.ownerBonusPercent)}%</p>
            </div>
            <div className="rounded-2xl bg-white/5 p-2">
              <p className="text-[10px] uppercase tracking-widest text-slate-400">Itens</p>
              <p className="text-sm font-semibold text-slate-200">{state.items.length}</p>
            </div>
            <div className="rounded-2xl bg-white/5 p-2">
              <p className="text-[10px] uppercase tracking-widest text-slate-400">Mineração</p>
              <p className="text-sm font-semibold text-amber-100">{state.miningRevealPending ? '???' : 'REVELADA'}</p>
            </div>
          </div>
          {state.miningRevealPending ? <p className="mt-2 text-[10px] text-slate-400">{t('svp.revealNote')}</p> : null}
        </div>
      </div>
    );
  }

  const trigger = (
    <button
      type="button"
      onClick={() => setOpen(true)}
      className="relative w-full overflow-hidden rounded-3xl border border-amber-300/60 bg-forge-black/80 p-4 text-left shadow-[0_0_28px_rgba(251,191,36,0.22)]"
    >
      <img src={packArt} alt="Mythreon Celestial Sovereign Pack" loading="lazy" width={1024} height={640} className="absolute inset-0 h-full w-full object-cover opacity-40" />
      <div className="relative">
        <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-amber-200">
          <Crown className="h-3 w-3" /> 👑 {t('svp.badge')}
        </p>
        <h3 className="mt-1 text-lg font-black text-white">{t('svp.hero')} + {t('svp.pet')}</h3>
        <p className="text-[11px] text-slate-300">{t('svp.mysteryHint')}</p>
        <p className="text-[10px] uppercase tracking-[0.16em] text-slate-400">{soldOut ? t('svp.soldOut') : t('svp.stock', { value: stock })}</p>
        <div className="mt-2 flex items-center gap-2">
          <span className="inline-flex rounded-full bg-amber-400/25 px-3 py-1 text-xs font-black text-amber-100">{t('svp.price', { value: formatTon(state.priceTon) })}</span>
          <span className="inline-flex rounded-full border border-white/15 px-3 py-1 text-[10px] font-black uppercase tracking-[0.14em] text-white">{t('svp.view')}</span>
        </div>
      </div>
    </button>
  );

  if (!open) return trigger;

  const secondary = [
    t('svp.fc', { value: int(state.fcReward) }),
    t('svp.chests', { value: state.legendaryChests }),
    t('svp.mythicChests', { value: state.mythicChests }),
    t('svp.weapons', { value: state.nftWeapons }),
    t('svp.mythicArmors', { value: state.mythicArmors }),
    t('svp.celestialArmors', { value: state.celestialArmors }),
    t('svp.random', { value: state.randomItems }),
  ];

  const mainAction = () => {
    if (paymentPending) { void reconcile(); return; }
    void trackOfferImpression(telegramInitData, 'CELESTIAL_SOVEREIGN_PACK', 'clicked').catch(() => {});
    setConfirming(true);
  };

  return (
    <div className="fixed inset-0 z-[95] flex items-center justify-center bg-black/90 p-3">
      <div className="relative mx-auto flex max-h-[92vh] w-full max-w-[460px] flex-col overflow-hidden rounded-[1.9rem] border border-amber-200/60 bg-gradient-to-b from-[#0a0710] via-[#140c1f] to-black shadow-[0_0_70px_rgba(251,191,36,0.26)]">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_22%_12%,rgba(251,191,36,0.26),transparent_55%),radial-gradient(circle_at_82%_28%,rgba(168,85,247,0.24),transparent_52%)]" aria-hidden />
        <div className="forge-nft-sparkles pointer-events-none absolute inset-0 opacity-80" aria-hidden />

        <div className="relative flex items-start justify-between px-4 pt-4">
          <div>
            <p className="text-[9px] font-black uppercase tracking-[0.3em] text-amber-200">{t('svp.badge')}</p>
            <h2 className="text-lg font-black leading-tight text-white drop-shadow-[0_0_14px_rgba(251,191,36,0.55)]">{t('svp.title')}</h2>
          </div>
          <button onClick={close} aria-label="Fechar" className="grid h-8 w-8 shrink-0 place-items-center rounded-full border border-white/10 bg-black/60">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="relative overflow-y-auto px-4 pb-4">
          <img src={packArt} alt="Mythreon Celestial Sovereign Pack" loading="lazy" width={1024} height={640} className="mt-3 h-40 w-full rounded-2xl border border-amber-200/30 object-cover" />

          <div className="mt-3 grid grid-cols-2 gap-2">
            <div className="rounded-2xl border border-amber-200/25 bg-black/50 p-3">
              <p className="text-[10px] font-black uppercase tracking-[0.18em] text-amber-200">👑 {t('svp.hero')}</p>
              <p className="mt-1 text-[11px] text-slate-300">{t('svp.mystery')} — ???</p>
            </div>
            <div className="rounded-2xl border border-fuchsia-300/25 bg-black/50 p-3">
              <p className="text-[10px] font-black uppercase tracking-[0.18em] text-fuchsia-200">🐾 {t('svp.pet')}</p>
              <p className="mt-1 text-[11px] text-slate-300">{t('svp.mystery')} — ???</p>
            </div>
          </div>

          <div className="mt-2 rounded-2xl border border-amber-200/25 bg-black/50 p-3">
            <p className="text-[10px] font-black uppercase tracking-[0.18em] text-amber-100">⛏ {t('svp.bonus', { value: formatTon(state.accountBonusPercent) })}</p>
            <p className="mt-2 flex items-center gap-1 text-[9px] font-black uppercase tracking-[0.22em] text-slate-400">
              <Sparkles className="h-3 w-3" /> + BONUS
            </p>
            <p className="mt-1 text-[11px] leading-relaxed text-slate-200">{secondary.join(' · ')}</p>
          </div>

          <p className="mt-2 text-[10px] leading-relaxed text-slate-400">{t('svp.revealNote')}</p>

          <div className="mt-3 flex items-center justify-between rounded-2xl border border-amber-200/30 bg-black/50 px-3 py-2">
            <p className="text-xl font-black text-amber-100">{t('svp.price', { value: formatTon(state.priceTon) })}</p>
            <p className="text-right text-[9px] uppercase tracking-[0.14em] text-slate-400">
              {soldOut ? t('svp.soldOut') : t('svp.stock', { value: stock })}
            </p>
          </div>
          <p className="mt-1 text-[10px] text-slate-400">{payWithInternal ? t('svp.internal') : t('svp.external')}</p>

          {processing ? (
            <p className="mt-3 w-full rounded-2xl border border-emerald-300/30 bg-emerald-500/10 px-4 py-3 text-center text-sm font-black uppercase tracking-[0.14em] text-emerald-200">
              {t('svp.fulfilling')}
            </p>
          ) : (
            <button
              type="button"
              disabled={buy.isPending || soldOut || !state.eligible || !(state.windowOpen ?? true)}
              onClick={mainAction}
              className="mt-3 w-full rounded-2xl bg-gradient-to-b from-amber-300 to-orange-500 px-4 py-3 text-sm font-black uppercase tracking-[0.14em] text-black disabled:opacity-60"
            >
              {buy.isPending ? t('svp.processing')
                : soldOut ? t('svp.soldOut')
                : paymentPending ? `${t('svp.paymentPending')} · ${t('svp.checkPayment')}`
                : t('svp.buy', { value: formatTon(state.priceTon) })}
            </button>
          )}
        </div>

        {confirming ? (
          <div className="absolute inset-0 z-10 flex items-end bg-black/85 p-3" onClick={() => (buy.isPending ? undefined : setConfirming(false))}>
            <div className="w-full rounded-[1.6rem] border border-amber-200/50 bg-gradient-to-b from-[#140c1f] to-black p-4" onClick={event => event.stopPropagation()}>
              <p className="text-[9px] font-black uppercase tracking-[0.28em] text-amber-200">{t('svp.confirmTitle')}</p>
              <h3 className="text-lg font-black text-white">{t('svp.title')}</h3>
              <p className="text-sm font-black text-amber-100">{t('svp.price', { value: formatTon(state.priceTon) })}</p>
              <ul className="mt-2 space-y-0.5 text-[11px] text-slate-300">
                <li>👑 {t('svp.hero')} — {t('svp.mystery')} (???)</li>
                <li>🐾 {t('svp.pet')} — {t('svp.mystery')} (???)</li>
                <li>⛏ {t('svp.bonus', { value: formatTon(state.accountBonusPercent) })}</li>
                <li>✨ {secondary.join(' · ')}</li>
              </ul>
              <div className="mt-3 flex gap-2">
                <button type="button" disabled={buy.isPending} onClick={() => setConfirming(false)} className="w-1/3 rounded-xl bg-white/5 px-3 py-2.5 text-[11px] font-black uppercase text-slate-300">
                  {t('svp.cancel')}
                </button>
                <button
                  type="button"
                  disabled={buy.isPending}
                  onClick={() => buy.mutate()}
                  className="flex-1 rounded-xl bg-gradient-to-b from-amber-300 to-orange-500 px-3 py-2.5 text-[11px] font-black uppercase tracking-[0.14em] text-black disabled:opacity-60"
                >
                  {buy.isPending ? t('svp.processing') : t('svp.confirm')}
                </button>
              </div>
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}
