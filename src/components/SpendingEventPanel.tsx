import { useEffect, useMemo, useState } from 'react';
import { Coins, Crown, Flame, Gem, Gift, Hourglass, Lock, Rocket, ShieldCheck, Sparkles, Star, Timer, Wallet, CheckCircle2 } from 'lucide-react';
import { useMythSale } from '../hooks';
import { formatTon } from '../economy';
import { abbreviateMyth, mythFull } from '../mythSale';
import { MYTH_EVENT_DAYS, MYTH_EVENT_MILESTONES, mythBoughtInEvent, mythEventCountdown, mythMilestoneProgress, nextMythMilestone } from '../mythEvent';

/**
 * SPENDING EVENT — premium 14-day promotional panel.
 * Supply, sold, burned and TON raised are the live backend numbers (same dashboard as the MYTH sale);
 * only the event window and the milestone table are local constants.
 */
export function SpendingEventPanel({ telegramInitData, onGoToSale, onGoToWallet }: { telegramInitData: string; onGoToSale: () => void; onGoToWallet?: () => void }) {
  const { data, isLoading, error, refetch } = useMythSale(telegramInitData, true);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => { const id = window.setInterval(() => setNow(Date.now()), 1000); return () => window.clearInterval(id); }, []);

  const stats = data?.stats;
  const clock = useMemo(() => mythEventCountdown(now), [now]);
  const bought = useMemo(() => mythBoughtInEvent(data?.purchases ?? [], now), [data?.purchases, now]);
  const next = nextMythMilestone(bought);
  const milestoneProgress = mythMilestoneProgress(bought);
  const unlocked = MYTH_EVENT_MILESTONES.filter(m => bought >= m.amount).length;

  if (isLoading) return <div className="space-y-3 pt-6">{[1, 2, 3].map(x => <div key={x} className="h-28 animate-pulse rounded-3xl bg-white/5" />)}</div>;
  if (error || !data || !stats) return (
    <div className="py-20 text-center">
      <p className="text-rose-300">Unable to load the Spending Event.</p>
      <button onClick={() => void refetch()} className="mt-4 rounded-xl border border-amber-300/30 px-5 py-3 text-xs font-black">RETRY</button>
    </div>
  );

  const internalTon = data.player.internalTon;

  return (
    <div className="pb-12">
      {/* HEADER */}
      <section className="relative overflow-hidden rounded-[2rem] border border-amber-300/50 bg-gradient-to-br from-[#241703] via-[#0a1020] to-black p-5 text-center shadow-[0_0_60px_rgba(245,158,11,.25)]">
        <div className="pointer-events-none absolute -left-10 -top-12 h-40 w-40 rounded-full bg-amber-400/20 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-16 -right-8 h-44 w-44 rounded-full bg-yellow-200/10 blur-3xl" />
        {[8, 26, 48, 66, 84].map((left, i) => (
          <Sparkles key={left} className="pointer-events-none absolute h-3 w-3 animate-pulse text-amber-200/50" style={{ left: `${left}%`, top: `${12 + ((i * 17) % 60)}%`, animationDelay: `${i * 320}ms` }} />
        ))}
        <div className="relative">
          <div className="mx-auto grid h-16 w-16 place-items-center rounded-full border border-amber-300/60 bg-black/60 shadow-[0_0_35px_rgba(245,158,11,.45)]">
            <Coins className="h-9 w-9 animate-pulse text-amber-300" />
          </div>
          <h2 className="mt-3 bg-gradient-to-b from-amber-100 to-amber-400 bg-clip-text text-2xl font-black tracking-[.08em] text-transparent">SPENDING EVENT</h2>
          <p className="mt-1 text-[9px] font-black uppercase tracking-[.34em] text-amber-300">LIMITED {MYTH_EVENT_DAYS}-DAY EVENT</p>
          <p className="mx-auto mt-2 max-w-[16rem] text-[10px] leading-4 text-slate-300">Buy MYTH during the event and unlock exclusive rewards, milestone bonuses and special advantages.</p>
          <div className="mt-4 rounded-2xl border border-amber-300/30 bg-black/60 p-3">
            <p className="text-[8px] font-black uppercase tracking-[.3em] text-amber-300/80"><Timer className="mr-1 inline h-3 w-3" />{clock.ended ? 'EVENT ENDED' : 'ENDS IN'}</p>
            <b className="mt-1 block text-xl font-black tabular-nums text-amber-100">
              {clock.ended ? '--' : `${clock.days}d ${String(clock.hours).padStart(2, '0')}h ${String(clock.minutes).padStart(2, '0')}m ${String(clock.seconds).padStart(2, '0')}s`}
            </b>
          </div>
        </div>
      </section>

      {/* SECTION 1 — EVENT OVERVIEW */}
      <SectionTitle icon={<Gem className="h-3.5 w-3.5" />} title="EVENT OVERVIEW" subtitle="Live supply and event progress." />
      <div className="grid grid-cols-2 gap-2">
        <Cell label="Total supply" value={`${abbreviateMyth(stats.initialSupply)} ${stats.symbol}`} />
        <Cell label="Available" value={`${abbreviateMyth(stats.available)} ${stats.symbol}`} tone="emerald" />
        <Cell label="Sold" value={`${abbreviateMyth(stats.sold)} ${stats.symbol}`} />
        <Cell label="Burned" value={`${abbreviateMyth(stats.burned)} ${stats.symbol}`} tone="rose" />
        <Cell label="TON raised" value={`${formatTon(stats.tonRaised)} TON`} tone="cyan" />
        <Cell label="Price" value={`1 TON = ${abbreviateMyth(stats.mythPerTon)}`} />
      </div>
      <div className="mt-2 rounded-3xl border border-amber-300/30 bg-gradient-to-br from-amber-950/40 to-black p-4">
        <div className="flex items-center justify-between text-[9px] font-black uppercase tracking-[.22em]">
          <span className="text-amber-200/80">Event progress</span>
          <b className="text-amber-100">{clock.progressPercent.toFixed(1)}%</b>
        </div>
        <Bar percent={clock.progressPercent} />
        <div className="mt-3 flex items-center justify-between text-[9px] font-black uppercase tracking-[.22em]">
          <span className="text-amber-200/80">Sold progress</span>
          <b className="text-amber-100">{stats.soldPercent.toFixed(2)}%</b>
        </div>
        <Bar percent={stats.soldPercent} />
      </div>

      {/* SECTION 2 — EVENT REWARDS */}
      <SectionTitle icon={<Gift className="h-3.5 w-3.5" />} title="EVENT REWARDS" subtitle="Unlock bonus rewards as you buy more MYTH." />
      <div className="space-y-2">
        {MYTH_EVENT_MILESTONES.map((m, index) => {
          const done = bought >= m.amount;
          const active = next?.amount === m.amount;
          return (
            <div key={m.amount} className={`relative overflow-hidden rounded-3xl border p-3.5 ${done ? 'border-emerald-300/45 bg-gradient-to-br from-emerald-950/50 to-black' : active ? 'border-amber-300/60 bg-gradient-to-br from-amber-950/50 to-black shadow-[0_0_28px_rgba(245,158,11,.18)]' : 'border-white/10 bg-black/55'}`}>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className={`grid h-9 w-9 place-items-center rounded-xl border ${done ? 'border-emerald-300/50 bg-emerald-500/10' : active ? 'border-amber-300/50 bg-amber-500/10' : 'border-white/10 bg-white/5'}`}>
                    {done ? <CheckCircle2 className="h-4 w-4 text-emerald-300" /> : active ? <Star className="h-4 w-4 text-amber-300" /> : <Lock className="h-4 w-4 text-slate-500" />}
                  </div>
                  <div>
                    <p className="text-[8px] font-black uppercase tracking-[.26em] text-slate-400">Milestone {index + 1}</p>
                    <b className={`text-[13px] font-black ${done ? 'text-emerald-100' : 'text-amber-100'}`}>BUY {mythFull(m.amount)} {stats.symbol}</b>
                  </div>
                </div>
                <b className={`text-[9px] font-black uppercase tracking-[.2em] ${done ? 'text-emerald-300' : active ? 'text-amber-300' : 'text-slate-500'}`}>{done ? 'UNLOCKED' : active ? 'NEXT' : 'LOCKED'}</b>
              </div>
              <ul className="mt-2 space-y-1 pl-1">
                {m.rewards.map(reward => (
                  <li key={reward} className="flex items-center gap-1.5 text-[10px] text-slate-300"><Sparkles className="h-3 w-3 shrink-0 text-amber-300/80" />{reward}</li>
                ))}
              </ul>
            </div>
          );
        })}
      </div>

      {/* SECTION 3 — YOUR EVENT STATUS */}
      <SectionTitle icon={<Crown className="h-3.5 w-3.5" />} title="YOUR EVENT STATUS" subtitle="Tracked from your purchases inside the event window." />
      <div className="rounded-3xl border border-amber-300/35 bg-gradient-to-br from-[#160f04] to-black p-4">
        <div className="grid grid-cols-2 gap-2">
          <Cell label="Your bought" value={`${mythFull(bought)} ${stats.symbol}`} tone="emerald" />
          <Cell label="Your MYTH balance" value={`${mythFull(data.player.mythBalance)} ${stats.symbol}`} />
        </div>
        <div className="mt-3 flex items-center justify-between text-[9px] font-black uppercase tracking-[.22em]">
          <span className="text-amber-200/80">Your progress</span>
          <b className="text-amber-100">{milestoneProgress.toFixed(1)}%</b>
        </div>
        <Bar percent={milestoneProgress} />
        <div className="mt-3 rounded-2xl border border-white/10 bg-black/55 p-3">
          <p className="text-[8px] font-black uppercase tracking-[.26em] text-slate-400">Next reward</p>
          {next ? (
            <>
              <b className="text-[12px] text-amber-100">BUY {mythFull(next.amount)} {stats.symbol}</b>
              <p className="mt-1 text-[10px] text-slate-300">{next.rewards.join(' · ')}</p>
              <p className="mt-1 text-[9px] text-amber-300/80">{mythFull(Math.max(0, next.amount - bought))} {stats.symbol} to go</p>
            </>
          ) : <b className="text-[12px] text-emerald-200">All milestones unlocked — maximum event tier reached.</b>}
        </div>
        <div className="mt-2 rounded-2xl border border-white/10 bg-black/55 p-3">
          <p className="text-[8px] font-black uppercase tracking-[.26em] text-slate-400">Event bonus status</p>
          <b className={`text-[12px] ${unlocked > 0 ? 'text-emerald-200' : 'text-slate-300'}`}>{unlocked > 0 ? `${unlocked}/${MYTH_EVENT_MILESTONES.length} milestones unlocked` : 'No bonus unlocked yet'}</b>
        </div>
      </div>

      {/* SECTION 4 — EVENT BONUSES */}
      <SectionTitle icon={<Rocket className="h-3.5 w-3.5" />} title="EVENT BONUSES" subtitle="Advantages active while the event runs." />
      <div className="grid grid-cols-2 gap-2">
        <Bonus icon={<Coins className="h-4 w-4 text-amber-300" />} text="Bonus MYTH on larger purchases" />
        <Bonus icon={<Gift className="h-4 w-4 text-amber-300" />} text="Special event rewards" />
        <Bonus icon={<Flame className="h-4 w-4 text-amber-300" />} text="Access to exclusive future drops" />
        <Bonus icon={<ShieldCheck className="h-4 w-4 text-amber-300" />} text="Better positioning for future holder benefits" />
      </div>

      {/* SECTION 5 — BUY CTA */}
      <section className="relative mt-4 overflow-hidden rounded-[2rem] border border-amber-300/50 bg-gradient-to-br from-[#231703] via-[#0a1020] to-black p-5 text-center shadow-[0_0_45px_rgba(245,158,11,.2)]">
        <div className="pointer-events-none absolute -top-10 left-1/2 h-32 w-32 -translate-x-1/2 rounded-full bg-amber-400/20 blur-3xl" />
        <div className="relative">
          <h3 className="bg-gradient-to-b from-amber-100 to-amber-400 bg-clip-text text-xl font-black tracking-[.06em] text-transparent">BUY MYTH NOW</h3>
          <p className="mx-auto mt-1 max-w-[15rem] text-[10px] leading-4 text-slate-300">Use your internal TON balance to buy instantly. Without enough balance, the payment goes through your TON wallet.</p>
          <div className="mt-3 flex items-center justify-between rounded-2xl border border-white/10 bg-black/55 px-3 py-2 text-[10px]">
            <span className="text-slate-400"><Wallet className="mr-1 inline h-3.5 w-3.5 text-emerald-300" />Internal TON balance</span>
            <b className={internalTon > 0 ? 'text-emerald-300' : 'text-slate-300'}>{formatTon(internalTon)} TON</b>
          </div>
          <button onClick={onGoToSale} className="mt-3 w-full rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-3.5 text-xs font-black uppercase tracking-[.24em] text-black shadow-[0_0_25px_rgba(245,158,11,.35)]">BUY WITH TON</button>
          {onGoToWallet && <button onClick={onGoToWallet} className="mt-2 w-full rounded-2xl border border-amber-300/35 bg-black/50 py-3 text-[11px] font-black uppercase tracking-[.24em] text-amber-200">GO TO WALLET</button>}
        </div>
      </section>

      {/* SECTION 6 — EVENT RULES */}
      <section className="mt-3 rounded-3xl border border-white/10 bg-black/55 p-4">
        <b className="text-[10px] font-black uppercase tracking-[.24em] text-amber-200"><Hourglass className="mr-1 inline h-3.5 w-3.5" />EVENT RULES</b>
        <ul className="mt-2 space-y-1 text-[10px] leading-4 text-slate-400">
          <li>· Event duration: {MYTH_EVENT_DAYS} days</li>
          <li>· Rewards are based on total MYTH purchased during the event</li>
          <li>· Rewards are claimable only once per milestone</li>
          <li>· Event purchases update in real time</li>
          <li>· Final availability depends on remaining supply</li>
        </ul>
      </section>
    </div>
  );
}

function SectionTitle({ icon, title, subtitle }: { icon: React.ReactNode; title: string; subtitle: string }) {
  return (
    <div className="mb-2 mt-5">
      <b className="flex items-center gap-1.5 text-[11px] font-black uppercase tracking-[.24em] text-amber-200">{icon}{title}</b>
      <p className="mt-0.5 text-[9px] text-slate-400">{subtitle}</p>
    </div>
  );
}

function Bar({ percent }: { percent: number }) {
  return (
    <div className="mt-1.5 h-2.5 overflow-hidden rounded-full bg-white/10">
      <div className="h-full rounded-full bg-gradient-to-r from-amber-600 via-amber-400 to-yellow-200 shadow-[0_0_14px_rgba(245,158,11,.6)] transition-all" style={{ width: `${Math.min(100, Math.max(0, percent))}%` }} />
    </div>
  );
}

function Cell({ label, value, tone }: { label: string; value: string; tone?: 'rose' | 'emerald' | 'cyan' }) {
  const color = tone === 'rose' ? 'text-rose-200' : tone === 'emerald' ? 'text-emerald-200' : tone === 'cyan' ? 'text-cyan-200' : 'text-white';
  return (
    <div className="rounded-2xl border border-white/10 bg-black/55 p-2.5">
      <p className="text-[8px] uppercase tracking-[.18em] text-slate-400">{label}</p>
      <b className={`text-[13px] ${color}`}>{value}</b>
    </div>
  );
}

function Bonus({ icon, text }: { icon: React.ReactNode; text: string }) {
  return (
    <div className="rounded-2xl border border-amber-300/25 bg-gradient-to-br from-amber-950/30 to-black p-3">
      <div className="grid h-8 w-8 place-items-center rounded-xl border border-amber-300/30 bg-black/60">{icon}</div>
      <p className="mt-2 text-[10px] leading-4 text-slate-300">{text}</p>
    </div>
  );
}
