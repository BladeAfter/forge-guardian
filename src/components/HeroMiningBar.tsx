import { useEffect, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Pickaxe } from 'lucide-react';
import { claimHeroMining } from '../services';
import { formatMiningTon, miningActive, projectUnclaimed, type HeroMiningState } from '../heroMining';
import { useT } from '../LanguageContext';

/**
 * Compact TON mining summary for the HEROES screen.
 * The rate and the claimable amount come from the server; the local ticker is
 * only a visual projection between refetches.
 */
export function HeroMiningBar({ telegramInitData, state }: { telegramInitData: string; state: HeroMiningState | undefined }) {
  const t = useT();
  const client = useQueryClient();
  const [tick, setTick] = useState(() => Date.now());
  const [feedback, setFeedback] = useState<string | null>(null);

  useEffect(() => {
    if (!state?.enabled || !state.dailyRateTon || !miningActive(state)) return;
    const timer = window.setInterval(() => setTick(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [state?.enabled, state?.dailyRateTon, state?.remainingTon, state?.investedTon]);

  const claim = useMutation({
    mutationFn: () => claimHeroMining(telegramInitData),
    onSuccess: (result) => {
      setFeedback(t('mining.claimed', { amount: formatMiningTon(result.claimedTon) }));
      client.setQueryData(['hero-mining', telegramInitData], result);
      void client.invalidateQueries({ queryKey: ['ton-wallet'] });
      void client.invalidateQueries({ queryKey: ['wallet-summary'] });
    },
    onError: (error) => setFeedback(error instanceof Error ? error.message : t('mining.error')),
  });

  useEffect(() => {
    if (!feedback) return;
    const timer = window.setTimeout(() => setFeedback(null), 3500);
    return () => window.clearTimeout(timer);
  }, [feedback]);

  if (!state) return null;
  const unclaimed = projectUnclaimed(state, tick);
  const active = miningActive(state);
  const claimable = Math.min(unclaimed, Math.max(0, state.investedTon - state.returnedTon));
  const canClaim = state.enabled && state.investedTon > 0 && claimable >= Math.max(state.minClaimTon, 0.000001) && !claim.isPending;

  return (
    <section className="mt-2 rounded-2xl border border-cyan-300/25 bg-cyan-300/5 p-2.5">
      <div className="flex items-center justify-between gap-2">
        <p className="flex min-w-0 items-center gap-1.5 truncate text-[10px] font-black uppercase tracking-[.14em] text-cyan-200">
          <Pickaxe size={12} /> {t('mining.title')}
        </p>
        <p className="shrink-0 text-[8px] uppercase tracking-[.12em] text-slate-400">{t('mining.eligible', { count: state.eligibleHeroes })}</p>
      </div>

      <div className="mt-2 grid grid-cols-2 gap-2">
        <div className="rounded-xl border border-white/10 bg-black/50 px-2 py-1.5 text-center">
          <p className="text-[8px] uppercase tracking-[.14em] text-slate-400">{t('mining.totalRate')}</p>
          <p className="text-[12px] font-black text-white">{formatMiningTon(state.dailyRateTon)}</p>
          <p className="text-[8px] text-slate-400">{t('mining.perDay')}</p>
        </div>
        <div className="rounded-xl border border-cyan-300/30 bg-black/50 px-2 py-1.5 text-center">
          <p className="text-[8px] uppercase tracking-[.14em] text-slate-400">{t('mining.unclaimed')}</p>
          <p className="text-[12px] font-black text-cyan-200">{formatMiningTon(unclaimed, 6)}</p>
          <p className="text-[8px] text-slate-400">TON</p>
        </div>
      </div>

      <div className="mt-2 grid grid-cols-3 gap-1.5">
        <div className="rounded-xl border border-white/10 bg-black/40 px-1.5 py-1 text-center">
          <p className="text-[7px] uppercase tracking-[.12em] text-slate-400">{t('mining.investment')}</p>
          <p className="text-[10px] font-black text-white">{formatMiningTon(state.investedTon, 3)}</p>
        </div>
        <div className="rounded-xl border border-white/10 bg-black/40 px-1.5 py-1 text-center">
          <p className="text-[7px] uppercase tracking-[.12em] text-slate-400">{t('mining.returned')}</p>
          <p className="text-[10px] font-black text-white">{formatMiningTon(state.returnedTon, 3)}</p>
        </div>
        <div className={`rounded-xl border px-1.5 py-1 text-center ${state.remainingTon > 0 ? 'border-emerald-300/30 bg-emerald-400/5' : 'border-amber-300/30 bg-amber-400/5'}`}>
          <p className="text-[7px] uppercase tracking-[.12em] text-slate-400">{t('mining.remaining')}</p>
          <p className={`text-[10px] font-black ${state.remainingTon > 0 ? 'text-emerald-200' : 'text-amber-300'}`}>{formatMiningTon(state.remainingTon, 3)}</p>
        </div>
      </div>

      <button
        onClick={() => { if (canClaim) claim.mutate(); }}
        disabled={!canClaim}
        className={`mt-2 flex min-h-[36px] w-full items-center justify-center rounded-xl border text-[10px] font-black uppercase tracking-[.14em] transition-colors ${canClaim ? 'border-cyan-300/50 bg-cyan-300/15 text-cyan-100' : 'border-white/10 bg-black/40 text-slate-500'}`}
      >
        {claim.isPending ? t('mining.claiming') : t('mining.claimAll')}
      </button>

      {state.investedTon <= 0 ? (
        <p className="mt-1.5 text-center text-[8px] font-black uppercase tracking-[.1em] text-amber-300">{t('mining.noInvestment')}</p>
      ) : !active ? (
        <>
          <p className="mt-1.5 text-center text-[8px] font-black uppercase tracking-[.12em] text-amber-300">{t('mining.roiReached')}</p>
          <p className="mt-0.5 text-center text-[8px] text-slate-400">{t('mining.reactivate')}</p>
        </>
      ) : null}
      {!state.enabled ? <p className="mt-1.5 text-center text-[8px] font-black uppercase tracking-[.1em] text-amber-300">{t('mining.paused')}</p> : null}
      {state.minClaimTon > 0 ? <p className="mt-1 text-center text-[8px] text-slate-400">{t('mining.min', { amount: formatMiningTon(state.minClaimTon, 6) })}</p> : null}
      {state.lifetimeTon > 0 ? <p className="mt-1 text-center text-[8px] text-slate-400">{t('mining.lifetime', { amount: formatMiningTon(state.lifetimeTon, 6) })}</p> : null}
      {feedback ? <p className="mt-1 text-center text-[9px] font-black text-cyan-200">{feedback}</p> : null}
    </section>
  );
}
