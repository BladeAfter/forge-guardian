import { useEffect, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { Shield, Sparkles, X } from 'lucide-react';
import { toast } from 'sonner';
import { useAdventurerPack } from '../hooks';
import { startAdventurerPackPurchase, trackOfferImpression, verifyAdventurerPackPurchases } from '../services';
import { sendTonPayment } from '../tonPayment';
import { adventurerPackErrorText } from '../adventurerPack';
import { formatTon } from '../economy';
import { useT } from '../LanguageContext';
import packArt from '../assets/legendary-adventurer-pack.jpg';

const int = (value: number) => Math.round(Number(value || 0)).toLocaleString('pt-BR');

/**
 * 🏆 LEGENDARY ADVENTURER PACK (30 TON) — card permanente em OFERTAS PREMIUM e popup diário.
 *
 * Identidade visual própria (azul-marinho profundo + ouro real), abaixo do Mythic Vanguard e dos
 * packs Celestiais na hierarquia. Todo o conteúdo, janela, estoque, limite de compra, entrega, o
 * passe oficial de 5 TON incluído no preço e o bônus permanente de +X% na mineração de TON da conta
 * vêm do servidor. O Herói Lendário chega com a mineração "A SER REVELADA" — avisado ANTES da
 * compra, sem valor prometido e sem mineração retroativa. Teto LEGENDARY: nada Celestial/Mythic.
 *
 * Fechar o popup só silencia o popup do dia: a oferta continua no menu OFERTAS PREMIUM.
 */
export function LegendaryAdventurerPackCard({ telegramInitData, popupMode = false, onPopupClose }: {
  telegramInitData: string;
  popupMode?: boolean;
  onPopupClose?: () => void;
}) {
  const t = useT();
  const client = useQueryClient();
  const [tonConnectUI] = useTonConnectUI();
  const { data: state } = useAdventurerPack(telegramInitData, Boolean(telegramInitData));
  const [open, setOpen] = useState(popupMode);
  const [confirming, setConfirming] = useState(false);

  const refreshAll = () => Promise.all(
    ['adventurer-pack', 'premium-offers', 'game-state', 'ton-wallet', 'wallet-summary', 'player-inventory', 'player-heroes', 'hero-mining', 'arsenal', 'season-pass', 'telegram-profile']
      .map(key => client.invalidateQueries({ queryKey: [key] })),
  );

  const reconcile = async () => {
    try {
      const result = await verifyAdventurerPackPurchases(telegramInitData);
      if (result.confirmed.length) toast.success('Legendary Adventurer Pack entregue!');
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
      const order = await startAdventurerPackPurchase(telegramInitData, crypto.randomUUID(), walletAddress);
      if (order.status === 'payment_required') {
        await sendTonPayment(
          { paymentAddress: String(order.paymentAddress), paymentComment: String(order.paymentComment), amountNano: String(order.amountNano) },
          tx => tonConnectUI.sendTransaction(tx),
        );
      }
      return order;
    },
    onSuccess: async order => {
      void trackOfferImpression(telegramInitData, 'LEGENDARY_ADVENTURER_PACK', 'purchased').catch(() => {});
      await refreshAll();
      if (order.status === 'completed') { close(); toast.success('Legendary Adventurer Pack garantido! Recompensas entregues.'); }
      else { toast.success('Pagamento enviado. Confirmando na blockchain…'); window.setTimeout(() => { void reconcile(); }, 6_000); }
    },
    onError: error => { setConfirming(false); toast.error(adventurerPackErrorText(error)); },
  });

  useEffect(() => { if (state?.pendingOrder) void reconcile(); }, [state?.pendingOrder?.orderId]);
  useEffect(() => { if (popupMode && state && (!state.show || state.purchased)) onPopupClose?.(); }, [popupMode, state?.show, state?.purchased]);

  const close = () => { setOpen(false); setConfirming(false); onPopupClose?.(); };

  if (!state || (!state.show && !state.purchased)) return null;

  const payWithInternal = state.availableTon >= state.priceTon;
  const stock = Number(state.stockRemaining ?? state.legendaryAvailable ?? 0);
  const soldOut = Boolean(state.soldOut) || stock <= 0;
  const paymentPending = Boolean(state.paymentPending);
  const processing = Boolean(state.processing);

  if (state.purchased) {
    if (popupMode) return null;
    return (
      <div className="relative w-full overflow-hidden rounded-3xl border border-amber-300/30 bg-forge-black/80 p-4 shadow-card">
        <img src={packArt} alt="Mythic Seas Legendary Adventurer Pack" loading="lazy" width={1024} height={1024} className="absolute inset-0 h-full w-full object-cover opacity-25" />
        <div className="relative">
          <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-amber-200">
            <Shield className="h-3 w-3" /> {t('ap.title')}
          </p>
          <div className="mt-1 flex items-center gap-2">
            <h3 className="text-base font-semibold text-white">{t('ap.title')}</h3>
            <span className="rounded-full bg-emerald-500/20 px-2 py-0.5 text-[9px] font-black tracking-[0.16em] text-emerald-200">{t('ap.owned')}</span>
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
              <p className="text-sm font-semibold text-amber-200">{state.miningRevealPending ? '???' : 'REVELADA'}</p>
            </div>
          </div>
          {state.miningRevealPending ? <p className="mt-2 text-[10px] text-slate-400">{t('ap.revealNote')}</p> : null}
        </div>
      </div>
    );
  }

  // Card compacto de OFERTAS PREMIUM.
  const trigger = (
    <button
      type="button"
      onClick={() => setOpen(true)}
      className="relative w-full overflow-hidden rounded-3xl border border-amber-300/40 bg-forge-black/80 p-4 text-left shadow-card"
    >
      <img src={packArt} alt="Mythic Seas Legendary Adventurer Pack" loading="lazy" width={1024} height={1024} className="absolute inset-0 h-full w-full object-cover opacity-40" />
      <div className="relative">
        <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-amber-200">
          <Shield className="h-3 w-3" /> 🏆 {t('ap.title')}
        </p>
        <h3 className="mt-1 text-lg font-black text-white">{t('ap.hero')}</h3>
        <p className="text-[11px] text-slate-300">{t('ap.mysteryHint')}</p>
        <p className="text-[10px] uppercase tracking-[0.16em] text-slate-400">{soldOut ? t('ap.soldOut') : t('ap.stock', { value: stock })}</p>
        <div className="mt-2 flex items-center gap-2">
          <span className="inline-flex rounded-full bg-amber-400/25 px-3 py-1 text-xs font-black text-amber-100">{t('ap.price', { value: formatTon(state.priceTon) })}</span>
          <span className="inline-flex rounded-full border border-white/15 px-3 py-1 text-[10px] font-black uppercase tracking-[0.14em] text-white">{t('ap.view')}</span>
        </div>
      </div>
    </button>
  );

  if (!open) return trigger;

  const secondary = [
    t('ap.pass'),
    t('ap.fc', { value: int(state.fcReward) }),
    t('ap.chests', { value: state.legendaryChests }),
    t('ap.weapons', { value: state.nftWeapons }),
    t('ap.armors', { value: state.legendaryArmors }),
    t('ap.fragments', { value: state.universalFragments }),
    t('ap.random', { value: state.randomItems }),
  ];

  const mainAction = () => {
    if (paymentPending) { void reconcile(); return; }
    void trackOfferImpression(telegramInitData, 'LEGENDARY_ADVENTURER_PACK', 'clicked').catch(() => {});
    setConfirming(true);
  };

  return (
    <div className="fixed inset-0 z-[95] flex items-center justify-center bg-black/90 p-3">
      {/* Aura lendária: azul-marinho profundo + ouro real, um degrau abaixo do Mythic Vanguard. */}
      <div className="relative mx-auto flex max-h-[92vh] w-full max-w-[460px] flex-col overflow-hidden rounded-[1.9rem] border border-amber-300/45 bg-gradient-to-b from-[#070d1f] via-[#050916] to-black shadow-[0_0_60px_rgba(251,191,36,0.18)]">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_18%_12%,rgba(251,191,36,0.18),transparent_55%),radial-gradient(circle_at_85%_25%,rgba(56,110,200,0.22),transparent_50%)]" aria-hidden />

        <div className="relative flex items-start justify-between px-4 pt-4">
          <div>
            <p className="text-[9px] font-black uppercase tracking-[0.3em] text-amber-200">{t('ap.badge')}</p>
            <h2 className="text-lg font-black leading-tight text-white drop-shadow-[0_0_12px_rgba(251,191,36,0.4)]">{t('ap.title')}</h2>
            <p className="text-[9px] font-black uppercase tracking-[0.2em] text-slate-400">{t('ap.cap')}</p>
          </div>
          <button onClick={close} aria-label="Fechar" className="grid h-8 w-8 shrink-0 place-items-center rounded-full border border-white/10 bg-black/60">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="relative flex-1 overflow-y-auto px-4 pb-4">
          <div className="relative mt-3 overflow-hidden rounded-2xl border border-amber-300/30 bg-black/50 p-2 text-center">
            <img src={packArt} alt={t('ap.hero')} loading="lazy" width={1024} height={1024} className="h-40 w-full rounded-xl object-cover opacity-95" />
            <p className="mt-1 text-[11px] font-black uppercase tracking-[0.16em] text-white">{t('ap.hero')}</p>
            <p className="text-[10px] font-bold text-amber-200">{t('ap.mystery')}</p>
            <p className="text-xl font-black leading-none text-amber-100">???</p>
          </div>
          <p className="mt-2 text-center text-[9px] font-black uppercase tracking-[0.16em] text-amber-200/90">{t('ap.mysteryHint')}</p>

          <p className="mt-3 rounded-2xl border border-amber-300/30 bg-amber-400/10 px-3 py-2 text-center text-[11px] font-black uppercase tracking-[0.12em] text-amber-100">
            {t('ap.bonus', { value: formatTon(state.accountBonusPercent) })}
          </p>
          <p className="mt-2 rounded-2xl border border-sky-300/30 bg-sky-400/10 px-3 py-2 text-center text-[11px] font-black uppercase tracking-[0.12em] text-sky-100">
            {t('ap.pass')}
          </p>

          <div className="mt-3 rounded-2xl border border-white/10 bg-white/5 px-3 py-2">
            <p className="flex items-center gap-1 text-[9px] font-black uppercase tracking-[0.18em] text-amber-200">
              <Sparkles className="h-3 w-3" /> + BONUS
            </p>
            <p className="mt-1 text-[11px] leading-relaxed text-slate-200">{secondary.join(' · ')}</p>
          </div>

          <p className="mt-2 text-[10px] leading-relaxed text-slate-400">{t('ap.revealNote')}</p>

          <div className="mt-3 flex items-center justify-between rounded-2xl border border-amber-300/30 bg-black/50 px-3 py-2">
            <div>
              <p className="text-xl font-black text-amber-100">{t('ap.price', { value: formatTon(state.priceTon) })}</p>
              <p className="text-[9px] font-black uppercase tracking-[0.14em] text-emerald-200">{t('ap.noExtra')}</p>
            </div>
            <p className="text-right text-[9px] uppercase tracking-[0.14em] text-slate-400">
              {soldOut ? t('ap.soldOut') : t('ap.stock', { value: stock })}
            </p>
          </div>
          <p className="mt-1 text-[10px] text-slate-400">{payWithInternal ? t('ap.internal') : t('ap.external')}</p>

          {processing ? (
            <p className="mt-3 w-full rounded-2xl border border-emerald-300/30 bg-emerald-500/10 px-4 py-3 text-center text-sm font-black uppercase tracking-[0.14em] text-emerald-200">
              {t('ap.fulfilling')}
            </p>
          ) : (
            <button
              type="button"
              disabled={buy.isPending || soldOut || !state.eligible || !(state.windowOpen ?? true)}
              onClick={mainAction}
              className="mt-3 w-full rounded-2xl bg-gradient-to-b from-amber-300 to-amber-600 px-4 py-3 text-sm font-black uppercase tracking-[0.14em] text-[#0b1020] disabled:opacity-60"
            >
              {buy.isPending ? t('ap.processing')
                : soldOut ? t('ap.soldOut')
                : paymentPending ? `${t('ap.paymentPending')} · ${t('ap.checkPayment')}`
                : t('ap.buy', { value: formatTon(state.priceTon) })}
            </button>
          )}
        </div>

        {/* Segundo passo obrigatório: nada é pago sem confirmação explícita. */}
        {confirming ? (
          <div className="absolute inset-0 z-10 flex items-end bg-black/85 p-3" onClick={() => (buy.isPending ? undefined : setConfirming(false))}>
            <div className="w-full rounded-[1.6rem] border border-amber-300/45 bg-gradient-to-b from-[#050916] to-black p-4" onClick={event => event.stopPropagation()}>
              <p className="text-[9px] font-black uppercase tracking-[0.28em] text-amber-200">{t('ap.confirmTitle')}</p>
              <h3 className="text-lg font-black text-white">{t('ap.title')}</h3>
              <p className="text-sm font-black text-amber-100">{t('ap.price', { value: formatTon(state.priceTon) })}</p>
              <ul className="mt-2 space-y-0.5 text-[11px] text-slate-300">
                <li>🏆 {t('ap.hero')} — {t('ap.mystery')} (???)</li>
                <li>🎟 {t('ap.pass')}</li>
                <li>⛏ {t('ap.bonus', { value: formatTon(state.accountBonusPercent) })}</li>
                <li>✨ {secondary.slice(1).join(' · ')}</li>
              </ul>
              <div className="mt-3 flex gap-2">
                <button type="button" disabled={buy.isPending} onClick={() => setConfirming(false)} className="w-1/3 rounded-xl bg-white/5 px-3 py-2.5 text-[11px] font-black uppercase text-slate-300">
                  {t('ap.cancel')}
                </button>
                <button
                  type="button"
                  disabled={buy.isPending}
                  onClick={() => buy.mutate()}
                  className="flex-1 rounded-xl bg-gradient-to-b from-amber-300 to-amber-600 px-3 py-2.5 text-[11px] font-black uppercase tracking-[0.14em] text-[#0b1020] disabled:opacity-60"
                >
                  {buy.isPending ? t('ap.processing') : t('ap.confirm')}
                </button>
              </div>
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}
