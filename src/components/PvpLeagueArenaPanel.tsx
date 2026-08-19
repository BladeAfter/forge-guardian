import { useState } from 'react';
import { BookOpen, Clock3, Shield, Swords, Trophy, Users } from 'lucide-react';
import { useT } from '../LanguageContext';
import { formatTon } from '../economy';
import { leagueCountdown, leagueMedal, type PvpLeagueDashboard } from '../pvpLeague';
import { PlayerTag } from '../premiumTitles';

const ton = (value: number) => `${formatTon(value)} TON`;
/** Estimates are projections: at most 3 decimals, trailing zeros trimmed. */
const estTon = (value: number) => `${formatTon(Math.round((Number(value) || 0) * 1e3) / 1e3)} TON`;

/**
 * Arena Championship screen: takes over the weekly pool slot while the event is ACTIVE.
 * Fully read-only — the event score is written by the PvP engine on the server.
 */
export function PvpLeagueArenaPanel({ data }: { data: PvpLeagueDashboard }) {
  const t = useT();
  const [full, setFull] = useState(false);
  const [rules, setRules] = useState(false);
  const c = leagueCountdown(data.event.endsAt);
  const rows = full ? data.ranking : data.ranking.slice(0, 10);
  const top = data.event.topLimit;

  return (
    <>
      <section className="relative overflow-hidden rounded-[2rem] border border-amber-300/40 bg-gradient-to-br from-[#2a0c12] via-[#0d1526] to-black p-5 text-center shadow-[0_0_45px_rgba(245,158,11,.18)]">
        <div className="pointer-events-none absolute -left-8 -top-8 h-32 w-32 rounded-full bg-rose-500/10 blur-2xl" />
        <div className="pointer-events-none absolute -right-8 bottom-0 h-32 w-32 rounded-full bg-sky-500/10 blur-2xl" />
        <div className="relative mx-auto grid h-16 w-16 place-items-center rounded-2xl border border-amber-300/40 bg-black/50">
          <Swords className="h-9 w-9 text-amber-300" />
        </div>
        <h2 className="relative mt-3 text-2xl font-black tracking-[.06em] text-amber-100">{t('league.title')}</h2>
        <p className="relative mt-1 text-[9px] font-bold uppercase tracking-[.32em] text-rose-200/80">{t('league.subtitle')}</p>
        <p className="relative mt-3 inline-block rounded-full border border-amber-300/40 bg-amber-400/10 px-4 py-1 text-sm font-black text-amber-200">
          {t('league.prizePool', { amount: formatTon(data.event.prizePoolTon) })}
        </p>
        <div className="relative mt-4 rounded-2xl bg-black/50 p-3">
          <Clock3 className="mr-2 inline h-4 w-4 text-amber-300" />
          <span className="text-[10px] font-bold uppercase tracking-[.2em] text-amber-200">{t('league.endsIn')}</span>
          <b className="mt-1 block text-sm">
            {c.ended ? t('league.ended') : t('league.countdown', { days: c.days, hours: c.hours, minutes: c.minutes })}
          </b>
        </div>
      </section>

      <div className="mt-3 grid grid-cols-2 gap-2">
        <Stat label={t('league.yourScore')} value={data.player.score.toLocaleString()} icon={<Swords />} />
        <Stat label={t('league.yourPosition')} value={data.player.position ? `#${data.player.position}` : '--'} icon={<Trophy />} />
        <Stat label={t('league.participants')} value={data.participants.toLocaleString()} icon={<Users />} />
        <Stat
          label={t('league.estReward')}
          value={data.player.inTop ? `~ ${estTon(data.player.estimatedRewardTon)}` : '0 TON'}
          icon={<Trophy />}
          good={data.player.inTop && data.player.estimatedRewardTon > 0}
        />
      </div>

      <div className="mt-3 rounded-2xl border border-amber-300/25 bg-black/55 p-3">
        <p className="text-[10px] font-black uppercase tracking-[.2em] text-amber-200">{t('league.yourPositionCard')}</p>
        <div className="mt-2 flex items-end justify-between">
          <b className="text-3xl font-black text-white">{data.player.position ? `#${data.player.position}` : '--'}</b>
          <div className="text-right">
            <p className="text-[9px] uppercase text-slate-400">{t('league.yourScore')}</p>
            <b className="text-amber-200">{data.player.score.toLocaleString()}</b>
          </div>
        </div>
        <div className="mt-2 flex justify-between text-[10px] text-slate-300">
          <span>
            <Shield className="mr-1 inline h-3 w-3 text-sky-300" />
            {t('league.league')}: <b className="text-sky-200">{data.player.league ?? '--'}</b>
          </span>
          <span>
            {t('league.matches')}: <b>{data.player.matches}</b> · {t('league.wins')}: <b className="text-emerald-300">{data.player.wins}</b>
          </span>
        </div>
        {!data.player.inTop && <p className="mt-2 text-[9px] text-rose-300/90">{t('league.reachTop', { top })}</p>}
      </div>

      <div className="mt-3 rounded-2xl border border-white/10 bg-black/50 p-3">
        <p className="text-[10px] font-black uppercase tracking-[.2em] text-amber-200">{t('league.rewards')}</p>
        <div className="mt-2 grid grid-cols-3 gap-2 text-center">
          {data.tiers.map((tier) => (
            <div key={tier.label} className="rounded-xl border border-amber-300/20 bg-amber-950/20 p-2">
              <p className="text-[9px] uppercase tracking-[.12em] text-amber-200/80">{tier.label}</p>
              <b className="text-xs text-amber-100">{ton(tier.ton)}</b>
            </div>
          ))}
        </div>
      </div>

      <button onClick={() => setRules(true)} className="mt-3 w-full rounded-xl border border-amber-300/30 bg-amber-950/20 py-3 text-xs font-black">
        <BookOpen className="mr-2 inline h-4 w-4" />
        {t('league.howItWorksTitle')}
      </button>

      <h3 className="mb-2 mt-5 text-xs font-black tracking-[.2em] text-amber-200">{t('league.liveRanking')}</h3>
      <div className="space-y-2 pb-8">
        {rows.length === 0 && <p className="rounded-2xl border border-white/10 bg-black/55 p-4 text-center text-[10px] text-slate-400">{t('league.empty')}</p>}
        {rows.map((r) => (
          <div
            key={r.userId}
            className={`grid grid-cols-[44px_1fr_auto] items-center rounded-2xl border p-3 ${r.isYou ? 'border-amber-300/60 bg-amber-500/10' : 'border-white/10 bg-black/55'}`}
          >
            <b className="text-amber-300">{leagueMedal(r.position) || `#${r.position}`}</b>
            <div className="min-w-0">
              <b className="block truncate text-xs"><PlayerTag username={r.username} fallback={r.name}/></b>
              <p className="text-[9px] text-slate-400">
                {r.score.toLocaleString()} {t('league.points')} · {r.wins}W
              </p>
            </div>
            <b className={`text-[10px] ${r.rewardTon > 0 ? 'text-cyan-300' : 'text-slate-500'}`}>{r.rewardTon > 0 ? estTon(r.rewardTon) : '0 TON'}</b>
          </div>
        ))}
        {data.ranking.length > 10 && (
          <button onClick={() => setFull(!full)} className="w-full rounded-xl border border-amber-300/30 py-3 text-[10px] font-black uppercase tracking-[.16em] text-amber-200">
            {full ? t('league.viewLess') : t('league.viewTop', { top })}
          </button>
        )}
      </div>

      {rules && (
        <div className="fixed inset-0 z-[100] grid place-items-center bg-black/85 p-5" onClick={() => setRules(false)}>
          <div className="max-w-sm rounded-3xl border border-amber-300/35 bg-[#09111f] p-5" onClick={(e) => e.stopPropagation()}>
            <h2 className="text-xl font-black text-amber-200">{t('league.howItWorksTitle')}</h2>
            <p className="mt-3 text-sm leading-6 text-slate-300">
              {t('league.howItWorks', { top, amount: formatTon(data.event.prizePoolTon) })}
            </p>
            <button onClick={() => setRules(false)} className="mt-5 w-full rounded-xl bg-amber-400 py-3 font-black text-black">
              {t('league.gotIt')}
            </button>
          </div>
        </div>
      )}
    </>
  );
}

function Stat({ label, value, icon, good }: { label: string; value: string; icon: React.ReactNode; good?: boolean }) {
  return (
    <div className="rounded-2xl border border-white/10 bg-black/55 p-3">
      <span className={`float-right h-5 w-5 ${good ? 'text-emerald-300' : 'text-amber-300'}`}>{icon}</span>
      <p className="text-[9px] uppercase text-slate-400">{label}</p>
      <b className={good ? 'text-emerald-300' : 'text-white'}>{value}</b>
    </div>
  );
}
