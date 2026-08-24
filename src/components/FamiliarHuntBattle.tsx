import { useEffect, useMemo, useRef, useState } from 'react';
import { FastForward, Play, Pause, SkipForward } from 'lucide-react';
import type { FamiliarHuntResult } from '../services';

const ARENA = '/assets/game/familiar-hunt/hunt-arena.jpg';

type Floating = { id: number; unit: string; damage: number; crit: boolean };

/**
 * ⚔️ FAMILIAR HUNT — BATTLE SCENE.
 * The whole fight was already resolved server-side: this screen only *plays back*
 * the authoritative combat log (never re-rolls damage) with visual effects.
 */
export function FamiliarHuntBattle({ result, onFinished }: { result: FamiliarHuntResult; onFinished: () => void }) {
  const events = result.log ?? [];
  const [cursor, setCursor] = useState(0);
  const [speed, setSpeed] = useState<1 | 2>(1);
  const [auto, setAuto] = useState(true);
  const [floats, setFloats] = useState<Floating[]>([]);
  const [hit, setHit] = useState<string | null>(null);
  const floatId = useRef(0);

  const petMax = result.team.map((pet) => Math.max(1, pet.maxHp));
  const enemyMax = result.enemies.map((enemy) => Math.max(1, enemy.maxHp));

  // HP snapshot = full HP minus every damage entry already played back.
  const { petHp, enemyHp } = useMemo(() => {
    const pets = petMax.slice();
    const enemies = enemyMax.slice();
    for (let index = 0; index < cursor; index += 1) {
      const event = events[index];
      if (!event) continue;
      if (event.side === 'pet') enemies[event.target] = Math.max(0, (enemies[event.target] ?? 0) - event.damage);
      else pets[event.target] = Math.max(0, (pets[event.target] ?? 0) - event.damage);
    }
    return { petHp: pets, enemyHp: enemies };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cursor, result.runId]);

  useEffect(() => {
    if (!auto) return;
    if (cursor >= events.length) {
      const done = window.setTimeout(onFinished, 700);
      return () => window.clearTimeout(done);
    }
    const event = events[cursor];
    const timer = window.setTimeout(() => {
      const unit = `${event.side === 'pet' ? 'e' : 'p'}${event.target}`;
      const id = (floatId.current += 1);
      setFloats((current) => [...current, { id, unit, damage: event.damage, crit: event.crit }]);
      window.setTimeout(() => setFloats((current) => current.filter((row) => row.id !== id)), 700);
      setHit(unit);
      window.setTimeout(() => setHit(null), 220);
      setCursor((value) => value + 1);
    }, 620 / speed);
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cursor, auto, speed, events.length]);

  const round = events[Math.min(cursor, events.length - 1)]?.round ?? 1;
  const attacker = cursor > 0 ? events[cursor - 1] : null;

  const unitFloats = (unit: string) => floats.filter((row) => row.unit === unit);

  return (
    <div className="space-y-3 pb-6">
      <div
        className="relative overflow-hidden rounded-[26px] border border-amber-300/25 shadow-[0_0_50px_-12px_rgba(251,191,36,.35)]"
        style={{ backgroundImage: `url(${ARENA})`, backgroundSize: 'cover', backgroundPosition: 'center' }}
      >
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_15%,rgba(56,189,248,.18),rgba(2,6,16,.9)_70%)]" />
        <div className="relative flex flex-col gap-4 p-3">
          <div className="flex items-center justify-between">
            <p className="rounded-full border border-amber-300/40 bg-black/60 px-2.5 py-1 text-[9px] font-black uppercase tracking-[.2em] text-amber-200">
              RODADA {round}
            </p>
            <p className="rounded-full border border-sky-300/30 bg-black/60 px-2.5 py-1 text-[9px] font-black uppercase tracking-[.16em] text-sky-200">
              DANO {Math.round(result.totalDamage).toLocaleString('pt-BR')}
            </p>
          </div>

          {/* ENEMIES */}
          <div className="flex items-end justify-center gap-2">
            {result.enemies.map((enemy, index) => {
              const unit = `e${index}`;
              const hp = enemyHp[index] ?? 0;
              const dead = hp <= 0;
              return (
                <div key={unit} className={`relative flex-1 transition-all duration-200 ${dead ? 'opacity-25 grayscale' : ''} ${hit === unit ? 'translate-y-1 scale-[.97]' : ''}`}>
                  {unitFloats(unit).map((row) => (
                    <span key={row.id} className={`pointer-events-none absolute left-1/2 top-0 z-20 -translate-x-1/2 animate-[fade-out_.7s_ease-out_forwards] font-black drop-shadow-[0_2px_6px_rgba(0,0,0,.9)] ${row.crit ? 'text-[17px] text-amber-300' : 'text-[13px] text-rose-300'}`}>
                      {row.crit ? 'CRIT ' : ''}-{Math.round(row.damage).toLocaleString('pt-BR')}
                    </span>
                  ))}
                  {hit === unit ? <div className="pointer-events-none absolute inset-0 z-10 rounded-2xl bg-white/35 mix-blend-screen" /> : null}
                  {enemy.image ? (
                    <img
                      src={enemy.image}
                      alt={enemy.name}
                      loading="lazy"
                      className={`mx-auto object-contain drop-shadow-[0_0_20px_rgba(244,63,94,.45)] ${enemy.elite ? 'h-32' : 'h-24'}`}
                    />
                  ) : null}
                  <p className="truncate text-center text-[8px] font-black uppercase tracking-[.1em] text-rose-200">{enemy.name}</p>
                  <HpBar value={hp} max={enemyMax[index] ?? 1} tone="rose" />
                </div>
              );
            })}
          </div>

          <div className="mx-auto h-px w-3/4 bg-gradient-to-r from-transparent via-amber-300/40 to-transparent shadow-[0_0_16px_rgba(251,191,36,.6)]" />

          {/* PLAYER PETS */}
          <div className="flex items-end justify-center gap-2">
            {result.team.map((pet, index) => {
              const unit = `p${index}`;
              const hp = petHp[index] ?? 0;
              const dead = hp <= 0;
              const acting = attacker?.side === 'pet' && attacker.actor === index;
              return (
                <div key={unit} className={`relative flex-1 transition-all duration-200 ${dead ? 'opacity-25 grayscale' : ''} ${hit === unit ? '-translate-y-1 scale-[.97]' : ''} ${acting ? '-translate-y-1.5' : ''}`}>
                  {unitFloats(unit).map((row) => (
                    <span key={row.id} className="pointer-events-none absolute left-1/2 top-0 z-20 -translate-x-1/2 animate-[fade-out_.7s_ease-out_forwards] text-[13px] font-black text-rose-300 drop-shadow-[0_2px_6px_rgba(0,0,0,.9)]">
                      -{Math.round(row.damage).toLocaleString('pt-BR')}
                    </span>
                  ))}
                  {acting ? <div className="pointer-events-none absolute inset-x-2 bottom-8 top-2 z-0 rounded-full bg-sky-300/25 blur-xl" /> : null}
                  {hit === unit ? <div className="pointer-events-none absolute inset-0 z-10 rounded-2xl bg-white/30 mix-blend-screen" /> : null}
                  {pet.image ? (
                    <img src={pet.image} alt={pet.name} loading="lazy" className="relative mx-auto h-24 object-contain drop-shadow-[0_0_18px_rgba(56,189,248,.5)]" />
                  ) : null}
                  {dead ? <p className="text-center text-[8px] font-black uppercase tracking-[.2em] text-rose-400">KO</p> : null}
                  <p className="truncate text-center text-[8px] font-black uppercase tracking-[.1em] text-sky-200">{pet.name}</p>
                  <HpBar value={hp} max={petMax[index] ?? 1} tone="emerald" />
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <div className="flex items-center justify-center gap-2">
        <button
          type="button"
          onClick={() => setAuto((value) => !value)}
          className={`flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[9px] font-black uppercase tracking-[.14em] transition active:scale-95 ${auto ? 'border-emerald-300/60 bg-emerald-300/10 text-emerald-200' : 'border-white/15 bg-white/[.04] text-slate-300'}`}
        >
          {auto ? <Pause className="h-3.5 w-3.5" /> : <Play className="h-3.5 w-3.5" />} AUTO
        </button>
        <button
          type="button"
          onClick={() => setSpeed((value) => (value === 1 ? 2 : 1))}
          className="flex items-center gap-1.5 rounded-full border border-sky-300/40 bg-sky-300/10 px-3 py-1.5 text-[9px] font-black uppercase tracking-[.14em] text-sky-200 transition active:scale-95"
        >
          <FastForward className="h-3.5 w-3.5" /> x{speed}
        </button>
        <button
          type="button"
          onClick={() => { setCursor(events.length); setFloats([]); onFinished(); }}
          className="flex items-center gap-1.5 rounded-full border border-amber-300/50 bg-amber-300/10 px-3 py-1.5 text-[9px] font-black uppercase tracking-[.14em] text-amber-200 transition active:scale-95"
        >
          <SkipForward className="h-3.5 w-3.5" /> SKIP
        </button>
      </div>
    </div>
  );
}

function HpBar({ value, max, tone }: { value: number; max: number; tone: 'rose' | 'emerald' }) {
  const pct = Math.max(0, Math.min(100, (value / Math.max(1, max)) * 100));
  return (
    <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full border border-black/60 bg-black/70">
      <div
        className={`h-full rounded-full transition-[width] duration-200 ${tone === 'rose' ? 'bg-gradient-to-r from-rose-500 to-rose-300 shadow-[0_0_10px_rgba(244,63,94,.7)]' : 'bg-gradient-to-r from-emerald-500 to-emerald-300 shadow-[0_0_10px_rgba(52,211,153,.7)]'}`}
        style={{ width: `${pct}%` }}
      />
    </div>
  );
}

export default FamiliarHuntBattle;
