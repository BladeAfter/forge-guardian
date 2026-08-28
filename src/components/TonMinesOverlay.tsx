import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { Coins, Gem, Loader2, Lock, Pickaxe, Sparkles, TrendingUp, X } from 'lucide-react';
import { toast } from 'sonner';
import {
  buyTonMineWithBalance,
  claimTonMine,
  createTonMineOrder,
  fetchTonMines,
  verifyTonMinePurchases,
  type TonMineTemplate,
  type TonMinesState,
} from '../services';
import { sendTonPayment } from '../tonPayment';

const ton = (value: number) => Number(value || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 4 });
const ton2 = (value: number) => Number(value || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** Countdown until the storage is full — after that the mine stops accruing. */
function fullInLabel(fullAt: string | null): string {
  if (!fullAt) return '—';
  const diff = new Date(fullAt).getTime() - Date.now();
  if (!Number.isFinite(diff) || diff <= 0) return 'ARMAZENAMENTO CHEIO';
  const hours = Math.floor(diff / 3_600_000);
  const days = Math.floor(hours / 24);
  if (days >= 1) return `Cheio em ${days}d ${hours % 24}h`;
  return `Cheio em ${hours}h ${Math.floor((diff % 3_600_000) / 60_000)}m`;
}

/**
 * ⛏ MINAS DE TON — overlay fullscreen premium.
 *
 * O servidor é a única fonte de verdade: preço, rendimento diário, capacidade de
 * armazenamento, bônus de fidelidade, limites por jogador e visibilidade. O cliente
 * apenas renderiza o estado e envia as ações de compra e coleta.
 */
export function TonMinesOverlay({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const client = useQueryClient();
  const [tonUI] = useTonConnectUI();
  const [selected, setSelected] = useState<TonMineTemplate | null>(null);
  const [tick, setTick] = useState(0);

  const { data: state, isLoading } = useQuery<TonMinesState>({
    queryKey: ['ton-mines'],
    queryFn: () => fetchTonMines(telegramInitData),
    enabled: Boolean(telegramInitData),
    refetchInterval: 30_000,
  });

  useEffect(() => {
    const id = window.setInterval(() => setTick(value => value + 1), 60_000);
    return () => window.clearInterval(id);
  }, []);

  const refresh = () => Promise.all(
    ['ton-mines', 'game-state', 'ton-wallet', 'wallet-summary']
      .map(key => client.invalidateQueries({ queryKey: [key] })),
  );

  useEffect(() => {
    if (!telegramInitData) return;
    verifyTonMinePurchases(telegramInitData)
      .then(result => { if (result.completed.length) { toast.success('Mina adquirida! Rendimento iniciado.'); void refresh(); } })
      .catch(() => { /* retried on the next open */ });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [telegramInitData]);

  const ensureWallet = async (): Promise<string> => {
    const current = tonUI.account?.address;
    if (current) return current;
    const linked = new Promise<string>((resolve, reject) => {
      const unsubscribe = tonUI.onStatusChange(wallet => {
        if (wallet?.account?.address) { unsubscribe(); resolve(wallet.account.address); }
      });
      window.setTimeout(() => { unsubscribe(); reject(new Error('Conecte uma carteira TON para continuar.')); }, 120_000);
    });
    await tonUI.openModal();
    return linked;
  };

  const buy = useMutation({
    mutationFn: async ({ mine, useBalance }: { mine: TonMineTemplate; useBalance: boolean }) => {
      const key = `${mine.id}:${Date.now()}`;
      if (useBalance) return buyTonMineWithBalance(telegramInitData, mine.id, key);
      await ensureWallet();
      const order = await createTonMineOrder(telegramInitData, mine.id, key);
      await sendTonPayment(order, tx => tonUI.sendTransaction(tx as never));
      await new Promise(resolve => window.setTimeout(resolve, 6_000));
      return verifyTonMinePurchases(telegramInitData);
    },
    onSuccess: async () => {
      toast.success('Compra registrada! Confirmando na blockchain se necessário.');
      setSelected(null);
      await refresh();
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const claim = useMutation({
    mutationFn: (holdingId?: string) => claimTonMine(telegramInitData, holdingId),
    onSuccess: async result => {
      toast.success(`+${ton(result.claimedTon || 0)} TON coletados!`);
      await refresh();
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const summary = state?.summary;
  const canClaimAll = (summary?.unclaimedTon ?? 0) > 0;
  const mines = useMemo(() => state?.mines ?? [], [state]);

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto bg-forge-black">
      <div
        className="pointer-events-none absolute inset-x-0 top-0 h-64 opacity-40"
        style={{ background: 'radial-gradient(120% 100% at 50% 0%, hsl(var(--primary) / 0.35), transparent 70%)' }}
      />
      <div className="forge-safe-page relative mx-auto w-full max-w-lg space-y-4 px-4 pb-24 pt-4">
        <header className="flex items-center justify-between">
          <div>
            <p className="flex items-center gap-2 text-[10px] uppercase tracking-[0.35em] text-primary/80">
              <Pickaxe className="h-3.5 w-3.5" /> Mythreon
            </p>
            <h1 className="text-2xl font-black uppercase tracking-wide text-foreground">Minas de TON</h1>
            <p className="text-xs text-muted-foreground">Investimento passivo permanente. Rende offline, 24h por dia.</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Fechar"
            className="rounded-full border border-white/10 bg-white/5 p-2 text-muted-foreground transition hover:text-foreground"
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <section className="rounded-3xl border border-primary/25 bg-gradient-to-br from-primary/15 via-forge-black/90 to-forge-black p-4 shadow-card">
          <div className="grid grid-cols-2 gap-3">
            {[
              { label: 'Investido', value: `${ton2(summary?.investedTon ?? 0)} TON`, icon: Coins },
              { label: 'Minas ativas', value: `${summary?.activeMines ?? 0}`, icon: Pickaxe },
              { label: 'Rendimento diário', value: `${ton(summary?.dailyTon ?? 0)} TON`, icon: TrendingUp },
              { label: 'Total coletado', value: `${ton2(summary?.lifetimeClaimedTon ?? 0)} TON`, icon: Gem },
            ].map(item => (
              <div key={item.label} className="rounded-2xl border border-white/10 bg-white/5 p-3">
                <p className="flex items-center gap-1.5 text-[10px] uppercase tracking-widest text-muted-foreground">
                  <item.icon className="h-3 w-3" /> {item.label}
                </p>
                <p className="mt-1 text-lg font-bold text-foreground">{item.value}</p>
              </div>
            ))}
          </div>

          <div className="mt-3 rounded-2xl border border-emerald-400/25 bg-emerald-400/10 p-3">
            <div className="flex items-end justify-between gap-3">
              <div>
                <p className="text-[10px] uppercase tracking-widest text-emerald-200/80">Disponível para coletar</p>
                <p className="text-2xl font-black text-emerald-300">{ton(summary?.unclaimedTon ?? 0)} TON</p>
              </div>
              <button
                type="button"
                disabled={!canClaimAll || claim.isPending}
                onClick={() => claim.mutate(undefined)}
                className="rounded-xl bg-emerald-500 px-4 py-2.5 text-xs font-black uppercase tracking-wider text-emerald-950 transition disabled:opacity-40"
              >
                {claim.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Coletar tudo'}
              </button>
            </div>
            <p className="mt-2 text-[11px] text-muted-foreground">
              Saldo TON interno: <span className="font-semibold text-foreground">{ton(state?.balanceTon ?? 0)} TON</span>
            </p>
          </div>

          {state?.loyalty.enabled ? (
            <p className="mt-3 flex items-center gap-1.5 text-[11px] text-amber-200/90">
              <Sparkles className="h-3.5 w-3.5" />
              Fidelidade: +{state.loyalty.bonus30}% após 30 dias e +{state.loyalty.bonus60}% após 60 dias de posse.
            </p>
          ) : null}
        </section>

        {isLoading ? (
          <div className="flex justify-center py-10"><Loader2 className="h-6 w-6 animate-spin text-primary" /></div>
        ) : null}

        {state && !state.visible ? (
          <p className="rounded-2xl border border-white/10 bg-white/5 p-4 text-center text-sm text-muted-foreground">
            As MINAS DE TON ainda não foram liberadas para o seu acesso.
          </p>
        ) : null}

        <div className="space-y-3" key={tick}>
          {mines.map(mine => {
            const holding = mine.holdings[0];
            const progress = holding && holding.capacityTon > 0
              ? Math.min(100, (holding.storedTon / holding.capacityTon) * 100)
              : 0;
            return (
              <article key={mine.id} className="overflow-hidden rounded-3xl border border-white/10 bg-forge-black/80 shadow-card">
                <div className="relative h-40">
                  {mine.imageUrl ? (
                    <img src={mine.imageUrl} alt={mine.name} loading="lazy" className="h-full w-full object-cover" />
                  ) : (
                    <div className="h-full w-full bg-white/5" />
                  )}
                  <div className="absolute inset-0 bg-gradient-to-t from-forge-black via-forge-black/40 to-transparent" />
                  <div className="absolute inset-x-3 bottom-3 flex items-end justify-between gap-2">
                    <div>
                      <h2 className="text-lg font-black uppercase tracking-wide text-foreground drop-shadow">{mine.name}</h2>
                      <p className="text-[11px] font-semibold text-primary">{ton(mine.dailyTon)} TON / dia</p>
                    </div>
                    <span className={`rounded-full px-2.5 py-1 text-[10px] font-black uppercase tracking-wider ${
                      mine.status === 'OWNED' ? 'bg-emerald-500/90 text-emerald-950'
                        : mine.status === 'LOCKED' ? 'bg-white/15 text-muted-foreground' : 'bg-primary text-primary-foreground'
                    }`}>
                      {mine.status === 'OWNED' ? 'Adquirida' : mine.status === 'LOCKED' ? 'Indisponível' : `${ton2(mine.priceTon)} TON`}
                    </span>
                  </div>
                </div>

                <div className="space-y-3 p-4">
                  <p className="text-xs leading-relaxed text-muted-foreground">{mine.description}</p>
                  <div className="grid grid-cols-3 gap-2 text-center">
                    {[
                      { label: 'Preço', value: `${ton2(mine.priceTon)} TON` },
                      { label: 'ROI', value: mine.roiDays ? `${mine.roiDays} dias` : '—' },
                      { label: 'Armazena', value: `${mine.storageDays} dias` },
                    ].map(item => (
                      <div key={item.label} className="rounded-xl border border-white/10 bg-white/5 px-2 py-1.5">
                        <p className="text-[9px] uppercase tracking-widest text-muted-foreground">{item.label}</p>
                        <p className="text-xs font-bold text-foreground">{item.value}</p>
                      </div>
                    ))}
                  </div>

                  {holding ? (
                    <div className="space-y-2 rounded-2xl border border-emerald-400/20 bg-emerald-400/5 p-3">
                      <div className="flex items-center justify-between text-[11px]">
                        <span className="text-muted-foreground">Armazenado</span>
                        <span className="font-bold text-emerald-300">{ton(holding.storedTon)} / {ton(holding.capacityTon)} TON</span>
                      </div>
                      <div className="h-2 overflow-hidden rounded-full bg-white/10">
                        <div className="h-full rounded-full bg-gradient-to-r from-emerald-400 to-emerald-200" style={{ width: `${progress}%` }} />
                      </div>
                      <div className="flex items-center justify-between text-[10px] text-muted-foreground">
                        <span>{fullInLabel(holding.fullAt)}</span>
                        <span>{holding.daysHeld}d de posse{holding.multiplier > 1 ? ` · +${Math.round((holding.multiplier - 1) * 100)}%` : ''}</span>
                      </div>
                      <button
                        type="button"
                        disabled={holding.storedTon <= 0 || claim.isPending}
                        onClick={() => claim.mutate(holding.id)}
                        className="w-full rounded-xl bg-emerald-500 py-2.5 text-xs font-black uppercase tracking-wider text-emerald-950 transition disabled:opacity-40"
                      >
                        Coletar {ton(holding.storedTon)} TON
                      </button>
                    </div>
                  ) : (
                    <button
                      type="button"
                      disabled={mine.status === 'LOCKED' || !state?.visible}
                      onClick={() => setSelected(mine)}
                      className="flex w-full items-center justify-center gap-2 rounded-xl bg-primary py-3 text-xs font-black uppercase tracking-wider text-primary-foreground transition disabled:opacity-40"
                    >
                      {mine.status === 'LOCKED' ? <Lock className="h-4 w-4" /> : <Pickaxe className="h-4 w-4" />}
                      {mine.status === 'LOCKED' ? 'Indisponível' : `Comprar por ${ton2(mine.priceTon)} TON`}
                    </button>
                  )}
                </div>
              </article>
            );
          })}
        </div>

        {state?.claims.length ? (
          <section className="rounded-3xl border border-white/10 bg-forge-black/80 p-4">
            <h3 className="text-[10px] uppercase tracking-[0.3em] text-muted-foreground">Últimas coletas</h3>
            <ul className="mt-2 space-y-1.5">
              {state.claims.map(item => (
                <li key={item.id} className="flex items-center justify-between text-xs">
                  <span className="text-muted-foreground">{item.mineName ?? 'Mina'}</span>
                  <span className="font-semibold text-emerald-300">+{ton(item.amountTon)} TON</span>
                </li>
              ))}
            </ul>
          </section>
        ) : null}
      </div>

      {selected ? (
        <div className="fixed inset-0 z-[60] flex items-end justify-center bg-forge-black/80 p-4" role="dialog">
          <div className="w-full max-w-md space-y-3 rounded-3xl border border-primary/30 bg-forge-black p-4 shadow-card">
            <h3 className="text-lg font-black uppercase text-foreground">{selected.name}</h3>
            <p className="text-xs text-muted-foreground">
              {ton2(selected.priceTon)} TON · {ton(selected.dailyTon)} TON/dia · armazena {selected.storageDays} dias.
              A mina é permanente e nunca expira.
            </p>
            <button
              type="button"
              disabled={buy.isPending || (state?.balanceTon ?? 0) < selected.priceTon}
              onClick={() => buy.mutate({ mine: selected, useBalance: true })}
              className="w-full rounded-xl bg-primary py-3 text-xs font-black uppercase tracking-wider text-primary-foreground transition disabled:opacity-40"
            >
              Pagar com saldo interno ({ton(state?.balanceTon ?? 0)} TON)
            </button>
            <button
              type="button"
              disabled={buy.isPending}
              onClick={() => buy.mutate({ mine: selected, useBalance: false })}
              className="w-full rounded-xl border border-primary/40 bg-primary/10 py-3 text-xs font-black uppercase tracking-wider text-primary transition disabled:opacity-40"
            >
              {buy.isPending ? <Loader2 className="mx-auto h-4 w-4 animate-spin" /> : 'Pagar com carteira TON'}
            </button>
            <button
              type="button"
              onClick={() => setSelected(null)}
              className="w-full rounded-xl border border-white/10 py-2.5 text-xs font-bold uppercase tracking-wider text-muted-foreground"
            >
              Cancelar
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}
