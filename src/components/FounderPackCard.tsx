import { useLocalizedText } from '../LanguageContext';
import { useEffect, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { Crown, Loader2, ShieldCheck, Sparkles, Wallet, X } from 'lucide-react';
import { toast } from 'sonner';
import { useFounderPack } from '../hooks';
import { startFounderPackPurchase, verifyFounderPackPurchases } from '../services';
import { sendTonPayment } from '../tonPayment';
import { founderCountdown, founderErrorText } from '../founderPack';
import { formatTon } from '../economy';
import founderArt from '../assets/founder-pack.jpg';

/**
 * 👑 Mythic Seas FOUNDER PACK — 25 TON, exclusive to brand new accounts.
 *
 * The card only renders when the SERVER says the player is inside the eligibility window and has not
 * bought it yet (`state.show`). Payment follows the same rule as every other TON product in the game:
 * 1. internal TON balance when it covers 100% of the price (instant delivery);
 * 2. TonConnect otherwise, charging the full price there — balances are never mixed.
 * Rewards are granted atomically inside the database; nothing is credited from here.
 */
export function FounderPackCard({ telegramInitData, popupMode = false, onPopupClose }: {
  telegramInitData: string;
  /** Popup mode: rendered by the daily premium-offer queue — no trigger card, opens immediately. */
  popupMode?: boolean;
  onPopupClose?: () => void;
}) {
  const localizeText = useLocalizedText();

  const client = useQueryClient();
  const [tonConnectUI] = useTonConnectUI();
  const { data: state } = useFounderPack(telegramInitData, Boolean(telegramInitData));
  const [open, setOpen] = useState(popupMode);
  const [tick, setTick] = useState(0);

  useEffect(() => { const id = window.setInterval(() => setTick(v => v + 1), 1000); return () => window.clearInterval(id); }, []);

  const refreshAll = () => Promise.all(
    ['founder-pack', 'game-state', 'ton-wallet', 'wallet-summary', 'myth-wallet', 'player-inventory', 'player-heroes', 'pet-dashboard', 'season-pass', 'telegram-profile']
      .map(key => client.invalidateQueries({ queryKey: [key] })),
  );

  const reconcile = async () => {
    try {
      const result = await verifyFounderPackPurchases(telegramInitData);
      if (result.confirmed.length) toast.success('Founder Pack entregue! Confira heróis, pets e inventário.');
      await refreshAll();
    } catch { /* the reconciler is retried on the next open */ }
  };

  /** TonConnect must always end inside the wallet: open the modal when nothing is linked yet. */
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
      const order = await startFounderPackPurchase(telegramInitData, crypto.randomUUID(), walletAddress);
      if (order.status === 'payment_required') {
        await sendTonPayment(
          { paymentAddress: String(order.paymentAddress), paymentComment: String(order.paymentComment), amountNano: String(order.amountNano) },
          tx => tonConnectUI.sendTransaction(tx),
        );
      }
      return order;
    },
    onSuccess: async order => {
      await refreshAll();
      if (order.status === 'completed') { close(); toast.success('Founder Pack garantido! Todas as recompensas foram entregues.'); }
      else { toast.success('Pagamento enviado. Confirmando na blockchain…'); window.setTimeout(() => { void reconcile(); }, 6_000); }
    },
    onError: error => toast.error(founderErrorText(error)),
  });

  // A pending TonConnect intent means the wallet was already opened: settle it as soon as we mount.
  useEffect(() => { if (state?.pendingOrder) void reconcile(); }, [state?.pendingOrder?.orderId]);

  const close = () => { setOpen(false); onPopupClose?.(); };

  // Enquanto o estado do servidor não chega, o popup espera: fechar aqui faria a oferta
  // desaparecer antes de renderizar (e queimar a exibição do dia).
  useEffect(() => { if (popupMode && state && !state.show) onPopupClose?.(); }, [popupMode, state?.show]);

  if (!state || !state.show) return null;

  const countdown = founderCountdown(state.eligibleUntil, Date.now() + tick * 0);
  const payWithInternal = state.availableTon >= state.priceTon;
  const rewards = [
    { icon: '🎟️', label: 'Season Pass Premium', detail: state.passTier === 'legendary' ? 'Tier Legendary' : 'Tier Adventurer' },
    { icon: '🪙', label: `${state.mythAmount.toLocaleString('pt-BR')} MYTH`, detail: 'Creditado na carteira' },
    { icon: '⚔️', label: 'Herói Founder EXCLUSIVE', detail: `MYTH MINING · ${Math.round(state.heroDailyMyth ?? 0).toLocaleString('pt-BR')} MYTH/dia` },
    { icon: '🐾', label: 'Pet Founder EXCLUSIVE', detail: `MYTH MINING · ${Math.round(state.petDailyMyth ?? 0).toLocaleString('pt-BR')} MYTH/dia` },
    { icon: '🗡️', label: 'Arma Founder EXCLUSIVE', detail: 'Equipamento exclusivo 1/1' },
    { icon: '🗝️', label: `${state.legendaryChests ?? 1} Baús Lendários`, detail: 'Equipamentos lendários' },
    { icon: '💎', label: `${state.fragments} Fragmentos`, detail: 'Universais' },
    { icon: '📦', label: 'Baú Premium', detail: 'BERRIES · tickets · fragmentos' },
    { icon: '👑', label: 'Badge de Fundador', detail: 'Perfil permanente' },
    { icon: '🖼️', label: 'Moldura de Fundador', detail: 'Cosmético exclusivo' },
  ];

  return (
    <>
      {popupMode ? null : (
      <button
        onClick={() => setOpen(true)}
        className="relative w-full overflow-hidden rounded-3xl border border-amber-300/40 bg-forge-black/80 text-left shadow-card"
      >
        <img src={founderArt} alt={localizeText("Mythic Seas Founder Pack ")} loading="lazy" width={1024} height={640} className="absolute inset-0 h-full w-full object-cover opacity-40" />
        <div className="relative flex items-center justify-between gap-3 p-4">
          <div className="min-w-0">
            <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-amber-300">
              <Crown className="h-3 w-3" /> {localizeText("Founder Pack ")}</p>
            <h3 className="mt-1 truncate text-base font-semibold text-white">{localizeText("Pacote de Fundador ")}</h3>
            <p className="text-[11px] text-slate-300">
              {state.requireNewAccount ? localizeText("Somente contas novas") : localizeText("Disponível para todos")} · {countdown === '--' ? localizeText("oferta ativa") : `encerra em ${countdown}`}
            </p>
          </div>
          <div className="shrink-0 rounded-2xl bg-amber-400/20 px-3 py-2 text-center">
            <p className="text-sm font-bold text-amber-200">{formatTon(state.priceTon)} TON</p>
            <p className="text-[10px] uppercase tracking-widest text-amber-100/80">{localizeText("Ver pacote ")}</p>
          </div>
        </div>
      </button>
      )}

      {open ? (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/80 p-3 sm:items-center">
          <div className="forge-safe-page max-h-[90vh] w-full max-w-md overflow-y-auto rounded-3xl border border-amber-300/30 bg-forge-black p-4 shadow-card">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-amber-300">
                  <Sparkles className="h-3 w-3" /> {localizeText("Oferta única ")}</p>
                <h3 className="text-lg font-semibold text-white">{localizeText("Mythic Seas Founder Pack ")}</h3>
              </div>
              <button onClick={close} className="rounded-full bg-white/5 p-2 text-slate-300" aria-label={localizeText("Fechar")}>
                <X className="h-4 w-4" />
              </button>
            </div>

            <img src={founderArt} alt={localizeText("Recompensas do Founder Pack")} loading="lazy" width={1024} height={640} className="mt-3 h-32 w-full rounded-2xl object-cover" />

            <div className="mt-3 grid grid-cols-1 gap-2">
              {rewards.map(reward => (
                <div key={reward.label} className="flex items-center gap-3 rounded-2xl border border-white/10 bg-white/5 px-3 py-2">
                  <span className="text-lg" aria-hidden>{reward.icon}</span>
                  <div className="min-w-0">
                    <p className="truncate text-xs font-semibold text-white">{reward.label}</p>
                    <p className="truncate text-[11px] text-slate-400">{reward.detail}</p>
                  </div>
                </div>
              ))}
            </div>

            <div className="mt-3 rounded-2xl border border-white/10 bg-white/5 p-3 text-[11px] text-slate-300">
              <p className="flex items-center gap-1 text-slate-200"><ShieldCheck className="h-3 w-3 text-emerald-300" /> {localizeText(" Uma compra por conta · entrega automática ")}</p>
              <p className="mt-1">
                {state.requireNewAccount
                  ? `Janela de contas novas: ${state.eligibilityDays} dias`
                  : localizeText("Disponível para todos os jogadores")}
                {countdown === '--' ? '' : ` · encerra em ${countdown}`}
              </p>
              <p className="mt-1 text-amber-200">{localizeText(" Herói, pet e arma Founder mineram MYTH (sem TON mining) e não recebem o bônus do Veteran Vault. ")}</p>
              <p className="mt-1 flex items-center gap-1"><Wallet className="h-3 w-3 text-sky-300" /> {localizeText("Saldo interno:")}{formatTon(state.availableTon)} TON</p>
              {state.testMode ? <p className="mt-1 text-amber-300">{localizeText("Modo administrador: visível para testes.")}</p> : null}
            </div>

            <button
              onClick={() => buy.mutate()}
              disabled={buy.isPending || !state.eligible}
              className="mt-3 inline-flex w-full items-center justify-center gap-2 rounded-3xl bg-amber-400/20 px-4 py-3 text-sm font-semibold text-amber-100 transition hover:bg-amber-400/30 disabled:opacity-50"
            >
              {buy.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Crown className="h-4 w-4" />}
              {state.eligible
                ? `Comprar por ${formatTon(state.priceTon)} TON ${payWithInternal ? '(saldo interno)' : '(TonConnect)'}`
                : localizeText("Fora da janela de elegibilidade")}
            </button>
          </div>
        </div>
      ) : null}
    </>
  );
}
