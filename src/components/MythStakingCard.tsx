import { useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Lock, Sparkles, X } from 'lucide-react';
import { mythToken } from '../gameAssets';
import { useMythStaking } from '../hooks';
import { claimMythStakingRewards, stakeMyth, unstakeMyth } from '../services';
import {
  formatApr, formatMyth, formatUnlockDate, mythStakingErrorLabel,
  type MythStakingDashboard,
} from '../mythStaking';

/**
 * MYTH STAKING — Mythreon Ecosystem Staking (internal, backend-controlled).
 *
 * Deliberately NOT presented as on-chain/TON validator staking: there is no smart contract yet.
 * The card only mirrors backend state; STAKED/REWARDS/APR, limits, locks and the ON/OFF switch are
 * decided by the Admin Bot, so activating staking needs no deploy. All mutations are idempotent
 * (one server key per click) and MYTH never leaves the MYTH economy.
 */
export function MythStakingCard({ initData, enabled }: { initData: string | null; enabled: boolean }) {
  const [open, setOpen] = useState(false);
  const { data } = useMythStaking(initData, enabled);
  const staked = data?.player.staked ?? 0;
  const apr = data?.settings.bestApr ?? null;
  const active = data?.settings.enabled === true;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="relative w-full overflow-hidden rounded-2xl border border-amber-400/45 bg-gradient-to-r from-[#1b0f2e] via-[#0b0715] to-[#2a1a05] p-3 text-left shadow-[0_0_28px_rgba(168,85,247,.22),inset_0_0_20px_rgba(251,191,36,.12)]"
      >
        <span className="pointer-events-none absolute -right-6 -top-8 h-24 w-24 rounded-full bg-amber-400/20 blur-2xl" />
        <span className="relative flex items-center gap-3">
          <span className="relative shrink-0">
            <img src={mythToken} alt="MYTH" loading="lazy" width={64} height={64} className="h-11 w-11 object-contain drop-shadow-[0_0_12px_rgba(251,191,36,.5)]" />
            <span className="absolute -bottom-1 -right-1 grid h-5 w-5 place-items-center rounded-full border border-amber-300/60 bg-black/80">
              <Lock className="h-3 w-3 text-amber-200" />
            </span>
          </span>
          <span className="min-w-0 flex-1">
            <span className="flex items-center gap-2">
              <span className="truncate text-[11px] font-black uppercase tracking-[.16em] text-amber-100">MYTH Staking</span>
              {!active ? (
                <span className="rounded-full border border-amber-400/50 bg-black/60 px-2 py-[2px] text-[8px] font-black uppercase tracking-[.14em] text-amber-200">Coming Soon</span>
              ) : null}
            </span>
            <span className="block text-[10px] uppercase tracking-[.1em] text-fuchsia-300/90">Mythreon Ecosystem Staking</span>
            <span className="mt-1 flex items-center gap-3 text-[9px] font-black uppercase tracking-[.12em] text-slate-300">
              <span>{formatMyth(staked)} <span className="text-amber-300">staked</span></span>
              <span>APR <span className="text-emerald-300">{formatApr(apr)}</span></span>
            </span>
          </span>
          <span className="shrink-0 rounded-xl border border-amber-400/50 bg-amber-400/10 px-3 py-2 text-[10px] font-black uppercase tracking-[.16em] text-amber-200">
            {active ? 'Stake' : 'View'}
          </span>
        </span>
      </button>

      {open ? <MythStakingModal initData={initData} data={data} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

function MythStakingModal({ initData, data, onClose }: { initData: string | null; data?: MythStakingDashboard; onClose: () => void }) {
  const client = useQueryClient();
  const [amount, setAmount] = useState('');
  const [planCode, setPlanCode] = useState('');
  const [feedback, setFeedback] = useState<string | null>(null);
  const plans = data?.plans ?? [];
  const plan = useMemo(() => plans.find((p) => p.code === (planCode || plans[0]?.code)) ?? null, [plans, planCode]);
  const active = data?.settings.enabled === true;
  const available = data?.player.available ?? 0;
  const value = Number(String(amount).replace(',', '.')) || 0;

  const refresh = () => {
    void client.invalidateQueries({ queryKey: ['myth-staking'] });
    void client.invalidateQueries({ queryKey: ['myth-wallet'] });
  };

  const run = useMutation({
    mutationFn: async (op: { kind: 'stake' | 'claim' | 'unstake'; positionId?: string }) => {
      const key = crypto.randomUUID(); // single server-side idempotency key per click
      if (op.kind === 'stake') return stakeMyth(initData ?? '', value, plan?.code ?? '', key);
      if (op.kind === 'claim') return claimMythStakingRewards(initData ?? '', key, op.positionId ?? null);
      return unstakeMyth(initData ?? '', op.positionId ?? '', key);
    },
    onSuccess: (_res, op) => {
      setFeedback(op.kind === 'stake' ? 'MYTH staked.' : op.kind === 'claim' ? 'Rewards claimed.' : 'Position closed.');
      if (op.kind === 'stake') setAmount('');
      refresh();
    },
    onError: (error: unknown) => setFeedback(mythStakingErrorLabel(error instanceof Error ? error.message : String(error))),
  });
  const busy = run.isPending;

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-black/85 p-4" role="dialog" aria-modal="true">
      <div className="max-h-[90vh] w-full max-w-sm overflow-y-auto rounded-3xl border border-amber-400/35 bg-forge-surface p-4 shadow-card">
        <div className="flex items-center gap-3">
          <img src={mythToken} alt="" loading="lazy" width={64} height={64} className="h-10 w-10 object-contain" />
          <div className="flex-1">
            <p className="text-sm font-black uppercase tracking-[.16em] text-amber-100">MYTH Staking</p>
            <p className="text-[10px] uppercase tracking-[.1em] text-fuchsia-300/90">Mythreon Ecosystem Staking</p>
          </div>
          <button type="button" onClick={onClose} aria-label="Close" className="rounded-full border border-white/15 bg-black/60 p-1 text-slate-300">
            <X className="h-4 w-4" />
          </button>
        </div>

        {!active ? (
          <p className="mt-3 rounded-xl border border-amber-400/30 bg-black/50 p-3 text-xs leading-relaxed text-slate-300">
            Staking is being prepared for a future Mythreon update.
          </p>
        ) : null}

        <div className="mt-3 grid grid-cols-2 gap-2 text-center">
          <Stat label="Your MYTH" value={`${formatMyth(data?.player.totalOwned)} MYTH`} />
          <Stat label="Staked" value={`${formatMyth(data?.player.staked)} MYTH`} />
          <Stat label="Available" value={`${formatMyth(available)} MYTH`} />
          <Stat label="Claimable Rewards" value={`${formatMyth(data?.player.claimable)} MYTH`} />
          <Stat label="Current APR" value={formatApr(data?.settings.bestApr)} />
          <Stat label="Reward Pool" value={`${formatMyth(data?.settings.rewardPoolAvailable)} MYTH`} />
        </div>

        {active && plans.length ? (
          <div className="mt-4 space-y-2 rounded-2xl border border-white/10 bg-black/40 p-3">
            <p className="text-[9px] font-black uppercase tracking-[.18em] text-amber-200">Stake MYTH</p>
            <div className="flex items-center gap-2">
              <input
                value={amount}
                onChange={(event) => setAmount(event.target.value)}
                inputMode="decimal"
                placeholder={`min ${formatMyth(data?.settings.minStake)}`}
                className="min-w-0 flex-1 rounded-xl border border-white/15 bg-black/60 px-3 py-2 text-sm font-bold text-white outline-none"
              />
              {[0.25, 0.5, 1].map((pct) => (
                <button
                  key={pct}
                  type="button"
                  onClick={() => setAmount(String(Math.floor(available * pct)))}
                  className="rounded-lg border border-white/15 bg-black/60 px-2 py-2 text-[9px] font-black uppercase text-slate-300"
                >
                  {pct === 1 ? 'MAX' : `${pct * 100}%`}
                </button>
              ))}
            </div>
            <div className="flex flex-wrap gap-2">
              {plans.map((option) => {
                const selected = plan?.code === option.code;
                return (
                  <button
                    key={option.code}
                    type="button"
                    onClick={() => setPlanCode(option.code)}
                    className={`rounded-xl border px-2 py-1 text-[9px] font-black uppercase tracking-[.12em] ${selected ? 'border-amber-400/70 bg-amber-400/15 text-amber-100' : 'border-white/15 bg-black/50 text-slate-300'}`}
                  >
                    {option.label} · {formatApr(option.aprPercent)}
                  </button>
                );
              })}
            </div>
            <p className="text-[10px] text-slate-400">
              Stake {formatMyth(value)} MYTH · APR {formatApr(plan?.aprPercent)} · Lock {plan?.lockDays ? `${plan.lockDays} days` : 'Flexible'}
            </p>
            <button
              type="button"
              disabled={busy || value <= 0}
              onClick={() => run.mutate({ kind: 'stake' })}
              className="w-full rounded-xl border border-amber-400/50 bg-amber-400/15 py-2 text-[11px] font-black uppercase tracking-[.16em] text-amber-100 disabled:opacity-40"
            >
              Confirm Stake
            </button>
          </div>
        ) : null}

        {active ? (
          <button
            type="button"
            disabled={busy || (data?.player.claimable ?? 0) <= 0}
            onClick={() => run.mutate({ kind: 'claim' })}
            className="mt-3 flex w-full items-center justify-center gap-2 rounded-xl border border-emerald-400/40 bg-emerald-500/10 py-2 text-[11px] font-black uppercase tracking-[.16em] text-emerald-200 disabled:opacity-40"
          >
            <Sparkles className="h-4 w-4" /> Claim Rewards
          </button>
        ) : null}

        {data?.positions?.length ? (
          <div className="mt-3 space-y-2">
            <p className="text-[9px] font-black uppercase tracking-[.18em] text-slate-400">Your Positions</p>
            {data.positions.map((position) => (
              <div key={position.id} className="rounded-xl border border-white/10 bg-black/45 p-2">
                <div className="flex items-center justify-between text-[10px] font-black uppercase tracking-[.12em] text-slate-200">
                  <span>{position.planLabel} · {formatApr(position.aprPercent)}</span>
                  <span className="text-amber-200">{formatMyth(position.amount)} MYTH</span>
                </div>
                <div className="mt-1 flex items-center justify-between gap-2">
                  <span className="text-[9px] uppercase tracking-[.12em] text-slate-400">
                    {position.unlocked ? `Rewards ${formatMyth(position.claimable)} MYTH` : `Locked until ${formatUnlockDate(position.unlockAt)}`}
                  </span>
                  <button
                    type="button"
                    disabled={busy || !position.unlocked}
                    onClick={() => run.mutate({ kind: 'unstake', positionId: position.id })}
                    className="rounded-lg border border-white/20 bg-black/60 px-2 py-1 text-[9px] font-black uppercase tracking-[.12em] text-slate-200 disabled:opacity-40"
                  >
                    Unstake
                  </button>
                </div>
              </div>
            ))}
          </div>
        ) : null}

        {feedback ? <p className="mt-3 text-center text-[10px] font-bold text-amber-200">{feedback}</p> : null}
        <p className="mt-3 text-center text-[8px] uppercase tracking-[.16em] text-slate-500">
          Internal MYTH staking · MYTH → MYTH · No new supply
        </p>
      </div>
    </div>
  );
}

const Stat = ({ label, value }: { label: string; value: string }) => (
  <div className="rounded-xl border border-white/10 bg-black/50 p-2">
    <p className="text-[8px] uppercase tracking-[.14em] text-slate-400">{label}</p>
    <p className="text-xs font-black text-white">{value}</p>
  </div>
);
