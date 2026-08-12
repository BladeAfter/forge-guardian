import { useEffect, useMemo, useRef, useState } from 'react';
import { ArrowLeft, Flame, History, Skull, Sword, Trophy, Users } from 'lucide-react';
import { toast } from 'sonner';
import { useT } from '../LanguageContext';
import { useClanBoss, useClanBossRealtime } from '../hooks';
import { abbreviateDamage, countdownLabel, strikeClanBoss, type ClanBossState } from '../clanBoss';
import { ClanCrest } from './ClanHall';
import { FloatingDamage, NextAttackBar, TurnIndicator, useCombatFx, useEasedPercent, type CombatEvent } from './ClanBossCombatFx';
import warlordArt from '../assets/clan-boss/abyssal-warlord.webp';


const STRIKE_ERRORS: Record<string, string> = {
  CLAN_BOSS_COOLDOWN: 'clanBoss.error.cooldown',
  CLAN_BOSS_DEFEATED: 'clanBoss.error.defeated',
  CLAN_BOSS_EXPIRED: 'clanBoss.error.expired',
  FORBIDDEN_CLAN_BOSS: 'clanBoss.error.forbidden',
  NOT_IN_CLAN: 'clan.error.notInClan',
};

/**
 * Fullscreen Abyssal Warlord battle, exclusive to the player's own clan.
 * Every number rendered here comes from the clan-scoped backend state; the
 * component never computes damage, HP or eligibility on its own.
 */
export function ClanBossScreen({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const t = useT();
  const { data, isLoading, isError, refetch } = useClanBoss(telegramInitData, true);
  const [now, setNow] = useState(() => Date.now());
  const [busy, setBusy] = useState(false);
  const [showHistory, setShowHistory] = useState(false);
  const [impact, setImpact] = useState<{ id: string; kind: 'player' | 'crit' | 'boss' } | null>(null);
  const { events, phase, push } = useCombatFx();
  const seen = useRef<Set<string>>(new Set());

  useClanBossRealtime(data?.boss?.id, data?.clan?.id, Boolean(data?.inClan));

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  const boss = data?.boss;
  const me = data?.me;
  const hpPercent = useMemo(() => {
    if (!boss || boss.maxHp <= 0) return 0;
    return Math.max(0, Math.min(100, (boss.currentHp / boss.maxHp) * 100));
  }, [boss]);
  // Bar eases old -> new; the numeric readout below always shows the real value.
  const easedHp = useEasedPercent(hpPercent);

  const cooldownLeft = me?.nextAttackAt ? new Date(me.nextAttackAt).getTime() - now : 0;
  const onCooldown = cooldownLeft > 0;
  const defeated = Boolean(boss && (boss.status !== 'active' || boss.currentHp <= 0));


  const attack = async () => {
    if (busy || !boss) return;
    setBusy(true);
    try {
      const result = await strikeClanBoss(telegramInitData, boss.id);
      // One animation per confirmed backend combat event (never on refetch).
      const eventId = result.eventId ?? `${boss.id}:${result.nextAttackAt}:${result.currentHp}`;
      if (!seen.current.has(eventId)) {
        seen.current.add(eventId);
        push({ id: `${eventId}:player`, kind: result.critical ? 'CRITICAL' : 'PLAYER_ATTACK', damage: result.damage, critical: result.critical });
        setImpact({ id: eventId, kind: result.critical ? 'crit' : 'player' });
        window.setTimeout(() => setImpact((current) => (current?.id === eventId ? null : current)), 620);

        // Boss retaliation / hero status only animate when the backend reports them.
        const bossDamage = Number(result.bossAttack?.teamDamage ?? result.bossAttack?.damage ?? result.teamDamage ?? 0);
        const extras: CombatEvent[] = [];
        if (bossDamage > 0) extras.push({ id: `${eventId}:boss`, kind: 'BOSS_ATTACK', damage: bossDamage });
        (result.heroesDefeated ?? []).forEach((name, index) => extras.push({ id: `${eventId}:down:${index}`, kind: 'HERO_DEFEATED', label: `${name} DEFEATED` }));
        (result.heroesRevived ?? []).forEach((name, index) => extras.push({ id: `${eventId}:up:${index}`, kind: 'HERO_REVIVED', label: `${name} REVIVED` }));
        if (extras.length) {
          window.setTimeout(() => {
            extras.forEach(push);
            if (bossDamage > 0) {
              setImpact({ id: `${eventId}:boss`, kind: 'boss' });
              window.setTimeout(() => setImpact((current) => (current?.id === `${eventId}:boss` ? null : current)), 720);
            }
          }, 700);
        }
      }
      if (result.defeated) toast.success(t('clanBoss.defeated'));
      await refetch();

    } catch (error) {
      const raw = error instanceof Error ? error.message : '';
      console.error('[CLAN BOSS STRIKE FAILED]', raw);
      toast.error(STRIKE_ERRORS[raw] ? t(STRIKE_ERRORS[raw]) : t('clanBoss.error'));
      await refetch();
    } finally {
      setBusy(false);
    }
  };

  if (isLoading) return <Frame onClose={onClose}><p className="py-20 text-center text-[10px] tracking-[.2em] text-violet-200/70">{t('clanBoss.loading')}</p></Frame>;

  if (isError || !data) {
    return (
      <Frame onClose={onClose}>
        <div className="py-16 text-center">
          <p className="text-[11px] text-rose-200">{t('clanBoss.error')}</p>
          <button type="button" onClick={() => void refetch()} className="mt-4 rounded-xl border border-violet-300/40 bg-violet-500/20 px-5 py-3 text-[10px] font-black text-violet-100">{t('clanBoss.tryAgain')}</button>
        </div>
      </Frame>
    );
  }

  if (!data.inClan) {
    return (
      <Frame onClose={onClose}>
        <div className="mt-16 rounded-3xl border border-violet-400/25 bg-black/60 p-6 text-center">
          <Skull className="mx-auto h-10 w-10 text-violet-300" />
          <p className="mt-4 text-[11px] font-black leading-relaxed tracking-[.12em] text-violet-100">{t('clanBoss.noClan')}</p>
        </div>
      </Frame>
    );
  }

  // In a clan, but the backend has no active instance for THIS clan (cycle settled,
  // creation pending). Never an endless spinner: show the state plus a retry.
  if (!boss) {
    return (
      <Frame onClose={onClose} clan={data.clan}>
        <div className="mt-16 rounded-3xl border border-violet-400/25 bg-black/60 p-6 text-center">
          <Skull className="mx-auto h-10 w-10 text-violet-300" />
          <p className="mt-4 text-[11px] font-black tracking-[.12em] text-violet-100">{t('clanBoss.noActive')}</p>
          <button type="button" onClick={() => void refetch()} className="mt-4 w-full rounded-xl border border-violet-300/40 bg-violet-500/20 py-3 text-[10px] font-black text-violet-100">{t('clanBoss.tryAgain')}</button>
        </div>
      </Frame>
    );
  }


  return (
    <Frame onClose={onClose} clan={data.clan} cycle={boss?.cycle}>
      {/* Boss stage — container size never changes, only the art transforms */}
      <div className="cb-stage relative overflow-hidden rounded-3xl border border-violet-400/25 bg-[radial-gradient(circle_at_50%_10%,rgba(139,92,246,.35),rgba(0,0,0,.9)_70%)] p-3">
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-rose-900/50 to-transparent" />
        {impact ? <div className={`cb-flash ${impact.kind === 'boss' ? 'cb-flash-boss' : impact.kind === 'crit' ? 'cb-flash-crit' : 'cb-flash-player'}`} /> : null}
        {impact && impact.kind !== 'boss' ? <div className="cb-slash"><i /><i /></div> : null}
        <div className="relative h-56">
          <img
            src={warlordArt}
            alt={boss?.name ?? 'Abyssal Warlord'}
            width={1024}
            height={1280}
            className={`cb-boss-art mx-auto h-56 w-auto object-contain drop-shadow-[0_0_28px_rgba(168,85,247,.55)] ${impact ? (impact.kind === 'boss' ? 'cb-charge' : 'cb-hit') : ''}`}
          />
          <FloatingDamage events={events} />
        </div>
        <div className="relative mt-2 text-center">
          <b className="text-base font-black tracking-[.14em] text-violet-100">{boss?.name}</b>
          <p className="text-[8px] tracking-[.28em] text-amber-300/80">{t('clanBoss.level')} {boss?.level ?? 1}</p>
          <div className="mt-2"><TurnIndicator phase={phase} idleLabel={t('clanBoss.waiting')} /></div>
        </div>

        {/* HP — bar eases, number stays exact */}
        <div className="relative mt-3">
          <div className="flex items-end justify-between text-[9px] tracking-[.2em] text-violet-200/80">
            <span>{t('clanBoss.hp')}</span>
            <span className="font-black text-white">{Math.round(boss?.currentHp ?? 0).toLocaleString()} / {Math.round(boss?.maxHp ?? 0).toLocaleString()}</span>
          </div>
          <div className="mt-1 h-4 overflow-hidden rounded-full border border-violet-300/30 bg-black/70">
            <div className="h-full bg-gradient-to-r from-rose-700 via-rose-500 to-violet-400" style={{ width: `${easedHp}%` }} />
          </div>
        </div>

        {/* NEXT ATTACK — driven by the real cooldown, no extra timers */}
        <div className="relative mt-3 space-y-1 rounded-2xl border border-white/10 bg-black/45 p-2">
          <p className="text-[8px] font-black tracking-[.22em] text-slate-400">{t('clanBoss.nextAttack')}</p>
          <NextAttackBar
            label={t('clanBoss.playerSlot')}
            remainingMs={cooldownLeft}
            totalSeconds={boss?.cooldownSeconds ?? 1}
            readyLabel={t('clanBoss.ready')}
          />
        </div>
      </div>


      {defeated ? (
        <div className="mt-3 rounded-3xl border border-amber-300/40 bg-amber-400/10 p-4 text-center">
          <b className="text-[12px] font-black tracking-[.16em] text-amber-200">{t('clanBoss.defeated')}</b>
          <p className="mt-2 text-[10px] text-slate-200">{t('clanBoss.clanDamage')}: <b>{Math.round(boss?.clanDamage ?? 0).toLocaleString()}</b></p>
          <p className="text-[10px] text-slate-200">{t('clanBoss.topDamage')}: <b>{data.ranking?.[0]?.name ?? '—'}</b></p>
          <p className="text-[10px] text-emerald-300">{t('clanBoss.clanXp')}: +{boss?.clanXpReward ?? 0}</p>
          <p className="text-[10px] text-amber-200">{t('clanBoss.rewardsReady')}</p>
          <button onClick={() => setShowHistory(true)} className="mt-3 w-full rounded-xl border border-amber-300/40 bg-black/50 py-3 text-[10px] font-black tracking-[.18em] text-amber-200">{t('clanBoss.viewResults')}</button>
        </div>
      ) : null}

      {/* Stats */}
      <div className="mt-3 grid grid-cols-2 gap-2">
        <Stat label={t('clanBoss.clanDamage')} value={abbreviateDamage(boss?.clanDamage)} tone="violet" />
        <Stat label={t('clanBoss.yourDamage')} value={abbreviateDamage(me?.damage)} tone="rose" />
        <Stat label={t('clanBoss.yourRank')} value={me?.rank ? `#${me.rank}` : '—'} tone="amber" />
        <Stat label={t('clanBoss.timeLeft')} value={countdownLabel(boss?.endsAt, now)} tone="cyan" />
      </div>

      <div className="mt-2 grid grid-cols-2 gap-2">
        <Stat label={t('clanBoss.participants')} value={String(boss?.participants ?? 0)} tone="violet" />
        <Stat label={t('clanBoss.power')} value={abbreviateDamage(me?.power)} tone="cyan" />
      </div>

      {/* Attack */}
      <button
        disabled={busy || defeated || onCooldown}
        onClick={() => void attack()}
        className="mt-3 w-full rounded-2xl border border-rose-300/40 bg-gradient-to-b from-rose-500 to-violet-800 py-4 text-[11px] font-black tracking-[.24em] text-white shadow-[0_0_24px_rgba(168,85,247,.35)] disabled:opacity-50"
      >
        {onCooldown ? `${t('clanBoss.cooldown')} ${countdownLabel(me?.nextAttackAt, now)}` : t('clanBoss.attack')}
      </button>

      {/* Reward requirement */}
      <div className="mt-3 rounded-2xl border border-white/10 bg-black/55 p-3">
        <p className="text-[9px] uppercase tracking-[.18em] text-slate-400">{t('clanBoss.minDamage')}</p>
        <b className="text-[11px] text-amber-200">{Math.round(boss?.minDamageForRewards ?? 0).toLocaleString()}</b>
        <p className={`mt-1 text-[9px] ${me?.eligibleForRewards ? 'text-emerald-300' : 'text-slate-400'}`}>
          {me?.eligibleForRewards ? `✓ ${t('clanBoss.eligible')}` : `✗ ${t('clanBoss.notEligible')}`}
        </p>
      </div>

      {/* Internal ranking (this clan only) */}
      <div className="mt-3">
        <h3 className="mb-2 flex items-center gap-1 text-[10px] font-black tracking-[.2em] text-amber-200"><Trophy className="h-3 w-3" />{t('clanBoss.ranking')}</h3>
        {(data.ranking ?? []).length === 0 ? (
          <p className="py-4 text-center text-[10px] text-slate-400">{t('clanBoss.noDamage')}</p>
        ) : (
          <div className="space-y-1">
            {(data.ranking ?? []).map((row, index) => (
              <div key={row.userId} className={`flex items-center gap-2 rounded-xl border p-2 ${row.isMe ? 'border-amber-300/50 bg-amber-400/10' : 'border-white/10 bg-black/55'}`}>
                <b className="w-8 text-center text-[10px] text-amber-300">{['🥇', '🥈', '🥉'][index] ?? `#${index + 1}`}</b>
                {row.avatar ? <img src={row.avatar} alt="" loading="lazy" className="h-6 w-6 rounded-full object-cover" /> : <div className="h-6 w-6 rounded-full bg-violet-500/30" />}
                <span className="min-w-0 flex-1 truncate text-[10px] text-white">{row.username ? `@${row.username}` : row.name}</span>
                <b className="text-[10px] text-rose-300">{abbreviateDamage(row.damage)}</b>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* History */}
      <button onClick={() => setShowHistory((value) => !value)} className="mt-3 flex w-full items-center justify-center gap-1 rounded-xl border border-white/10 bg-black/50 py-3 text-[9px] font-black tracking-[.2em] text-violet-200">
        <History className="h-3 w-3" />{t('clanBoss.history')}
      </button>
      {showHistory ? (
        <div className="mt-2 space-y-1">
          {(data.history ?? []).length === 0 ? <p className="py-3 text-center text-[9px] text-slate-500">—</p> : null}
          {(data.history ?? []).map((row) => (
            <div key={row.cycle} className="rounded-xl border border-white/10 bg-black/55 p-2">
              <div className="flex justify-between text-[10px]">
                <b className="text-violet-200">{t('clanBoss.cycle')} #{row.cycle}</b>
                <span className={row.status === 'defeated' ? 'text-emerald-300' : 'text-slate-400'}>
                  {row.status === 'defeated' ? t('clanBoss.historyDefeated') : t('clanBoss.historyExpired')}
                </span>
              </div>
              <p className="text-[9px] text-slate-400">
                {t('clanBoss.topDamage')}: {row.topName ? `@${row.topName}` : '—'} · {abbreviateDamage(row.totalDamage)} · {t('clanBoss.clanXp')} +{row.clanXp}
              </p>
            </div>
          ))}
        </div>
      ) : null}
      <div className="h-6" />
    </Frame>
  );
}

function Stat({ label, value, tone }: { label: string; value: string; tone: 'violet' | 'rose' | 'amber' | 'cyan' }) {
  const tones: Record<string, string> = {
    violet: 'text-violet-200 border-violet-400/25',
    rose: 'text-rose-200 border-rose-400/25',
    amber: 'text-amber-200 border-amber-300/25',
    cyan: 'text-cyan-200 border-cyan-300/25',
  };
  return (
    <div className={`rounded-2xl border bg-black/55 p-2 ${tones[tone]}`}>
      <p className="text-[8px] uppercase tracking-[.16em] text-slate-400">{label}</p>
      <b className="text-sm font-black">{value}</b>
    </div>
  );
}

function Frame({ children, onClose, clan, cycle }: { children: React.ReactNode; onClose: () => void; clan?: ClanBossState['clan']; cycle?: number }) {
  const t = useT();
  return (
    <div className="fullscreen-page overflow-y-auto bg-[radial-gradient(circle_at_50%_0%,rgba(76,29,149,.55),#070610_70%)] text-white">
      <div className="forge-safe-page mx-auto min-h-full w-full max-w-[480px] p-3">
        <header className="mb-3 flex items-center justify-between">
          <button onClick={onClose} className="grid h-10 w-10 place-items-center rounded-xl border border-violet-300/25 bg-black/50"><ArrowLeft /></button>
          <div className="flex items-center gap-2">
            {clan ? <ClanCrest emblem={clan.emblem} size={28} /> : null}
            <div className="text-center">
              <p className="text-[8px] tracking-[.28em] text-amber-300">{clan ? `[${clan.tag}] ${clan.name}` : 'MYTHREON'}</p>
              <b className="text-[12px] tracking-[.14em] text-violet-100">{t('clanBoss.title')}</b>
              {cycle ? <p className="text-[8px] tracking-[.2em] text-violet-300/80">{t('clanBoss.cycle')} #{cycle}</p> : null}
            </div>
          </div>
          <div className="grid h-10 w-10 place-items-center rounded-xl border border-rose-300/25 bg-black/50"><Sword className="h-4 w-4 text-rose-300" /></div>
        </header>
        {children}
      </div>
    </div>
  );
}

/** Compact entry card rendered inside the Clan Hub boss tab. */
export function ClanBossTeaser({ onOpen }: { onOpen: () => void }) {
  const t = useT();
  return (
    <button type="button" onClick={onOpen} className="relative z-10 w-full cursor-pointer overflow-hidden rounded-3xl border border-violet-400/30 bg-[radial-gradient(circle_at_50%_0%,rgba(139,92,246,.4),rgba(0,0,0,.85)_70%)] p-3 text-left">
      <div className="flex items-center gap-3">
        <img src={warlordArt} alt="Abyssal Warlord" loading="lazy" width={1024} height={1280} className="h-24 w-auto object-contain drop-shadow-[0_0_18px_rgba(168,85,247,.5)]" />
        <div className="min-w-0 flex-1">
          <b className="block text-[12px] font-black tracking-[.12em] text-violet-100">ABYSSAL WARLORD</b>
          <p className="mt-1 flex items-center gap-1 text-[9px] text-amber-300/90"><Flame className="h-3 w-3" />{t('clanBoss.title')}</p>
          <p className="mt-1 flex items-center gap-1 text-[9px] text-slate-400"><Users className="h-3 w-3" />{t('clanBoss.participants')}</p>
          <span className="mt-2 inline-block rounded-xl border border-rose-300/40 bg-rose-500/20 px-3 py-2 text-[9px] font-black tracking-[.16em] text-rose-100">{t('clanBoss.open')}</span>
        </div>
      </div>
    </button>
  );
}
