import { useEffect, useMemo, useState } from 'react';
import { Coins, Crown, Flame, Gift, ListOrdered, Trophy, Users, X } from 'lucide-react';
import { useT } from '../LanguageContext';
import { useSpendingEvent } from '../hooks';
import { abbreviatePoints, countdownLabel, fullPoints, rankMedal, rankTone, spendingCountdown } from '../spendingEvent';
import { formatTon } from '../economy';

/**
 * SPENDING EVENT panel (third tab of the Community Pool screen).
 *
 * Fully independent from the Weekly Pool and the Referral Event: it only renders
 * what `get_spending_event_dashboard` returns. Every number (points, position,
 * totals, estimated reward) is backend-computed from confirmed spends.
 */
export function SpendingEventPanel({ telegramInitData }: { telegramInitData: string }) {
  const t = useT();
  const [full, setFull] = useState(false);
  const [rewards, setRewards] = useState(false);
  const [tick, setTick] = useState(0);
  const { data, isLoading, error, refetch } = useSpendingEvent(telegramInitData, true, full ? 100 : 20);

  useEffect(() => {
    const timer = window.setInterval(() => setTick((value) => value + 1), 30_000);
    return () => window.clearInterval(timer);
  }, []);

  const countdown = useMemo(
    () => spendingCountdown(data?.event?.endsAt, Date.now() + tick * 0),
    [data?.event?.endsAt, tick],
  );

  if (isLoading) {
    return (
      <div className="space-y-3">
        {[1, 2, 3].map((row) => (
          <div key={row} className="h-24 animate-pulse rounded-3xl bg-white/5" />
        ))}
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="py-20 text-center">
        <p className="text-sm text-rose-300">{t('spending.loadError')}</p>
        <button onClick={() => void refetch()} className="mt-4 rounded-xl border border-amber-300/30 px-5 py-3 text-xs font-black">
          {t('spending.retry')}
        </button>
      </div>
    );
  }

  if (!data.event) {
    return (
      <div className="rounded-3xl border border-white/10 bg-black/50 p-8 text-center">
        <Flame className="mx-auto h-10 w-10 text-amber-300/70" />
        <p className="mt-3 text-xs text-slate-300">{t('spending.noEvent')}</p>
      </div>
    );
  }

  const { event, player, totals } = data;
  const finished = event.status === 'finished';

  return (
    <div className="space-y-3">
      <section className="relative overflow-hidden rounded-[1.75rem] border border-amber-300/35 bg-gradient-to-br from-[#141024] via-[#0b1120] to-black p-4 shadow-[0_0_35px_rgba(245,158,11,.12)]">
        <div className="flex items-center gap-2">
          <Flame className="h-5 w-5 text-amber-300" />
          <div className="leading-tight">
            <p className="text-[11px] font-black uppercase tracking-[.22em] text-amber-200">{t('spending.title')}</p>
            <p className="text-[8px] font-bold uppercase tracking-[.3em] text-amber-300/60">{t('spending.subtitle')}</p>
          </div>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-2">
          <Cell label={t('spending.yourSpent')} value={`${abbreviatePoints(player.points)} ${t('spending.points')}`} icon={<Coins className="h-4 w-4" />} />
          <Cell label={t('spending.yourRank')} value={player.position ? `#${player.position}` : '--'} icon={<Trophy className="h-4 w-4" />} />
          <Cell label={t('spending.totalSpent')} value={`${abbreviatePoints(totals.points)} ${t('spending.points')}`} icon={<Flame className="h-4 w-4" />} />
          <Cell label={t('spending.participants')} value={fullPoints(totals.participants)} icon={<Users className="h-4 w-4" />} />
        </div>
        <div className="mt-2 flex items-center justify-between rounded-2xl bg-black/50 px-3 py-2">
          <span className="text-[9px] font-bold uppercase tracking-[.22em] text-slate-400">
            {finished ? t('spending.finished') : t('spending.endsIn')}
          </span>
          <b className="text-sm text-amber-200">{finished ? '—' : countdownLabel(countdown)}</b>
        </div>
        <p className="mt-2 text-[8px] uppercase tracking-[.16em] text-slate-500">
          {t('spending.rateInfo', { rate: fullPoints(event.tonRateFc) })}
        </p>
      </section>

      <section className="rounded-2xl border border-white/10 bg-black/55 p-3">
        <p className="text-[9px] font-black uppercase tracking-[.22em] text-amber-200">{t('spending.yourSpending')}</p>
        <div className="mt-2 grid grid-cols-3 gap-2 text-center">
          <Mini label={t('spending.fcSpent')} value={`${fullPoints(player.fcSpent)} FC`} />
          <Mini label={t('spending.tonSpent')} value={`${formatTon(player.tonSpent)} TON`} />
          <Mini label={t('spending.score')} value={`${fullPoints(player.points)} ${t('spending.points')}`} good />
        </div>
      </section>

      <section className="rounded-2xl border border-amber-300/25 bg-gradient-to-r from-amber-950/40 to-black/60 p-3">
        <p className="text-[9px] font-black uppercase tracking-[.22em] text-amber-200">{t('spending.yourPosition')}</p>
        <div className="mt-1 flex items-center justify-between">
          <b className="text-lg text-white">{player.position ? `#${player.position}` : t('spending.notRanked')}</b>
          <b className="text-xs text-amber-200">{abbreviatePoints(player.points)} {t('spending.points')}</b>
        </div>
        {player.nextRank ? (
          <p className="mt-1 text-[10px] text-cyan-300">
            +{abbreviatePoints(player.neededToNext)} → #{player.nextRank}
          </p>
        ) : null}
        <p className="mt-1 text-[10px] text-slate-300">
          <span className="font-black text-amber-300">{t('spending.estReward')}:</span> {player.estimatedReward ?? '—'}
        </p>
        {!finished ? <p className="mt-1 text-[8px] text-slate-500">{t('spending.estimateOnly')}</p> : null}
      </section>

      <div>
        <p className="mb-2 text-[10px] font-black uppercase tracking-[.22em] text-amber-200">{t('spending.liveRanking')}</p>
        <div className="space-y-1.5">
          {data.ranking.map((row) => (
            <div
              key={row.userId}
              className={`grid grid-cols-[42px_1fr_auto] items-center gap-2 rounded-xl border px-2 py-2 ${rankTone(row.position)}`}
            >
              <b className="text-[11px] text-amber-200">{rankMedal(row.position)}#{row.position}</b>
              <div className="min-w-0">
                <b className="block truncate text-[11px] text-white">{row.username ? `@${row.username}` : row.name}</b>
                <p className="truncate text-[8px] text-slate-400">{row.estimatedReward ?? '—'}</p>
              </div>
              <b className="text-[11px] text-cyan-200">{abbreviatePoints(row.points)}</b>
            </div>
          ))}
          {!data.ranking.length ? (
            <p className="rounded-xl border border-white/10 bg-black/50 p-4 text-center text-[10px] text-slate-400">
              {t('spending.notRanked')}
            </p>
          ) : null}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2 pb-8">
        <button onClick={() => setRewards(true)} className="rounded-xl border border-amber-300/30 bg-amber-950/25 py-3 text-[10px] font-black uppercase tracking-[.14em]">
          <Gift className="mr-1 inline h-3.5 w-3.5" />{t('spending.viewRewards')}
        </button>
        <button onClick={() => setFull((value) => !value)} className="rounded-xl border border-white/15 bg-black/50 py-3 text-[10px] font-black uppercase tracking-[.14em]">
          <ListOrdered className="mr-1 inline h-3.5 w-3.5" />{t('spending.viewFullRanking')}
        </button>
      </div>

      {rewards ? (
        <div className="fixed inset-0 z-[120] grid place-items-center bg-black/85 p-4" onClick={() => setRewards(false)}>
          <div className="max-h-[80vh] w-full max-w-sm overflow-y-auto rounded-3xl border border-amber-300/35 bg-[#09111f] p-4" onClick={(e) => e.stopPropagation()}>
            <div className="mb-3 flex items-center justify-between">
              <b className="text-xs font-black uppercase tracking-[.2em] text-amber-200">
                <Crown className="mr-1 inline h-4 w-4" />{t('spending.rewardsTitle')}
              </b>
              <button onClick={() => setRewards(false)} className="text-slate-400"><X className="h-4 w-4" /></button>
            </div>
            <div className="space-y-1.5">
              {data.rewards.map((slot) => (
                <div key={`${slot.from}-${slot.to}`} className="rounded-xl border border-white/10 bg-black/50 px-3 py-2">
                  <b className="text-[10px] text-amber-300">{slot.from === slot.to ? `#${slot.from}` : `#${slot.from}–#${slot.to}`}</b>
                  <p className="text-[10px] text-slate-300">{slot.label}</p>
                </div>
              ))}
            </div>
            <button onClick={() => setRewards(false)} className="mt-4 w-full rounded-xl bg-amber-400 py-3 text-xs font-black text-black">
              {t('spending.close')}
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function Cell({ label, value, icon }: { label: string; value: string; icon: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-white/10 bg-black/50 p-2.5">
      <span className="float-right text-amber-300">{icon}</span>
      <p className="text-[8px] uppercase tracking-[.16em] text-slate-400">{label}</p>
      <b className="text-sm text-white">{value}</b>
    </div>
  );
}

function Mini({ label, value, good }: { label: string; value: string; good?: boolean }) {
  return (
    <div>
      <p className="text-[8px] uppercase tracking-[.14em] text-slate-500">{label}</p>
      <b className={`text-[11px] ${good ? 'text-emerald-300' : 'text-white'}`}>{value}</b>
    </div>
  );
}
