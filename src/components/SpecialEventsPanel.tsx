import { useEffect, useMemo, useState } from 'react';
import { Flame, Gift, Info, RefreshCw, Sparkles, Trophy, UserPlus, Users } from 'lucide-react';
import championshipTrophy from '../assets/referral-championship-trophy.png';
import { useSpecialEvents } from '../hooks';
import { describeDistribution, eventCountdown, formatEventTon } from '../specialEvents';
import { useT, useLanguage } from '../LanguageContext';

/**
 * EVENTS tab of the Community Pool. Fully independent from the weekly pool:
 * separate prize pool, separate ranking, separate distribution. Every number
 * comes from `get_special_events_dashboard` — the client never counts invites.
 */
export function SpecialEventsPanel({ telegramInitData, onInvite }: { telegramInitData: string; onInvite: () => void }) {
  const t = useT();
  useLanguage();
  const { data, isLoading, error, refetch } = useSpecialEvents(telegramInitData, true);
  const [tick, setTick] = useState(Date.now());
  const [showRules, setShowRules] = useState(false);
  const [showRanking, setShowRanking] = useState(true);

  useEffect(() => {
    const id = window.setInterval(() => setTick(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);

  const event = data?.event ?? null;
  const countdown = useMemo(() => eventCountdown(event?.endsAt, tick), [event?.endsAt, tick]);
  const prizeTable = useMemo(() => describeDistribution(event), [event]);

  if (isLoading) {
    return <div className="space-y-3">{[1, 2, 3].map((x) => <div key={x} className="h-28 animate-pulse rounded-3xl bg-white/5" />)}</div>;
  }

  if (error) {
    return (
      <div className="rounded-3xl border border-rose-400/30 bg-rose-950/25 p-6 text-center">
        <p className="text-sm text-rose-200">{t('events.loadError')}</p>
        <button onClick={() => void refetch()} className="mt-4 inline-flex items-center gap-2 rounded-xl border border-amber-300/40 px-4 py-2 text-xs font-black text-amber-200">
          <RefreshCw className="h-4 w-4" />{t('events.retry')}
        </button>
      </div>
    );
  }

  if (!event) {
    return (
      <div className="relative overflow-hidden rounded-[2rem] border border-violet-300/25 bg-gradient-to-br from-[#1b1338] via-[#0d1326] to-black p-7 text-center">
        <Sparkles className="mx-auto h-12 w-12 text-violet-300/80" />
        <p className="mt-3 text-sm font-black uppercase tracking-[.2em] text-violet-200">{t('events.noEvent')}</p>
        <p className="mt-4 text-[10px] uppercase tracking-[.3em] text-slate-400">{t('events.nextEvent')}</p>
        <b className="mt-1 block text-amber-200">
          {data?.nextEvent ? `${data.nextEvent.name} · ${formatEventTon(data.nextEvent.prizePoolTon)}` : t('events.comingSoon')}
        </b>
        {data?.nextEvent && <p className="mt-1 text-[10px] text-slate-400">{new Date(data.nextEvent.startsAt).toLocaleString()}</p>}
      </div>
    );
  }

  const player = data!.player;

  return (
    <div className="space-y-3">
      {/* ---------------------------------------------------------------- premium event banner */}
      <section className="relative overflow-hidden rounded-[2rem] border border-amber-300/45 bg-gradient-to-br from-[#2a1b4d] via-[#101a33] to-black p-5 text-center shadow-[0_0_55px_rgba(168,85,247,.22)]">
        <div className="pointer-events-none absolute -left-8 -top-8 h-32 w-32 rounded-full bg-amber-400/20 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-10 -right-6 h-32 w-32 rounded-full bg-violet-500/25 blur-3xl" />
        <div className="pointer-events-none absolute inset-0 opacity-40">
          {[12, 34, 56, 78, 90].map((left, index) => (
            <span
              key={left}
              className="absolute block h-1.5 w-1.5 animate-pulse rounded-full bg-amber-300/70"
              style={{ left: `${left}%`, top: `${18 + index * 14}%`, animationDelay: `${index * 260}ms` }}
            />
          ))}
        </div>
        <p className="relative text-[9px] font-bold uppercase tracking-[.35em] text-violet-200">{t('events.activeEvent')}</p>
        <img
          src={championshipTrophy}
          alt={t('events.trophyAlt')}
          width={1024}
          height={1024}
          loading="lazy"
          className="relative mx-auto mt-2 h-[130px] w-[130px] max-w-full object-contain drop-shadow-[0_0_28px_rgba(251,191,36,.35)] sm:h-[160px] sm:w-[160px]"
        />
        <h2 className="relative mt-1 text-2xl font-black uppercase tracking-wide text-amber-100">{event.name}</h2>
        <p className="relative mt-2 text-3xl font-black text-amber-300">{formatEventTon(event.prizePoolTon)}</p>
        <p className="relative text-[9px] font-bold uppercase tracking-[.3em] text-amber-200/80">{t('events.prizePool')}</p>
        <p className="relative mt-3 text-[11px] leading-5 text-slate-300">{t('events.tagline')}</p>

        <div className="relative mt-4 rounded-2xl bg-black/50 p-3">
          <p className="text-[9px] uppercase tracking-[.28em] text-slate-400">{t('events.endsIn')}</p>
          <div className="mt-2 grid grid-cols-3 gap-2">
            {[[countdown.days, t('events.days')], [countdown.hours, t('events.hours')], [countdown.minutes, t('events.minutes')]].map(([value, label]) => (
              <div key={String(label)} className="rounded-xl border border-amber-300/20 bg-black/45 py-2">
                <b className="block text-lg text-amber-200">{String(value).padStart(2, '0')}</b>
                <span className="text-[8px] uppercase tracking-[.2em] text-slate-400">{label}</span>
              </div>
            ))}
          </div>
          {countdown.ended && <p className="mt-2 text-[10px] font-black text-rose-300">{t('events.finished')}</p>}
        </div>

        <div className="relative mt-3 grid grid-cols-2 gap-2">
          <div className="rounded-2xl border border-white/10 bg-black/55 p-3 text-left">
            <Trophy className="float-right h-4 w-4 text-amber-300" />
            <p className="text-[9px] uppercase text-slate-400">{t('events.yourRank')}</p>
            <b className="text-lg text-white">{player.position ? `#${player.position}` : '--'}</b>
          </div>
          <div className="rounded-2xl border border-white/10 bg-black/55 p-3 text-left">
            <UserPlus className="float-right h-4 w-4 text-emerald-300" />
            <p className="text-[9px] uppercase text-slate-400">{t('events.validInvites')}</p>
            <b className="text-lg text-emerald-300">{player.validReferrals.toLocaleString()}</b>
          </div>
        </div>

        <div className="relative mt-3 grid grid-cols-2 gap-2 text-[10px]">
          <div className="rounded-xl bg-black/40 p-2">
            <Users className="mr-1 inline h-3 w-3 text-cyan-300" />{t('events.participants')}: <b>{data!.participantCount.toLocaleString()}</b>
          </div>
          <div className="rounded-xl bg-black/40 p-2">
            <Gift className="mr-1 inline h-3 w-3 text-amber-300" />{t('events.estimatedPrize')}: <b>{formatEventTon(player.estimatedRewardTon)}</b>
          </div>
        </div>

        <div className="relative mt-3 grid grid-cols-2 gap-2">
          <button onClick={() => setShowRanking((v) => !v)} className="rounded-xl border border-amber-300/35 bg-amber-950/25 py-3 text-[11px] font-black text-amber-200">
            <Trophy className="mr-1 inline h-4 w-4" />{t('events.viewRanking')}
          </button>
          <button onClick={onInvite} className="rounded-xl bg-gradient-to-r from-amber-400 to-yellow-200 py-3 text-[11px] font-black text-black">
            <UserPlus className="mr-1 inline h-4 w-4" />{t('events.inviteNow')}
          </button>
        </div>
      </section>

      {/* ---------------------------------------------------------------- your position (sticky card) */}
      <div className="rounded-2xl border border-violet-300/25 bg-gradient-to-r from-violet-950/50 to-black p-3">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-[9px] font-black uppercase tracking-[.28em] text-violet-200">{t('events.yourPosition')}</p>
            <b className="text-xl text-white">{player.position ? `#${player.position}` : t('events.unranked')}</b>
          </div>
          <div className="text-right">
            <p className="text-[9px] uppercase text-slate-400">{t('events.validInvites')}</p>
            <b className="text-lg text-emerald-300">{player.validReferrals.toLocaleString()}</b>
          </div>
        </div>
      </div>

      <button onClick={() => setShowRules(true)} className="w-full rounded-xl border border-white/10 bg-black/50 py-3 text-[11px] font-black text-amber-200">
        <Info className="mr-2 inline h-4 w-4" />{t('events.howItWorks')}
      </button>

      {/* ---------------------------------------------------------------- ranking (top 100) */}
      {showRanking && (
        <section>
          <h3 className="mb-2 mt-4 flex items-center gap-2 text-xs font-black tracking-[.2em] text-amber-200">
            <Trophy className="h-4 w-4" />🏆 {t('events.ranking')}
          </h3>
          {data!.ranking.length === 0 ? (
            <p className="rounded-2xl border border-white/10 bg-black/50 p-4 text-center text-[11px] text-slate-400">{t('events.noParticipants')}</p>
          ) : (
            <div className="space-y-2 pb-6">
              {data!.ranking.map((row) => (
                <div
                  key={row.userId}
                  className={`grid grid-cols-[40px_1fr_auto] items-center rounded-2xl border p-3 ${row.isYou ? 'border-amber-300/60 bg-amber-950/25' : 'border-white/10 bg-black/55'}`}
                >
                  <b className={row.position <= 3 ? 'text-amber-300' : 'text-slate-300'}>
                    {row.position === 1 ? '🥇' : row.position === 2 ? '🥈' : row.position === 3 ? '🥉' : `#${row.position}`}
                  </b>
                  <div className="min-w-0">
                    <b className="block truncate text-xs">{row.username ? `@${row.username}` : row.name}</b>
                    <p className="text-[9px] text-slate-400">{row.validReferrals.toLocaleString()} {t('events.validInvitesShort')}</p>
                  </div>
                  <b className="text-[10px] text-cyan-300">{formatEventTon(row.estimatedRewardTon)}</b>
                </div>
              ))}
            </div>
          )}
        </section>
      )}

      {/* ---------------------------------------------------------------- how it works */}
      {showRules && (
        <div className="fixed inset-0 z-[120] grid place-items-center bg-black/85 p-5" onClick={() => setShowRules(false)}>
          <div className="max-h-[80vh] w-full max-w-sm overflow-y-auto rounded-3xl border border-amber-300/35 bg-[#0a1020] p-5" onClick={(e) => e.stopPropagation()}>
            <h2 className="flex items-center gap-2 text-lg font-black text-amber-200"><Flame className="h-5 w-5" />{t('events.howItWorks')}</h2>
            <ol className="mt-3 space-y-2 text-[12px] leading-5 text-slate-300">
              {[t('events.step1'), t('events.step2'), t('events.step3'), t('events.step4'), t('events.step5')].map((step, index) => (
                <li key={step}><b className="text-amber-300">{index + 1}.</b> {step}</li>
              ))}
            </ol>
            <p className="mt-4 text-[11px] leading-5 text-slate-400">{t('events.validRule', { quests: event.minDailyQuests })}</p>
            <p className="mt-2 text-[11px] leading-5 text-slate-400">{t('events.oldReferralsNote')}</p>
            <p className="mt-2 text-[11px] leading-5 text-slate-400">{t('events.separateNote')}</p>
            <h3 className="mt-4 text-[10px] font-black uppercase tracking-[.2em] text-amber-200">
              {t('events.prizeTable')} · {event.distributionMode === 'proportional' ? t('events.modeProportional') : t('events.modeFixed')}
            </h3>
            <div className="mt-2 space-y-1">
              {prizeTable.map((slice) => (
                <div key={slice.label} className="flex justify-between rounded-lg bg-black/45 px-3 py-1.5 text-[11px]">
                  <span className="text-slate-300">{slice.label}</span><b className="text-amber-200">{slice.value}</b>
                </div>
              ))}
            </div>
            <button onClick={() => setShowRules(false)} className="mt-5 w-full rounded-xl bg-amber-400 py-3 font-black text-black">{t('events.gotIt')}</button>
          </div>
        </div>
      )}
    </div>
  );
}
