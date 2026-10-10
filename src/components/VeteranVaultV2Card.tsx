import { useLocalizedText } from '../LanguageContext';
import { useEffect, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { Loader2, ShieldCheck, Sparkles, Swords, X } from 'lucide-react';
import { toast } from 'sonner';
import { useVeteranV2 } from '../hooks';
import { startVeteranV2Purchase, verifyVeteranV2Purchases } from '../services';
import { sendTonPayment } from '../tonPayment';
import { veteranV2DailyMyth, veteranV2ErrorText } from '../veteranVaultV2';
import { formatTon } from '../economy';
import vaultArt from '../assets/veteran-vault-v2.webp';

const myth = (value: number) => Math.round(Number(value || 0)).toLocaleString('pt-BR');

/**
 * ⚔️ VETERAN VAULT (100 TON) — pacote premium com linha Veteran exclusiva.
 *
 * O servidor decide tudo: visibilidade (`show`), preço, estoque via fundo de MYTH (`soldOut`),
 * entrega dos itens, taxas de mineração em MYTH e o bônus de +10% para quem compra.
 * Pagamento segue a regra oficial: 100% TON interno quando cobre o preço, senão 100% TonConnect.
 */
export function VeteranVaultV2Card({ telegramInitData, popupMode = false, onPopupClose }: {
  telegramInitData: string;
  /** Popup mode: rendered by the daily premium-offer queue — no trigger card, opens immediately. */
  popupMode?: boolean;
  onPopupClose?: () => void;
}) {
  const localizeText = useLocalizedText();

  const client = useQueryClient();
  const [tonConnectUI] = useTonConnectUI();
  const { data: state } = useVeteranV2(telegramInitData, Boolean(telegramInitData));
  const [open, setOpen] = useState(popupMode);

  const refreshAll = () => Promise.all(
    ['veteran-v2', 'game-state', 'ton-wallet', 'wallet-summary', 'myth-wallet', 'player-inventory', 'player-heroes', 'pet-dashboard', 'season-pass', 'hero-mining', 'telegram-profile']
      .map(key => client.invalidateQueries({ queryKey: [key] })),
  );

  const reconcile = async () => {
    try {
      const result = await verifyVeteranV2Purchases(telegramInitData);
      if (result.confirmed.length) toast.success('Veteran Vault ativo! Recompensas entregues.');
      await refreshAll();
    } catch { /* retried on the next mount */ }
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
      const order = await startVeteranV2Purchase(telegramInitData, crypto.randomUUID(), walletAddress);
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
      if (order.status === 'completed') { close(); toast.success('Veteran Vault garantido! Recompensas entregues.'); }
      else { toast.success('Pagamento enviado. Confirmando na blockchain…'); window.setTimeout(() => { void reconcile(); }, 6_000); }
    },
    onError: error => toast.error(veteranV2ErrorText(error)),
  });

  useEffect(() => { if (state?.pendingOrder) void reconcile(); }, [state?.pendingOrder?.orderId]);

  const close = () => { setOpen(false); onPopupClose?.(); };

  // Enquanto o estado do servidor não chega, o popup espera: fechar aqui faria a oferta
  // desaparecer antes de renderizar (e queimar a exibição do dia).
  useEffect(() => { if (popupMode && state && (!state.show || state.purchased)) onPopupClose?.(); }, [popupMode, state?.show, state?.purchased]);

  if (!state || !state.show) return null;

  const payWithInternal = state.availableTon >= state.priceTon;
  const rewards = [
    { icon: '🎫', label: 'Season Pass Legendary', detail: 'Temporada atual' },
    { icon: '🪙', label: `${myth(state.mythReward)} MYTH`, detail: 'Creditado na carteira' },
    { icon: '🦸', label: 'Herói Veteran exclusivo', detail: `${myth(state.heroDailyMyth)} MYTH/dia` },
    { icon: '🐾', label: 'Pet Veteran exclusivo', detail: `${myth(state.petDailyMyth)} MYTH/dia` },
    { icon: '🥚', label: 'Ovo de Dragão Veteran', detail: `Dragão: ${myth(state.dragonDailyMyth)} MYTH/dia` },
    { icon: '⚔️', label: `${state.weaponsPerPurchase} Armas Veteran`, detail: 'NFT Exclusive 1/1' },
    { icon: '🎁', label: `${state.legendaryChests} Baús Lendários`, detail: 'Equipamentos lendários' },
    { icon: '💎', label: `${state.fragments} Fragmentos`, detail: 'Universais' },
    { icon: '👑', label: 'Cosméticos Veteran', detail: 'Badge + moldura' },
  ];

  if (state.purchased) {
    if (popupMode) return null;
    return (
      <div className="relative w-full overflow-hidden rounded-3xl border border-amber-300/30 bg-forge-black/80 p-4 shadow-card">
        <img src={vaultArt} alt={localizeText("Mythic Seas Veteran Vault")} loading="lazy" width={1024} height={640} className="absolute inset-0 h-full w-full object-cover opacity-25" />
        <div className="relative">
          <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-amber-300">
            <Swords className="h-3 w-3" /> {localizeText("Veteran Vault")}</p>
          <h3 className="mt-1 text-base font-semibold text-white">{localizeText("Linha Veteran ativa")}</h3>
          <div className="mt-3 grid grid-cols-3 gap-2 text-center">
            <div className="rounded-2xl bg-white/5 p-2">
              <p className="text-[10px] uppercase tracking-widest text-slate-400">{localizeText("Bônus MYTH")}</p>
              <p className="text-sm font-semibold text-amber-200">+{Math.round(state.ownerBoostPercent)}%</p>
            </div>
            <div className="rounded-2xl bg-white/5 p-2">
              <p className="text-[10px] uppercase tracking-widest text-slate-400">{localizeText("Itens Veteran")}</p>
              <p className="text-sm font-semibold text-slate-200">{state.items.length}</p>
            </div>
            <div className="rounded-2xl bg-white/5 p-2">
              <p className="text-[10px] uppercase tracking-widest text-slate-400">{localizeText("Mineração ref.")}</p>
              <p className="text-sm font-semibold text-cyan-200">{myth(veteranV2DailyMyth(state))}/dia</p>
            </div>
          </div>
          <p className="mt-2 text-[10px] text-slate-400">
            {localizeText("Recompensas Veteran mineram apenas MYTH. O bônus de +")}{Math.round(state.ownerBoostPercent)}{localizeText("% vale para toda a mineração de MYTH da conta.")}</p>
        </div>
      </div>
    );
  }

  return (
    <>
      {popupMode ? null : (
      <button
        onClick={() => setOpen(true)}
        className="relative w-full overflow-hidden rounded-3xl border border-amber-300/40 bg-forge-black/80 text-left shadow-card"
      >
        <img src={vaultArt} alt={localizeText("Mythic Seas Veteran Vault")} loading="lazy" width={1024} height={640} className="absolute inset-0 h-full w-full object-cover opacity-40" />
        <div className="relative flex items-center justify-between gap-3 p-4">
          <div className="min-w-0">
            <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-amber-300">
              <Swords className="h-3 w-3" /> {localizeText("Veteran Vault")}</p>
            <h3 className="mt-1 truncate text-base font-semibold text-white">{localizeText("Linha Veteran exclusiva")}</h3>
            <p className="text-[11px] text-slate-300">{localizeText("Herói · pet · dragão · armas · +")}{Math.round(state.boostPercent)}{localizeText("% MYTH")}</p>
          </div>
          <div className="shrink-0 rounded-2xl bg-amber-400/20 px-3 py-2 text-center">
            <p className="text-sm font-bold text-amber-100">{formatTon(state.priceTon)} TON</p>
            <p className="text-[10px] uppercase tracking-widest text-amber-100/80">{state.soldOut ? localizeText("Sold out") : localizeText("Ver pacote")}</p>
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
                  <Swords className="h-3 w-3" /> {localizeText("Mythic Seas Veteran Vault")}</p>
                <h3 className="mt-1 text-lg font-semibold text-white">{localizeText("Pacote premium Veteran")}</h3>
                <p className="text-[11px] text-slate-300">{localizeText("Uma compra por conta · itens exclusivos da linha Veteran")}</p>
              </div>
              <button onClick={close} className="rounded-full bg-white/10 p-2 text-slate-300"><X className="h-4 w-4" /></button>
            </div>

            <img src={vaultArt} alt={localizeText("Recompensas do Veteran Vault")} loading="lazy" width={1024} height={640} className="mt-3 h-36 w-full rounded-2xl object-cover" />

            <div className="mt-3 grid grid-cols-1 gap-2">
              {rewards.map(reward => (
                <div key={reward.label} className="flex items-center gap-3 rounded-2xl bg-white/5 px-3 py-2">
                  <span className="text-lg">{reward.icon}</span>
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-white">{reward.label}</p>
                    <p className="text-[11px] text-slate-400">{reward.detail}</p>
                  </div>
                </div>
              ))}
            </div>

            <div className="mt-3 flex items-start gap-2 rounded-2xl border border-amber-300/20 bg-amber-400/5 p-3">
              <Sparkles className="mt-0.5 h-4 w-4 shrink-0 text-amber-300" />
              <p className="text-[11px] text-slate-300">
                {localizeText("Bônus exclusivo de compradores:")}<strong className="text-amber-200">+{Math.round(state.boostPercent)}{localizeText("% de MYTH")}</strong> {localizeText("em toda a mineração da conta. As recompensas Veteran mineram somente MYTH — nunca TON — e rendem cerca de")}{' '}
                {myth(veteranV2DailyMyth(state))} {localizeText("MYTH/dia como referência.")}</p>
            </div>

            <div className="mt-3 flex items-center gap-2 rounded-2xl bg-white/5 px-3 py-2 text-[11px] text-slate-300">
              <ShieldCheck className="h-4 w-4 text-amber-300" />
              {payWithInternal
                ? `Pagamento com saldo interno: ${formatTon(state.availableTon)} TON disponíveis.`
                : `Saldo interno insuficiente (${formatTon(state.availableTon)} TON): a cobrança será integral via TonConnect.`}
            </div>

            <button
              onClick={() => buy.mutate()}
              disabled={buy.isPending || state.soldOut || !state.eligible}
              className="mt-3 flex w-full items-center justify-center gap-2 rounded-2xl bg-amber-400 px-4 py-3 text-sm font-semibold text-forge-black disabled:opacity-50"
            >
              {buy.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
              {state.soldOut ? 'Sold out — fundo em financiamento' : `Comprar — ${formatTon(state.priceTon)} TON`}
            </button>
            <p className="mt-2 text-center text-[10px] text-slate-400">
              {localizeText("Valores de mineração são referência configurável pelo servidor, não retorno garantido.")}</p>
          </div>
        </div>
      ) : null}
    </>
  );
}
