import { useEffect, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { Sparkles, X, Zap } from 'lucide-react';
import { toast } from 'sonner';
import { useMythicPowerPack } from '../hooks';
import { startMythicPowerPackPurchase, trackOfferImpression, verifyMythicPowerPackPurchases } from '../services';
import { sendTonPayment } from '../tonPayment';
import { mythicPowerPackErrorText } from '../mythicPowerPack';
import { formatTon } from '../economy';
import { useT } from '../LanguageContext';
import packArt from '../assets/mythic-power-pack.jpg';

const int = (value: number) => Math.round(Number(value || 0)).toLocaleString('pt-BR');

/**
 * ⚡ 20 TON MYTHIC PACK — card permanente em OFERTAS PREMIUM.
 *
 * Compras ilimitadas: o bônus de primeira compra (+MYTH e 1 Celestial Key) é decidido pelo servidor
 * e só existe uma vez por conta. O pagamento é integral: saldo interno quando cobre 100% do preço,
 * TonConnect caso contrário — nunca combinado. Nenhum valor é calculado no cliente.
 */
export function MythicPowerPackCard({ telegramInitData }: { telegramInitData: string }) {
  const t = useT();
  const client = useQueryClient();
  const [tonConnectUI] = useTonConnectUI();
  const { data: state } = useMythicPowerPack(telegramInitData, Boolean(telegramInitData));
  const [open, setOpen] = useState(false);
  const [confirming, setConfirming] = useState(false);

  const refreshAll = () => Promise.all(
    ['mythic-power-pack', 'premium-offers', 'game-state', 'ton-wallet', 'wallet-summary', 'player-inventory', 'player-heroes', 'pets', 'myth-wallet', 'arsenal', 'telegram-profile']
      .map(key => client.invalidateQueries({ queryKey: [key] })),
  );

  const reconcile = async () => {
    try {
      const result = await verifyMythicPowerPackPurchases(telegramInitData);
      if (result.confirmed.length) toast.success('20 TON MYTHIC PACK entregue!');
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
      const order = await startMythicPowerPackPurchase(telegramInitData, crypto.randomUUID(), walletAddress);
      if (order.status === 'payment_required') {
        await sendTonPayment(
          { paymentAddress: String(order.paymentAddress), paymentComment: String(order.paymentComment), amountNano: String(order.amountNano) },
          tx => tonConnectUI.sendTransaction(tx),
        );
      }
      return order;
    },
    onSuccess: async order => {
      void trackOfferImpression(telegramInitData, 'MYTHIC_POWER_PACK', 'purchased').catch(() => {});
      await refreshAll();
      setConfirming(false);
      if (order.status === 'completed') { setOpen(false); toast.success('20 TON MYTHIC PACK entregue! Recompensas creditadas.'); }
      else { toast.success('Pagamento enviado. Confirmando na blockchain…'); window.setTimeout(() => { void reconcile(); }, 6_000); }
    },
    onError: error => { setConfirming(false); toast.error(mythicPowerPackErrorText(error)); },
  });

  useEffect(() => { if (state?.pendingOrder) void reconcile(); }, [state?.pendingOrder?.orderId]);

  if (!state || !state.show) return null;

  const payWithInternal = state.availableTon >= state.priceTon;
  const paymentPending = Boolean(state.paymentPending);
  const processing = Boolean(state.processing);

  const rewards = [
    t('mpp.myth', { value: int(state.mythReward) }),
    t('mpp.egg', { value: state.mythicEggs }),
    t('mpp.voidChest', { value: state.voidChests }),
    t('mpp.equipChest', { value: state.equipmentChests }),
    t('mpp.fragments', { value: state.universalFragments }),
    t('mpp.tickets', { value: state.pvpTickets }),
    t('mpp.eternityKeys', { value: state.eternityKeys }),
    t('mpp.voidKeys', { value: state.voidKeys }),
    t('mpp.petFood', { value: state.petFood }),
    t('mpp.heroXp', { value: int(state.heroXp) }),
  ];

  const trigger = (
    <button
      type="button"
      onClick={() => setOpen(true)}
      className="relative w-full overflow-hidden rounded-3xl border border-fuchsia-300/40 bg-forge-black/80 p-4 text-left shadow-card"
    >
      <img src={packArt} alt="Mythreon 20 TON Mythic Pack" loading="lazy" width={1024} height={1024} className="absolute inset-0 h-full w-full object-cover opacity-40" />
      <div className="relative">
        <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-fuchsia-200">
          <Zap className="h-3 w-3" /> ⚡ {t('mpp.badge')}
        </p>
        <h3 className="mt-1 text-lg font-black text-white">{t('mpp.title')}</h3>
        <p className="text-[11px] text-slate-300">{t('mpp.subtitle')}</p>
        <p className="text-[10px] uppercase tracking-[0.16em] text-slate-400">
          {state.firstPurchaseAvailable ? `${t('mpp.bonusTitle')} · ${t('mpp.bonusMyth', { value: int(state.firstBonusMyth) })} + ${t('mpp.bonusKey')}` : t('mpp.owned', { value: state.purchasedCount })}
        </p>
        <div className="mt-2 flex items-center gap-2">
          <span className="inline-flex rounded-full bg-fuchsia-400/25 px-3 py-1 text-xs font-black text-fuchsia-100">{t('mpp.price', { value: formatTon(state.priceTon) })}</span>
          <span className="inline-flex rounded-full border border-white/15 px-3 py-1 text-[10px] font-black uppercase tracking-[0.14em] text-white">{t('mpp.view')}</span>
        </div>
      </div>
    </button>
  );

  if (!open) return trigger;

  const mainAction = () => {
    if (paymentPending) { void reconcile(); return; }
    void trackOfferImpression(telegramInitData, 'MYTHIC_POWER_PACK', 'clicked').catch(() => {});
    setConfirming(true);
  };

  return (
    <div className="fixed inset-0 z-[95] flex items-center justify-center bg-black/90 p-3">
      <div className="relative mx-auto flex max-h-[92vh] w-full max-w-[460px] flex-col overflow-hidden rounded-[1.9rem] border border-fuchsia-300/45 bg-gradient-to-b from-[#160726] via-[#0a0616] to-black shadow-[0_0_60px_rgba(217,70,239,0.2)]">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_20%_10%,rgba(217,70,239,0.22),transparent_55%),radial-gradient(circle_at_85%_25%,rgba(56,189,248,0.2),transparent_50%)]" aria-hidden />

        <div className="relative flex items-start justify-between px-4 pt-4">
          <div>
            <p className="text-[9px] font-black uppercase tracking-[0.3em] text-fuchsia-200">{t('mpp.badge')}</p>
            <h2 className="text-lg font-black leading-tight text-white drop-shadow-[0_0_12px_rgba(217,70,239,0.4)]">{t('mpp.title')}</h2>
            <p className="text-[9px] font-black uppercase tracking-[0.2em] text-slate-400">{t('mpp.unlimited')}</p>
          </div>
          <button onClick={() => { setOpen(false); setConfirming(false); }} aria-label="Fechar" className="grid h-8 w-8 shrink-0 place-items-center rounded-full border border-white/10 bg-black/60">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="relative flex-1 overflow-y-auto px-4 pb-4">
          <div className="relative mt-3 overflow-hidden rounded-2xl border border-fuchsia-300/30 bg-black/50 p-2 text-center">
            <img src={packArt} alt={t('mpp.title')} loading="lazy" width={1024} height={1024} className="h-40 w-full rounded-xl object-cover opacity-95" />
            <p className="mt-1 text-[11px] font-black uppercase tracking-[0.16em] text-white">{t('mpp.subtitle')}</p>
          </div>

          <div className="mt-3 rounded-2xl border border-white/10 bg-white/5 px-3 py-2">
            <p className="flex items-center gap-1 text-[9px] font-black uppercase tracking-[0.18em] text-fuchsia-200">
              <Sparkles className="h-3 w-3" /> REWARDS
            </p>
            <p className="mt-1 text-[11px] leading-relaxed text-slate-200">{rewards.join(' · ')}</p>
          </div>

          {state.firstPurchaseAvailable ? (
            <div className="mt-2 rounded-2xl border border-amber-300/40 bg-amber-400/10 px-3 py-2 text-center">
              <p className="text-[9px] font-black uppercase tracking-[0.2em] text-amber-200">{t('mpp.bonusTitle')}</p>
              <p className="text-[12px] font-black text-amber-100">
                {t('mpp.bonusMyth', { value: int(state.firstBonusMyth) })} · {t('mpp.bonusKey')}
              </p>
            </div>
          ) : (
            <p className="mt-2 rounded-2xl border border-white/10 bg-black/40 px-3 py-2 text-center text-[10px] uppercase tracking-[0.14em] text-slate-400">
              {t('mpp.bonusUsed')}
            </p>
          )}

          <p className="mt-2 text-[10px] leading-relaxed text-slate-400">{t('mpp.note')}</p>

          <div className="mt-3 flex items-center justify-between rounded-2xl border border-fuchsia-300/30 bg-black/50 px-3 py-2">
            <p className="text-xl font-black text-fuchsia-100">{t('mpp.price', { value: formatTon(state.priceTon) })}</p>
            <p className="text-right text-[9px] uppercase tracking-[0.14em] text-slate-400">{t('mpp.owned', { value: state.purchasedCount })}</p>
          </div>
          <p className="mt-1 text-[10px] text-slate-400">{payWithInternal ? t('mpp.internal') : t('mpp.external')}</p>

          {processing ? (
            <p className="mt-3 w-full rounded-2xl border border-emerald-300/30 bg-emerald-500/10 px-4 py-3 text-center text-sm font-black uppercase tracking-[0.14em] text-emerald-200">
              {t('mpp.fulfilling')}
            </p>
          ) : (
            <button
              type="button"
              disabled={buy.isPending || !state.windowOpen}
              onClick={mainAction}
              className="mt-3 w-full rounded-2xl bg-gradient-to-b from-fuchsia-300 to-fuchsia-600 px-4 py-3 text-sm font-black uppercase tracking-[0.14em] text-[#150720] disabled:opacity-60"
            >
              {buy.isPending ? t('mpp.processing')
                : paymentPending ? `${t('mpp.paymentPending')} · ${t('mpp.checkPayment')}`
                : t('mpp.buy', { value: formatTon(state.priceTon) })}
            </button>
          )}
        </div>

        {confirming ? (
          <div className="absolute inset-0 z-10 flex items-end bg-black/85 p-3" onClick={() => (buy.isPending ? undefined : setConfirming(false))}>
            <div className="w-full rounded-[1.6rem] border border-fuchsia-300/45 bg-gradient-to-b from-[#0a0616] to-black p-4" onClick={event => event.stopPropagation()}>
              <p className="text-[9px] font-black uppercase tracking-[0.28em] text-fuchsia-200">{t('mpp.confirmTitle')}</p>
              <h3 className="text-lg font-black text-white">{t('mpp.title')}</h3>
              <p className="text-sm font-black text-fuchsia-100">{t('mpp.price', { value: formatTon(state.priceTon) })}</p>
              <ul className="mt-2 space-y-0.5 text-[11px] text-slate-300">
                <li>✨ {rewards.slice(0, 5).join(' · ')}</li>
                <li>🔑 {rewards.slice(5).join(' · ')}</li>
                {state.firstPurchaseAvailable ? <li>🎁 {t('mpp.bonusMyth', { value: int(state.firstBonusMyth) })} · {t('mpp.bonusKey')}</li> : null}
              </ul>
              <div className="mt-3 flex gap-2">
                <button type="button" disabled={buy.isPending} onClick={() => setConfirming(false)} className="w-1/3 rounded-xl bg-white/5 px-3 py-2.5 text-[11px] font-black uppercase text-slate-300">
                  {t('mpp.cancel')}
                </button>
                <button
                  type="button"
                  disabled={buy.isPending}
                  onClick={() => buy.mutate()}
                  className="flex-1 rounded-xl bg-gradient-to-b from-fuchsia-300 to-fuchsia-600 px-3 py-2.5 text-[11px] font-black uppercase tracking-[0.14em] text-[#150720] disabled:opacity-60"
                >
                  {buy.isPending ? t('mpp.processing') : t('mpp.confirm')}
                </button>
              </div>
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}
