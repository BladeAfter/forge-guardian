import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ChevronsRight, Cloud, Flame, Heart, Leaf, Moon, Orbit, Shield, Skull, Snowflake,
  Sparkles, Swords, Wind, X, Zap,
} from 'lucide-react';
import type { FamiliarHuntResult } from '../services';
import { abilityKitFor, TONE_STYLE, type Ability } from './familiarHuntAbilities';

const ARENA = '/assets/game/familiar-hunt/hunt-arena.jpg';

const ICONS: Record<string, typeof Flame> = {
  flame: Flame, snowflake: Snowflake, leaf: Leaf, shield: Shield, heart: Heart,
  zap: Zap, moon: Moon, orbit: Orbit, sparkles: Sparkles, swords: Swords, wind: Wind,
  cloud: Cloud, skull: Skull,
};

type Float = { id: number; unit: string; text: string; tone: 'damage' | 'crit' | 'heal' | 'buff' };
type Queued = { damage: number; crit: boolean; target: number };

const fmt = (value: number) => Math.round(value).toLocaleString('pt-BR');
const wait = (ms: number) => new Promise<void>((resolve) => window.setTimeout(resolve, ms));

/**
 * ⚔️ FAMILIAR HUNT — FULLSCREEN TURN-BASED BATTLE SCENE.
 * The fight was already resolved server-side; this scene *plays back* the authoritative
 * combat log through a Pokémon-style turn flow: pet 1 → pet 2 → pet 3 → enemy turn.
 * Ability choices are presentation only — they never invent damage or rewards.
 */
export function FamiliarHuntBattle({ result, missionName, onFinished, onExit }: {
  result: FamiliarHuntResult;
  missionName?: string;
  onFinished: () => void;
  onExit?: () => void;
}) {
  const petMax = useMemo(() => result.team.map((pet) => Math.max(1, pet.maxHp)), [result.runId]);
  const enemyMax = useMemo(() => result.enemies.map((enemy) => Math.max(1, enemy.maxHp)), [result.runId]);

  const [petHp, setPetHp] = useState<number[]>(() => petMax.slice());
  const [enemyHp, setEnemyHp] = useState<number[]>(() => enemyMax.slice());
  const [round, setRound] = useState(1);
  const [activeSlot, setActiveSlot] = useState(0);
  const [phase, setPhase] = useState<'pets' | 'enemy' | 'done'>('pets');
  const [busy, setBusy] = useState(false);
  const [auto, setAuto] = useState(false);
  const [speed, setSpeed] = useState<1 | 2>(1);
  const [floats, setFloats] = useState<Float[]>([]);
  const [hit, setHit] = useState<string | null>(null);
  const [casting, setCasting] = useState<{ slot: number; ability: Ability } | null>(null);
  const [shielded, setShielded] = useState(false);
  const [banner, setBanner] = useState<string | null>(null);

  const floatId = useRef(0);
  const finished = useRef(false);

  // authoritative log split into per-pet and enemy queues
  const queues = useRef<{ pets: Queued[][]; enemies: Queued[] }>({ pets: [], enemies: [] });
  useEffect(() => {
    const pets: Queued[][] = result.team.map(() => []);
    const enemies: Queued[] = [];
    for (const event of result.log ?? []) {
      const row = { damage: event.damage, crit: event.crit, target: event.target };
      if (event.side === 'pet') (pets[event.actor] ??= []).push(row);
      else enemies.push(row);
    }
    queues.current = { pets, enemies };
  }, [result.runId]);

  const pushFloat = useCallback((unit: string, text: string, tone: Float['tone']) => {
    const id = (floatId.current += 1);
    setFloats((current) => [...current, { id, unit, text, tone }]);
    window.setTimeout(() => setFloats((current) => current.filter((row) => row.id !== id)), 900);
  }, []);

  const flash = useCallback((unit: string) => {
    setHit(unit);
    window.setTimeout(() => setHit(null), 240);
  }, []);

  const finish = useCallback(async () => {
    if (finished.current) return;
    finished.current = true;
    setPhase('done');
    setBanner(result.victory ? 'INIMIGOS DERROTADOS' : 'EQUIPE CAIU EM COMBATE');
    await wait(900);
    onFinished();
  }, [onFinished, result.victory]);

  const step = 620 / speed;

  const runEnemyTurn = useCallback(async (currentEnemyHp: number[], currentPetHp: number[]) => {
    setPhase('enemy');
    setBanner('TURNO DOS INIMIGOS');
    await wait(step * 0.6);
    const pets = currentPetHp.slice();
    const attacks = Math.max(1, result.enemies.filter((_, index) => (currentEnemyHp[index] ?? 0) > 0).length);
    for (let index = 0; index < attacks; index += 1) {
      const next = queues.current.enemies.shift();
      if (!next) break;
      let slot = next.target;
      if ((pets[slot] ?? 0) <= 0) slot = pets.findIndex((hp) => hp > 0);
      if (slot < 0) break;
      const damage = shielded ? next.damage * 0.6 : next.damage;
      pets[slot] = Math.max(0, (pets[slot] ?? 0) - damage);
      setPetHp(pets.slice());
      pushFloat(`p${slot}`, `-${fmt(damage)}`, next.crit ? 'crit' : 'damage');
      flash(`p${slot}`);
      if (pets[slot] <= 0) pushFloat(`p${slot}`, 'KO', 'damage');
      await wait(step);
    }
    setShielded(false);
    if (pets.every((hp) => hp <= 0)) { await finish(); return; }
    const first = pets.findIndex((hp) => hp > 0);
    setRound((value) => value + 1);
    setActiveSlot(first < 0 ? 0 : first);
    setPhase('pets');
    setBanner(null);
  }, [finish, flash, pushFloat, result.enemies, shielded, step]);

  const advance = useCallback(async (currentEnemyHp: number[], currentPetHp: number[], slot: number) => {
    if (currentEnemyHp.every((hp) => hp <= 0)) { await finish(); return; }
    const nextSlot = currentPetHp.findIndex((hp, index) => index > slot && hp > 0);
    if (nextSlot >= 0) {
      setActiveSlot(nextSlot);
      setBanner(null);
      return;
    }
    const petsExhausted = queues.current.pets.every((rows) => rows.length === 0);
    if (petsExhausted && queues.current.enemies.length === 0) { await finish(); return; }
    await runEnemyTurn(currentEnemyHp, currentPetHp);
  }, [finish, runEnemyTurn]);

  const cast = useCallback(async (slot: number, ability: Ability) => {
    if (busy || phase !== 'pets') return;
    setBusy(true);
    setCasting({ slot, ability });
    setBanner(`${result.team[slot]?.name ?? 'FAMILIAR'} · ${ability.name}`);
    await wait(step * 0.45);

    let nextEnemyHp = enemyHp.slice();
    let nextPetHp = petHp.slice();

    if (ability.kind === 'support') {
      nextPetHp = nextPetHp.map((hp, index) => (hp > 0 ? Math.min(petMax[index] ?? hp, hp + (petMax[index] ?? 0) * 0.08) : hp));
      setPetHp(nextPetHp);
      setShielded(true);
      nextPetHp.forEach((hp, index) => { if (hp > 0) pushFloat(`p${index}`, `+${fmt((petMax[index] ?? 0) * 0.08)}`, 'heal'); });
      pushFloat(`p${slot}`, 'ESCUDO', 'buff');
    } else {
      const queued = queues.current.pets[slot]?.shift();
      const target = (() => {
        const preferred = queued?.target ?? 0;
        if ((nextEnemyHp[preferred] ?? 0) > 0) return preferred;
        return nextEnemyHp.findIndex((hp) => hp > 0);
      })();
      const damage = queued?.damage ?? Math.max(1, (result.team[slot]?.atk ?? 1) * (ability.kind === 'special' ? 1.6 : 1));
      if (target >= 0) {
        nextEnemyHp[target] = Math.max(0, (nextEnemyHp[target] ?? 0) - damage);
        setEnemyHp(nextEnemyHp.slice());
        pushFloat(`e${target}`, `${queued?.crit || ability.kind === 'special' ? 'CRIT ' : ''}-${fmt(damage)}`, queued?.crit || ability.kind === 'special' ? 'crit' : 'damage');
        flash(`e${target}`);
      }
    }

    await wait(step * 0.8);
    setCasting(null);
    setBusy(false);
    await advance(nextEnemyHp, nextPetHp, slot);
  }, [advance, busy, enemyHp, flash, petHp, petMax, phase, pushFloat, result.team, step]);

  // AUTO — picks abilities for the player, weighted toward attacks.
  useEffect(() => {
    if (!auto || busy || phase !== 'pets') return;
    const pet = result.team[activeSlot];
    if (!pet) return;
    const kit = abilityKitFor(pet.name, activeSlot);
    const pick = kit.abilities[Math.random() < 0.18 ? 1 : Math.random() < 0.4 ? 2 : 0];
    const timer = window.setTimeout(() => void cast(activeSlot, pick), step * 0.5);
    return () => window.clearTimeout(timer);
  }, [auto, busy, phase, activeSlot, cast, result.team, step]);

  const activePet = result.team[activeSlot];
  const kit = activePet ? abilityKitFor(activePet.name, activeSlot) : null;
  const unitFloats = (unit: string) => floats.filter((row) => row.unit === unit);

  return (
    <div className="fixed inset-0 z-[140] flex flex-col overflow-hidden bg-[#03060d]">
      {/* ── arena backdrop ─────────────────────────────── */}
      <div className="absolute inset-0" style={{ backgroundImage: `url(${ARENA})`, backgroundSize: 'cover', backgroundPosition: 'center' }} />
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_18%,rgba(56,189,248,.16),rgba(3,6,13,.93)_62%)]" />
      <div className="absolute inset-x-0 top-0 h-40 bg-gradient-to-b from-black/85 to-transparent" />
      <div className="absolute inset-x-0 bottom-0 h-72 bg-gradient-to-t from-black/95 via-black/70 to-transparent" />

      {/* ── top bar ────────────────────────────────────── */}
      <header className="relative z-10 flex flex-none items-center justify-between px-4 pt-[max(env(safe-area-inset-top),0.75rem)]">
        <div className="min-w-0">
          <p className="truncate text-[10px] font-black uppercase tracking-[.24em] text-amber-200/90">{missionName || 'FAMILIAR HUNT'}</p>
          <p className="text-[9px] font-bold uppercase tracking-[.2em] text-slate-500">RODADA {round}</p>
        </div>
        <div className="flex items-center gap-1.5">
          <button
            type="button"
            onClick={() => setAuto((value) => !value)}
            className={`rounded-full border px-2.5 py-1 text-[8px] font-black uppercase tracking-[.14em] transition active:scale-95 ${auto ? 'border-emerald-300/60 bg-emerald-300/15 text-emerald-200' : 'border-white/15 bg-black/50 text-slate-400'}`}
          >
            AUTO
          </button>
          <button
            type="button"
            onClick={() => setSpeed((value) => (value === 1 ? 2 : 1))}
            className="rounded-full border border-sky-300/40 bg-black/50 px-2.5 py-1 text-[8px] font-black uppercase tracking-[.14em] text-sky-200 transition active:scale-95"
          >
            x{speed}
          </button>
          <button
            type="button"
            onClick={() => void finish()}
            className="flex items-center gap-1 rounded-full border border-amber-300/45 bg-black/50 px-2.5 py-1 text-[8px] font-black uppercase tracking-[.14em] text-amber-200 transition active:scale-95"
          >
            <ChevronsRight className="h-3 w-3" /> SKIP
          </button>
          {onExit ? (
            <button type="button" onClick={onExit} className="grid h-6 w-6 place-items-center rounded-full border border-white/15 bg-black/50 text-slate-400">
              <X className="h-3 w-3" />
            </button>
          ) : null}
        </div>
      </header>

      {/* ── stage: enemies + banner + team, always fits the viewport ── */}
      <div className="relative z-10 flex min-h-0 flex-1 flex-col justify-between gap-1 py-2">
      <section className="relative z-10 flex-none px-4">
        <div className="flex items-end justify-center gap-3">
          {result.enemies.map((enemy, index) => {
            const unit = `e${index}`;
            const hp = enemyHp[index] ?? 0;
            const dead = hp <= 0;
            return (
              <div key={unit} className={`relative flex-1 transition-all duration-200 ${dead ? 'translate-y-2 opacity-20 grayscale' : ''} ${hit === unit ? 'translate-y-1.5 scale-[.96]' : ''}`}>
                {unitFloats(unit).map((row) => (
                  <FloatText key={row.id} row={row} />
                ))}
                {hit === unit ? <div className="pointer-events-none absolute inset-0 z-10 rounded-3xl bg-white/40 mix-blend-screen" /> : null}
                {enemy.image ? (
                  <img
                    src={enemy.image}
                    alt={enemy.name}
                    className={`mx-auto object-contain drop-shadow-[0_0_26px_rgba(244,63,94,.5)] ${enemy.elite ? 'h-[15vh] max-h-36 min-h-16' : 'h-[11vh] max-h-24 min-h-12'}`}
                  />
                ) : null}
                <p className="truncate text-center text-[8px] font-black uppercase tracking-[.12em] text-rose-200">{enemy.name}</p>
                <Bar value={hp} max={enemyMax[index] ?? 1} tone="rose" />
                <p className="text-center text-[7px] font-bold tracking-wider text-slate-500">{fmt(hp)}</p>
              </div>
            );
          })}
        </div>
      </section>

      {/* ── banner ─────────────────────────────────────── */}
      <div className="relative z-10 flex h-7 flex-none items-center justify-center px-6">
        {banner ? (
          <p className="animate-[scale-in_.2s_ease-out] rounded-full border border-amber-300/40 bg-black/70 px-4 py-1.5 text-center text-[9px] font-black uppercase tracking-[.2em] text-amber-100 shadow-[0_0_24px_-8px_rgba(251,191,36,.8)]">
            {banner}
          </p>
        ) : null}
      </div>

      <div className="relative z-10 mx-auto h-px w-2/3 flex-none bg-gradient-to-r from-transparent via-amber-300/45 to-transparent shadow-[0_0_18px_rgba(251,191,36,.6)]" />

      {/* ── player team ───────────────────────────────── */}
      <section className="relative z-10 flex-none px-4">
        <div className="flex items-end justify-center gap-2.5">
          {result.team.map((pet, index) => {
            const unit = `p${index}`;
            const hp = petHp[index] ?? 0;
            const dead = hp <= 0;
            const active = phase === 'pets' && index === activeSlot;
            const isCasting = casting?.slot === index;
            const tone = TONE_STYLE[abilityKitFor(pet.name, index).tone];
            return (
              <div
                key={unit}
                className={`relative flex-1 rounded-2xl border px-1 pb-1.5 pt-2 transition-all duration-200 ${
                  dead ? 'border-white/5 opacity-25 grayscale'
                    : active ? `${tone.border} bg-black/55 ${tone.glow} -translate-y-1`
                    : 'border-white/10 bg-black/35'
                } ${hit === unit ? 'translate-y-1 scale-[.97]' : ''} ${isCasting ? '-translate-y-3' : ''}`}
              >
                {unitFloats(unit).map((row) => <FloatText key={row.id} row={row} />)}
                {active ? <div className={`pointer-events-none absolute inset-x-3 bottom-10 top-3 -z-0 rounded-full ${tone.flash} blur-2xl`} /> : null}
                {hit === unit ? <div className="pointer-events-none absolute inset-0 z-10 rounded-2xl bg-white/30 mix-blend-screen" /> : null}
                {pet.image ? (
                  <img src={pet.image} alt={pet.name} className="relative mx-auto h-[11vh] max-h-24 min-h-12 object-contain drop-shadow-[0_0_18px_rgba(56,189,248,.5)]" />
                ) : null}
                <p className="relative truncate text-center text-[8px] font-black uppercase tracking-[.08em] text-slate-100">{pet.name}</p>
                <Bar value={hp} max={petMax[index] ?? 1} tone="emerald" />
                {shielded && !dead ? (
                  <span className="absolute right-1 top-1 grid h-4 w-4 place-items-center rounded-full border border-sky-300/60 bg-sky-300/20 text-sky-100">
                    <Shield className="h-2.5 w-2.5" />
                  </span>
                ) : null}
                {dead ? <p className="text-center text-[8px] font-black uppercase tracking-[.2em] text-rose-400">KO</p> : null}
              </div>
            );
          })}
        </div>
      </section>
      </div>

      {/* ── skill panel — only the ACTIVE pet's 3 abilities ── */}
      <footer className="relative z-10 flex-none border-t border-white/10 bg-black/70 px-3 pb-[max(env(safe-area-inset-bottom),0.75rem)] pt-2 backdrop-blur-sm">
        {phase === 'pets' && kit && activePet ? (
          <>
            <p className="mb-1.5 text-center text-[8px] font-black uppercase tracking-[.24em] text-slate-500">
              HABILIDADES DE <span className="text-amber-200">{activePet.name}</span>
            </p>
            <div className="grid grid-cols-3 gap-2">
              {kit.abilities.map((ability) => {
                const tone = TONE_STYLE[ability.tone];
                const Icon = ICONS[ability.icon] ?? Swords;
                return (
                  <button
                    key={ability.name}
                    type="button"
                    disabled={busy}
                    onClick={() => void cast(activeSlot, ability)}
                    className={`group relative overflow-hidden rounded-2xl border bg-gradient-to-b ${tone.border} ${tone.bg} px-2 pb-2 pt-2.5 text-center transition active:scale-95 disabled:opacity-40 ${tone.glow}`}
                  >
                    <span className="pointer-events-none absolute -top-6 left-1/2 h-12 w-12 -translate-x-1/2 rounded-full bg-white/25 blur-2xl" />
                    <Icon className={`relative mx-auto h-5 w-5 ${tone.text}`} />
                    <span className={`relative mt-1 block text-[8.5px] font-black uppercase leading-tight tracking-[.04em] ${tone.text}`}>{ability.name}</span>
                    <span className="relative mt-0.5 block text-[7px] font-bold uppercase tracking-[.1em] text-white/45">{ability.blurb}</span>
                  </button>
                );
              })}
            </div>
          </>
        ) : (
          <div className="grid h-[78px] place-items-center">
            <p className="text-[9px] font-black uppercase tracking-[.24em] text-slate-500">
              {phase === 'enemy' ? 'INIMIGOS ATACANDO...' : 'BATALHA ENCERRADA'}
            </p>
          </div>
        )}
      </footer>
    </div>
  );
}

function FloatText({ row }: { row: Float }) {
  const tone = row.tone === 'heal' ? 'text-emerald-300 text-[13px]'
    : row.tone === 'buff' ? 'text-sky-200 text-[10px]'
    : row.tone === 'crit' ? 'text-amber-300 text-[18px]'
    : 'text-rose-300 text-[14px]';
  return (
    <span className={`pointer-events-none absolute left-1/2 top-0 z-20 -translate-x-1/2 animate-[fade-out_.9s_ease-out_forwards] font-black drop-shadow-[0_2px_6px_rgba(0,0,0,.95)] ${tone}`}>
      {row.text}
    </span>
  );
}

function Bar({ value, max, tone }: { value: number; max: number; tone: 'rose' | 'emerald' }) {
  const pct = Math.max(0, Math.min(100, (value / Math.max(1, max)) * 100));
  return (
    <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full border border-black/70 bg-black/70">
      <div
        className={`h-full rounded-full transition-[width] duration-300 ${tone === 'rose' ? 'bg-gradient-to-r from-rose-500 to-rose-300 shadow-[0_0_10px_rgba(244,63,94,.7)]' : 'bg-gradient-to-r from-emerald-500 to-emerald-300 shadow-[0_0_10px_rgba(52,211,153,.7)]'}`}
        style={{ width: `${pct}%` }}
      />
    </div>
  );
}

export default FamiliarHuntBattle;
