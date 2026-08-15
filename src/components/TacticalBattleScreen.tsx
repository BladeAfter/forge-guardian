import { useEffect, useMemo, useRef, useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { Clock, Swords, X } from 'lucide-react';
import { toast } from 'sonner';
import { useLanguage, useT } from '../LanguageContext';
import { fetchTacticalMatch, submitTacticalAction } from '../services';
import { BASIC_ATTACK, type TacticalMatch, type TacticalSkill, type TacticalUnit } from '../tactical';

const RARITY: Record<string, string> = { common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc', legendary: '#fbbf24', mythic: '#f472b6', ancestral: '#f97316', nft_exclusive: '#22d3ee' };
const needsTarget = (skill: TacticalSkill) => skill.target === 'SINGLE_ENEMY' || skill.target === 'SINGLE_ALLY';

function UnitCard({ unit, selectable, selected, onClick }: { unit: TacticalUnit; selectable: boolean; selected: boolean; onClick: () => void }) {
  const pct = Math.max(0, Math.min(100, Math.round((unit.hp / Math.max(1, unit.maxHp)) * 100)));
  return (
    <button
      type="button"
      disabled={!selectable}
      onClick={onClick}
      className={`relative overflow-hidden rounded-2xl border bg-black/70 p-1 text-left transition ${unit.alive ? '' : 'grayscale opacity-45'} ${selectable ? 'ring-1 ring-amber-300/40' : ''} ${selected ? 'ring-2 ring-amber-300' : ''}`}
      style={{ borderColor: selected ? '#fbbf24' : RARITY[String(unit.rarity || '').toLowerCase()] || '#475569' }}
    >
      <img src={unit.image} alt={unit.name} className="aspect-square w-full rounded-xl object-cover" />
      <p className="truncate px-1 pt-1 text-[9px] font-black text-slate-100">{unit.name}</p>
      <div className="mx-1 mt-1 h-[5px] overflow-hidden rounded-full bg-black/70">
        <div className="h-full rounded-full bg-gradient-to-r from-emerald-400 to-lime-300" style={{ width: `${pct}%` }} />
      </div>
      <p className="px-1 text-[8px] font-bold text-slate-300">
        {Math.max(0, Math.round(unit.hp)).toLocaleString()}/{Math.round(unit.maxHp).toLocaleString()}
      </p>
      <p className="px-1 pb-1 text-[8px] uppercase tracking-[.1em] text-slate-500">{unit.class}</p>
      {unit.shield > 0 ? <span className="absolute right-1 top-1 rounded-full bg-sky-500/80 px-1.5 py-[1px] text-[7px] font-black text-black">🛡 {Math.round(unit.shield)}</span> : null}
      {unit.statuses?.length ? (
        <span className="absolute left-1 top-1 rounded-full bg-fuchsia-500/80 px-1.5 py-[1px] text-[7px] font-black uppercase text-black">{unit.statuses.map((s) => s.key).join(' ')}</span>
      ) : null}
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
  const lastTurn = useRef(0);

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

  return (
    <div className="forge-safe-page mx-auto w-full max-w-md px-3 pb-8">
      <header className="flex items-center justify-between py-3">
        <div>
          <p className="text-[10px] font-black uppercase tracking-[.2em] text-amber-300">{t('tactical.turn', { turn: data.turn })}</p>
          <p className="text-[11px] font-bold text-slate-300">
            {data.you} <span className="text-slate-500">vs</span> {data.opponent}
          </p>
        </div>
        <div className="flex items-center gap-2">
          {!finished ? (
            <span className="inline-flex items-center gap-1 rounded-full border border-white/15 bg-black/50 px-2 py-1 text-[10px] font-black text-amber-200">
              <Clock className="h-3 w-3" /> {data.secondsLeft}s
            </span>
          ) : null}
          <button type="button" onClick={onExit} aria-label="close">
            <X className="h-4 w-4 text-slate-300" />
          </button>
        </div>
      </header>

      {Number(data.damageScale) > 1 ? (
        <p className="mb-2 rounded-xl border border-orange-400/40 bg-orange-500/10 px-3 py-1 text-center text-[9px] font-black uppercase tracking-[.1em] text-orange-200">
          {t('tactical.stalemate', { scale: Number(data.damageScale).toFixed(2) })}
        </p>
      ) : null}

      <p className="mb-1 text-[9px] font-black uppercase tracking-[.2em] text-rose-300">{t('tactical.enemyTeam')}</p>
      <div className="grid grid-cols-3 gap-2">
        {foes.map((u) => (
          <UnitCard key={u.uid} unit={u} selectable={canSelectTarget && targets.includes(u) && u.alive} selected={target === u.uid} onClick={() => setTarget(u.uid)} />
        ))}
      </div>

      <p className="mb-1 mt-4 text-[9px] font-black uppercase tracking-[.2em] text-emerald-300">{t('tactical.yourTeam')}</p>
      <div className="grid grid-cols-3 gap-2">
        {mine.map((u) => (
          <UnitCard key={u.uid} unit={u} selectable={canSelectTarget && targets.includes(u) && u.alive} selected={target === u.uid} onClick={() => setTarget(u.uid)} />
        ))}
      </div>

      {finished ? (
        <section className="mt-5 rounded-2xl border border-amber-300/35 bg-black/60 p-5 text-center">
          <p className={`text-2xl font-black ${data.winner === 'you' ? 'text-emerald-300' : data.winner === 'opponent' ? 'text-rose-300' : 'text-slate-200'}`}>
            {data.winner === 'you' ? t('tactical.victory') : data.winner === 'opponent' ? t('tactical.defeat') : t('tactical.draw')}
          </p>
          {data.ratingDelta !== null && !data.practice ? (
            <p className="mt-1 text-[11px] font-bold text-amber-200">{t('tactical.ratingDelta', { delta: `${Number(data.ratingDelta) > 0 ? '+' : ''}${data.ratingDelta}` })}</p>
          ) : null}
          <button type="button" onClick={onExit} className="mt-4 w-full rounded-2xl bg-gradient-to-b from-amber-300 to-orange-500 py-3 text-xs font-black uppercase tracking-[.12em] text-black">
            {t('tactical.continue')}
          </button>
        </section>
      ) : (
        <section className="mt-4 rounded-2xl border border-white/10 bg-black/55 p-3">
          <p className="text-[9px] font-black uppercase tracking-[.15em] text-slate-400">
            {data.submitted ? t('tactical.waitingOpponent') : needsTarget(skill) && !target ? t('tactical.pickTarget') : t('tactical.pickSkill')}
          </p>
          <div className="mt-2 grid grid-cols-2 gap-2">
            {deck.map((s) => {
              const cd = Number(data.cooldowns?.[s.skillKey] ?? 0);
              const disabled = data.submitted || cd > 0 || submit.isPending;
              return (
                <button
                  key={s.skillKey}
                  type="button"
                  disabled={disabled}
                  onClick={() => {
                    setSkillKey(s.skillKey);
                    setTarget(null);
                  }}
                  className={`rounded-xl border px-2 py-2 text-left disabled:opacity-40 ${skillKey === s.skillKey ? 'border-amber-300 bg-amber-500/15' : 'border-white/12 bg-black/40'}`}
                >
                  <b className="block truncate text-[10px] text-slate-100">{t(s.nameKey)}</b>
                  <p className="text-[8px] uppercase tracking-[.1em] text-slate-400">
                    {s.type} {s.multiplier ? `· x${Number(s.multiplier).toFixed(2)}` : ''}
                  </p>
                  {cd > 0 ? <p className="text-[8px] font-black text-rose-300">{t('tactical.cooldown', { turns: cd })}</p> : null}
                </button>
              );
            })}
          </div>
          <button
            type="button"
            disabled={data.submitted || submit.isPending || !ready}
            onClick={() => submit.mutate({ skillKey, targetUid: needsTarget(skill) ? target : null })}
            className="mt-3 w-full rounded-2xl bg-gradient-to-b from-amber-300 to-orange-500 py-3 text-xs font-black uppercase tracking-[.12em] text-black disabled:grayscale disabled:opacity-40"
          >
            <Swords className="mr-2 inline h-4 w-4" />
            {data.submitted ? t('tactical.waitingOpponent') : t('tactical.confirm')}
          </button>
          <p className="mt-2 text-center text-[9px] text-slate-500">{t('tactical.autoIn', { seconds: data.secondsLeft })}</p>
        </section>
      )}

      {data.log?.length ? (
        <section className="mt-4 rounded-2xl border border-white/10 bg-black/45 p-3">
          <p className="text-[9px] font-black uppercase tracking-[.15em] text-slate-400">{t('tactical.log')}</p>
          <div className="mt-1 max-h-40 space-y-1 overflow-y-auto">
            {data.log
              .slice()
              .reverse()
              .map((entry) => (
                <div key={entry.turn} className="rounded-lg bg-black/40 p-2">
                  <b className="text-[9px] text-amber-200">{t('tactical.turn', { turn: entry.turn })}</b>
                  {(entry.entries as { text?: string; actor?: string; skill?: string; target?: string; amount?: number; kind?: string }[]).map((line, index) => (
                    <p key={index} className="text-[9px] text-slate-300">
                      {line.text ?? `${line.actor ?? ''} ${line.skill ?? ''} ${line.target ?? ''} ${line.amount ? `(${Math.round(line.amount)})` : ''}`}
                    </p>
                  ))}
                </div>
              ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
