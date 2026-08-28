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
  if (!Number.isFinite(diff) || diff <= 0) return 'CHEIO';
  const hours = Math.floor(diff / 3_600_000);
  const days = Math.floor(hours / 24);
  if (days >= 1) return `Cheio em ${days}d ${hours % 24}h`;
  return `Cheio em ${hours}h ${Math.floor((diff % 3_600_000) / 60_000)}m`;
}

/**
 * ⛏ MINAS DE TON — overlay compacto premium.
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
        className="pointer-events-none absolute inset-x-0 top-0 h-48 opacity-40"
        style={{ background: 'radial-gradient(120% 100% at 50% 0%, hsl(var(--primary) / 0.35), transparent 70%)' }}
      />
      <div className="forge-safe-page relative mx-auto w-full max-w-lg space-y-2.5 px-3 pb-20 pt-3">
        {/* ── Header compacto ── */}
        <header className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <span className="flex h-8 w-8 items-center justify-center rounded-lg border border-primary/30 bg-primary/10">
              <Pickaxe className="h-4 w-4 text-primary" />
            </span>
            <div>
              <h1 className="text-base font-black uppercase tracking-wider text-foreground">Minas de TON</h1>
              <p className="text-[10px] text-muted-foreground">Investimento passivo · rende offline 24h</p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Fechar"
            className="rounded-full border border-white/10 bg-white/5 p-1.5 text-muted-foreground transition hover:text-foreground"
          >
            <X className="h-4 w-4" />
          </button>
        </header>

        {/* ── Painel resumo compacto ── */}
        <section className="rounded-xl border border-primary/20 bg-gradient-to-br from-primary/10 via-forge-black/90 to-forge-black p-2.5">
          {/* Linha 1: 4 mini-cards */}
          <div className="grid grid-cols-4 gap-1.5">
            {[
              { label: 'Investido', value: `${ton2(summary?.investedTon ?? 0)}`, icon: Coins },
              { label: 'Minas', value: `${summary?.activeMines ?? 0}`, icon: Pickaxe },
              { label: 'Diário', value: `${ton(summary?.dailyTon ?? 0)}`, icon: TrendingUp },
              { label: 'Coletado', value: `${ton2(summary?.lifetimeClaimedTon ?? 0)}`, icon: Gem },
            ].map(item => (
              <div key={item.label} className="rounded-lg border border-white/10 bg-white/5 px-1.5 py-1.5 text-center">
                <p className="flex items-center justify-center gap-1 text-[8px] uppercase tracking-wider text-muted-foreground">
                  <item.icon className="h-2.5 w-2.5" /> {item.label}
                </p>
                <p className="mt-0.5 truncate text-[11px] font-bold text-foreground">{item.value}</p>
              </div>
            ))}
          </div>

          {/* Linha 2: disponível + coletar tudo */}
          <div className="mt-1.5 flex items-center justify-between gap-2 rounded-lg border border-emerald-400/20 bg-emerald-400/10 px-2.5 py-1.5">
            <div className="min-w-0">
              <p className="text-[8px] uppercase tracking-wider text-emerald-200/80">Disponível para coletar</p>
              <p className="truncate text-sm font-black text-emerald-300">{ton(summary?.unclaimedTon ?? 0)} TON</p>
            </div>
            <button
              type="button"
              disabled={!canClaimAll || claim.isPending}
              onClick={() => claim.mutate(undefined)}
              className="shrink-0 rounded-lg bg-emerald-500 px-3 py-1.5 text-[10px] font-black uppercase tracking-wider text-emerald-950 transition disabled:opacity-40"
            >
              {claim.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : 'Coletar tudo'}
            </button>
          </div>

          {/* Saldo interno + fidelidade — linhas pequenas */}
          <div className="mt-1.5 flex flex-wrap items-center justify-between gap-x-3 gap-y-0.5 px-0.5">
            <p className="text-[10px] text-muted-foreground">
              Saldo interno: <span className="font-semibold text-foreground">{ton(state?.balanceTon ?? 0)} TON</span>
            </p>
            {state?.loyalty.enabled ? (
              <p className="flex items-center gap-1 text-[10px] text-amber-200/90">
                <Sparkles className="h-3 w-3" />
                +{state.loyalty.bonus30}% 30d · +{state.loyalty.bonus60}% 60d
              </p>
            ) : null}
          </div>
        </section>

        {isLoading ? (
          <div className="flex justify-center py-8"><Loader2 className="h-5 w-5 animate-spin text-primary" /></div>
        ) : null}

        {state && !state.visible ? (
          <p className="rounded-xl border border-white/10 bg-white/5 p-3 text-center text-xs text-muted-foreground">
            As MINAS DE TON ainda não foram liberadas para o seu acesso.
          </p>
        ) : null}

        {/* ── Cards horizontais compactos ── */}
        <div className="space-y-2" key={tick}>
          {mines.map(mine => {
            const holding = mine.holdings[0];
            const progress = holding && holding.capacityTon > 0
              ? Math.min(100, (holding.storedTon / holding.capacityTon) * 100)
              : 0;
            const owned = Boolean(holding);
            return (
              <article
                key={mine.id}
                className="flex h-[122px] overflow-hidden rounded-xl border border-primary/20 bg-forge-black/85"
              >
                {/* Imagem — 35% */}
                <div className="relative w-[35%] shrink-0">
                  {mine.imageUrl ? (
                    <img src={mine.imageUrl} alt={mine.name} loading="lazy" className="h-full w-full object-cover" />
                  ) : (
                    <div className="h-full w-full bg-white/5" />
                  )}
                  <div className="absolute inset-0 bg-gradient-to-r from-transparent via-transparent to-forge-black/80" />
                </div>

                {/* Conteúdo — 65% */}
                <div className="flex min-w-0 flex-1 flex-col justify-between p-2">
                  <div className="min-w-0">
                    <div className="flex items-start justify-between gap-1.5">
                      <h2 className="truncate text-[11px] font-black uppercase tracking-wide text-foreground">{mine.name}</h2>
                      <span className={`shrink-0 rounded px-1.5 py-0.5 text-[9px] font-black uppercase tracking-wide ${
                        owned ? 'bg-emerald-500/90 text-emerald-950'
                          : mine.status === 'LOCKED' ? 'bg-white/15 text-muted-foreground' : 'bg-primary text-primary-foreground'
                      }`}>
                        {owned ? 'Owned' : mine.status === 'LOCKED' ? 'Indisponível' : `${ton2(mine.priceTon)} TON`}
                      </span>
                    </div>
                    <p className="mt-0.5 text-[11px] font-bold text-primary">{ton(mine.dailyTon)} TON/dia</p>
                    <p className="mt-0.5 truncate text-[9px] text-muted-foreground">
                      ROI {mine.roiDays ? `${mine.roiDays}d` : '—'} · Storage {mine.storageDays}d
                      {state?.loyalty.enabled ? ` · +${state.loyalty.bonus30}% Loyalty` : ''}
                    </p>
                  </div>

                  {holding ? (
                    <div className="space-y-1">
                      <div className="flex items-center justify-between text-[9px]">
                        <span className="font-bold text-emerald-300">{ton(holding.storedTon)} / {ton(holding.capacityTon)} TON</span>
                        <span className="text-muted-foreground">
                          {fullInLabel(holding.fullAt)} · {holding.daysHeld}d{holding.multiplier > 1 ? ` +${Math.round((holding.multiplier - 1) * 100)}%` : ''}
                        </span>
                      </div>
                      <div className="h-1 overflow-hidden rounded-full bg-white/10">
                        <div className="h-full rounded-full bg-gradient-to-r from-emerald-400 to-emerald-200" style={{ width: `${progress}%` }} />
                      </div>
                      <button
                        type="button"
                        disabled={holding.storedTon <= 0 || claim.isPending}
                        onClick={() => claim.mutate(holding.id)}
                        className="w-full rounded-lg bg-emerald-500 py-1.5 text-[10px] font-black uppercase tracking-wider text-emerald-950 transition disabled:opacity-40"
                      >
                        Coletar · {ton(holding.storedTon)} TON
                      </button>
                    </div>
                  ) : (
                    <button
                      type="button"
                      disabled={mine.status === 'LOCKED' || !state?.visible}
                      onClick={() => setSelected(mine)}
                      className="flex w-full items-center justify-center gap-1.5 rounded-lg bg-primary py-1.5 text-[10px] font-black uppercase tracking-wider text-primary-foreground transition disabled:opacity-40"
                    >
                      {mine.status === 'LOCKED' ? <Lock className="h-3 w-3" /> : <Pickaxe className="h-3 w-3" />}
                      {mine.status === 'LOCKED' ? 'Indisponível' : `Comprar — ${ton2(mine.priceTon)} TON`}
                    </button>
                  )}
                </div>
              </article>
            );
          })}
        </div>

        {state?.claims.length ? (
          <section className="rounded-xl border border-white/10 bg-forge-black/80 p-2.5">
            <h3 className="text-[9px] uppercase tracking-[0.3em] text-muted-foreground">Últimas coletas</h3>
            <ul className="mt-1.5 space-y-1">
              {state.claims.map(item => (
                <li key={item.id} className="flex items-center justify-between text-[11px]">
                  <span className="text-muted-foreground">{item.mineName ?? 'Mina'}</span>
                  <span className="font-semibold text-emerald-300">+{ton(item.amountTon)} TON</span>
                </li>
              ))}
            </ul>
          </section>
        ) : null}
      </div>

      {selected ? (
        <div className="fixed inset-0 z-[60] flex items-end justify-center bg-forge-black/80 p-3" role="dialog">
          <div className="w-full max-w-md space-y-2 rounded-xl border border-primary/30 bg-forge-black p-3">
            <h3 className="text-sm font-black uppercase text-foreground">{selected.name}</h3>
            {selected.imageUrl ? (
              <img src={selected.imageUrl} alt={selected.name} className="h-28 w-full rounded-lg object-cover" />
            ) : null}
            <p className="text-[11px] leading-relaxed text-muted-foreground">{selected.description}</p>
            <p className="text-[10px] text-muted-foreground">
              {ton2(selected.priceTon)} TON · {ton(selected.dailyTon)} TON/dia · armazena {selected.storageDays} dias · permanente, nunca expira.
            </p>
            <button
              type="button"
              disabled={buy.isPending || (state?.balanceTon ?? 0) < selected.priceTon}
              onClick={() => buy.mutate({ mine: selected, useBalance: true })}
              className="w-full rounded-lg bg-primary py-2 text-[11px] font-black uppercase tracking-wider text-primary-foreground transition disabled:opacity-40"
            >
              Pagar com saldo interno ({ton(state?.balanceTon ?? 0)} TON)
            </button>
            <button
              type="button"
              disabled={buy.isPending}
              onClick={() => buy.mutate({ mine: selected, useBalance: false })}
              className="w-full rounded-lg border border-primary/40 bg-primary/10 py-2 text-[11px] font-black uppercase tracking-wider text-primary transition disabled:opacity-40"
            >
              {buy.isPending ? <Loader2 className="mx-auto h-3.5 w-3.5 animate-spin" /> : 'Pagar com carteira TON'}
            </button>
            <button
              type="button"
              onClick={() => setSelected(null)}
              className="w-full rounded-lg border border-white/10 py-1.5 text-[10px] font-bold uppercase tracking-wider text-muted-foreground"
            >
              Cancelar
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}
