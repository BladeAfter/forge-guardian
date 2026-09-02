import { useEffect, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { Sparkles, Stars, X } from 'lucide-react';
import { toast } from 'sonner';
import { useCelestialPack } from '../hooks';
import { startCelestialPackPurchase, verifyCelestialPackPurchases } from '../services';
import { sendTonPayment } from '../tonPayment';
import { celestialPackErrorText } from '../celestialPack';
import { formatTon } from '../economy';
import packArt from '../assets/celestial-mystery-pack.jpg';

const int = (value: number) => Math.round(Number(value || 0)).toLocaleString('pt-BR');

/**
 * 💫 CELESTIAL MYSTERY PACK (100 TON).
 *
 * Todo o conteúdo, o estoque de Heróis Celestiais sem dono, a entrega e o bônus permanente de
 * +X% na mineração de TON da conta vêm do servidor. O Herói Celestial e o Pet NFT chegam com a
 * mineração "A SER REVELADA" — isso é informado ANTES da compra, sem valor prometido e sem
 * mineração retroativa.
 */
export function CelestialPackCard({ telegramInitData, popupMode = false, onPopupClose }: {
  telegramInitData: string;
  popupMode?: boolean;
  onPopupClose?: () => void;
}) {
  const client = useQueryClient();
  const [tonConnectUI] = useTonConnectUI();
  const { data: state } = useCelestialPack(telegramInitData, Boolean(telegramInitData));
  const [open, setOpen] = useState(popupMode);

  const refreshAll = () => Promise.all(
    ['celestial-pack', 'game-state', 'ton-wallet', 'wallet-summary', 'player-inventory', 'player-heroes', 'pet-dashboard', 'hero-mining', 'arsenal', 'telegram-profile']
      .map(key => client.invalidateQueries({ queryKey: [key] })),
  );

  const reconcile = async () => {
    try {
      const result = await verifyCelestialPackPurchases(telegramInitData);
      if (result.confirmed.length) toast.success('Celestial Mystery Pack entregue!');
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
      const order = await startCelestialPackPurchase(telegramInitData, crypto.randomUUID(), walletAddress);
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
      if (order.status === 'completed') { close(); toast.success('Celestial Mystery Pack garantido! Recompensas entregues.'); }
      else { toast.success('Pagamento enviado. Confirmando na blockchain…'); window.setTimeout(() => { void reconcile(); }, 6_000); }
    },
    onError: error => toast.error(celestialPackErrorText(error)),
  });

  useEffect(() => { if (state?.pendingOrder) void reconcile(); }, [state?.pendingOrder?.orderId]);
  useEffect(() => { if (popupMode && state && (!state.show || state.purchased)) onPopupClose?.(); }, [popupMode, state?.show, state?.purchased]);

  const close = () => { setOpen(false); onPopupClose?.(); };

  if (!state || !state.show) return null;

  const payWithInternal = state.availableTon >= state.priceTon;
  const rewards = [
    { icon: '🌌', label: 'Herói Celestial 1/1', detail: 'Mineração A SER REVELADA' },
    { icon: '🐾', label: 'Pet NFT Exclusivo', detail: 'Mineração A SER REVELADA' },
    { icon: '🪙', label: `${int(state.fcReward)} FC`, detail: 'Creditado na hora' },
    { icon: '🎁', label: `${state.legendaryChests} Baús Lendários`, detail: 'Equipamentos lendários' },
    { icon: '⚔️', label: `${state.nftWeapons} Armas NFT`, detail: 'Unidades 1/1' },
    { icon: '🛡', label: `${state.armors} Armaduras`, detail: 'Lendárias' },
    { icon: '⛏', label: `+${formatTon(state.accountBonusPercent)}% mineração TON`, detail: 'Permanente, toda a conta' },
    { icon: '✨', label: `${state.randomItems} Itens Premium`, detail: 'Sorteados na entrega' },
  ];

  if (state.purchased) {
    if (popupMode) return null;
    return (
      <div className="relative w-full overflow-hidden rounded-3xl border border-violet-300/30 bg-forge-black/80 p-4 shadow-card">
        <img src={packArt} alt="Mythreon Celestial Mystery Pack" loading="lazy" width={1024} height={640} className="absolute inset-0 h-full w-full object-cover opacity-25" />
        <div className="relative">
          <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-violet-200">
            <Stars className="h-3 w-3" /> Celestial Mystery Pack
          </p>
          <h3 className="mt-1 text-base font-semibold text-white">Pacote ativo na sua conta</h3>
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
              <p className="text-sm font-semibold text-violet-200">{state.miningRevealPending ? 'A REVELAR' : 'REVELADA'}</p>
            </div>
          </div>
          {state.miningRevealPending ? (
            <p className="mt-2 text-[10px] text-slate-400">
              As taxas do Herói Celestial e do Pet NFT serão definidas e reveladas pela administração. A mineração começa
              no momento da revelação — nada é retroativo.
            </p>
          ) : null}
        </div>
      </div>
    );
  }

  const trigger = (
    <button
      type="button"
      onClick={() => setOpen(true)}
      className="relative w-full overflow-hidden rounded-3xl border border-violet-300/40 bg-forge-black/80 p-4 text-left shadow-card"
    >
      <img src={packArt} alt="Mythreon Celestial Mystery Pack" loading="lazy" width={1024} height={640} className="absolute inset-0 h-full w-full object-cover opacity-40" />
      <div className="relative">
        <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-violet-200">
          <Stars className="h-3 w-3" /> Celestial Mystery Pack
        </p>
        <h3 className="mt-1 text-lg font-black text-white">Herói Celestial + Pet NFT</h3>
        <p className="text-[11px] text-slate-300">Mineração revelada só depois da compra · {state.celestialAvailable} Celestiais sem dono</p>
        <p className="mt-2 inline-flex rounded-full bg-violet-500/20 px-3 py-1 text-xs font-black text-violet-100">{formatTon(state.priceTon)} TON</p>
      </div>
    </button>
  );

  if (!open) return trigger;

  return (
    <div className="fixed inset-0 z-[95] flex items-end overflow-y-auto bg-black/85 p-3">
      <div className="mx-auto w-full max-w-[440px] overflow-hidden rounded-[1.8rem] border border-violet-300/40 bg-gradient-to-b from-[#150f2b]/95 to-black/95">
        <div className="relative">
          <img src={packArt} alt="Mythreon Celestial Mystery Pack" loading="lazy" width={1024} height={640} className="h-36 w-full object-cover opacity-80" />
          <button onClick={close} aria-label="Fechar" className="absolute right-3 top-3 grid h-8 w-8 place-items-center rounded-full bg-black/60">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="p-4">
          <p className="text-[10px] font-black uppercase tracking-[0.28em] text-violet-200">💫 Celestial Mystery Pack</p>
          <h2 className="text-xl font-black text-white">{formatTon(state.priceTon)} TON · 1 por conta</h2>

          <div className="mt-3 rounded-2xl border border-violet-300/25 bg-black/50 p-3">
            <p className="flex items-center gap-1 text-[10px] font-black uppercase tracking-[0.16em] text-amber-200">
              <Sparkles className="h-3 w-3" /> Mineração a ser revelada
            </p>
            <p className="mt-1 text-[11px] leading-relaxed text-slate-300">
              O Herói Celestial e o Pet NFT são entregues com o status <b>MINING TO BE REVEALED</b>. A administração define
              e revela as taxas depois da compra. Não há valor prometido, não há mineração retroativa: a acumulação começa
              no instante da revelação.
            </p>
          </div>

          <div className="mt-3 grid grid-cols-2 gap-2">
            {rewards.map(reward => (
              <div key={reward.label} className="rounded-2xl border border-white/10 bg-white/5 p-2">
                <p className="text-xs font-bold text-white">{reward.icon} {reward.label}</p>
                <p className="text-[10px] uppercase tracking-widest text-slate-400">{reward.detail}</p>
              </div>
            ))}
          </div>

          <p className="mt-3 text-[10px] text-slate-400">
            {payWithInternal
              ? `Será debitado do seu saldo TON interno (${formatTon(state.availableTon)} TON disponíveis).`
              : 'Pagamento 100% via carteira TON conectada.'}
          </p>

          <button
            type="button"
            disabled={buy.isPending || !state.eligible}
            onClick={() => buy.mutate()}
            className="mt-3 w-full rounded-2xl bg-gradient-to-b from-violet-400 to-indigo-600 px-4 py-3 text-sm font-black uppercase tracking-[0.14em] text-white disabled:opacity-60"
          >
            {buy.isPending ? 'PROCESSANDO…' : state.soldOut ? 'ESGOTADO' : `COMPRAR POR ${formatTon(state.priceTon)} TON`}
          </button>
        </div>
      </div>
    </div>
  );
}
