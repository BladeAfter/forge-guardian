import { useEffect, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Pickaxe } from 'lucide-react';
import { claimHeroMining } from '../services';
import { miningActive, miningStateCurrency, miningStateRate, projectUnclaimed, type HeroMiningState } from '../heroMining';
import { formatMiningAmount, miningSymbol } from '../miningCurrency';
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
    if (!state?.enabled || !miningStateRate(state) || !miningActive(state)) return;
    const timer = window.setInterval(() => setTick(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [state?.enabled, state?.dailyRate, state?.dailyRateTon, state?.miningCurrency, state?.remainingTon, state?.investedTon]);

  const claim = useMutation({
    mutationFn: () => claimHeroMining(telegramInitData),
    onSuccess: (result) => {
      const paid = result.currency === 'myth' ? Number(result.claimedMyth ?? 0) : Number(result.claimedTon ?? 0);
      setFeedback(t('mining.claimed', { amount: `${formatMiningAmount(paid, result.currency === 'myth' ? 'myth' : 'ton')} ${miningSymbol(result.currency === 'myth' ? 'myth' : 'ton')}` }));
      client.setQueryData(['hero-mining', telegramInitData], result);
      void client.invalidateQueries({ queryKey: ['ton-wallet'] });
      void client.invalidateQueries({ queryKey: ['wallet-summary'] });
      void client.invalidateQueries({ queryKey: ['myth-token'] });
    },
    onError: (error) => setFeedback(error instanceof Error ? error.message : t('mining.error')),
  });

  useEffect(() => {
    if (!feedback) return;
    const timer = window.setTimeout(() => setFeedback(null), 3500);
    return () => window.clearTimeout(timer);
  }, [feedback]);

  if (!state) return null;
  /**
   * Visibility gate: the mining card is only shown to players who really put 5 TON or more
   * into the game (deposits + TON purchases), or to legacy players that already mined TON.
   * Everyone else does not see the panel at all.
   */
  const MINING_CARD_MIN_TON = 5;
  const unlocked = Number(state.investedTon || 0) >= MINING_CARD_MIN_TON
    || Number(state.lifetimeTon || 0) > 0 || Number(state.lifetimeMyth || 0) > 0;
  if (!unlocked) return null;
  // Mining is per-NFT: sold units keep TON, units with a MYTH rate mine MYTH.
  const tonRate = miningStateRate(state);
  const mythRate = miningStateMythRate(state);
  const unclaimedTon = projectUnclaimed(state, tick);
  const unclaimedMyth = projectUnclaimedMyth(state, tick);
  const active = miningActive(state);
  const minTon = Math.max(Number(state.minClaimTon ?? 0), 0.000001);
  const minMyth = Math.max(Number(state.minClaimMyth ?? 0), 0.000001);
  const claimableTon = Math.min(unclaimedTon, Math.max(0, state.investedTon - state.returnedTon));
  const claimableMyth = Math.min(unclaimedMyth, Math.max(0, Number(state.mythPoolAvailable ?? 0)));
  const canClaim = state.enabled && !claim.isPending
    && ((state.investedTon > 0 && claimableTon >= minTon) || claimableMyth >= minMyth);

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
          <p className="text-[12px] font-black text-white">{formatMiningAmount(tonRate, 'ton')} <span className="text-[8px] text-slate-400">{miningSymbol('ton')}</span></p>
          {mythRate > 0 ? <p className="text-[12px] font-black text-amber-200">{formatMiningAmount(mythRate, 'myth')} <span className="text-[8px] text-amber-200/70">{miningSymbol('myth')}</span></p> : null}
          <p className="text-[8px] text-slate-400">{t('mining.perDay')}</p>
        </div>
        <div className="rounded-xl border border-cyan-300/30 bg-black/50 px-2 py-1.5 text-center">
          <p className="text-[8px] uppercase tracking-[.14em] text-slate-400">{t('mining.unclaimed')}</p>
          <p className="text-[12px] font-black text-cyan-200">{formatMiningAmount(unclaimedTon, 'ton', 6)} <span className="text-[8px] text-slate-400">{miningSymbol('ton')}</span></p>
          {mythRate > 0 || unclaimedMyth > 0 ? <p className="text-[12px] font-black text-amber-200">{formatMiningAmount(unclaimedMyth, 'myth', 6)} <span className="text-[8px] text-amber-200/70">{miningSymbol('myth')}</span></p> : null}
        </div>
      </div>

      {/*
        The ROI rule stays fully enforced server-side (eligible invested TON, returned TON and
        remaining capacity). Those values are intentionally NOT rendered for players — only the
        admin panel exposes them. Never re-add invested/returned/remaining cards or an ROI bar.
      */}

      <button
        onClick={() => { if (canClaim) claim.mutate(); }}
        disabled={!canClaim}
        className={`mt-2 flex min-h-[36px] w-full items-center justify-center rounded-xl border text-[10px] font-black uppercase tracking-[.14em] transition-colors ${canClaim ? 'border-cyan-300/50 bg-cyan-300/15 text-cyan-100' : 'border-white/10 bg-black/40 text-slate-500'}`}
      >
        {claim.isPending ? t('mining.claiming') : t('mining.claimAll')}
      </button>

      {/* Discreet status only: no amounts, no explanation of the internal cap. */}
      {!state.enabled || !active ? (
        <p className="mt-1.5 text-center text-[8px] font-black uppercase tracking-[.12em] text-amber-300">{t('mining.inactive')}</p>
      ) : null}
      <p className="mt-1 text-center text-[8px] text-slate-400">{t('mining.min')}</p>
      {Number(state.lifetimeTon ?? 0) > 0
        ? <p className="mt-1 text-center text-[8px] text-slate-400">{t('mining.lifetime', { amount: `${formatMiningAmount(state.lifetimeTon, 'ton', 6)} ${miningSymbol('ton')}` })}</p>
        : null}
      {Number(state.lifetimeMyth ?? 0) > 0
        ? <p className="mt-1 text-center text-[8px] text-slate-400">{t('mining.lifetime', { amount: `${formatMiningAmount(state.lifetimeMyth, 'myth', 6)} ${miningSymbol('myth')}` })}</p>
        : null}

      {feedback ? <p className="mt-1 text-center text-[9px] font-black text-cyan-200">{feedback}</p> : null}
    </section>
  );
}
