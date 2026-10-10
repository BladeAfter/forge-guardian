import { useLocalizedText } from '../LanguageContext';
import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { Coins, Flame, Loader2, ShieldCheck, Wallet } from 'lucide-react';
import { toast } from 'sonner';
import { useMythSale } from '../hooks';
import { startMythPurchase, verifyMythPurchases } from '../services';
import { sendTonPayment } from '../tonPayment';
import { formatTon } from '../economy';
import { abbreviateMyth, mythCostTon, mythFull, mythIntentCountdown, type MythSaleDashboard } from '../mythSale';

/**
 * MYTH TOKEN SALE (Community Pool tab).
 *
 * Payment rule, decided exclusively by the backend and only rendered here:
 * 1. INTERNAL TON BALANCE when it covers 100% of the cost (instant credit);
 * 2. TON CONNECT external wallet otherwise, charging 100% there — balances are never mixed.
 * The supply is reserved by the server during the TonConnect checkout, so no oversell is possible.
 */
export function MythTokenSalePanel({ telegramInitData }: { telegramInitData: string }) {
  const localizeText = useLocalizedText();

  const client = useQueryClient();
  const [tonConnectUI] = useTonConnectUI();
  const { data, isLoading, error, refetch } = useMythSale(telegramInitData, true);
  const [amountText, setAmountText] = useState('');
  const [tick, setTick] = useState(0);

  useEffect(() => { const id = window.setInterval(() => setTick(v => v + 1), 1000); return () => window.clearInterval(id); }, []);

  const stats = data?.stats;
  const amount = Math.max(0, Math.floor(Number(amountText.replace(/[^\d]/g, '')) || 0));
  const cost = useMemo(() => mythCostTon(amount, stats?.mythPerTon ?? 0), [amount, stats?.mythPerTon]);
  const internalTon = data?.player.internalTon ?? 0;
  const payWithInternal = cost > 0 && internalTon >= cost;
  const intent = data?.pendingIntent ?? null;
  const countdown = mythIntentCountdown(intent?.expiresAt, Date.now() + tick * 0);
  const saleActive = stats?.saleStatus === 'active';

  const reconcile = async () => {
    try {
      const result = await verifyMythPurchases(telegramInitData);
      if (result.confirmed.length) toast.success('MYTH credited to your balance.');
      await client.invalidateQueries({ queryKey: ['myth-sale'] });
      await client.invalidateQueries({ queryKey: ['myth-wallet'] });
      await client.invalidateQueries({ queryKey: ['ton-wallet'] });
      return result.confirmed.length > 0;
    } catch { return false; }
  };

  const buy = useMutation({
    mutationFn: async () => {
      if (!saleActive) throw new Error('SALE_PAUSED');
      if (amount < (stats?.minPurchase ?? 1)) throw new Error(`Minimum purchase: ${mythFull(stats?.minPurchase ?? 0)} ${stats?.symbol ?? 'MYTH'}.`);
      const walletAddress = payWithInternal ? undefined : await ensureWallet();
      const order = await startMythPurchase(telegramInitData, amount, crypto.randomUUID(), walletAddress);
      if (order.method === 'TONCONNECT') {
        await sendTonPayment(
          { paymentAddress: order.paymentAddress, paymentComment: order.paymentComment, amountNano: order.amountNano },
          tx => tonConnectUI.sendTransaction(tx),
        );
      }
      return order;
    },
    onSuccess: async order => {
      setAmountText('');
      await client.invalidateQueries({ queryKey: ['myth-sale'] });
      await client.invalidateQueries({ queryKey: ['myth-wallet'] });
      await client.invalidateQueries({ queryKey: ['ton-wallet'] });
      if (order.method === 'INTERNAL') toast.success(`${mythFull(order.mythAmount)} ${stats?.symbol ?? 'MYTH'} purchased with your internal TON balance.`);
      else { toast.success('Payment sent. Verifying on-chain…'); window.setTimeout(() => { void reconcile(); }, 6_000); }
    },
    onError: err => toast.error(saleErrorText(err, stats?.symbol ?? 'MYTH')),
  });

  /** TonConnect must always end inside the wallet: open the modal when nothing is linked yet. */
  const ensureWallet = async (): Promise<string> => {
    const current = tonConnectUI.account?.address;
    if (current) return current;
    const linked = new Promise<string>((resolve, reject) => {
      const unsubscribe = tonConnectUI.onStatusChange(wallet => {
        if (wallet?.account?.address) { unsubscribe(); resolve(wallet.account.address); }
      });
      window.setTimeout(() => { unsubscribe(); reject(new Error('Connect your TON wallet to continue.')); }, 180_000);
    });
    await tonConnectUI.openModal();
    return linked;
  };

  if (isLoading) return <div className="space-y-3 pt-6">{[1, 2, 3].map(x => <div key={x} className="h-28 animate-pulse rounded-3xl bg-white/5" />)}</div>;
  if (error || !data || !stats) return (
    <div className="py-20 text-center">
      <p className="text-rose-300">{localizeText("Unable to load the MYTH sale.")}</p>
      <button onClick={() => void refetch()} className="mt-4 rounded-xl border border-amber-300/30 px-5 py-3 text-xs font-black">{localizeText("RETRY")}</button>
    </div>
  );

  return (
    <div className="pb-10">
      <section className="relative overflow-hidden rounded-[2rem] border border-amber-300/40 bg-gradient-to-br from-[#1b1206] via-[#0b0f1c] to-black p-5 shadow-[0_0_50px_rgba(245,158,11,.18)]">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-[9px] font-bold uppercase tracking-[.35em] text-amber-300">{stats.name}</p>
            <h2 className="text-3xl font-black text-amber-100">{abbreviateMyth(stats.effectiveSupply)} {stats.symbol}</h2>
            <p className="text-[9px] uppercase tracking-[.2em] text-slate-400">{localizeText("Total supply · ")}{mythFull(stats.initialSupply)}</p>
          </div>
          <Coins className="h-12 w-12 animate-pulse text-amber-300" />
        </div>

        <div className="mt-4 grid grid-cols-2 gap-2">
          <Cell label="Available" value={`${abbreviateMyth(stats.available)} ${stats.symbol}`} />
          <Cell label="Sold" value={`${abbreviateMyth(stats.sold)} ${stats.symbol}`} />
          <Cell label="Burned" value={`${abbreviateMyth(stats.burned)} ${stats.symbol}`} tone="rose" />
          <Cell label="TON raised" value={`${formatTon(stats.tonRaised)} TON`} />
          <Cell label="Current price" value={`1 TON = ${mythFull(stats.mythPerTon)}`} />
          <Cell label="Your balance" value={`${mythFull(data.player.mythBalance)} ${stats.symbol}`} tone="emerald" />
        </div>

        <div className="mt-4">
          <div className="flex justify-between text-[9px] uppercase tracking-[.2em] text-slate-400">
            <span>{localizeText("Sold progress")}</span><b className="text-amber-200">{stats.soldPercent.toFixed(2)}%</b>
          </div>
          <div className="mt-1 h-2.5 overflow-hidden rounded-full bg-white/10">
            <div className="h-full bg-gradient-to-r from-amber-500 to-yellow-200 transition-all" style={{ width: `${Math.min(100, stats.soldPercent)}%` }} />
          </div>
          {stats.reserved > 0 && <p className="mt-1 text-[9px] text-slate-500">{mythFull(stats.reserved)} {stats.symbol} {localizeText("reserved in open checkouts.")}</p>}
        </div>
      </section>

      <section className="mt-3 rounded-3xl border border-rose-400/30 bg-gradient-to-br from-rose-950/40 to-black p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2"><Flame className="h-5 w-5 text-rose-300" /><b className="text-xs font-black uppercase tracking-[.2em] text-rose-200">{localizeText("Burn")}</b></div>
          <b className="text-lg font-black text-rose-200">{stats.burnedPercent.toFixed(2)}%</b>
        </div>
        <p className="mt-1 text-[10px] text-slate-400">{mythFull(stats.burned)} {stats.symbol} {localizeText("permanently removed from the supply.")}</p>
        <div className="mt-2 h-2 overflow-hidden rounded-full bg-white/10"><div className="h-full bg-gradient-to-r from-rose-600 to-orange-300" style={{ width: `${Math.min(100, stats.burnedPercent)}%` }} /></div>
      </section>

      {intent && !countdown.expired ? (
        <section className="mt-3 rounded-3xl border border-cyan-300/35 bg-black/60 p-4">
          <b className="text-xs font-black uppercase tracking-[.2em] text-cyan-200">{localizeText("Checkout open")}</b>
          <p className="mt-1 text-[11px] text-slate-300">{mythFull(intent.mythAmount)} {stats.symbol} for {formatTon(intent.amountTon)} {localizeText("TON — supply reserved for ")}{countdown.minutes}m {String(countdown.seconds).padStart(2, '0')}s.</p>
          <button onClick={() => void reconcile()} className="mt-3 w-full rounded-xl border border-cyan-300/35 bg-cyan-500/10 py-3 text-[11px] font-black uppercase tracking-[.2em] text-cyan-100">{localizeText("I already paid — verify now")}</button>
        </section>
      ) : null}

      <section className="mt-3 rounded-3xl border border-white/10 bg-black/60 p-4">
        <b className="text-xs font-black uppercase tracking-[.2em] text-amber-200">{localizeText("Buy ")}{stats.symbol}</b>
        {!saleActive && <p className="mt-2 rounded-xl border border-amber-300/20 bg-amber-950/30 p-3 text-[11px] text-amber-200">{localizeText("The sale is currently ")}{stats.saleStatus}{localizeText(". Purchases are disabled.")}</p>}
        <input
          value={amountText}
          onChange={e => setAmountText(e.target.value.replace(/[^\d]/g, ''))}
          inputMode="numeric"
          placeholder={`Minimum ${mythFull(stats.minPurchase)} ${stats.symbol}`}
          className="mt-3 w-full rounded-xl border border-white/10 bg-black/60 px-4 py-3 text-sm font-black text-white outline-none focus:border-amber-300/50"
        />
        <div className="mt-2 flex gap-1.5">
          {[stats.minPurchase, stats.mythPerTon, stats.mythPerTon * 5, stats.mythPerTon * 10].map((preset, index) => (
            <button key={index} onClick={() => setAmountText(String(Math.floor(preset)))} className="flex-1 rounded-lg border border-white/10 bg-white/5 py-2 text-[9px] font-black text-slate-200">
              {abbreviateMyth(preset)}
            </button>
          ))}
        </div>
        <div className="mt-3 flex items-center justify-between text-[11px]">
          <span className="text-slate-400">{localizeText("Cost")}</span><b className="text-amber-200">{formatTon(cost)} TON</b>
        </div>
        <div className="mt-1 flex items-center justify-between text-[11px]">
          <span className="text-slate-400">{localizeText("Internal TON balance")}</span><b className={payWithInternal ? 'text-emerald-300' : 'text-slate-300'}>{formatTon(internalTon)} TON</b>
        </div>
        <p className="mt-2 flex items-start gap-1.5 text-[10px] text-slate-400">
          {payWithInternal ? <Wallet className="mt-[1px] h-3.5 w-3.5 shrink-0 text-emerald-300" /> : <ShieldCheck className="mt-[1px] h-3.5 w-3.5 shrink-0 text-cyan-300" />}
          {payWithInternal
            ? localizeText("Paying 100% with your internal TON balance — instant credit.")
            : localizeText("Internal balance does not cover the full amount: the whole payment is charged to your external TON wallet.")}
        </p>
        <button
          disabled={!saleActive || buy.isPending || amount < stats.minPurchase || amount > stats.available}
          onClick={() => buy.mutate()}
          className="mt-3 w-full rounded-xl bg-gradient-to-r from-amber-400 to-yellow-200 py-3 text-xs font-black uppercase tracking-[.2em] text-black disabled:opacity-40"
        >
          {buy.isPending ? <Loader2 className="mx-auto h-4 w-4 animate-spin" /> : payWithInternal ? 'Buy with internal TON' : 'Buy with TON wallet'}
        </button>
        {amount > stats.available && <p className="mt-2 text-[10px] text-rose-300">{localizeText("Only ")}{mythFull(stats.available)} {stats.symbol} {localizeText("available right now.")}</p>}
      </section>

      <History data={data} />
    </div>
  );
}

function Cell({ label, value, tone }: { label: string; value: string; tone?: 'rose' | 'emerald' }) {
  const color = tone === 'rose' ? 'text-rose-200' : tone === 'emerald' ? 'text-emerald-200' : 'text-white';
  return (
    <div className="rounded-2xl border border-white/10 bg-black/50 p-2.5">
      <p className="text-[8px] uppercase tracking-[.18em] text-slate-400">{label}</p>
      <b className={`text-[13px] ${color}`}>{value}</b>
    </div>
  );
}

function History({ data }: { data: MythSaleDashboard }) {
  const localizeText = useLocalizedText();

  const symbol = data.stats.symbol;
  return (
    <>
      {data.purchases.length > 0 && (
        <section className="mt-4">
          <h3 className="mb-2 text-[10px] font-black uppercase tracking-[.2em] text-amber-200">{localizeText("Your purchases")}</h3>
          <div className="space-y-2">
            {data.purchases.map(row => (
              <div key={row.id} className="flex items-center justify-between rounded-2xl border border-white/10 bg-black/55 p-3">
                <div>
                  <b className="text-xs text-white">{mythFull(row.mythAmount)} {symbol}</b>
                  <p className="text-[9px] text-slate-400">{row.method === 'INTERNAL' ? localizeText("Internal TON") : localizeText("TON wallet")} · {new Date(row.createdAt).toLocaleDateString()}</p>
                </div>
                <b className="text-[11px] text-cyan-300">{formatTon(row.amountTon)} TON</b>
              </div>
            ))}
          </div>
        </section>
      )}
      {data.burns.length > 0 && (
        <section className="mt-4">
          <h3 className="mb-2 text-[10px] font-black uppercase tracking-[.2em] text-rose-200">{localizeText("Burn history")}</h3>
          <div className="space-y-2">
            {data.burns.map(row => (
              <div key={row.id} className="flex items-center justify-between rounded-2xl border border-rose-400/20 bg-black/55 p-3">
                <div>
                  <b className="text-xs text-rose-200">- {mythFull(row.amount)} {symbol}</b>
                  <p className="text-[9px] text-slate-400">{row.reason || 'Supply burn'} · {new Date(row.createdAt).toLocaleDateString()}</p>
                </div>
                <Flame className="h-4 w-4 text-rose-300" />
              </div>
            ))}
          </div>
        </section>
      )}
    </>
  );
}

/** Backend error codes translated for the sale surface only. */
function saleErrorText(error: unknown, symbol: string): string {
  const message = error instanceof Error ? error.message : String(error);
  const map: Record<string, string> = {
    SALE_PAUSED: 'The MYTH sale is not active right now.',
    MIN_PURCHASE_NOT_MET: 'Amount below the minimum purchase.',
    INSUFFICIENT_SUPPLY: `Not enough ${symbol} available for this amount.`,
    ACCOUNT_BANNED: 'This account cannot buy tokens.',
    PLAYER_NOT_FOUND: 'Open the game from Telegram to buy.',
    TON_PAYMENT_ALREADY_SENT: 'This payment was already sent to your wallet.',
    TON_PAYMENT_AMOUNT_MISMATCH: 'Payment blocked: amount mismatch. Nothing was charged.',
  };
  return map[message] || message;
}
