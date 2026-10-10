import { useLocalizedText } from '../LanguageContext';
import { useMemo } from 'react';
import { CheckCircle2, Gift, Lock, Sparkles, Star } from 'lucide-react';
import { useMythSale } from '../hooks';
import { abbreviateMyth, mythFull } from '../mythSale';
import { MYTH_SALE_MILESTONES, mythBoughtTotal, mythMilestoneProgress, nextMythMilestone } from '../mythSaleMilestones';

/**
 * Chest / reward ladder rendered under the MYTH SALE panel. Read-only: rewards are
 * delivered by the backend, and nothing here touches the SPENDING EVENT ranking.
 */
export function MythSaleMilestones({ telegramInitData }: { telegramInitData: string }) {
  const localizeText = useLocalizedText();

  const { data } = useMythSale(telegramInitData, true);
  // O servidor consolida compras diretas + MYTH dos pacotes premium (35 / 100 TON).
  const bought = useMemo(
    () => Number(data?.player?.mythPurchasedTotal ?? NaN) || mythBoughtTotal(data?.purchases ?? []),
    [data?.player?.mythPurchasedTotal, data?.purchases],
  );
  const next = nextMythMilestone(bought);
  const progress = mythMilestoneProgress(bought);
  const unlocked = MYTH_SALE_MILESTONES.filter(m => bought >= m.amount).length;

  return (
    <section className="mt-6 space-y-3 pb-10">
      <div className="rounded-3xl border border-amber-300/35 bg-gradient-to-br from-[#241703] via-[#0a1020] to-black p-4">
        <h3 className="flex items-center gap-2 text-[11px] font-black uppercase tracking-[.28em] text-amber-200">
          <Gift className="h-4 w-4" />{localizeText("Milestone Rewards")}</h3>
        <p className="mt-1 text-[10px] text-slate-400">
          {unlocked}/{MYTH_SALE_MILESTONES.length} {localizeText("unlocked ·")}{mythFull(bought)} {localizeText("MYTH purchased")}</p>
        <div className="mt-3 h-2 overflow-hidden rounded-full bg-white/10">
          <div className="h-full rounded-full bg-gradient-to-r from-amber-400 to-yellow-200" style={{ width: `${progress}%` }} />
        </div>
        {next && (
          <p className="mt-2 text-[10px] text-amber-200/80">
            <Sparkles className="mr-1 inline h-3 w-3" />{localizeText("Next: buy")}{abbreviateMyth(next.amount)} MYTH
          </p>
        )}
      </div>

      {MYTH_SALE_MILESTONES.map((milestone, index) => {
        const done = bought >= milestone.amount;
        const isNext = next?.amount === milestone.amount;
        return (
          <div
            key={milestone.amount}
            className={`rounded-3xl border p-4 ${done ? 'border-emerald-400/40 bg-emerald-950/20' : isNext ? 'border-amber-300/50 bg-amber-950/15' : 'border-white/10 bg-black/50'}`}
          >
            <div className="flex items-start gap-3">
              <div className={`grid h-11 w-11 shrink-0 place-items-center rounded-2xl border ${done ? 'border-emerald-400/50 bg-emerald-500/10' : isNext ? 'border-amber-300/50 bg-amber-400/10' : 'border-white/10 bg-white/5'}`}>
                {done ? <CheckCircle2 className="h-5 w-5 text-emerald-300" /> : isNext ? <Star className="h-5 w-5 text-amber-300" /> : <Lock className="h-5 w-5 text-slate-500" />}
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-[9px] font-black uppercase tracking-[.3em] text-slate-400">{localizeText("Milestone")}{index + 1}</p>
                <b className="block text-lg font-black text-white">{localizeText("BUY")}{mythFull(milestone.amount)} MYTH</b>
                <ul className="mt-2 space-y-1">
                  {milestone.rewards.map(reward => (
                    <li key={reward} className="flex items-center gap-2 text-[11px] text-slate-300">
                      <Sparkles className="h-3 w-3 text-amber-300" />{reward}
                    </li>
                  ))}
                </ul>
              </div>
              <span className={`text-[9px] font-black uppercase tracking-[.22em] ${done ? 'text-emerald-300' : 'text-slate-500'}`}>
                {done ? localizeText("Unlocked") : localizeText("Locked")}
              </span>
            </div>
          </div>
        );
      })}
    </section>
  );
}
