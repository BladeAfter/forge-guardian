import { useEffect, useMemo, useState } from 'react';
import { Coins, Crown, Flame, Gift, Medal, Timer, TrendingUp, Trophy, Users, Wallet } from 'lucide-react';
import { useSpendingEvent } from '../hooks';
import { formatTon } from '../economy';
import { abbreviatePoints, countdownLabel, fullPoints, rankMedal, rankTone, spendingCountdown } from '../spendingEvent';
import type { SpendingRankRow } from '../spendingEvent';
import { PlayerTag } from '../premiumTitles';

/**
 * MYTHREON SPENDING EVENT — competitive 14-day spending leaderboard.
 * Every number (score, rank, totals, breakdown, ranking, reward table and end date) comes
 * from the backend scoring engine; the client never computes points.
 */
const GROUP_LABELS: Record<string, string> = {
  ton_direct_deposit: 'TON DIRECT DEPOSITS',
  ton_to_fc: 'TON → BERRIES',
  myth_sale: 'MYTH PURCHASES',
  season_pass: 'SEASON PASS',
  packs: 'PACKS (FOUNDER / VETERAN)',
  nft_shop: 'NFT SHOP',
  marketplace: 'MARKETPLACE',
  auction: 'AUCTION',
  fc_spend: 'BERRIES SPENDING',
  other_ton: 'OTHER TON SPENDING',
};

/** Compact reward tiers (presentation only — payouts follow the backend reward table). */
type RewardTier = { label: string; medal: string; from: number; to: number; items: string[]; grand?: boolean; wide?: boolean; note?: string };
const REWARD_TIERS: RewardTier[] = [
  { label: '#1', medal: '🥇', from: 1, to: 1, grand: true, wide: true, items: ['Exclusive Hero Chest', 'Exclusive Pet Chest', '2 NFT Weapons', 'NFT Grand Prize', '150,000 MYTH', '100 Universal Fragments', '1 Celestial Chest'], note: 'GRAND PRIZE ≈ 100 TON · TON MINING ENABLED' },
  { label: '#2', medal: '🥈', from: 2, to: 2, items: ['Exclusive Hero Chest', 'Mythic Egg', '1 NFT Weapon', '120,000 MYTH', '75 Universal Fragments', '1 Void Chest'] },
  { label: '#3', medal: '🥉', from: 3, to: 3, items: ['Exclusive Pet Chest', 'Celestial Chest (mythic)', '1 NFT Weapon', '90,000 MYTH', '50 Universal Fragments', '1 Premium Equipment Chest'] },
  { label: '#4 – #10', medal: '🏆', from: 4, to: 10, items: ['60,000 MYTH', '60 Universal Fragments', '1 Void Chest (legendary)', '1 Premium Equipment Chest', '10 PvP Tickets', '1 Mythic Egg Shard Pack'] },
  { label: '#11 – #20', medal: '🎁', from: 11, to: 20, items: ['30,000 MYTH', '30 Universal Fragments', '1 Eternity Chest', '1 Equipment Chest', '5 PvP Tickets', '1 Pet Food / Hero XP Pack'] },
  { label: '#21 – #50', medal: '✨', from: 21, to: 50, wide: true, items: ['10,000 MYTH', '10 Universal Fragments', '1 Random Chest', '3 PvP Tickets'] },
];


export function SpendingEventPanel({ telegramInitData, onGoToSale, onGoToWallet }: { telegramInitData: string; onGoToSale?: () => void; onGoToWallet?: () => void }) {
  const { data, isLoading, error, refetch } = useSpendingEvent(telegramInitData, true, 20);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => { const id = window.setInterval(() => setNow(Date.now()), 1000); return () => window.clearInterval(id); }, []);

  const event = data?.event ?? null;
  const clock = useMemo(() => spendingCountdown(event?.endsAt, now), [event?.endsAt, now]);
  const seconds = useMemo(() => {
    const end = event?.endsAt ? new Date(event.endsAt).getTime() : 0;
    return Math.max(0, Math.floor((Math.max(0, end - now) % 60_000) / 1000));
  }, [event?.endsAt, now]);

  if (isLoading) return <div className="space-y-3 pt-6">{[1, 2, 3].map(x => <div key={x} className="h-28 animate-pulse rounded-3xl bg-white/5" />)}</div>;
  if (error || !data) return (
    <div className="py-20 text-center">
      <p className="text-rose-300">Unable to load the Spending Event.</p>
      <button onClick={() => void refetch()} className="mt-4 rounded-xl border border-amber-300/30 px-5 py-3 text-xs font-black">RETRY</button>
    </div>
  );

  const player = data.player;
  const totals = data.totals;
  const ranking = Array.isArray(data.ranking) ? data.ranking : [];
  const rewards = Array.isArray(data.rewards) ? data.rewards : [];
  const breakdown = Array.isArray(data.breakdown) ? data.breakdown : [];
  const finished = event?.status === 'finished' || clock.ended;
  const myRow = ranking.find(r => r.position === player.position) ?? null;
  const breakdownTotal = breakdown.reduce((sum, row) => sum + Number(row.points || 0), 0);

  return (
    <div className="pb-12">
      {/* MAIN EVENT CARD */}
      <section className="relative overflow-hidden rounded-[2rem] border border-amber-300/50 bg-gradient-to-br from-[#241703] via-[#0a1020] to-black p-5 text-center shadow-[0_0_60px_rgba(245,158,11,.25)]">
        <div className="pointer-events-none absolute -left-10 -top-12 h-40 w-40 rounded-full bg-amber-400/20 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-16 -right-8 h-44 w-44 rounded-full bg-yellow-200/10 blur-3xl" />
        {[10, 30, 52, 70, 88].map((left, i) => (
          <Flame key={left} className="pointer-events-none absolute h-3 w-3 animate-pulse text-amber-300/40" style={{ left: `${left}%`, top: `${12 + ((i * 19) % 60)}%`, animationDelay: `${i * 300}ms` }} />
        ))}
        <div className="relative">
          <div className="mx-auto grid h-16 w-16 place-items-center rounded-full border border-amber-300/60 bg-black/60 shadow-[0_0_35px_rgba(245,158,11,.45)]">
            <Trophy className="h-9 w-9 animate-pulse text-amber-300" />
          </div>
          <h2 className="mt-3 bg-gradient-to-b from-amber-100 to-amber-400 bg-clip-text text-2xl font-black tracking-[.06em] text-transparent">🔥 MYTHREON SPENDING EVENT</h2>
          <p className="mt-1 text-[9px] font-black uppercase tracking-[.34em] text-amber-300">14-DAY SPENDING EVENT</p>
          <p className="mx-auto mt-2 max-w-[17rem] text-[10px] leading-4 text-slate-300">Spend, deposit and participate across Mythreon to climb the live leaderboard and compete for exclusive Top {event?.topLimit ?? 20} rewards.</p>
          <div className="mt-4 rounded-2xl border border-amber-300/30 bg-black/60 p-3">
            <p className="text-[8px] font-black uppercase tracking-[.3em] text-amber-300/80"><Timer className="mr-1 inline h-3 w-3" />{finished ? 'EVENT ENDED — FINAL RANKING LOCKED' : 'ENDS IN'}</p>
            <b className="mt-1 block text-xl font-black tabular-nums text-amber-100">
              {finished ? '--' : `${clock.days}d ${String(clock.hours).padStart(2, '0')}h ${String(clock.minutes).padStart(2, '0')}m ${String(seconds).padStart(2, '0')}s`}
            </b>
          </div>
          <div className="mt-3 grid grid-cols-2 gap-2 text-left">
            <Cell label="Your score" value={`${abbreviatePoints(player.points)} pts`} tone="emerald" />
            <Cell label="Your position" value={player.position ? `#${player.position}` : '—'} />
            <Cell label="Total participants" value={fullPoints(totals.participants)} tone="cyan" />
            <Cell label="Total event score" value={`${abbreviatePoints(totals.points)} pts`} />
          </div>
        </div>
      </section>

      {/* YOUR POSITION */}
      <SectionTitle icon={<Crown className="h-3.5 w-3.5" />} title="YOUR POSITION" subtitle="Overtake the player above you to climb the leaderboard." />
      <div className="rounded-3xl border border-amber-300/35 bg-gradient-to-br from-[#160f04] to-black p-4">
        <div className="flex items-end justify-between">
          <div>
            <p className="text-[8px] font-black uppercase tracking-[.26em] text-slate-400">Current rank</p>
            <b className="text-3xl font-black text-amber-100">{player.position ? `#${player.position}` : '—'}</b>
          </div>
          <div className="text-right">
            <p className="text-[8px] font-black uppercase tracking-[.26em] text-slate-400">Your score</p>
            <b className="text-lg font-black text-emerald-200">{abbreviatePoints(player.points)} pts</b>
            <p className="text-[9px] text-slate-400">{fullPoints(player.points)} pts</p>
          </div>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-2">
          <Cell label="Next position" value={player.nextRank ? `#${player.nextRank}` : player.position === 1 ? 'TOP 1' : '—'} />
          <Cell label="Points needed" value={player.neededToNext ? `+${abbreviatePoints(player.neededToNext)} pts` : player.position === 1 ? 'LEADING' : '—'} tone="cyan" />
          <Cell label="TON spent" value={`${formatTon(player.tonSpent)} TON`} />
          <Cell label="BERRIES spent" value={fullPoints(player.fcSpent)} />
        </div>
        {player.estimatedReward && (
          <div className="mt-2 rounded-2xl border border-amber-300/30 bg-black/55 p-3">
            <p className="text-[8px] font-black uppercase tracking-[.26em] text-amber-300/80">Reward at current rank</p>
            <b className="text-[11px] leading-4 text-amber-100">{player.estimatedReward}</b>
          </div>
        )}
      </div>

      {/* YOUR EVENT ACTIVITY */}
      <SectionTitle icon={<TrendingUp className="h-3.5 w-3.5" />} title="YOUR EVENT ACTIVITY" subtitle="Where your event points came from." />
      <div className="rounded-3xl border border-white/10 bg-black/55 p-3.5">
        {breakdown.length === 0 ? (
          <p className="py-4 text-center text-[10px] text-slate-400">No eligible activity yet. Deposits, purchases and BERRIES spending all score points.</p>
        ) : (
          <>
            <ul className="space-y-1.5">
              {breakdown.map(row => (
                <li key={row.group} className="flex items-center justify-between rounded-2xl border border-white/10 bg-black/50 px-3 py-2">
                  <span className="text-[9px] font-black uppercase tracking-[.16em] text-slate-300">{GROUP_LABELS[row.group] ?? row.group.replace(/_/g, ' ').toUpperCase()}</span>
                  <b className="text-[11px] text-amber-100">{abbreviatePoints(row.points)} pts</b>
                </li>
              ))}
            </ul>
            <div className="mt-2 flex items-center justify-between rounded-2xl border border-amber-300/35 bg-amber-500/10 px-3 py-2">
              <span className="text-[9px] font-black uppercase tracking-[.2em] text-amber-200">TOTAL</span>
              <b className="text-[12px] text-amber-100">{fullPoints(breakdownTotal)} pts</b>
            </div>
          </>
        )}
        <p className="mt-2 text-[9px] leading-4 text-slate-500">
          1 TON = {abbreviatePoints(event?.tonRateFc ?? 100000)} pts · 1 BERRIES spent = {fullPoints(event?.fcRate ?? 1)} pt. Rewards received (boss, PvP, clan, mining, pool) never score points.
        </p>
      </div>

      {/* LIVE RANKING */}
      <SectionTitle icon={<Medal className="h-3.5 w-3.5" />} title="LIVE RANKING" subtitle={`Top ${event?.topLimit ?? 20} · updates in real time.`} />
      <div className="space-y-1.5">
        {ranking.length === 0 && <p className="rounded-3xl border border-white/10 bg-black/55 py-6 text-center text-[10px] text-slate-400">No participants yet — be the first on the leaderboard.</p>}
        {ranking.map((row,index) => <RankRow key={row.userId||`rank-${index}`} row={row} me={row.position === player.position && !!myRow} />)}
      </div>

      {/* TOP REWARDS — compact tier grid */}
      <SectionTitle icon={<Gift className="h-3.5 w-3.5" />} title={`🏆 TOP ${event?.topLimit ?? 20} REWARDS`} subtitle="Paid by final rank at the end of the event." />
      <div className="grid grid-cols-2 gap-1.5">
        {REWARD_TIERS.map(tier => {
          const mine = player.position != null && player.position >= tier.from && player.position <= tier.to;
          return (
            <div key={tier.label} className={`rounded-2xl border p-2.5 ${tier.wide ? 'col-span-2' : ''} ${tier.grand ? 'border-amber-300/60 bg-gradient-to-br from-amber-950/60 to-black shadow-[0_0_22px_rgba(245,158,11,.18)]' : mine ? 'border-emerald-300/45 bg-gradient-to-br from-emerald-950/40 to-black' : 'border-white/10 bg-black/55'}`}>
              <div className="flex items-center justify-between">
                <b className={`text-[11px] font-black ${tier.grand ? 'text-amber-100' : 'text-slate-100'}`}>
                  {tier.grand && <Crown className="mr-1 inline h-3 w-3 text-amber-300" />}{tier.medal} {tier.label}
                </b>
                {mine && <span className="text-[7px] font-black uppercase tracking-[.2em] text-emerald-300">YOU</span>}
              </div>
              <ul className={`mt-1 space-y-0.5 text-[9px] leading-[13px] text-slate-300 ${tier.wide ? 'columns-2' : ''}`}>
                {tier.items.map(item => <li key={item}>· {item}</li>)}
              </ul>
              {tier.note && <p className="mt-1 text-[8px] font-black uppercase tracking-[.14em] text-amber-300">{tier.note}</p>}
            </div>
          );
        })}
      </div>
      {rewards.length > 0 && (
        <details className="mt-1.5 rounded-2xl border border-white/10 bg-black/45 px-3 py-2">
          <summary className="cursor-pointer text-[9px] font-black uppercase tracking-[.2em] text-amber-200/80">FULL RANK TABLE</summary>
          <div className="mt-1.5 space-y-1">
            {rewards.map(slot => (
              <div key={`${slot.from}-${slot.to}`} className="flex gap-2 text-[9px] leading-[13px]">
                <b className="shrink-0 text-amber-200">{slot.from === slot.to ? `#${slot.from}` : `#${slot.from}–${slot.to}`}</b>
                <span className="text-slate-400">{slot.label}</span>
              </div>
            ))}
          </div>
        </details>
      )}


      {/* WALLET SHORTCUTS */}
      <section className="relative mt-4 overflow-hidden rounded-[2rem] border border-amber-300/45 bg-gradient-to-br from-[#231703] via-[#0a1020] to-black p-5 text-center">
        <div className="pointer-events-none absolute -top-10 left-1/2 h-32 w-32 -translate-x-1/2 rounded-full bg-amber-400/20 blur-3xl" />
        <div className="relative">
          <h3 className="bg-gradient-to-b from-amber-100 to-amber-400 bg-clip-text text-lg font-black tracking-[.06em] text-transparent">CLIMB THE LEADERBOARD</h3>
          <p className="mx-auto mt-1 max-w-[16rem] text-[10px] leading-4 text-slate-300">Every eligible deposit, purchase and BERRIES sink adds points instantly.</p>
          {onGoToWallet && <button onClick={onGoToWallet} className="mt-3 w-full rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-3.5 text-xs font-black uppercase tracking-[.24em] text-black shadow-[0_0_25px_rgba(245,158,11,.35)]"><Wallet className="mr-1 inline h-4 w-4" />DEPOSIT TON</button>}
          {onGoToSale && <button onClick={onGoToSale} className="mt-2 w-full rounded-2xl border border-amber-300/35 bg-black/50 py-3 text-[11px] font-black uppercase tracking-[.24em] text-amber-200"><Coins className="mr-1 inline h-3.5 w-3.5" />MYTH SALE</button>}
        </div>
      </section>

      {/* RULES */}
      <section className="mt-3 rounded-3xl border border-white/10 bg-black/55 p-4">
        <b className="text-[10px] font-black uppercase tracking-[.24em] text-amber-200"><Users className="mr-1 inline h-3.5 w-3.5" />EVENT RULES</b>
        <ul className="mt-2 space-y-1 text-[10px] leading-4 text-slate-400">
          <li>· Duration: 14 days — the backend clock is the only authority</li>
          <li>· Score sources: TON deposits, TON → BERRIES, MYTH purchases, Season Pass, packs, NFT shop, marketplace, auction wins and every eligible BERRIES sink</li>
          <li>· Converting TON to BERRIES scores once; spending that BERRIES later scores again as a new sink</li>
          <li>· Rewards, mining, pool payouts and admin grants never score points</li>
          <li>· When the event ends the ranking is locked and rewards are paid by final rank</li>
        </ul>
      </section>
    </div>
  );
}

function RankRow({ row, me }: { row: SpendingRankRow; me: boolean }) {
  return (
    <div className={`flex items-center gap-2.5 rounded-2xl border px-3 py-2.5 ${me ? 'border-emerald-300/50 bg-emerald-500/10' : rankTone(row.position)}`}>
      <div className="grid h-8 w-8 shrink-0 place-items-center rounded-xl border border-white/10 bg-black/60 text-[11px] font-black text-amber-100">
        {rankMedal(row.position) || `#${row.position}`}
      </div>
      {row.avatarUrl
        ? <img src={row.avatarUrl} alt={row.name} loading="lazy" className="h-8 w-8 shrink-0 rounded-full border border-white/10 object-cover" />
        : <div className="grid h-8 w-8 shrink-0 place-items-center rounded-full border border-white/10 bg-white/5 text-[10px] font-black text-slate-300">{row.name.slice(0, 1).toUpperCase()}</div>}
      <div className="min-w-0 flex-1">
        <b className={`block truncate text-[11px] font-black ${me ? 'text-emerald-100' : 'text-slate-100'}`}>{me ? 'YOU' : null}{me ? null : <PlayerTag userId={row.userId} username={row.username} fallback={row.name}/>}</b>
        <p className="truncate text-[9px] text-slate-400">{formatTon(row.tonSpent)} TON · {abbreviatePoints(row.fcSpent)} BERRIES</p>
      </div>
      <b className="shrink-0 text-[12px] font-black text-amber-100">{abbreviatePoints(row.points)} pts</b>
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

function Cell({ label, value, tone }: { label: string; value: string; tone?: 'rose' | 'emerald' | 'cyan' }) {
  const color = tone === 'rose' ? 'text-rose-200' : tone === 'emerald' ? 'text-emerald-200' : tone === 'cyan' ? 'text-cyan-200' : 'text-white';
  return (
    <div className="rounded-2xl border border-white/10 bg-black/55 p-2.5">
      <p className="text-[8px] uppercase tracking-[.18em] text-slate-400">{label}</p>
      <b className={`text-[13px] ${color}`}>{value}</b>
    </div>
  );
}

export const spendingCountdownLabel = countdownLabel;
