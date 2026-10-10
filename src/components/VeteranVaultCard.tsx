import { useLocalizedText } from '../LanguageContext';
import { useEffect, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { Loader2, ShieldCheck, Swords, X } from 'lucide-react';
import { toast } from 'sonner';
import { useVeteranVault } from '../hooks';
import { claimVeteranVaultRewards, startVeteranVaultPurchase, verifyVeteranVaultPurchases } from '../services';
import { sendTonPayment } from '../tonPayment';
import { veteranCountdown, veteranErrorText } from '../veteranVault';
import { formatTon } from '../economy';
import veteranArt from '../assets/veteran-vault.jpg';

/**
 * ⚔️ Mythic Seas VETERAN VAULT — exclusive for veteran accounts, with a 45-day reward journey.
 *
 * The server owns everything: who sees the card (`state.show`), the price, whether the Veteran Reward
 * Pool is funded (`soldOut`), the current cycle day, matured rewards and each credited TON/MYTH.
 * Payment follows the official rule: 100% internal TON when it covers the price, otherwise 100%
 * TonConnect — never mixed. Values displayed here are REFERENCE values, not guaranteed profit.
 */
export function VeteranVaultCard({ telegramInitData }: { telegramInitData: string }) {
  const localizeText = useLocalizedText();

  const client = useQueryClient();
  const [tonConnectUI] = useTonConnectUI();
  const { data: state } = useVeteranVault(telegramInitData, Boolean(telegramInitData));
  const [open, setOpen] = useState(false);
  const [, setTick] = useState(0);

  useEffect(() => { const id = window.setInterval(() => setTick(v => v + 1), 30_000); return () => window.clearInterval(id); }, []);

  const refreshAll = () => Promise.all(
    ['veteran-vault', 'game-state', 'ton-wallet', 'wallet-summary', 'myth-wallet', 'player-inventory', 'player-heroes', 'pet-dashboard', 'season-pass', 'telegram-profile']
      .map(key => client.invalidateQueries({ queryKey: [key] })),
  );

  const reconcile = async () => {
    try {
      const result = await verifyVeteranVaultPurchases(telegramInitData);
      if (result.confirmed.length) toast.success('Veteran Vault ativo! Recompensas iniciais entregues.');
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
      const order = await startVeteranVaultPurchase(telegramInitData, crypto.randomUUID(), walletAddress);
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
      if (order.status === 'completed') { setOpen(false); toast.success('Veteran Vault garantido! Ciclo de 45 dias iniciado.'); }
      else { toast.success('Pagamento enviado. Confirmando na blockchain…'); window.setTimeout(() => { void reconcile(); }, 6_000); }
    },
    onError: error => toast.error(veteranErrorText(error)),
  });

  const claim = useMutation({
    mutationFn: () => claimVeteranVaultRewards(telegramInitData, crypto.randomUUID()),
    onSuccess: async result => {
      await refreshAll();
      if (result.nothingToClaim) { toast('Nenhuma recompensa disponível agora.'); return; }
      const parts = [
        (result.tonClaimed ?? 0) > 0 ? `${formatTon(result.tonClaimed ?? 0)} TON` : null,
        (result.mythClaimed ?? 0) > 0 ? `${Math.round(result.mythClaimed ?? 0).toLocaleString('pt-BR')} MYTH` : null,
      ].filter(Boolean);
      toast.success(parts.length ? `Coletado: ${parts.join(' · ')}` : 'Recompensa final entregue!');
    },
    onError: error => toast.error(veteranErrorText(error)),
  });

  useEffect(() => { if (state?.pendingOrder) void reconcile(); }, [state?.pendingOrder?.orderId]);

  if (!state?.show) return null;

  const vault = state.vault;
  const payWithInternal = state.availableTon >= state.priceTon;
  const rewards = [
    { icon: '🎫', label: 'Season Pass Premium', detail: state.passTier === 'legendary' ? 'Tier Legendary' : 'Tier Adventurer' },
    { icon: '🪙', label: `${state.initialMyth.toLocaleString('pt-BR')} MYTH`, detail: 'Creditado na carteira' },
    { icon: '🦸', label: 'Herói EXCLUSIVE', detail: 'Entrega imediata' },
    { icon: '🐉', label: 'Pet Premium', detail: 'Mítico / exclusivo' },
    { icon: '⚔️', label: 'Baú Lendário', detail: 'Equipamento lendário' },
    { icon: '💎', label: `${state.fragments} Fragmentos`, detail: 'Universais' },
    { icon: '🎁', label: 'Baús Premium', detail: 'BERRIES · tickets · fragmentos' },
    { icon: '💠', label: 'Recompensas TON', detail: `Até ${formatTon(state.tonRewardBudget)} TON no ciclo` },
    { icon: '👑', label: 'Cosméticos Veteran', detail: 'Badge + moldura' },
  ];

  if (vault) {
    const progress = Math.min(100, Math.round((vault.day / Math.max(1, vault.cycleDays)) * 100));
    const claimable = vault.claimable;
    return (
      <div className="relative w-full overflow-hidden rounded-3xl border border-cyan-300/30 bg-forge-black/80 p-4 shadow-card">
        <img src={veteranArt} alt={localizeText("Mythic Seas Veteran Vault")} loading="lazy" width={1024} height={640} className="absolute inset-0 h-full w-full object-cover opacity-25" />
        <div className="relative">
          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0">
              <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-cyan-300">
                <Swords className="h-3 w-3" /> {localizeText("Veteran Vault")}</p>
              <h3 className="mt-1 text-base font-semibold text-white">
                {vault.completed ? localizeText("Vault concluído") : `Dia ${vault.day} / ${vault.cycleDays}`}
              </h3>
            </div>
            <div className="shrink-0 rounded-2xl bg-cyan-400/15 px-3 py-2 text-right">
              <p className="text-[10px] uppercase tracking-widest text-cyan-100/80">{localizeText("Próxima recompensa")}</p>
              <p className="text-sm font-bold text-cyan-100">{claimable?.nextRewardAt ? veteranCountdown(claimable.nextRewardAt) : '—'}</p>
            </div>
          </div>

          <div className="mt-3 h-2 w-full overflow-hidden rounded-full bg-white/10">
            <div className="h-full rounded-full bg-cyan-400" style={{ width: `${progress}%` }} />
          </div>

          <div className="mt-3 grid grid-cols-3 gap-2 text-center">
            <div className="rounded-2xl bg-white/5 p-2">
              <p className="text-[10px] uppercase tracking-widest text-slate-400">{localizeText("TON real")}</p>
              <p className="text-sm font-semibold text-cyan-200">{formatTon(vault.tonEarned)}</p>
            </div>
            <div className="rounded-2xl bg-white/5 p-2">
              <p className="text-[10px] uppercase tracking-widest text-slate-400">MYTH</p>
              <p className="text-sm font-semibold text-amber-200">{Math.round(vault.mythEarned).toLocaleString('pt-BR')}</p>
            </div>
            <div className="rounded-2xl bg-white/5 p-2">
              <p className="text-[10px] uppercase tracking-widest text-slate-400">{localizeText("Valor ref.")}</p>
              <p className="text-sm font-semibold text-slate-200">{formatTon(vault.referenceValueTon)} TON</p>
            </div>
          </div>
          <p className="mt-2 text-[10px] text-slate-400">
            {localizeText("Valor de referência estimado dos itens — não é saldo sacável. TON real e MYTH aparecem separados acima.")}</p>

          <button
            onClick={() => claim.mutate()}
            disabled={claim.isPending || !claimable?.hasRewards}
            className="mt-3 flex w-full items-center justify-center gap-2 rounded-2xl bg-cyan-400/90 px-4 py-3 text-sm font-semibold text-forge-black disabled:opacity-50"
          >
            {claim.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
            {claimable?.hasRewards
              ? `Coletar disponível${claimable.ton > 0 ? ` · ${formatTon(claimable.ton)} TON` : ''}${claimable.myth > 0 ? ` · ${Math.round(claimable.myth).toLocaleString('pt-BR')} MYTH` : ''}`
              : localizeText("Nada disponível agora")}
          </button>
        </div>
      </div>
    );
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="relative w-full overflow-hidden rounded-3xl border border-cyan-300/40 bg-forge-black/80 text-left shadow-card"
      >
        <img src={veteranArt} alt={localizeText("Mythic Seas Veteran Vault")} loading="lazy" width={1024} height={640} className="absolute inset-0 h-full w-full object-cover opacity-40" />
        <div className="relative flex items-center justify-between gap-3 p-4">
          <div className="min-w-0">
            <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-cyan-300">
              <Swords className="h-3 w-3" /> {localizeText("Veteran Vault")}</p>
            <h3 className="mt-1 truncate text-base font-semibold text-white">{localizeText("Cofre do Veterano")}</h3>
            <p className="text-[11px] text-slate-300">{localizeText("Exclusivo para veteranos · jornada de")}{state.cycleDays} dias</p>
          </div>
          <div className="shrink-0 rounded-2xl bg-cyan-400/20 px-3 py-2 text-center">
            <p className="text-sm font-bold text-cyan-100">{formatTon(state.priceTon)} TON</p>
            <p className="text-[10px] uppercase tracking-widest text-cyan-100/80">{state.soldOut ? localizeText("Sold out") : localizeText("Ver pacote")}</p>
          </div>
        </div>
      </button>

      {open ? (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/80 p-3 sm:items-center">
          <div className="forge-safe-page max-h-[90vh] w-full max-w-md overflow-y-auto rounded-3xl border border-cyan-300/30 bg-forge-black p-4 shadow-card">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-[0.3em] text-cyan-300">
                  <Swords className="h-3 w-3" /> {localizeText("Mythic Seas Veteran Vault")}</p>
                <h3 className="mt-1 text-lg font-semibold text-white">{localizeText("Jornada de")}{state.cycleDays} dias</h3>
                <p className="text-[11px] text-slate-300">{localizeText("Exclusivo para jogadores antigos · uma compra por conta")}</p>
              </div>
              <button onClick={() => setOpen(false)} className="rounded-full bg-white/10 p-2 text-slate-300"><X className="h-4 w-4" /></button>
            </div>

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

            <div className="mt-3 rounded-2xl border border-cyan-300/20 bg-cyan-400/5 p-3">
              <p className="text-[11px] text-slate-300">
                {localizeText("Durante os")}{state.cycleDays} {localizeText("dias você acumula recompensas diárias em MYTH, marcos semanais e marcos em TON real pagos pelo Veteran Reward Pool. Recompensas vencidas ficam guardadas: não é preciso entrar todo dia.")}</p>
              <p className="mt-2 text-[10px] text-slate-400">
                {localizeText("Valor total de referência estimado:")}{formatTon(state.targetReferenceTon)} {localizeText("TON equivalentes em itens, benefícios, MYTH e TON. Trata-se de valor de referência, não de retorno garantido.")}</p>
            </div>

            <div className="mt-3 flex items-center gap-2 rounded-2xl bg-white/5 px-3 py-2 text-[11px] text-slate-300">
              <ShieldCheck className="h-4 w-4 text-cyan-300" />
              {payWithInternal
                ? `Pagamento com saldo interno: ${formatTon(state.availableTon)} TON disponíveis.`
                : `Saldo interno insuficiente (${formatTon(state.availableTon)} TON): a cobrança será integral via TonConnect.`}
            </div>

            <button
              onClick={() => buy.mutate()}
              disabled={buy.isPending || state.soldOut || !state.eligible}
              className="mt-3 flex w-full items-center justify-center gap-2 rounded-2xl bg-cyan-400 px-4 py-3 text-sm font-semibold text-forge-black disabled:opacity-50"
            >
              {buy.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
              {state.soldOut ? 'Sold out — pool em financiamento' : `Comprar — ${formatTon(state.priceTon)} TON`}
            </button>
            {!state.eligible && !state.soldOut ? (
              <p className="mt-2 text-center text-[11px] text-slate-400">
                {localizeText("Disponível para contas com")}{state.minAccountAgeDays}{localizeText("+ dias ou criadas antes do lançamento da oferta.")}</p>
            ) : null}
          </div>
        </div>
      ) : null}
    </>
  );
}
