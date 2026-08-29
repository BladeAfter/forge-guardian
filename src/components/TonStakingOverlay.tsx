import { useEffect, useMemo, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Coins, Gem, Loader2, Lock, LockOpen, Repeat, Sparkles, TrendingUp, X } from 'lucide-react';
import { toast } from 'sonner';
import {
  claimTonStaking,
  fetchTonStaking,
  setTonStakingPositionCompound,
  setTonStakingPreferences,
  stakeTon,
  unstakeTon,
  type TonStakingPlan,
  type TonStakingState,
} from '../services';

const ton = (value: number) => Number(value || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 4 });
const ton2 = (value: number) => Number(value || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const pct = (value: number) => Number(value || 0).toLocaleString('pt-BR', { maximumFractionDigits: 2 });

const GOLD_FRAME = {
  border: '1px solid rgba(212, 175, 55, 0.42)',
  boxShadow: '0 0 18px rgba(212, 175, 55, 0.08), inset 0 0 16px rgba(255, 190, 60, 0.04)',
} as const;

function unlockLabel(unlockAt: string): string {
  const diff = new Date(unlockAt).getTime() - Date.now();
  if (!Number.isFinite(diff) || diff <= 0) return 'Liberado';
  const hours = Math.floor(diff / 3_600_000);
  const days = Math.floor(hours / 24);
  if (days >= 1) return `Libera em ${days}d ${hours % 24}h`;
  return `Libera em ${hours}h ${Math.floor((diff % 3_600_000) / 60_000)}m`;
}

/**
 * 💎 TON STAKING — bloqueio de TON interno por período, com rendimento acumulado
 * 100% no servidor (funciona offline, sem precisar abrir o jogo todos os dias).
 *
 * O cliente só renderiza a verdade do servidor: planos, taxas, bônus por período,
 * datas de liberação, rendimento acumulado, auto-staking das Minas e compound.
 */
export function TonStakingOverlay({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const client = useQueryClient();
  const [planId, setPlanId] = useState<string | null>(null);
  const [amount, setAmount] = useState('');
  const [compound, setCompound] = useState(false);
  const stakeKey = useRef<string>('');

  const { data: state, isLoading } = useQuery<TonStakingState>({
    queryKey: ['ton-staking'],
    queryFn: () => fetchTonStaking(telegramInitData),
    enabled: Boolean(telegramInitData),
    refetchInterval: 30_000,
  });

  const plans = useMemo(() => state?.plans ?? [], [state]);
  useEffect(() => {
    if (!planId && plans.length) setPlanId(plans[0].id);
  }, [plans, planId]);

  const plan: TonStakingPlan | undefined = plans.find(p => p.id === planId) ?? plans[0];
  const summary = state?.summary;
  const prefs = state?.preferences;

  const refresh = () => Promise.all(
    ['ton-staking', 'ton-mines', 'game-state', 'ton-wallet', 'wallet-summary']
      .map(key => client.invalidateQueries({ queryKey: [key] })),
  );

  const stake = useMutation({
    mutationFn: async () => {
      if (!plan) throw new Error('Selecione um plano.');
      const value = Number(String(amount).replace(',', '.'));
      if (!Number.isFinite(value) || value <= 0) throw new Error('Informe um valor válido em TON.');
      if (!stakeKey.current) stakeKey.current = `stk:${Date.now()}`;
      return stakeTon(telegramInitData, plan.id, value, compound, stakeKey.current);
    },
    onSuccess: async result => {
      stakeKey.current = '';
      setAmount('');
      toast.success(`✓ ${ton(result.stakedTon || 0)} TON em staking por ${plan?.lockDays ?? 0} dias.`);
      await refresh();
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const claim = useMutation({
    mutationFn: (positionId?: string) => claimTonStaking(telegramInitData, positionId, `clm:${Date.now()}`),
    onSuccess: async result => {
      toast.success(`+${ton(result.claimedTon || 0)} TON creditados no saldo interno.`);
      await refresh();
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const withdraw = useMutation({
    mutationFn: (positionId: string) => unstakeTon(telegramInitData, positionId, `uns:${positionId}`),
    onSuccess: async result => {
      toast.success(`+${ton(result.returnedTon || 0)} TON resgatados.`);
      await refresh();
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const savePrefs = useMutation({
    mutationFn: (next: { enabled: boolean; percent: number; autoCompound: boolean }) =>
      setTonStakingPreferences(telegramInitData, { ...next, planId: plan?.id ?? null }),
    onSuccess: async () => {
      toast.success('Auto-staking atualizado.');
      await refresh();
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const togglePositionCompound = useMutation({
    mutationFn: (input: { id: string; value: boolean }) => setTonStakingPositionCompound(telegramInitData, input.id, input.value),
    onSuccess: async () => { await refresh(); },
    onError: (error: Error) => toast.error(error.message),
  });

  const balance = state?.balanceTon ?? 0;
  const parsed = Number(String(amount).replace(',', '.')) || 0;
  const monthlyPreview = plan ? (parsed * plan.effectiveMonthlyRate) / 100 : 0;
  const termPreview = plan ? (monthlyPreview * plan.lockDays) / (state?.monthDays || 30) : 0;
  const canClaimAll = (summary?.unclaimedTon ?? 0) > 0;

  return (
    <div className="fixed inset-0 z-[60] overflow-y-auto" style={{ background: 'linear-gradient(180deg, #05070f 0%, #04050b 60%, #020306 100%)' }}>
      <div
        className="pointer-events-none absolute inset-x-0 top-0 h-56 opacity-70"
        style={{ background: 'radial-gradient(120% 100% at 50% 0%, rgba(56,189,248,.18), rgba(212,175,55,.10) 45%, transparent 72%)' }}
      />
      <div className="forge-safe-page relative mx-auto w-full max-w-lg space-y-2.5 px-3 pb-20 pt-3">
        {/* ── Header ── */}
        <header className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <span
              className="flex h-9 w-9 items-center justify-center rounded-lg"
              style={{ ...GOLD_FRAME, background: 'linear-gradient(160deg, rgba(56,189,248,.22), rgba(8,10,20,.9))' }}
            >
              <Gem className="h-4 w-4" style={{ color: '#7dd3fc' }} />
            </span>
            <div>
              <h1 className="text-base font-black uppercase tracking-wider" style={{ color: '#f6e3ab', textShadow: '0 0 14px rgba(212,175,55,.35)' }}>
                TON Staking
              </h1>
              <p className="text-[10px] text-muted-foreground">Bloqueie TON interno · rende offline 24h</p>
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

        {/* ── Dashboard compacto ── */}
        <section
          className="rounded-xl p-2.5"
          style={{ ...GOLD_FRAME, background: 'linear-gradient(160deg, rgba(56,189,248,.10), rgba(6,9,18,.95) 45%, rgba(3,5,12,.98))' }}
        >
          <div className="grid grid-cols-4 gap-1.5">
            {[
              { label: 'Em stake', value: ton2(summary?.totalStakedTon ?? 0), icon: Lock },
              { label: 'Mensal', value: ton(summary?.monthlyEstimateTon ?? 0), icon: TrendingUp },
              { label: 'Posições', value: String(summary?.activePositions ?? 0), icon: Coins },
              { label: 'Ganho', value: ton2(summary?.totalEarnedTon ?? 0), icon: Gem },
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

          <div
            className="mt-1.5 flex items-center justify-between gap-2 rounded-lg px-2.5 py-1.5"
            style={{ border: '1px solid rgba(52,211,153,.28)', background: 'linear-gradient(120deg, rgba(16,185,129,.14), rgba(6,9,18,.6))' }}
          >
            <div className="min-w-0">
              <p className="text-[8px] uppercase tracking-wider text-emerald-200/80">Rendimento disponível</p>
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
              {claim.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : 'Coletar'}
            </button>
          </div>

          <div className="mt-1.5 flex flex-wrap items-center justify-between gap-x-3 gap-y-0.5 px-0.5">
            <p className="flex items-center gap-1 text-[10px]" style={{ color: 'rgba(148,197,235,.85)' }}>
              <span
                className="flex h-3.5 w-3.5 items-center justify-center rounded-full text-[7px] font-black"
                style={{ background: 'linear-gradient(160deg,#38bdf8,#0369a1)', color: '#04121c' }}
              >
                T
              </span>
              Saldo interno: <span className="font-black text-sky-200">{ton(balance)} TON</span>
            </p>
            {summary?.nextMaturityDays != null ? (
              <p className="flex items-center gap-1 text-[10px]" style={{ color: '#e2c57a' }}>
                <Sparkles className="h-3 w-3" /> Próxima liberação em {summary.nextMaturityDays}d
              </p>
            ) : null}
          </div>
        </section>

        {isLoading ? (
          <div className="flex justify-center py-8"><Loader2 className="h-5 w-5 animate-spin" style={{ color: '#e2c57a' }} /></div>
        ) : null}

        {state && !state.enabled ? (
          <p className="rounded-xl p-3 text-center text-xs text-muted-foreground" style={GOLD_FRAME}>
            O TON STAKING está temporariamente indisponível.
          </p>
        ) : null}

        {/* ── Novo stake ── */}
        {state?.enabled ? (
          <section
            className="space-y-2 rounded-xl p-2.5"
            style={{ ...GOLD_FRAME, background: 'linear-gradient(140deg, rgba(10,13,24,.96), rgba(3,5,12,.98))' }}
          >
            <h2 className="text-[11px] font-black uppercase tracking-wider" style={{ color: '#f6e3ab' }}>Novo stake</h2>

            <div className="grid grid-cols-5 gap-1.5">
              {plans.map(item => {
                const active = item.id === (plan?.id ?? '');
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => setPlanId(item.id)}
                    className="rounded-lg px-1 py-1.5 text-center transition active:scale-[0.97]"
                    style={active
                      ? { border: '1px solid rgba(212,175,55,.7)', background: 'linear-gradient(160deg, rgba(212,175,55,.22), rgba(6,9,18,.9))', boxShadow: '0 0 14px rgba(212,175,55,.22)' }
                      : { border: '1px solid rgba(212,175,55,.22)', background: 'rgba(212,175,55,.04)' }}
                  >
                    <p className="text-[10px] font-black" style={{ color: active ? '#f6e3ab' : 'rgba(226,197,122,.8)' }}>{item.lockDays}d</p>
                    <p className="text-[8px]" style={{ color: '#7dd3fc' }}>{pct(item.effectiveMonthlyRate)}%/mês</p>
                    {item.bonusRate > 0 ? <p className="text-[7px]" style={{ color: '#34d399' }}>+{pct(item.bonusRate)}% bônus</p> : null}
                  </button>
                );
              })}
            </div>

            <div className="flex items-center gap-1.5">
              <input
                inputMode="decimal"
                value={amount}
                onChange={event => setAmount(event.target.value.replace(/[^\d.,]/g, ''))}
                placeholder={`Mín. ${ton2(plan?.minStakeTon ?? state.minStakeTon)} TON`}
                className="min-w-0 flex-1 rounded-lg bg-transparent px-2.5 py-2 text-sm font-black text-sky-100 outline-none placeholder:text-[11px] placeholder:font-normal placeholder:text-muted-foreground"
                style={{ border: '1px solid rgba(56,189,248,.32)' }}
              />
              {[25, 50, 100].map(percent => (
                <button
                  key={percent}
                  type="button"
                  onClick={() => setAmount(String(Math.floor(((balance * percent) / 100) * 1000) / 1000))}
                  className="shrink-0 rounded-lg px-2 py-2 text-[9px] font-black uppercase"
                  style={{ border: '1px solid rgba(212,175,55,.28)', color: 'rgba(226,197,122,.9)' }}
                >
                  {percent}%
                </button>
              ))}
            </div>

            <div className="flex items-center justify-between gap-2 text-[9px]" style={{ color: 'rgba(203,213,225,.7)' }}>
              <span>
                Estimativa: <span className="font-black text-emerald-300">{ton(monthlyPreview)} TON/mês</span>
                {plan ? <> · {ton(termPreview)} TON em {plan.lockDays}d</> : null}
              </span>
              {plan?.autoCompoundAllowed ? (
                <button
                  type="button"
                  onClick={() => setCompound(value => !value)}
                  className="flex shrink-0 items-center gap-1 rounded-lg px-2 py-1 text-[9px] font-black uppercase tracking-wide"
                  style={compound
                    ? { border: '1px solid rgba(52,211,153,.5)', color: '#6ee7b7', background: 'rgba(16,185,129,.12)' }
                    : { border: '1px solid rgba(212,175,55,.25)', color: 'rgba(226,197,122,.8)' }}
                >
                  <Repeat className="h-3 w-3" /> Compound
                </button>
              ) : null}
            </div>

            <button
              type="button"
              disabled={stake.isPending || !state.newStakesOpen || parsed <= 0}
              onClick={() => stake.mutate()}
              className="w-full rounded-lg py-2 text-[11px] font-black uppercase tracking-wider transition active:scale-[0.98] disabled:opacity-40"
              style={{
                color: '#1b1405',
                border: '1px solid rgba(212,175,55,.5)',
                background: 'linear-gradient(160deg, #f7dd94, #c79a2e 60%, #8a640f)',
                boxShadow: '0 0 18px rgba(212,175,55,.22)',
              }}
            >
              {stake.isPending ? <Loader2 className="mx-auto h-4 w-4 animate-spin" /> : state.newStakesOpen ? '💎 Fazer stake com saldo interno' : 'Novos stakes pausados'}
            </button>
          </section>
        ) : null}

        {/* ── Auto-staking das Minas ── */}
        {state?.enabled ? (
          <section
            className="space-y-1.5 rounded-xl p-2.5"
            style={{ ...GOLD_FRAME, background: 'linear-gradient(140deg, rgba(10,13,24,.96), rgba(3,5,12,.98))' }}
          >
            <div className="flex items-center justify-between gap-2">
              <h2 className="text-[11px] font-black uppercase tracking-wider" style={{ color: '#f6e3ab' }}>Auto-staking das minas</h2>
              <span className="text-[9px]" style={{ color: 'rgba(203,213,225,.65)' }}>
                Buffer: {ton(prefs?.pendingAutoStakeTon ?? 0)} TON
              </span>
            </div>
            <p className="text-[9px]" style={{ color: 'rgba(203,213,225,.65)' }}>
              Uma parte do que você coleta nas MINAS DE TON entra direto em staking (plano selecionado acima).
              Acumula até {ton2(state.autoStakeMinTon)} TON antes de abrir uma nova posição.
            </p>
            <div className="grid grid-cols-5 gap-1.5">
              {[0, ...state.allowedPercents].map(percent => {
                const active = (prefs?.mineAutoStakeEnabled ? prefs.mineAutoStakePercent : 0) === percent;
                return (
                  <button
                    key={percent}
                    type="button"
                    disabled={savePrefs.isPending}
                    onClick={() => savePrefs.mutate({ enabled: percent > 0, percent, autoCompound: prefs?.autoCompound ?? false })}
                    className="rounded-lg py-1.5 text-[10px] font-black uppercase transition active:scale-[0.97] disabled:opacity-50"
                    style={active
                      ? { border: '1px solid rgba(56,189,248,.6)', color: '#7dd3fc', background: 'rgba(56,189,248,.14)' }
                      : { border: '1px solid rgba(212,175,55,.22)', color: 'rgba(226,197,122,.8)' }}
                  >
                    {percent === 0 ? 'OFF' : `${percent}%`}
                  </button>
                );
              })}
            </div>
            {state.autoCompoundAllowed ? (
              <button
                type="button"
                disabled={savePrefs.isPending}
                onClick={() => savePrefs.mutate({
                  enabled: prefs?.mineAutoStakeEnabled ?? false,
                  percent: prefs?.mineAutoStakePercent ?? 0,
                  autoCompound: !(prefs?.autoCompound ?? false),
                })}
                className="flex w-full items-center justify-center gap-1 rounded-lg py-1.5 text-[9px] font-black uppercase tracking-wide"
                style={prefs?.autoCompound
                  ? { border: '1px solid rgba(52,211,153,.5)', color: '#6ee7b7', background: 'rgba(16,185,129,.12)' }
                  : { border: '1px solid rgba(212,175,55,.25)', color: 'rgba(226,197,122,.8)' }}
              >
                <Repeat className="h-3 w-3" /> Compound automático nas novas posições
              </button>
            ) : null}
          </section>
        ) : null}

        {/* ── Posições ── */}
        <div className="space-y-2">
          {(state?.positions ?? []).map(position => {
            const matured = position.status === 'MATURED' || new Date(position.unlockAt).getTime() <= Date.now();
            return (
              <article
                key={position.id}
                className="rounded-xl p-2.5"
                style={{
                  border: matured ? '1px solid rgba(52,211,153,.45)' : '1px solid rgba(56,189,248,.32)',
                  background: 'linear-gradient(140deg, rgba(10,13,24,.96), rgba(3,5,12,.98))',
                }}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <h3 className="truncate text-[11px] font-black uppercase tracking-wide" style={{ color: '#f6e3ab' }}>
                      {position.planName} · {pct(position.effectiveMonthlyRate)}%/mês
                    </h3>
                    <p className="mt-0.5 text-[11px] font-black" style={{ color: '#7dd3fc' }}>{ton(position.principalTon)} TON em stake</p>
                  </div>
                  <span
                    className="shrink-0 rounded px-1.5 py-0.5 text-[9px] font-black uppercase tracking-wide"
                    style={matured
                      ? { color: '#04140d', background: 'linear-gradient(160deg,#6ee7b7,#059669)' }
                      : { color: 'rgba(226,197,122,.9)', border: '1px solid rgba(212,175,55,.3)' }}
                  >
                    {matured ? 'Liberado' : unlockLabel(position.unlockAt)}
                  </span>
                </div>

                <div className="mt-1.5 h-1 overflow-hidden rounded-full" style={{ background: 'rgba(212,175,55,.12)' }}>
                  <div
                    className="h-full rounded-full"
                    style={{ width: `${position.progressPercent}%`, background: 'linear-gradient(90deg,#38bdf8,#a7f3d0)', boxShadow: '0 0 8px rgba(56,189,248,.5)' }}
                  />
                </div>

                <div className="mt-1 flex items-center justify-between text-[9px]" style={{ color: 'rgba(203,213,225,.7)' }}>
                  <span>Acumulado: <span className="font-black text-emerald-300">{ton(position.accruedTon)} TON</span></span>
                  <span>Total ganho: {ton(position.earnedTon)} TON{position.compoundedTon > 0 ? ` · reinvestido ${ton(position.compoundedTon)}` : ''}</span>
                </div>

                <div className="mt-1.5 grid grid-cols-3 gap-1.5">
                  <button
                    type="button"
                    disabled={claim.isPending || position.accruedTon <= 0 || !position.canClaim}
                    onClick={() => claim.mutate(position.id)}
                    className="rounded-lg py-1.5 text-[9px] font-black uppercase tracking-wide transition active:scale-[0.97] disabled:opacity-40"
                    style={{ color: '#04140d', background: 'linear-gradient(160deg,#6ee7b7,#059669)' }}
                  >
                    Coletar
                  </button>
                  <button
                    type="button"
                    disabled={togglePositionCompound.isPending || !state?.autoCompoundAllowed}
                    onClick={() => togglePositionCompound.mutate({ id: position.id, value: !position.autoCompound })}
                    className="flex items-center justify-center gap-1 rounded-lg py-1.5 text-[9px] font-black uppercase tracking-wide disabled:opacity-40"
                    style={position.autoCompound
                      ? { border: '1px solid rgba(52,211,153,.5)', color: '#6ee7b7' }
                      : { border: '1px solid rgba(212,175,55,.25)', color: 'rgba(226,197,122,.85)' }}
                  >
                    <Repeat className="h-3 w-3" /> {position.autoCompound ? 'ON' : 'OFF'}
                  </button>
                  <button
                    type="button"
                    disabled={withdraw.isPending || (!matured && !state?.earlyUnstakeAllowed)}
                    onClick={() => withdraw.mutate(position.id)}
                    className="flex items-center justify-center gap-1 rounded-lg py-1.5 text-[9px] font-black uppercase tracking-wide disabled:opacity-40"
                    style={{ border: '1px solid rgba(212,175,55,.35)', color: '#f6e3ab' }}
                  >
                    {matured ? <LockOpen className="h-3 w-3" /> : <Lock className="h-3 w-3" />} Resgatar
                  </button>
                </div>
              </article>
            );
          })}
          {state && state.positions.length === 0 ? (
            <p className="rounded-xl p-3 text-center text-[11px] text-muted-foreground" style={GOLD_FRAME}>
              Você ainda não tem posições em staking. Bloqueie TON interno e receba rendimento diário automático.
            </p>
          ) : null}
        </div>

        {/* ── Histórico curto ── */}
        {state?.ledger?.length ? (
          <section className="rounded-xl p-2.5" style={{ ...GOLD_FRAME, background: 'rgba(6,9,18,.9)' }}>
            <h2 className="mb-1 text-[10px] font-black uppercase tracking-wider" style={{ color: '#f6e3ab' }}>Histórico</h2>
            <div className="space-y-0.5">
              {state.ledger.map(entry => (
                <p key={entry.id} className="flex items-center justify-between text-[9px]" style={{ color: 'rgba(203,213,225,.7)' }}>
                  <span>{entry.type}</span>
                  <span className="font-black" style={{ color: '#7dd3fc' }}>{ton(entry.amountTon)} TON</span>
                </p>
              ))}
            </div>
          </section>
        ) : null}
      </div>
    </div>
  );
}
