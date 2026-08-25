import { useEffect, useMemo, useRef, useState } from 'react';
import { ArrowLeft, Flame, History, Skull, Sword, Trophy, Users } from 'lucide-react';
import { toast } from 'sonner';
import { useT } from '../LanguageContext';
import { useClanBoss, useClanBossRealtime } from '../hooks';
import { abbreviateDamage, countdownLabel, setClanBossAutoAttack, strikeClanBoss, type ClanBossAutoAttackState, type ClanBossState } from '../clanBoss';
import { clanBossArt, clanBossTheme, DEFAULT_CLAN_BOSS_THEME } from '../clanBossThemes';
import { ClanCrest } from './ClanHall';
import { FloatingDamage, NextAttackBar, TurnIndicator, useCombatFx, useEasedPercent, type CombatEvent } from './ClanBossCombatFx';
import { PlayerTag } from '../premiumTitles';



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
  // Auto ATK is a backend benefit: the client only toggles the stored preference.
  const [autoBusy, setAutoBusy] = useState(false);
  const [autoOverride, setAutoOverride] = useState<ClanBossAutoAttackState | null>(null);
  // The panel is always visible on the Clan Boss screen (same as the Global Boss):
  // when the backend has no state yet we fall back to a locked/disabled view.
  const auto: ClanBossAutoAttackState =
    autoOverride ?? data?.autoAttack ?? { eligible: false, enabled: false, active: false, hasTeam: false, intervalSeconds: 1800, reason: 'no_pass' };
  // Once the server state refreshes it becomes the source of truth again.
  useEffect(() => { setAutoOverride(null); }, [data?.autoAttack?.nextAttackAt, data?.autoAttack?.enabled]);

  useClanBossRealtime(data?.boss?.id, data?.clan?.id, Boolean(data?.inClan));

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  const boss = data?.boss;
  const me = data?.me;
  const theme = clanBossTheme(boss?.key);
  const art = clanBossArt(boss?.key, boss?.imageUrl);
  const hpPercent = useMemo(() => {
    if (!boss || boss.maxHp <= 0) return 0;
    return Math.max(0, Math.min(100, (boss.currentHp / boss.maxHp) * 100));
  }, [boss]);
  // Bar eases old -> new; the numeric readout below always shows the real value.
  const easedHp = useEasedPercent(hpPercent);

  const cooldownLeft = me?.nextAttackAt ? new Date(me.nextAttackAt).getTime() - now : 0;
  const onCooldown = cooldownLeft > 0;
  const defeated = Boolean(boss && (boss.status !== 'active' || boss.currentHp <= 0));

  // Presentation-only cycle transition: when the backend hands over a NEW boss
  // instance we replay the "cycle completed" beat and fade the new art in.
  const previousInstance = useRef<string | null>(null);
  const [cycleSwap, setCycleSwap] = useState(0);
  useEffect(() => {
    if (!boss?.id) return;
    const previous = previousInstance.current;
    previousInstance.current = boss.id;
    if (previous && previous !== boss.id) setCycleSwap((value) => value + 1);
  }, [boss?.id]);
  useEffect(() => {
    if (!cycleSwap) return;
    const timer = window.setTimeout(() => setCycleSwap(0), 2200);
    return () => window.clearTimeout(timer);
  }, [cycleSwap]);



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

  // 24h CYCLE LOCK (server-side): the clan already had its rewarding boss for
  // this cycle. Killing it faster never unlocks a new farmable boss.
  if (!boss && data.cycleLocked) {
    const remaining = Math.max(0, data.nextBossInSeconds ?? 0);
    const hours = Math.floor(remaining / 3600);
    const minutes = Math.floor((remaining % 3600) / 60);
    const lastDuration = data.lastBoss?.durationSeconds ?? null;
    return (
      <Frame onClose={onClose} clan={data.clan}>
        <div className="mt-16 rounded-3xl border border-amber-300/30 bg-black/70 p-6 text-center">
          <Trophy className="mx-auto h-10 w-10 text-amber-300" />
          <p className="mt-4 text-[12px] font-black tracking-[.18em] text-amber-200">{t('clanBoss.cycleLocked')}</p>
          <p className="mt-5 text-[9px] font-black tracking-[.28em] text-violet-200/80">{t('clanBoss.nextBossIn')}</p>
          <p className="mt-1 text-3xl font-black tracking-[.08em] text-white">
            {String(hours).padStart(2, '0')}h {String(minutes).padStart(2, '0')}m
          </p>
          {lastDuration ? (
            <p className="mt-4 text-[9px] tracking-[.2em] text-violet-200/70">
              {t('clanBoss.lastDuration')}: {Math.floor(lastDuration / 3600)}h {Math.floor((lastDuration % 3600) / 60)}m
            </p>
          ) : null}
          <p className="mt-4 text-[9px] leading-relaxed tracking-[.12em] text-violet-200/60">{t('clanBoss.cycleLockedHint')}</p>
          <button type="button" onClick={() => void refetch()} className="mt-5 w-full rounded-xl border border-violet-300/40 bg-violet-500/20 py-3 text-[10px] font-black text-violet-100">{t('clanBoss.tryAgain')}</button>
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
    <Frame onClose={onClose} clan={data.clan} cycle={boss?.cycle} bossKey={boss?.key}>
      {/* Boss stage — layered themed arena: far backdrop, mid scene, floor, fx, boss */}
      <div
        className={`cb-stage relative overflow-hidden rounded-3xl border ${theme.border} p-3 shadow-[0_24px_70px_rgba(0,0,0,.6)]`}
        style={{ backgroundImage: theme.stage }}
      >
        <img
          key={`arena-${boss?.key}`}
          src={boss?.backgroundUrl && boss.backgroundUrl.length > 4 ? boss.backgroundUrl : theme.arena}
          alt=""
          aria-hidden
          loading="lazy"
          className="cb-arena-art"
        />
        <div className="cb-arena-shade" />
        <div className={`cb-arena-fx cb-fx-${theme.fx}`} />
        {/* depth: floor haze + vignette + subtle gold frame */}
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-28 bg-gradient-to-t from-black/85 to-transparent" />
        <div className="pointer-events-none absolute inset-0 rounded-3xl shadow-[inset_0_0_60px_rgba(0,0,0,.75)]" />
        <div className="pointer-events-none absolute inset-[3px] rounded-[22px] border border-amber-200/15" />
        {impact ? <div className={`cb-flash ${impact.kind === 'boss' ? 'cb-flash-boss' : impact.kind === 'crit' ? 'cb-flash-crit' : 'cb-flash-player'}`} /> : null}
        {impact && impact.kind !== 'boss' ? <div className="cb-slash"><i /><i /></div> : null}
        {cycleSwap ? (
          <div className="cb-cycle-overlay">
            <b>{t('clanBoss.defeated')}</b>
            <span>{t('clanBoss.cycleCompleted')}</span>
          </div>
        ) : null}
        <div className="cb-arena relative flex h-64 items-center justify-center sm:h-72">
          <div className="cb-boss-aura" style={{ backgroundImage: theme.aura }} />
          <div className="cb-boss-base" style={{ backgroundImage: theme.base }} />
          <img
            key={`${boss?.key}:${cycleSwap}`}
            src={art}
            alt={boss?.name ?? 'Clan Boss'}
            width={1024}
            height={1280}
            style={{ filter: theme.glow }}
            className={`cb-boss-art cb-enter ${impact ? (impact.kind === 'boss' ? 'cb-charge' : 'cb-hit') : ''}`}
          />
          <FloatingDamage events={events} />
        </div>
        <div className="relative mt-1 text-center">
          <b className="text-lg font-black tracking-[.14em] text-white drop-shadow-[0_2px_6px_rgba(0,0,0,.9)]">{boss?.name}</b>
          {boss?.subtitle ? <p className={`text-[9px] italic tracking-[.12em] ${theme.accent}`}>{boss.subtitle}</p> : null}
          <p className="mt-1 text-[8px] font-black tracking-[.28em] text-amber-300/90">
            {t('clanBoss.title')} • {t('clanBoss.cycle')} #{boss?.cycle ?? 1}
            {boss?.bossNumber ? ` • ${boss.bossNumber}/${data.totalBosses ?? 10}` : ''}
          </p>
          <div className="mt-2"><TurnIndicator phase={phase} idleLabel={t('clanBoss.waiting')} /></div>
        </div>


        {/* HP — bar eases, number stays exact */}
        <div className="relative mt-3">
          <div className="flex items-end justify-between text-[9px] tracking-[.2em] text-slate-200/80">
            <span>{t('clanBoss.hp')}</span>
            <span className="font-black text-white">{Math.round(boss?.currentHp ?? 0).toLocaleString()} / {Math.round(boss?.maxHp ?? 0).toLocaleString()}</span>
          </div>
          <div className="mt-1 h-5 overflow-hidden rounded-full border border-amber-200/30 bg-black/80 shadow-[inset_0_2px_8px_rgba(0,0,0,.9)]">
            <div className="cb-hpbar h-full transition-[width] duration-300" style={{ width: `${easedHp}%`, backgroundImage: theme.bar }} />
          </div>
        </div>

        {/* NEXT ATTACK — driven by the real cooldown, no extra timers */}
        <div className="relative mt-3 space-y-1 rounded-2xl border border-white/10 bg-black/55 p-2">
          <p className="text-[8px] font-black tracking-[.22em] text-slate-400">{t('clanBoss.nextAttack')}</p>
          <NextAttackBar
            label={t('clanBoss.playerSlot')}
            remainingMs={cooldownLeft}
            totalSeconds={boss?.cooldownSeconds ?? 1}
            readyLabel={t('clanBoss.ready')}
          />
        </div>
      </div>

      {/* Cycle reward preview — values come from the active boss template */}
      <div className="mt-2 grid grid-cols-3 gap-2">
        <Stat label={t('clanBoss.rewardFc')} value={abbreviateDamage(boss?.rewardFc)} tone="amber" />
        <Stat label={t('clanBoss.clanXp')} value={String(boss?.clanXpReward ?? 0)} tone="violet" />
        <Stat label={t('clanBoss.baseDamage')} value={abbreviateDamage(boss?.baseDamage)} tone="rose" />
      </div>

      {defeated ? (
        <div className="mt-3 rounded-3xl border border-amber-300/40 bg-amber-400/10 p-4 text-center">
          <b className="text-[12px] font-black tracking-[.16em] text-amber-200">{t('clanBoss.defeated')}</b>
          <p className="mt-2 text-[10px] text-slate-200">{t('clanBoss.clanDamage')}: <b>{Math.round(boss?.clanDamage ?? 0).toLocaleString()}</b></p>
          <p className="text-[10px] text-slate-200">{t('clanBoss.topDamage')}: <b>{data.ranking?.[0]?.name ?? '—'}</b></p>
          <p className="text-[10px] text-emerald-300">{t('clanBoss.clanXp')}: +{boss?.clanXpReward ?? 0}</p>
          <p className="text-[10px] text-amber-200">{t('clanBoss.rewardsReady')}</p>
          {boss?.isFinal ? <p className="mt-2 text-[10px] font-black tracking-[.14em] text-amber-100">{t('clanBoss.comingSoon')}</p> : null}
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
        <Stat label="DIFFICULTY" value={String(boss?.difficulty ?? '—')} tone="violet" />
        <Stat label={t('clanBoss.power')} value={abbreviateDamage(me?.power)} tone="cyan" />
      </div>

      <div className="mt-2 grid grid-cols-2 gap-2">
        <Stat label="BOSS POWER" value={abbreviateDamage(boss?.power)} tone="amber" />
        <Stat label="DAILY" value={`${data.daily?.defeated ?? 0} / ${data.daily?.limit ?? 4}`} tone="rose" />
      </div>


      {/* Season Pass benefit: offline Auto ATK (independent from the Global Boss) */}
      {(
        <div className={`mt-3 flex items-center justify-between gap-2 rounded-2xl border p-3 ${auto.active ? 'border-amber-300/50 bg-gradient-to-r from-amber-400/15 to-violet-500/10' : 'border-white/10 bg-black/60'}`}>
          <div className="min-w-0">
            <p className={`text-[11px] font-black uppercase tracking-[.18em] ${auto.active ? 'text-amber-200' : 'text-slate-300'}`}>
              {auto.eligible ? '⚔️' : '🔒'} {t('boss.autoAtk')}
            </p>
            <p className="mt-0.5 text-[9px] text-slate-300/80">
              {!auto.eligible
                ? t('boss.autoAtkRequired')
                : !auto.enabled
                  ? t('boss.autoAtkOff')
                  : auto.inClan === false
                    ? t('clan.error.notInClan')
                    : !auto.hasTeam
                      ? t('boss.autoAtkNoTeam')
                      : auto.bossActive === false
                        ? t('clanBoss.waiting')
                        : auto.waitingRevive
                          ? `${t('boss.autoAtkOffline')} · ${t('boss.autoAtkRevive')}`
                          /* single official countdown from the backend (cooldown + revive merged) */
                          : `${t('boss.autoAtkOffline')} · ${t('boss.autoAtkNext')} ${countdownLabel(auto.nextAttackAt, now)}`}
            </p>
          </div>
          {auto.eligible ? (
            <button
              type="button"
              disabled={autoBusy || !telegramInitData}
              onClick={async () => {
                setAutoBusy(true);
                try {
                  setAutoOverride(await setClanBossAutoAttack(telegramInitData, !auto.enabled));
                } catch (error) {
                  toast.error(error instanceof Error ? error.message : t('boss.autoAtkError'));
                } finally {
                  setAutoBusy(false);
                }
              }}
              className={`shrink-0 rounded-full px-4 py-2 text-[10px] font-black uppercase tracking-[.14em] transition active:scale-95 disabled:opacity-50 ${auto.enabled ? 'bg-gradient-to-b from-amber-300 to-orange-500 text-black' : 'border border-white/15 bg-black/60 text-slate-300'}`}
            >
              {auto.enabled ? t('boss.autoAtkOn') : t('boss.autoAtkOffLabel')}
            </button>
          ) : null}
        </div>
      )}

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
                <span className="min-w-0 flex-1 truncate text-[10px] text-white"><PlayerTag username={row.username} fallback={row.name}/></span>
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
            <div key={row.cycle} className="flex items-center gap-2 rounded-xl border border-white/10 bg-black/55 p-2">
              <img src={clanBossArt(row.bossKey)} alt="" loading="lazy" width={1024} height={1280} className="h-10 w-10 shrink-0 object-contain" />
              <div className="min-w-0 flex-1">
                <div className="flex justify-between text-[10px]">
                  <b className="text-violet-200">{t('clanBoss.cycle')} #{row.cycle} · {row.bossName ?? ''}</b>
                  <span className={row.status === 'defeated' ? 'text-emerald-300' : 'text-slate-400'}>
                    {row.status === 'defeated' ? t('clanBoss.historyDefeated') : t('clanBoss.historyExpired')}
                  </span>
                </div>
                <p className="text-[9px] text-slate-400">
                  {t('clanBoss.topDamage')}: {row.topName ? `@${row.topName}` : '—'}
                  {row.topDamage ? ` (${abbreviateDamage(row.topDamage)})` : ''} · {abbreviateDamage(row.totalDamage)} · {t('clanBoss.clanXp')} +{row.clanXp}
                </p>
              </div>
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

function Frame({ children, onClose, clan, cycle, bossKey }: { children: React.ReactNode; onClose: () => void; clan?: ClanBossState['clan']; cycle?: number; bossKey?: string }) {
  const t = useT();
  const theme = bossKey ? clanBossTheme(bossKey) : DEFAULT_CLAN_BOSS_THEME;
  return (
    <div className="fullscreen-page overflow-y-auto text-white" style={{ backgroundImage: theme.page }}>
      <div className="forge-safe-page mx-auto min-h-full w-full max-w-[480px] p-3">
        <header className="mb-3 flex items-center justify-between">
          <button onClick={onClose} className="grid h-10 w-10 place-items-center rounded-xl border border-amber-200/25 bg-black/50"><ArrowLeft /></button>
          <div className="flex items-center gap-2">
            {clan ? <ClanCrest emblem={clan.emblem} size={28} /> : null}
            <div className="text-center">
              <p className="text-[8px] tracking-[.28em] text-amber-300">{clan ? `[${clan.tag}] ${clan.name}` : 'MYTHREON'}</p>
              <b className="text-[12px] tracking-[.14em] text-white">{t('clanBoss.title')}</b>
              {cycle ? <p className={`text-[8px] tracking-[.2em] ${theme.accent}`}>{t('clanBoss.cycle')} #{cycle}</p> : null}
            </div>
          </div>
          <div className="grid h-10 w-10 place-items-center rounded-xl border border-amber-200/25 bg-black/50"><Sword className="h-4 w-4 text-amber-200" /></div>
        </header>
        {children}
      </div>
    </div>
  );
}

/** Compact entry card rendered inside the Clan Hub boss tab. */
export function ClanBossTeaser({ onOpen, bossKey, bossName }: { onOpen: () => void; bossKey?: string; bossName?: string }) {
  const t = useT();
  const theme = clanBossTheme(bossKey);
  return (
    <button type="button" onClick={onOpen} className={`relative z-10 w-full cursor-pointer overflow-hidden rounded-3xl border ${theme.border} p-3 text-left`} style={{ backgroundImage: `${theme.stage}, url(${theme.arena})`, backgroundSize: 'cover, cover', backgroundPosition: 'center, center' }}>
      <div className="relative flex items-center gap-3">
        <img src={theme.art} alt={bossName ?? 'Clan Boss'} loading="lazy" width={1024} height={1280} style={{ filter: theme.glow }} className="h-24 w-auto object-contain" />

        <div className="min-w-0 flex-1">
          <b className="block text-[12px] font-black tracking-[.12em] text-white">{(bossName ?? 'ABYSSAL WARLORD').toUpperCase()}</b>
          <p className="mt-1 flex items-center gap-1 text-[9px] text-amber-300/90"><Flame className="h-3 w-3" />{t('clanBoss.title')}</p>
          <p className="mt-1 flex items-center gap-1 text-[9px] text-slate-400"><Users className="h-3 w-3" />{t('clanBoss.participants')}</p>
          <span className="mt-2 inline-block rounded-xl border border-amber-200/40 bg-black/50 px-3 py-2 text-[9px] font-black tracking-[.16em] text-amber-100">{t('clanBoss.open')}</span>
        </div>
      </div>
    </button>
  );
}

