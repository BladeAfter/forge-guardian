import { useEffect, useMemo, useRef, useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import {
  ArrowUpRight,
  Bomb,
  Clock,
  Crosshair,
  Droplet,
  Eye,
  Flame,
  Ghost,
  Hammer,
  HeartPulse,
  MicOff,
  Orbit,
  ScrollText,
  Shield,
  ShieldCheck,
  ShieldPlus,
  Skull,
  Sparkles,
  Star,
  Sword,
  Swords,
  Target,
  Wand2,
  X,
  Zap,
} from 'lucide-react';
import { toast } from 'sonner';
import { useLanguage, useT } from '../LanguageContext';
import { fetchTacticalMatch, submitTacticalAction } from '../services';
import { BASIC_ATTACK, type TacticalMatch, type TacticalSkill, type TacticalUnit } from '../tactical';

const RARITY: Record<string, string> = { common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc', legendary: '#fbbf24', mythic: '#f472b6', ancestral: '#f97316', nft_exclusive: '#22d3ee' };
const needsTarget = (skill: TacticalSkill) => skill.target === 'SINGLE_ENEMY' || skill.target === 'SINGLE_ALLY';

type IconType = typeof Sword;

/** Visual identity only — the server keeps owning skill rules, damage and targets. */
const SKILL_ICONS: Record<string, IconType> = {
  basic_attack: Sword,
  heavy_strike: Hammer,
  rage: Flame,
  execute: Skull,
  shield_wall: Shield,
  taunt: Eye,
  fortify: ShieldPlus,
  precision_shot: Target,
  volley: ArrowUpRight,
  critical_focus: Crosshair,
  arcane_blast: Orbit,
  silence: MicOff,
  energy_surge: Zap,
  ambush: Ghost,
  bleed: Droplet,
  shadow_strike: Swords,
  heal: HeartPulse,
  cleanse: Sparkles,
  barrier: ShieldCheck,
};

const CLASS_ICONS: Record<string, IconType> = {
  warrior: Sword,
  knight: Shield,
  tank: Shield,
  guardian: ShieldCheck,
  archer: Target,
  ranger: Target,
  mage: Wand2,
  sorcerer: Wand2,
  assassin: Ghost,
  rogue: Ghost,
  support: HeartPulse,
  healer: HeartPulse,
  priest: HeartPulse,
};

type SkillFlavor = { label: string; ring: string; glow: string; text: string; tint: string };

const SKILL_FLAVORS: Record<string, SkillFlavor> = {
  DAMAGE: { label: 'Damage', ring: '#f97316', glow: 'rgba(249,115,22,.45)', text: '#fdba74', tint: 'rgba(249,115,22,.14)' },
  DOT: { label: 'Damage', ring: '#ef4444', glow: 'rgba(239,68,68,.45)', text: '#fca5a5', tint: 'rgba(239,68,68,.14)' },
  BUFF: { label: 'Buff', ring: '#facc15', glow: 'rgba(250,204,21,.4)', text: '#fde68a', tint: 'rgba(250,204,21,.12)' },
  SHIELD: { label: 'Buff', ring: '#38bdf8', glow: 'rgba(56,189,248,.4)', text: '#7dd3fc', tint: 'rgba(56,189,248,.12)' },
  DEBUFF: { label: 'Debuff', ring: '#c084fc', glow: 'rgba(192,132,252,.42)', text: '#d8b4fe', tint: 'rgba(192,132,252,.14)' },
  STUN: { label: 'Control', ring: '#22d3ee', glow: 'rgba(34,211,238,.42)', text: '#a5f3fc', tint: 'rgba(34,211,238,.12)' },
  HEAL: { label: 'Heal', ring: '#34d399', glow: 'rgba(52,211,153,.42)', text: '#6ee7b7', tint: 'rgba(52,211,153,.12)' },
  CLEANSE: { label: 'Heal', ring: '#5eead4', glow: 'rgba(94,234,212,.4)', text: '#99f6e4', tint: 'rgba(94,234,212,.12)' },
};

const flavorOf = (skill: TacticalSkill) => SKILL_FLAVORS[skill.type] ?? SKILL_FLAVORS.DAMAGE;

function UnitCard({
  unit,
  selectable,
  selected,
  hitAmount,
  onClick,
}: {
  unit: TacticalUnit;
  selectable: boolean;
  selected: boolean;
  hitAmount?: number;
  onClick: () => void;
}) {
  const pct = Math.max(0, Math.min(100, Math.round((unit.hp / Math.max(1, unit.maxHp)) * 100)));
  const accent = RARITY[String(unit.rarity || '').toLowerCase()] || '#64748b';
  const ClassIcon = CLASS_ICONS[String(unit.class || '').toLowerCase()] ?? Star;
  const bar = pct > 55 ? 'from-emerald-400 to-lime-300' : pct > 25 ? 'from-amber-300 to-orange-400' : 'from-rose-500 to-red-400';
  return (
    <button
      type="button"
      disabled={!selectable}
      onClick={onClick}
      className={`tac-unit ${selectable ? 'tac-unit--selectable' : ''} ${selected ? 'tac-unit--selected' : ''} ${unit.alive ? '' : 'tac-unit--ko'}`}
      style={{ ['--tac-accent' as string]: accent }}
    >
      <div className="tac-unit__frame">
        <img src={unit.image} alt={unit.name} className="tac-unit__art" loading="lazy" />
        <div className="tac-unit__vignette" />
        {!unit.alive ? (
          <div className="tac-unit__ko">
            <Skull className="h-5 w-5 text-rose-300" />
            <span>KO</span>
          </div>
        ) : null}
        {selected ? <span className="tac-unit__reticle" /> : null}
        {unit.shield > 0 ? <span className="tac-unit__shield">🛡 {Math.round(unit.shield)}</span> : null}
        <span className="tac-unit__class">
          <ClassIcon className="h-[9px] w-[9px]" />
        </span>
        {hitAmount ? <span className="tac-unit__hit">-{Math.round(hitAmount).toLocaleString()}</span> : null}
      </div>
      <p className="tac-unit__name">{unit.name}</p>
      <div className="tac-unit__hpTrack">
        <div className={`tac-unit__hpFill bg-gradient-to-r ${bar}`} style={{ width: `${pct}%` }} />
      </div>
      <p className="tac-unit__hpText">
        {Math.max(0, Math.round(unit.hp)).toLocaleString()}
        <span className="text-slate-500">/{Math.round(unit.maxHp).toLocaleString()}</span>
      </p>
      {unit.statuses?.length ? <span className="tac-unit__status">{unit.statuses.map((s) => s.key).join(' · ')}</span> : null}
    </button>
  );
}

/**
 * 3v3 turn UI. Every 1.2s it re-reads the authoritative match state, so the
 * opponent's turn, the 15s auto Basic Attack and the winner all come from the
 * server — this screen never simulates anything.
 */
export function TacticalBattleScreen({ initData, matchId, onExit }: { initData: string; matchId: string; onExit: () => void }) {
  const t = useT();
  const { tError } = useLanguage();
  const [skillKey, setSkillKey] = useState<string>('basic_attack');
  const [target, setTarget] = useState<string | null>(null);
  const [logOpen, setLogOpen] = useState(false);
  const [hits, setHits] = useState<Record<string, number>>({});
  const lastTurn = useRef(0);
  const hpRef = useRef<Record<string, number>>({});

  const match = useQuery<TacticalMatch>({
    queryKey: ['tactical-match', matchId],
    queryFn: () => fetchTacticalMatch(initData, matchId),
    refetchInterval: (query) => (query.state.data?.status === 'active' ? 1200 : false),
    refetchOnWindowFocus: true,
  });

  const data = match.data;
  useEffect(() => {
    if (data && data.turn !== lastTurn.current) {
      lastTurn.current = data.turn;
      setSkillKey('basic_attack');
      setTarget(null);
    }
  }, [data]);

  // Presentation only: floating damage numbers derived from HP deltas.
  useEffect(() => {
    if (!data) return;
    const next: Record<string, number> = {};
    const fresh: Record<string, number> = {};
    Object.values(data.units ?? {}).forEach((u) => {
      const prev = hpRef.current[u.uid];
      next[u.uid] = u.hp;
      if (prev !== undefined && prev - u.hp > 0) fresh[u.uid] = prev - u.hp;
    });
    hpRef.current = next;
    if (Object.keys(fresh).length) {
      setHits(fresh);
      const timer = setTimeout(() => setHits({}), 900);
      return () => clearTimeout(timer);
    }
  }, [data]);

  const submit = useMutation({
    mutationFn: (payload: { skillKey: string; targetUid: string | null }) =>
      submitTacticalAction(initData, matchId, payload.skillKey, payload.targetUid, `${matchId}:${data?.turn ?? 0}`),
    onSuccess: (next) => match.refetch().then(() => next),
    onError: (error) => toast.error(tError(error)),
  });

  const deck = useMemo<TacticalSkill[]>(() => [BASIC_ATTACK, ...(data?.deck ?? [])], [data?.deck]);
  const skill = deck.find((s) => s.skillKey === skillKey) ?? BASIC_ATTACK;
  const units = useMemo(() => Object.values(data?.units ?? {}), [data?.units]);
  const mine = units.filter((u) => u.side === data?.side).sort((a, b) => a.slot - b.slot);
  const foes = units.filter((u) => u.side !== data?.side).sort((a, b) => a.slot - b.slot);

  if (match.isLoading || !data)
    return (
      <div className="grid min-h-[60dvh] place-items-center">
        <p className="animate-pulse text-xs font-black uppercase tracking-[.2em] text-amber-200">{t('tactical.title')}</p>
      </div>
    );

  const finished = data.status !== 'active';
  const canSelectTarget = !finished && !data.submitted && needsTarget(skill);
  const targets = skill.target === 'SINGLE_ALLY' ? mine : foes;
  const ready = !needsTarget(skill) || Boolean(target);
  const sum = (list: TacticalUnit[], key: 'hp' | 'maxHp') => list.reduce((total, u) => total + Math.max(0, u[key]), 0);
  const mineHp = sum(mine, 'hp');
  const foesHp = sum(foes, 'hp');
  const tug = Math.max(4, Math.min(96, Math.round((mineHp / Math.max(1, mineHp + foesHp)) * 100)));
  const timerPct = Math.max(0, Math.min(100, Math.round((data.secondsLeft / Math.max(1, data.turnTimerSeconds || 15)) * 100)));

  return (
    <div className="tac-arena forge-safe-page mx-auto w-full max-w-md px-3 pb-6">
      <div className="tac-arena__bg" aria-hidden>
        <span className="tac-arena__glow" />
        <span className="tac-arena__floor" />
        <span className="tac-arena__fog" />
        <span className="tac-arena__dust" />
      </div>

      <header className="relative pt-3">
        <div className="flex items-center justify-between">
          <div className="min-w-0">
            <p className="tac-title">{t('tactical.battleTitle')}</p>
            <p className="truncate text-[10px] font-bold text-slate-400">
              {data.you} <span className="text-slate-600">vs</span> {data.opponent}
            </p>
          </div>
          <div className="flex items-center gap-1.5">
            {data.log?.length ? (
              <button type="button" onClick={() => setLogOpen(true)} aria-label={t('tactical.log')} className="tac-chip">
                <ScrollText className="h-3 w-3" />
              </button>
            ) : null}
            {!finished ? (
              <span className="tac-chip tac-chip--timer">
                <Clock className="h-3 w-3" /> {data.secondsLeft}s
              </span>
            ) : null}
            <button type="button" onClick={onExit} aria-label="close" className="tac-chip">
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>

        <div className="mt-2 flex items-center gap-2">
          <span className="text-[9px] font-black uppercase tracking-[.18em] text-amber-300/90">{t('tactical.turn', { turn: data.turn })}</span>
          <div className="tac-tug">
            <div className="tac-tug__mine" style={{ width: `${tug}%` }} />
            <div className="tac-tug__marker" style={{ left: `${tug}%` }} />
          </div>
        </div>
        {!finished ? (
          <div className="tac-timer">
            <div className="tac-timer__fill" style={{ width: `${timerPct}%` }} />
          </div>
        ) : null}
      </header>

      {Number(data.damageScale) > 1 ? (
        <p className="relative mt-2 rounded-xl border border-orange-400/30 bg-orange-500/10 px-3 py-1 text-center text-[9px] font-black uppercase tracking-[.1em] text-orange-200">
          {t('tactical.stalemate', { scale: Number(data.damageScale).toFixed(2) })}
        </p>
      ) : null}

      <section className="relative mt-3">
        <p className="tac-sideLabel text-rose-300/90">{t('tactical.enemyTeam')}</p>
        <div className="grid grid-cols-3 gap-2">
          {foes.map((u) => (
            <UnitCard
              key={u.uid}
              unit={u}
              hitAmount={hits[u.uid]}
              selectable={canSelectTarget && targets.includes(u) && u.alive}
              selected={target === u.uid}
              onClick={() => setTarget(u.uid)}
            />
          ))}
        </div>

        <div className="tac-divider">
          <Swords className="h-3.5 w-3.5 text-amber-300/80" />
        </div>

        <p className="tac-sideLabel text-emerald-300/90">{t('tactical.yourTeam')}</p>
        <div className="grid grid-cols-3 gap-2">
          {mine.map((u) => (
            <UnitCard
              key={u.uid}
              unit={u}
              hitAmount={hits[u.uid]}
              selectable={canSelectTarget && targets.includes(u) && u.alive}
              selected={target === u.uid}
              onClick={() => setTarget(u.uid)}
            />
          ))}
        </div>
      </section>

      {finished ? (
        <section className="tac-panel relative mt-4 p-5 text-center">
          <p className={`text-2xl font-black ${data.winner === 'you' ? 'text-emerald-300' : data.winner === 'opponent' ? 'text-rose-300' : 'text-slate-200'}`}>
            {data.winner === 'you' ? t('tactical.victory') : data.winner === 'opponent' ? t('tactical.defeat') : t('tactical.draw')}
          </p>
          {data.ratingDelta !== null && !data.practice ? (
            <p className="mt-1 text-[11px] font-bold text-amber-200">{t('tactical.ratingDelta', { delta: `${Number(data.ratingDelta) > 0 ? '+' : ''}${data.ratingDelta}` })}</p>
          ) : null}
          <button type="button" onClick={onExit} className="tac-confirm mt-4">
            {t('tactical.continue')}
          </button>
        </section>
      ) : (
        <section className="tac-panel relative mt-3 p-3">
          <p className="text-center text-[9px] font-black uppercase tracking-[.22em] text-slate-400">
            {data.submitted ? t('tactical.waitingOpponent') : needsTarget(skill) && !target ? t('tactical.selectTarget') : t('tactical.pickSkill')}
          </p>

          <div className="mt-2.5 grid grid-cols-2 gap-2">
            {deck.map((s) => {
              const cd = Number(data.cooldowns?.[s.skillKey] ?? 0);
              const disabled = data.submitted || cd > 0 || submit.isPending;
              const active = skillKey === s.skillKey;
              const flavor = flavorOf(s);
              const Icon = SKILL_ICONS[s.skillKey] ?? Sparkles;
              return (
                <button
                  key={s.skillKey}
                  type="button"
                  disabled={disabled}
                  onClick={() => {
                    setSkillKey(s.skillKey);
                    setTarget(null);
                  }}
                  className={`tac-skill ${active ? 'tac-skill--active' : ''}`}
                  style={{
                    ['--tac-ring' as string]: flavor.ring,
                    ['--tac-glow' as string]: flavor.glow,
                    ['--tac-tint' as string]: flavor.tint,
                  }}
                >
                  <span className="tac-skill__icon">
                    <Icon className="h-[18px] w-[18px]" style={{ color: flavor.ring }} />
                  </span>
                  <b className="tac-skill__name">{t(s.nameKey)}</b>
                  <p className="tac-skill__meta" style={{ color: flavor.text }}>
                    {flavor.label}
                    {s.multiplier ? ` • x${Number(s.multiplier).toFixed(2)}` : s.duration ? ` • ${s.duration}T` : ''}
                  </p>
                  {cd > 0 ? <span className="tac-skill__cd">{t('tactical.cooldown', { turns: cd })}</span> : null}
                </button>
              );
            })}
          </div>

          <button
            type="button"
            disabled={data.submitted || submit.isPending || !ready}
            onClick={() => submit.mutate({ skillKey, targetUid: needsTarget(skill) ? target : null })}
            className="tac-confirm mt-3"
          >
            {data.submitted ? t('tactical.waitingOpponent') : t('tactical.confirmAction')}
          </button>
          <p className="mt-1.5 text-center text-[8px] font-semibold tracking-[.08em] text-slate-500">{t('tactical.autoIn', { seconds: data.secondsLeft })}</p>
        </section>
      )}

      {logOpen ? (
        <div className="fixed inset-0 z-50 flex items-end bg-black/75 p-3 backdrop-blur-sm" onClick={() => setLogOpen(false)}>
          <div className="tac-panel max-h-[70dvh] w-full overflow-y-auto p-3" onClick={(event) => event.stopPropagation()}>
            <div className="mb-2 flex items-center justify-between">
              <p className="text-[10px] font-black uppercase tracking-[.2em] text-amber-200">{t('tactical.log')}</p>
              <button type="button" onClick={() => setLogOpen(false)} aria-label="close" className="tac-chip">
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
            <div className="space-y-1.5">
              {data.log
                .slice()
                .reverse()
                .map((entry) => (
                  <div key={entry.turn} className="rounded-xl border border-white/8 bg-black/45 p-2">
                    <b className="text-[9px] font-black uppercase tracking-[.14em] text-amber-200">{t('tactical.turn', { turn: entry.turn })}</b>
                    {(entry.entries as { text?: string; actor?: string; skill?: string; target?: string; amount?: number }[]).map((line, index) => (
                      <p key={index} className="text-[9px] text-slate-300">
                        {line.text ?? `${line.actor ?? ''} ${line.skill ?? ''} ${line.target ?? ''} ${line.amount ? `(${Math.round(line.amount)})` : ''}`}
                      </p>
                    ))}
                  </div>
                ))}
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
