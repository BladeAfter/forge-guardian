import { useEffect, useMemo, useRef, useState } from 'react';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowDownToLine, ArrowUpFromLine, CheckCircle2, Clock3, Coins, Egg, Wallet } from 'lucide-react';
import { toast } from 'sonner';
import type { GameState, LanguageStrings } from '../types';
import type { LanguageCode } from '../i18n';
import { coin } from '../gameAssets';
import { DEFAULT_WITHDRAW_FEE_PERCENT, FC_PER_TON, MIN_DEPOSIT_TON, MIN_WITHDRAWAL_FC, fcToTon, formatTon, tonToFc, validDeposit, validWithdrawal, withdrawalQuote } from '../economy';
import { createDepositIntent, requestWithdrawal, verifyPendingDeposits } from '../services';
import { eggPurchaseStatusLabel, eggRecoveryMessage, formatEggPrice, hatchedPurchase, purchasePremiumEgg, reconcilePendingEggPurchases, waitForEggPurchase } from '../eggPurchase';
import { PetEggOpeningOverlay, type EggRevealResult } from '../components/PetEggOpeningOverlay';
import type { PetDashboard } from '../pets';
import type { PetRarity } from '../petRules';
import { usePetDashboard, useWalletSummary } from '../hooks';
import { encodeCommentPayload } from '../tonComment';
import { useLanguage, useT } from '../LanguageContext';

type Props = {
  game: GameState;
  lang: LanguageStrings;
  languageCode: LanguageCode;
  telegramInitData: string | null;
  connected: boolean;
  address: string | null;
  onConnect: () => Promise<void>;
  onDisconnect: () => Promise<void>;
  isConnecting: boolean;
};

/** History labels arrive from the backend with raw 9-decimal amounts; trim them for display only. */
const cleanTonLabel = (label: string) => String(label ?? '').replace(/\d+\.\d+/g, match => formatTon(match));

export function WalletPage({ game, telegramInitData, connected, address, onConnect, onDisconnect, isConnecting }: Props) {
  const t = useT();
  const { tError } = useLanguage();
  const [tonConnectUI] = useTonConnectUI();
  const queryClient = useQueryClient();
  const backendEnabled = Boolean(telegramInitData);
  const { data: summary } = useWalletSummary(telegramInitData, backendEnabled);
  const { data: pets } = usePetDashboard(telegramInitData, backendEnabled);
  const balance = summary?.balanceFc ?? game.balance;
  const [depositTon, setDepositTon] = useState(1);
  const [withdrawFc, setWithdrawFc] = useState(MIN_WITHDRAWAL_FC);
  const [confirmWithdraw, setConfirmWithdraw] = useState(false);
  const [reveal, setReveal] = useState<{ result: EggRevealResult; eggImage: string } | null>(null);
  const recoveredRef = useRef(false);
  const premiumEggs = useMemo(() => pets?.eggs.filter(egg => egg.priceTon && egg.isPurchasable) ?? [], [pets?.eggs]);
  // Backend recalcula tudo; aqui é apenas a estimativa transparente para o jogador.
  const feePercent = summary?.withdrawFeePercent ?? DEFAULT_WITHDRAW_FEE_PERCENT;
  const quote = useMemo(() => withdrawalQuote(withdrawFc, feePercent), [withdrawFc, feePercent]);

  const invalidateWallet = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ['wallet-summary', telegramInitData] }),
      queryClient.invalidateQueries({ queryKey: ['wallet-deposits'] }),
      queryClient.invalidateQueries({ queryKey: ['wallet-withdrawals'] }),
      queryClient.invalidateQueries({ queryKey: ['wallet-history'] }),
      queryClient.invalidateQueries({ queryKey: ['fc-balance'] }),
      queryClient.invalidateQueries({ queryKey: ['game-state', telegramInitData] }),
      // Confirmed TON revenue feeds the 15% Community Pool contribution, so refresh it too.
      queryClient.invalidateQueries({ queryKey: ['community-pool'] })
    ]);
  };

  const verify = useMutation({
    mutationFn: async () => {
      if (!telegramInitData) throw new Error(t('wallet.errors.openFromTelegram'));
      return verifyPendingDeposits(telegramInitData);
    },
    onSuccess: async result => {
      await invalidateWallet();
      if (result.confirmed.length) toast.success(t('wallet.toast.depositsCredited', { count: result.confirmed.length }));
      else if (result.alreadyCredited?.length) toast(t('wallet.toast.alreadyCredited'));
      else if (result.checked) toast(t('wallet.toast.notFoundYet'));
      else toast(t('wallet.toast.noPending'));
    },
    onError: error => toast.error(tError(error))
  });

  /**
   * Automatic reconciliation: after paying, the app itself keeps asking the backend to match the
   * transfer on-chain (every 5s for up to 90s). The manual button is only a fallback, and a payment
   * that shows up later is still reconciled on the next open — a deposit is never lost.
   */
  const autoVerifyTimer = useRef<number | null>(null);
  const stopAutoVerify = () => { if (autoVerifyTimer.current !== null) { window.clearInterval(autoVerifyTimer.current); autoVerifyTimer.current = null; } };

  const reconcileOnce = async (): Promise<boolean> => {
    if (!telegramInitData) return false;
    try {
      const result = await verifyPendingDeposits(telegramInitData);
      if (result.confirmed.length || result.alreadyCredited?.length) {
        await invalidateWallet();
        if (result.confirmed.length) toast.success(t('wallet.toast.depositsCredited', { count: result.confirmed.length }));
        return true;
      }
      return false;
    } catch {
      return false;
    }
  };

  const startAutoVerify = () => {
    stopAutoVerify();
    const startedAt = Date.now();
    autoVerifyTimer.current = window.setInterval(() => {
      if (Date.now() - startedAt > 90_000) { stopAutoVerify(); return; }
      void reconcileOnce().then(done => { if (done) stopAutoVerify(); });
    }, 5_000);
  };

  // Reconcile silently whenever the wallet opens, so payments indexed later are credited on their own.
  useEffect(() => {
    if (!backendEnabled) return;
    void reconcileOnce();
    return stopAutoVerify;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [backendEnabled, telegramInitData]);

  const deposit = useMutation({
    mutationFn: async () => {
      if (!telegramInitData || !connected || !address) throw new Error(t('wallet.errors.connectWallet'));
      if (!validDeposit(depositTon)) throw new Error(t('wallet.errors.minDeposit'));
      const intent = await createDepositIntent(telegramInitData, depositTon, address, crypto.randomUUID());
      await tonConnectUI.sendTransaction({
        validUntil: Math.floor(Date.now() / 1000) + 300,
        // The comment is the on-chain marker the backend matches against the hot wallet transactions.
        messages: [{ address: intent.paymentAddress, amount: intent.amountNano, payload: encodeCommentPayload(intent.paymentComment) }]
      });
      return intent;
    },
    onSuccess: async () => {
      await invalidateWallet();
      toast.success(t('wallet.toast.paymentSentVerifying'));
      // Give the network a few seconds to include the transfer, then keep checking automatically.
      window.setTimeout(() => { void reconcileOnce().then(done => { if (!done) startAutoVerify(); }); }, 6_000);
    },
    onError: error => toast.error(tError(error))
  });


  const withdrawal = useMutation({
    mutationFn: async () => {
      if (!telegramInitData || !connected || !address) throw new Error(t('wallet.errors.connectWallet'));
      if (withdrawFc < MIN_WITHDRAWAL_FC) throw new Error(t('wallet.errors.minWithdraw'));
      if (withdrawFc % MIN_WITHDRAWAL_FC !== 0) throw new Error(t('wallet.errors.multipleWithdraw'));
      if (!validWithdrawal(withdrawFc, balance)) throw new Error(t('wallet.errors.insufficientBalance'));
      return requestWithdrawal(telegramInitData, withdrawFc, address, crypto.randomUUID());
    },
    onSuccess: async () => { setConfirmWithdraw(false); await invalidateWallet(); toast.success(t('wallet.toast.withdrawRequested')); },
    onError: error => toast.error(tError(error))
  });

  const invalidateEggs = async () => {
    await Promise.all(['pet-egg-orders', 'pet-inventory', 'pet-dashboard', 'wallet-history', 'wallet-summary', 'game-state', 'community-pool'].map(key =>
      queryClient.invalidateQueries({ queryKey: [key] })));
  };

  /** Shows the SAME hatching screen used by the pet tab. */
  const revealPurchase = async (verification: Awaited<ReturnType<typeof reconcilePendingEggPurchases>>, fallbackImage?: string) => {
    const hatched = hatchedPurchase(verification);
    await invalidateEggs();
    if (!hatched?.result) return false;
    const dashboard = hatched.dashboard as PetDashboard | undefined;
    const eggImage = dashboard?.eggs.find(egg => egg.id === hatched.eggId)?.image || fallbackImage || '/assets/game/pet-eggs/common-egg.webp';
    setReveal({ result: { ...hatched.result, rarity: hatched.result.rarity as PetRarity }, eggImage });
    return true;
  };

  // App closed right after paying? On reopen the purchase is recovered and the pet delivered (only once).
  useEffect(() => {
    if (!backendEnabled || recoveredRef.current) return;
    recoveredRef.current = true;
    reconcilePendingEggPurchases(telegramInitData)
      .then(verification => { if (hatchedPurchase(verification)) void revealPurchase(verification); })
      .catch(() => undefined);
  }, [backendEnabled, telegramInitData]);

  // Premium eggs use the exact same purchase pipeline as the pet shop (purchase, never a deposit).
  const buyEgg = useMutation({
    mutationFn: async (egg: { id: string; image: string }) => {
      if (!connected) throw new Error(t('wallet.errors.connectWallet'));
      await purchasePremiumEgg({ telegramInitData, eggId: egg.id, source: 'wallet', sendTransaction: tx => tonConnectUI.sendTransaction(tx) });
      toast.success(t('wallet.toast.paymentSentConfirming'));
      return { egg, verification: await waitForEggPurchase(telegramInitData) };
    },
    onSuccess: async ({ egg, verification }) => {
      const delivered = await revealPurchase(verification, egg.image);
      if (!delivered) toast(t('wallet.toast.processingEgg'));
    },
    onError: error => toast.error(tError(error))
  });

  // "JÁ PAGUEI" é apenas recuperação: nunca cria outro pedido nem procura pagamento aleatório.
  const reconcile = useMutation({
    mutationFn: () => reconcilePendingEggPurchases(telegramInitData),
    onSuccess: async verification => {
      const delivered = await revealPurchase(verification);
      const message = eggRecoveryMessage(verification);
      if (delivered) return;
      if (message.tone === 'success') toast.success(message.text);
      else toast(message.text);
    },
    onError: error => toast.error(tError(error))
  });


  return (
    <section className="space-y-3 pb-5">
      <div className="rounded-2xl border border-amber-300/25 bg-[#080d16]/90 p-4 shadow-card">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-[9px] uppercase tracking-[.26em] text-amber-300">{t('wallet.title')}</p>
            <div className="mt-1 flex items-center gap-2 text-sm font-bold">
              <span className={`h-2.5 w-2.5 rounded-full ${connected ? 'bg-emerald-400 shadow-[0_0_10px_#34d399]' : 'border border-slate-500'}`} />
              {connected ? t('wallet.connected') : t('wallet.disconnected')}
            </div>
          </div>
          <button onClick={connected ? onDisconnect : onConnect} disabled={isConnecting} className="rounded-xl border border-amber-300/20 bg-black/40 px-3 py-2 text-[9px] font-bold text-amber-100 disabled:opacity-40">
            {isConnecting ? t('wallet.requesting') : connected ? t('wallet.disconnect') : t('wallet.connectButton')}
          </button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <Panel title={t('wallet.balance')} icon={<Coins />}>
          <div className="flex items-center gap-2"><img src={coin} className="h-8 w-8 object-contain" alt="FC"/><strong className="text-lg text-amber-200">{Math.floor(balance).toLocaleString('pt-BR')} FC</strong></div>
          <p className="mt-1 text-[9px] text-slate-400">{t('wallet.balanceEquivalent', { ton: fcToTon(balance).toLocaleString('pt-BR', { maximumFractionDigits: 4 }) })}</p>
        </Panel>
        <Panel title={t('wallet.conversion')} icon={<Wallet />}>
          <strong className="text-sm text-sky-300">1 TON</strong><p className="text-[10px] text-slate-300">= {FC_PER_TON.toLocaleString('pt-BR')} FC</p>
        </Panel>
      </div>

      <Panel title={t('wallet.deposit')} icon={<ArrowDownToLine />}>
        <div className="grid grid-cols-4 gap-1">{[1,3,5,10].map(value => <Quick key={value} active={depositTon===value} onClick={() => setDepositTon(value)}>{value} TON</Quick>)}</div>
        <input type="number" min={MIN_DEPOSIT_TON} step="0.5" value={depositTon} onChange={event => setDepositTon(Number(event.target.value))} aria-label={t('wallet.tonAmountLabel')} className="mt-2 w-full rounded-xl border border-white/10 bg-black/45 px-3 py-2 text-sm outline-none focus:border-sky-400" />
        <p className="mt-1 text-[9px] uppercase tracking-wide text-slate-400">{t('wallet.minimumDepositNote', { ton: MIN_DEPOSIT_TON, fc: FC_PER_TON.toLocaleString('pt-BR') })}</p>
        {!validDeposit(depositTon) ? <p className="mt-1 text-[9px] font-bold text-rose-300">{t('wallet.errors.minDeposit')}</p> : null}
        <Result label={t('wallet.youWillReceive')} value={`${tonToFc(depositTon).toLocaleString('pt-BR')} FC`} />
        <Primary onClick={() => deposit.mutate()} disabled={!connected || deposit.isPending || !validDeposit(depositTon)}>{deposit.isPending ? t('wallet.openingWallet') : t('wallet.depositButton')}</Primary>
        <button onClick={() => verify.mutate()} disabled={verify.isPending} className="mt-2 w-full rounded-xl border border-sky-400/40 bg-sky-500/10 px-3 py-2 text-[11px] font-bold tracking-wide text-sky-200 transition hover:bg-sky-500/20 disabled:opacity-60">
          {verify.isPending ? t('wallet.verifying') : t('wallet.alreadyPaid')}
        </button>
      </Panel>

      <Panel title={t('wallet.withdraw')} icon={<ArrowUpFromLine />}>
        <div className="grid grid-cols-4 gap-1">{[100000,300000,500000].map(value => <Quick key={value} active={withdrawFc===value} onClick={() => setWithdrawFc(value)}>{value/1000} {t('wallet.thousandShort')}</Quick>)}<Quick active={withdrawFc===Math.floor(balance/100000)*100000} onClick={() => setWithdrawFc(Math.floor(balance/100000)*100000)}>{t('wallet.max')}</Quick></div>
        <input type="number" min="100000" step="100000" value={withdrawFc} onChange={event => setWithdrawFc(Number(event.target.value))} aria-label={t('wallet.fcAmountLabel')} className="mt-2 w-full rounded-xl border border-white/10 bg-black/45 px-3 py-2 text-sm outline-none focus:border-sky-400" />
        <div className="mt-3 space-y-2 rounded-xl border border-white/10 bg-black/30 p-3">
          <Line label={t('wallet.amount')} value={`${withdrawFc.toLocaleString('pt-BR')} FC`} />
          <Line label={t('wallet.grossValue')} value={`${formatTon(quote.grossTon)} TON`} />
          <Line label={t('wallet.withdrawFee', { percent: quote.feePercent })} value={`-${formatTon(quote.feeTon)} TON`} tone="fee" />
          <div className="h-px w-full bg-white/10" />
          <Line label={t('wallet.youWillReceiveTon')} value={`${formatTon(quote.netTon)} TON`} tone="net" />
        </div>
        <p className="mt-2 text-[9px] leading-relaxed text-slate-400">{t('wallet.debitNote', { amount: withdrawFc.toLocaleString('pt-BR'), percent: quote.feePercent })}</p>
        <div className="mt-3">
          <Primary onClick={() => setConfirmWithdraw(true)} disabled={!connected || withdrawal.isPending || !validWithdrawal(withdrawFc,balance)}>{withdrawal.isPending ? t('wallet.requesting') : t('wallet.requestWithdraw')}</Primary>
        </div>
      </Panel>

      {confirmWithdraw ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4">
          <div className="w-full max-w-xs rounded-2xl border border-amber-300/30 bg-[#0a0f19] p-4">
            <h4 className="text-center text-[10px] font-black tracking-[.2em] text-amber-300">{t('wallet.confirmTitle')}</h4>
            <div className="mt-3 space-y-2">
              <Line label={t('wallet.amount')} value={`${withdrawFc.toLocaleString('pt-BR')} FC`} />
              <Line label={t('wallet.grossValue')} value={`${formatTon(quote.grossTon)} TON`} />
              <Line label={t('wallet.fee', { percent: quote.feePercent })} value={`-${formatTon(quote.feeTon)} TON`} tone="fee" />
              <div className="h-px w-full bg-white/10" />
              <Line label={t('wallet.youWillReceiveTon')} value={`${formatTon(quote.netTon)} TON`} tone="net" />
            </div>
            <div className="mt-4 space-y-2">
              <Primary onClick={() => withdrawal.mutate()} disabled={withdrawal.isPending}>{withdrawal.isPending ? t('wallet.sending') : t('wallet.confirm')}</Primary>
              <button type="button" onClick={() => setConfirmWithdraw(false)} disabled={withdrawal.isPending} className="w-full rounded-xl border border-white/15 bg-black/40 py-2.5 text-[10px] font-black text-slate-300 disabled:opacity-40">{t('wallet.cancel')}</button>
            </div>
          </div>
        </div>
      ) : null}

      {premiumEggs.length ? <Panel title={t('wallet.premiumEggs')} icon={<Egg />}><div className="grid grid-cols-2 gap-2">{premiumEggs.map(egg => <div key={egg.id} className="rounded-xl border border-violet-400/20 bg-black/35 p-2 text-center"><img src={egg.image} className="mx-auto h-16 w-16 object-contain"/><p className="text-[10px] font-bold">{egg.name}</p><p className="text-xs font-black text-violet-300">{formatEggPrice(egg)}</p><button onClick={() => buyEgg.mutate({ id: egg.id, image: egg.image })} disabled={!connected || buyEgg.isPending} className="mt-2 w-full rounded-lg border border-violet-300/30 bg-violet-500/15 py-2 text-[8px] font-black text-violet-100 disabled:opacity-35">{t('wallet.buyButton', { price: formatEggPrice(egg) })}</button></div>)}</div>
        <button onClick={() => reconcile.mutate()} disabled={reconcile.isPending || buyEgg.isPending} className="mt-2 w-full rounded-xl border border-violet-400/40 bg-violet-500/10 px-3 py-2 text-[10px] font-black tracking-wide text-violet-100 disabled:opacity-50">
          {reconcile.isPending ? t('wallet.verifying') : t('wallet.receiveEgg')}
        </button></Panel> : null}

      <Panel title={t('wallet.history')} icon={<Clock3 />}>
        <div className="max-h-72 space-y-2 overflow-y-auto">{summary?.history.length ? summary.history.map(item => <div key={`${item.type}-${item.id}`} className="flex items-start gap-2 rounded-xl bg-black/35 p-2"><Status status={item.status}/><div className="min-w-0 flex-1"><p className="break-words text-[10px] font-bold">{item.type === 'egg_order' ? `${cleanTonLabel(item.label).toUpperCase()} · ${formatTon(Number(item.amountTon ?? 0))} TON` : cleanTonLabel(item.label)}</p>
          {item.type === 'withdrawal' ? <p className="mt-0.5 text-[8px] leading-relaxed text-slate-400">{t('wallet.historyGross')}: {formatTon(Number(item.grossTon ?? item.amountTon ?? 0))} TON · {t('wallet.historyFee', { percent: Number(item.feePercent ?? 0) })}: {formatTon(Number(item.feeTon ?? 0))} TON · {t('wallet.historyReceived')}: <strong className="text-emerald-300">{formatTon(Number(item.netTon ?? item.amountTon ?? 0))} TON</strong></p> : null}
          <p className="text-[8px] text-slate-500">{new Date(item.createdAt).toLocaleString('pt-BR')}</p></div><span className="text-[8px] uppercase text-slate-300">{item.type === 'egg_order' ? eggPurchaseStatusLabel(item.status) : statusLabel(item.status, t)}</span></div>) : <p className="py-5 text-center text-[10px] text-slate-500">{t('wallet.noMovement')}</p>}</div>
      </Panel>

      {reveal ? <PetEggOpeningOverlay result={reveal.result} eggImage={reveal.eggImage} onContinue={() => setReveal(null)} /> : null}
    </section>
  );
}

function Panel({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }) { return <div className="rounded-2xl border border-amber-300/15 bg-[#080d16]/82 p-3"><div className="mb-3 flex items-center gap-2 text-amber-300"><span className="h-4 w-4">{icon}</span><h3 className="text-[9px] font-black tracking-[.2em]">{title}</h3></div>{children}</div>; }
function Quick({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) { return <button type="button" onClick={onClick} className={`rounded-lg border px-1 py-2 text-[8px] font-bold ${active ? 'border-sky-300 bg-sky-500/20 text-sky-100' : 'border-white/10 bg-black/30 text-slate-300'}`}>{children}</button>; }
function Result({ label, value }: { label: string; value: string }) { return <div className="my-2 flex items-center justify-between rounded-xl bg-black/30 px-3 py-2"><span className="text-[9px] text-slate-400">{label}</span><strong className="text-xs text-emerald-300">{value}</strong></div>; }
/** Linha de detalhamento sempre visível (nunca truncada) do saque. */
function Line({ label, value, tone }: { label: string; value: string; tone?: 'fee' | 'net' }) {
  const color = tone === 'fee' ? 'text-rose-300' : tone === 'net' ? 'text-emerald-300' : 'text-slate-100';
  const size = tone === 'net' ? 'text-sm' : 'text-xs';
  return (
    <div className="flex flex-wrap items-baseline justify-between gap-x-2 gap-y-0.5">
      <span className="text-[9px] font-bold uppercase tracking-wide text-slate-400">{label}</span>
      <strong className={`${size} font-black ${color}`}>{value}</strong>
    </div>
  );
}
function Primary({ children, onClick, disabled }: { children: React.ReactNode; onClick: () => void; disabled?: boolean }) { return <button type="button" onClick={onClick} disabled={disabled} className="w-full rounded-xl border border-amber-300/35 bg-amber-400/90 py-2.5 text-[10px] font-black text-black transition active:scale-[.98] disabled:grayscale disabled:opacity-35">{children}</button>; }
function Status({ status }: { status: string }) { const done=['credited','completed','delivered','confirmed','paid'].includes(status);return done?<CheckCircle2 className="h-4 w-4 text-emerald-400"/>:<Clock3 className="h-4 w-4 text-amber-300"/>; }
function statusLabel(status: string, t: (key: string) => string) { return t(`wallet.status.${status}`) ?? status; }
