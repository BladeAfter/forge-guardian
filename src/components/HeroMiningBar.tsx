import { useEffect, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Lock, Pickaxe, Sparkles } from 'lucide-react';
import { claimHeroMining } from '../services';
import { miningActive, miningStateRate, projectUnclaimed, type HeroMiningState } from '../heroMining';
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
      if (result.currency !== 'myth') setFeedback(t('mining.claimed', { amount: `${formatMiningAmount(result.claimedTon, 'ton')} TON` }));
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
   * PREMIUM GATE (server decided): mining stays locked unless the player owns the
   * legacy 5 TON pass, the 20 TON pass, an NFT hero/pet, or deposited more than
   * 30 TON. When locked we show ONLY this premium card — never rates, unclaimed
   * amounts, claim button or mining counters.
   */
  if (state.accessLocked || state.miningAccess === 'LOCKED_PASS_REQUIRED') {
    const price = Number(state.passGate?.priceTon ?? 20);
    const goToPass = () => { window.location.href = '/season-pass'; };
    return (
      <section className="relative mt-2 overflow-hidden rounded-2xl border border-amber-300/45 bg-gradient-to-br from-[#0b0a08] via-[#141008] to-[#1c1206] p-3.5 shadow-[0_0_30px_-10px_rgba(251,191,36,.45)]">
        <span aria-hidden className="pointer-events-none absolute -left-10 -top-12 h-32 w-32 rounded-full bg-amber-400/15 blur-3xl" />
        <span aria-hidden className="pointer-events-none absolute -right-8 bottom-0 h-28 w-28 rounded-full bg-amber-200/10 blur-3xl" />

        <div className="relative flex items-start justify-between gap-2">
          <div className="min-w-0">
            <p className="flex items-center gap-1.5 truncate text-[11px] font-black uppercase tracking-[.18em] text-amber-100">
              <Pickaxe size={13} className="text-amber-300" /> {t('mining.locked.title')}
            </p>
            <p className="mt-0.5 text-[8px] font-black uppercase tracking-[.22em] text-amber-300/80">{t('mining.locked.subtitle')}</p>
          </div>
          <span className="flex shrink-0 items-center gap-1 rounded-full border border-amber-300/50 bg-gradient-to-b from-amber-300/20 to-amber-500/10 px-2 py-0.5 text-[8px] font-black uppercase tracking-[.14em] text-amber-100">
            <Lock size={9} /> {t('mining.locked.badge')}
          </span>
        </div>

        <div className="relative mt-3 rounded-xl border border-amber-300/25 bg-black/50 px-3 py-2.5">
          <p className="text-center text-[11px] font-bold leading-snug text-amber-50">{t('mining.locked.desc')}</p>
          
        </div>

        <button
          onClick={goToPass}
          className="relative mt-3 flex min-h-[42px] w-full items-center justify-center gap-1.5 rounded-xl border border-amber-200/70 bg-gradient-to-r from-amber-400 via-amber-300 to-yellow-500 text-[11px] font-black uppercase tracking-[.16em] text-[#1a1204] shadow-[0_6px_20px_-8px_rgba(251,191,36,.9)]"
        >
          <Sparkles size={13} /> {t('mining.locked.cta', { price: String(price) })}
        </button>
        <button
          onClick={goToPass}
          className="relative mt-1.5 w-full text-center text-[9px] font-black uppercase tracking-[.2em] text-amber-300/85 underline decoration-amber-300/40 underline-offset-4"
        >
          {t('mining.locked.alt')}
        </button>
      </section>
    );
  }


  /**
   * Visibility gate: the mining card only exists for players that actually own a
   * yielding NFT (hero, pet or equipment). Ownership is proven by the server-side
   * rate (TON or MYTH), by a pending accrual, or by past mining payouts.
   * Never gate this on invested TON again — buying TON does not unlock mining.
   */
  const unlocked = Number(state.dailyRateTon || 0) > 0

    || Number(state.unclaimedTon || 0) > 0

    || Number(state.lifetimeTon || 0) > 0
;
  if (!unlocked) return null;


  // Mining is per-NFT: sold units keep TON, units with a MYTH rate mine MYTH.
  const tonRate = miningStateRate(state);
  const unclaimedTon = projectUnclaimed(state, tick);
  const active = miningActive(state);
  const minTon = Math.max(Number(state.minClaimTon ?? 0), 0.000001);
  const claimableTon = Math.min(unclaimedTon, Math.max(0, state.investedTon - state.returnedTon));
  const canClaim = state.enabled && !claim.isPending
    && (state.investedTon > 0 && claimableTon >= minTon && state.miningCurrency !== 'myth');

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
          <p className="text-[8px] text-slate-400">{t('mining.perDay')}</p>
        </div>
        <div className="rounded-xl border border-cyan-300/30 bg-black/50 px-2 py-1.5 text-center">
          <p className="text-[8px] uppercase tracking-[.14em] text-slate-400">{t('mining.unclaimed')}</p>
          <p className="text-[12px] font-black text-cyan-200">{formatMiningAmount(unclaimedTon, 'ton', 6)} <span className="text-[8px] text-slate-400">{miningSymbol('ton')}</span></p>
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

      {feedback ? <p className="mt-1 text-center text-[9px] font-black text-cyan-200">{feedback}</p> : null}
    </section>
  );
}
