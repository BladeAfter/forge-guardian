import { useEffect, useMemo, useRef, useState } from 'react';
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

/** Premium gold frame shared by panels and cards (never plain white borders). */
const GOLD_FRAME = {
  border: '1px solid rgba(212, 175, 55, 0.42)',
  boxShadow: '0 0 18px rgba(212, 175, 55, 0.08), inset 0 0 16px rgba(255, 190, 60, 0.04)',
} as const;

/** Per-mine ambient glow — image blends into the card instead of sitting on top of it. */
function mineGlow(index: number): string {
  const tints = [
    'rgba(251, 191, 36, 0.30)', // Ferro Arcano — amber
    'rgba(56, 189, 248, 0.30)', // Cristal Azul — blue
    'rgba(168, 85, 247, 0.30)', // Obsidiana — purple
    'rgba(253, 224, 71, 0.30)', // Celestial — gold/blue
  ];
  return tints[index % tints.length];
}

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

type BuyPhase = 'idle' | 'processing' | 'wallet' | 'error';

/**
 * ⛏ MINAS DE TON — overlay compacto premium.
 *
 * O servidor é a única fonte de verdade: preço, rendimento diário, capacidade de
 * armazenamento, bônus de fidelidade, limites por jogador e visibilidade.
 *
 * Compra ONE-TAP: o cliente nunca pergunta a forma de pagamento. Se o saldo TON
 * interno cobre o preço do servidor, a compra é 100% interna (transação atômica no
 * backend); caso contrário abre o TonConnect direto pelo valor TOTAL em nanoton
 * assinado pelo payment intent. Nunca há pagamento misto.
 */
export function TonMinesOverlay({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const client = useQueryClient();
  const [tonUI] = useTonConnectUI();
  const [tick, setTick] = useState(0);
  const [phase, setPhase] = useState<{ mineId: string | null; state: BuyPhase }>({ mineId: null, state: 'idle' });
  /** Idempotency key per mine: reused on retry so a double tap can never buy twice. */
  const purchaseKeys = useRef<Record<string, string>>({});

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
    mutationFn: async (mine: TonMineTemplate) => {
      const key = purchaseKeys.current[mine.id] ?? (purchaseKeys.current[mine.id] = `${mine.id}:${Date.now()}`);
      const balance = state?.balanceTon ?? 0;
      // ONE-TAP: internal balance covers the full price → 100% internal, atomic server-side.
      if (balance >= mine.priceTon) {
        setPhase({ mineId: mine.id, state: 'processing' });
        return { mode: 'internal' as const, result: await buyTonMineWithBalance(telegramInitData, mine.id, key) };
      }
      // Otherwise → TonConnect direct, full price, amount authored by the server intent.
      setPhase({ mineId: mine.id, state: 'wallet' });
      await ensureWallet();
      const order = await createTonMineOrder(telegramInitData, mine.id, key);
      await sendTonPayment(order, tx => tonUI.sendTransaction(tx as never));
      setPhase({ mineId: mine.id, state: 'processing' });
      await new Promise(resolve => window.setTimeout(resolve, 6_000));
      return { mode: 'wallet' as const, result: await verifyTonMinePurchases(telegramInitData) };
    },
    onSuccess: async (data, mine) => {
      delete purchaseKeys.current[mine.id];
      setPhase({ mineId: null, state: 'idle' });
      toast.success(
        data.mode === 'internal'
          ? `✓ ${mine.name} ativada — ${ton2(mine.priceTon)} TON pagos com saldo interno.`
          : 'Pagamento enviado! A mina é ativada após a confirmação na blockchain.',
      );
      await refresh();
    },
    onError: (error: Error, mine) => {
      setPhase({ mineId: mine.id, state: 'error' });
      toast.error(/cancel|reject|declin/i.test(error.message) ? 'Compra cancelada.' : error.message);
    },
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

  const buyLabel = (mine: TonMineTemplate): string => {
    if (phase.mineId !== mine.id) return `⛏ Comprar • ${ton2(mine.priceTon)} TON`;
    if (phase.state === 'wallet') return '◇ Confirme na carteira';
    if (phase.state === 'processing') return '◌ Processando...';
    if (phase.state === 'error') return 'Tentar novamente';
    return `⛏ Comprar • ${ton2(mine.priceTon)} TON`;
  };

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto" style={{ background: 'linear-gradient(180deg, #05070f 0%, #04050b 60%, #020306 100%)' }}>
      <div
        className="pointer-events-none absolute inset-x-0 top-0 h-56 opacity-70"
        style={{ background: 'radial-gradient(120% 100% at 50% 0%, rgba(212,175,55,.18), rgba(56,189,248,.08) 45%, transparent 72%)' }}
      />
      <div className="forge-safe-page relative mx-auto w-full max-w-lg space-y-2.5 px-3 pb-20 pt-3">
        {/* ── Header compacto ── */}
        <header className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <span
              className="flex h-9 w-9 items-center justify-center rounded-lg"
              style={{ ...GOLD_FRAME, background: 'linear-gradient(160deg, rgba(212,175,55,.22), rgba(8,10,20,.9))' }}
            >
              <Pickaxe className="h-4 w-4" style={{ color: '#f3d98b' }} />
            </span>
            <div>
              <h1 className="text-base font-black uppercase tracking-wider" style={{ color: '#f6e3ab', textShadow: '0 0 14px rgba(212,175,55,.35)' }}>
                Minas de TON
              </h1>
              <p className="text-[10px] text-muted-foreground">Investimento passivo · rende offline 24h</p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Fechar"
            className="rounded-full p-1.5 text-muted-foreground transition hover:text-amber-100"
            style={GOLD_FRAME}
          >
            <X className="h-4 w-4" />
          </button>
        </header>

        {/* ── Painel resumo compacto ── */}
        <section
          className="rounded-xl p-2.5"
          style={{ ...GOLD_FRAME, background: 'linear-gradient(160deg, rgba(212,175,55,.10), rgba(6,9,18,.95) 45%, rgba(3,5,12,.98))' }}
        >
          {/* Linha 1: 4 mini-cards */}
          <div className="grid grid-cols-4 gap-1.5">
            {[
              { label: 'Investido', value: `${ton2(summary?.investedTon ?? 0)}`, icon: Coins },
              { label: 'Minas', value: `${summary?.activeMines ?? 0}`, icon: Pickaxe },
              { label: 'Diário', value: `${ton(summary?.dailyTon ?? 0)}`, icon: TrendingUp },
              { label: 'Coletado', value: `${ton2(summary?.lifetimeClaimedTon ?? 0)}`, icon: Gem },
            ].map(item => (
              <div
                key={item.label}
                className="rounded-lg px-1.5 py-1.5 text-center"
                style={{ border: '1px solid rgba(212,175,55,.24)', background: 'rgba(212,175,55,.05)' }}
              >
                <p className="flex items-center justify-center gap-1 text-[8px] uppercase tracking-wider" style={{ color: 'rgba(226,197,122,.75)' }}>
                  <item.icon className="h-2.5 w-2.5" /> {item.label}
                </p>
                <p className="mt-0.5 truncate text-[11px] font-black" style={{ color: '#f6e3ab' }}>{item.value}</p>
              </div>
            ))}
          </div>

          {/* Linha 2: disponível + coletar tudo */}
          <div
            className="mt-1.5 flex items-center justify-between gap-2 rounded-lg px-2.5 py-1.5"
            style={{ border: '1px solid rgba(52,211,153,.28)', background: 'linear-gradient(120deg, rgba(16,185,129,.14), rgba(6,9,18,.6))' }}
          >
            <div className="min-w-0">
              <p className="text-[8px] uppercase tracking-wider text-emerald-200/80">Disponível para coletar</p>
              <p className="truncate text-sm font-black text-emerald-300" style={{ textShadow: '0 0 12px rgba(52,211,153,.35)' }}>
                {ton(summary?.unclaimedTon ?? 0)} TON
              </p>
            </div>
            <button
              type="button"
              disabled={!canClaimAll || claim.isPending}
              onClick={() => claim.mutate(undefined)}
              className="shrink-0 rounded-lg px-3 py-1.5 text-[10px] font-black uppercase tracking-wider transition active:scale-[0.97] disabled:opacity-40"
              style={{
                color: '#04140d',
                border: '1px solid rgba(212,175,55,.45)',
                background: 'linear-gradient(160deg, #6ee7b7, #10b981 55%, #047857)',
                boxShadow: canClaimAll ? '0 0 16px rgba(16,185,129,.35)' : 'none',
              }}
            >
              {claim.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : 'Coletar tudo'}
            </button>
          </div>

          {/* Saldo interno + fidelidade — linhas pequenas */}
          <div className="mt-1.5 flex flex-wrap items-center justify-between gap-x-3 gap-y-0.5 px-0.5">
            <p className="flex items-center gap-1 text-[10px]" style={{ color: 'rgba(148,197,235,.85)' }}>
              <span
                className="flex h-3.5 w-3.5 items-center justify-center rounded-full text-[7px] font-black"
                style={{ background: 'linear-gradient(160deg,#38bdf8,#0369a1)', color: '#04121c' }}
              >
                T
              </span>
              Saldo interno: <span className="font-black text-sky-200">{ton(state?.balanceTon ?? 0)} TON</span>
            </p>
            {state?.loyalty.enabled ? (
              <p className="flex items-center gap-1 text-[10px]" style={{ color: '#e2c57a' }}>
                <Sparkles className="h-3 w-3" />
                +{state.loyalty.bonus30}% 30d · +{state.loyalty.bonus60}% 60d
              </p>
            ) : null}
          </div>
        </section>

        {isLoading ? (
          <div className="flex justify-center py-8"><Loader2 className="h-5 w-5 animate-spin" style={{ color: '#e2c57a' }} /></div>
        ) : null}

        {state && !state.visible ? (
          <p className="rounded-xl p-3 text-center text-xs text-muted-foreground" style={GOLD_FRAME}>
            As MINAS DE TON ainda não foram liberadas para o seu acesso.
          </p>
        ) : null}

        {/* ── Cards horizontais compactos ── */}
        <div className="space-y-2" key={tick}>
          {mines.map((mine, index) => {
            const holding = mine.holdings[0];
            const progress = holding && holding.capacityTon > 0
              ? Math.min(100, (holding.storedTon / holding.capacityTon) * 100)
              : 0;
            const owned = Boolean(holding);
            const glow = mineGlow(index);
            const busy = phase.mineId === mine.id && (phase.state === 'processing' || phase.state === 'wallet');
            return (
              <article
                key={mine.id}
                className="relative flex h-[122px] overflow-hidden rounded-xl"
                style={{
                  border: owned ? '1px solid rgba(52,211,153,.45)' : '1px solid rgba(212,175,55,.42)',
                  background: 'linear-gradient(140deg, rgba(10,13,24,.96), rgba(3,5,12,.98))',
                  boxShadow: owned
                    ? '0 0 20px rgba(16,185,129,.12), inset 0 0 16px rgba(52,211,153,.05)'
                    : '0 0 18px rgba(212,175,55,.08), inset 0 0 16px rgba(255,190,60,.04)',
                }}
              >
                {/* Imagem — 35% */}
                <div className="relative w-[35%] shrink-0">
                  {mine.imageUrl ? (
                    <img src={mine.imageUrl} alt={mine.name} loading="lazy" className="h-full w-full object-cover" />
                  ) : (
                    <div className="h-full w-full" style={{ background: 'rgba(212,175,55,.06)' }} />
                  )}
                  {/* glow temático + fusão com o card */}
                  <div className="absolute inset-0" style={{ background: `radial-gradient(80% 70% at 20% 40%, ${glow}, transparent 70%)` }} />
                  <div className="absolute inset-0" style={{ background: 'linear-gradient(90deg, rgba(3,5,12,.55) 0%, transparent 35%, rgba(3,5,12,.92) 100%)' }} />
                  <div className="absolute inset-0" style={{ boxShadow: 'inset 0 0 22px rgba(0,0,0,.75)' }} />
                </div>

                {/* Conteúdo — 65% */}
                <div className="flex min-w-0 flex-1 flex-col justify-between p-2">
                  <div className="min-w-0">
                    <div className="flex items-start justify-between gap-1.5">
                      <h2 className="truncate text-[11px] font-black uppercase tracking-wide" style={{ color: '#f6e3ab' }}>{mine.name}</h2>
                      <span
                        className="shrink-0 rounded px-1.5 py-0.5 text-[9px] font-black uppercase tracking-wide"
                        style={owned
                          ? { color: '#04140d', background: 'linear-gradient(160deg,#6ee7b7,#059669)' }
                          : mine.status === 'LOCKED'
                            ? { color: 'rgba(226,197,122,.6)', border: '1px solid rgba(212,175,55,.25)' }
                            : { color: '#1b1405', background: 'linear-gradient(160deg,#f7dd94,#c79a2e)' }}
                      >
                        {owned ? 'Ativa' : mine.status === 'LOCKED' ? 'Indisponível' : `${ton2(mine.priceTon)} TON`}
                      </span>
                    </div>
                    <p className="mt-0.5 text-[11px] font-black" style={{ color: '#7dd3fc', textShadow: '0 0 10px rgba(56,189,248,.35)' }}>
                      {ton(mine.dailyTon)} TON/dia
                    </p>
                    <p className="mt-0.5 truncate text-[9px]" style={{ color: 'rgba(203,213,225,.65)' }}>
                      ROI {mine.roiDays ? `${mine.roiDays}d` : '—'} · Storage {mine.storageDays}d
                      {state?.loyalty.enabled ? <span style={{ color: '#e2c57a' }}>{` · +${state.loyalty.bonus30}% Loyalty`}</span> : ''}
                    </p>
                  </div>

                  {holding ? (
                    <div className="space-y-1">
                      <div className="flex items-center justify-between text-[9px]">
                        <span className="font-bold text-emerald-300">{ton(holding.storedTon)} / {ton(holding.capacityTon)} TON</span>
                        <span style={{ color: 'rgba(203,213,225,.6)' }}>
                          {fullInLabel(holding.fullAt)} · {holding.daysHeld}d{holding.multiplier > 1 ? ` +${Math.round((holding.multiplier - 1) * 100)}%` : ''}
                        </span>
                      </div>
                      <div className="h-1 overflow-hidden rounded-full" style={{ background: 'rgba(212,175,55,.12)' }}>
                        <div className="h-full rounded-full" style={{ width: `${progress}%`, background: 'linear-gradient(90deg,#10b981,#a7f3d0)', boxShadow: '0 0 8px rgba(52,211,153,.5)' }} />
                      </div>
                      <button
                        type="button"
                        disabled={holding.storedTon <= 0 || claim.isPending}
                        onClick={() => claim.mutate(holding.id)}
                        className="w-full rounded-lg py-1.5 text-[10px] font-black uppercase tracking-wider transition active:scale-[0.98] disabled:opacity-40"
                        style={{
                          color: '#04140d',
                          border: '1px solid rgba(212,175,55,.4)',
                          background: 'linear-gradient(160deg,#6ee7b7,#10b981 55%,#047857)',
                          boxShadow: '0 0 14px rgba(16,185,129,.28)',
                        }}
                      >
                        Coletar · {ton(holding.storedTon)} TON
                      </button>
                    </div>
                  ) : (
                    <button
                      type="button"
                      disabled={mine.status === 'LOCKED' || !state?.visible || busy || buy.isPending}
                      onClick={() => buy.mutate(mine)}
                      className="flex w-full items-center justify-center gap-1.5 rounded-lg py-1.5 text-[10px] font-black uppercase tracking-wider transition active:scale-[0.98] disabled:opacity-45"
                      style={mine.status === 'LOCKED'
                        ? { color: 'rgba(226,197,122,.6)', border: '1px solid rgba(212,175,55,.25)', background: 'rgba(212,175,55,.05)' }
                        : {
                          color: '#1b1405',
                          border: '1px solid rgba(247,221,148,.6)',
                          background: 'linear-gradient(160deg,#f9e6a9,#d4af37 48%,#8a6414)',
                          boxShadow: '0 0 16px rgba(212,175,55,.28), inset 0 1px 0 rgba(255,255,255,.35)',
                        }}
                    >
                      {mine.status === 'LOCKED' ? <><Lock className="h-3 w-3" /> Indisponível</> : buyLabel(mine)}
                    </button>
                  )}
                </div>
              </article>
            );
          })}
        </div>

        {state?.claims.length ? (
          <section className="rounded-xl p-2.5" style={{ ...GOLD_FRAME, background: 'rgba(4,6,14,.85)' }}>
            <h3 className="text-[9px] uppercase tracking-[0.3em]" style={{ color: 'rgba(226,197,122,.7)' }}>Últimas coletas</h3>
            <ul className="mt-1.5 space-y-1">
              {state.claims.map(item => (
                <li key={item.id} className="flex items-center justify-between text-[11px]">
                  <span style={{ color: 'rgba(203,213,225,.7)' }}>{item.mineName ?? 'Mina'}</span>
                  <span className="font-black text-emerald-300">+{ton(item.amountTon)} TON</span>
                </li>
              ))}
            </ul>
          </section>
        ) : null}
      </div>
    </div>
  );
}
