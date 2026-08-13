import { useEffect, useMemo, useRef, useState } from 'react';
import { Swords, Zap } from 'lucide-react';
import type { PvpHero } from '../pvp';
import type { TowerBattle, TowerEquipmentDrop } from '../tower';
import { towerBossTheme } from '../towerBosses';
import { PetCompanion } from './PetCompanion';
import { activePetBonuses } from '../petBonuses';

const GEAR_TONES: Record<string, { border: string; bg: string; text: string }> = {
  common: { border: 'border-slate-500/40', bg: 'bg-slate-500/10', text: 'text-slate-300' },
  uncommon: { border: 'border-emerald-400/40', bg: 'bg-emerald-500/10', text: 'text-emerald-300' },
  rare: { border: 'border-sky-400/40', bg: 'bg-sky-500/10', text: 'text-sky-300' },
  epic: { border: 'border-fuchsia-400/40', bg: 'bg-fuchsia-500/10', text: 'text-fuchsia-300' },
  legendary: { border: 'border-amber-300/50', bg: 'bg-amber-400/10', text: 'text-amber-300' },
};

const GEAR_SLOTS: Record<string, string> = { weapon: 'Arma', armor: 'Armadura', ring: 'Anel' };

/**
 * Tower of Eternity battle screen: 5 heroes vs 1 floor boss.
 * Same turn-based playback base as the PvP arena — the log is produced server-side.
 */
const rarityColor: Record<string, string> = {
  common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc',
  legendary: '#fbbf24', mythic: '#f472b6', ancestral: '#fb923c', nft_exclusive: '#fbbf24',
};

type Fighter = { heroId: string; name: string; imageUrl: string; rarity: string; maxHp: number; hp: number };

const compact = (value: number) => Math.floor(Math.max(0, value)).toLocaleString();

export function TowerBattleArena({ battle, onContinue }: { battle: TowerBattle; onContinue: () => void }) {
  const theme = towerBossTheme(battle.boss.bossKey);
  const events = useMemo(() => battle.battleLog.filter(e => Number.isFinite(e?.damage)), [battle]);
  const baseHeroes = useMemo<Fighter[]>(
    () => (battle.attackerState?.length ? battle.attackerState : battle.team).map((h: PvpHero & { currentHp?: number }) => ({
      heroId: h.heroId, name: h.name, imageUrl: h.imageUrl, rarity: String(h.rarity),
      maxHp: Math.max(1, Number(h.finalHp) || 1), hp: Math.max(1, Number(h.finalHp) || 1),
    })),
    [battle],
  );
  const bossMaxHp = Math.max(1, Number(battle.boss.finalHp) || 1);

  const [heroes, setHeroes] = useState<Fighter[]>(baseHeroes);
  const [bossHp, setBossHp] = useState(bossMaxHp);
  const [index, setIndex] = useState(0);
  const [speed, setSpeed] = useState(1);
  const [done, setDone] = useState(false);
  const [fx, setFx] = useState<{ attackerId: string; targetId: string; damage: number; side: string; key: number } | null>(null);
  const timer = useRef<number | null>(null);

  const finish = () => {
    setHeroes(baseHeroes.map((h, i) => ({ ...h, hp: Math.max(0, Number(battle.attackerState?.[i]?.currentHp ?? h.hp)) })));
    setBossHp(Math.max(0, Number(battle.defenderState?.[0]?.currentHp ?? 0)));
    setIndex(events.length);
    setFx(null);
    setDone(true);
  };

  useEffect(() => {
    if (done) return;
    if (index >= events.length) {
      const t = window.setTimeout(() => setDone(true), 450);
      return () => window.clearTimeout(t);
    }
    const e = events[index];
    setFx({ attackerId: e.attackerId, targetId: e.targetId, damage: e.damage, side: e.side, key: index });
    if (e.side === 'attacker') setBossHp(Math.max(0, Number.isFinite(e.remainingHp) ? e.remainingHp : bossHp - e.damage));
    else if (e.targetId !== 'tower-boss') setHeroes(list => list.map(h => (h.heroId === e.targetId ? { ...h, hp: Math.max(0, e.remainingHp) } : h)));
    else setBossHp(Math.max(0, Number(e.remainingHp)));
    timer.current = window.setTimeout(() => { setFx(null); setIndex(i => i + 1); }, 780 / speed);
    return () => { if (timer.current) window.clearTimeout(timer.current); };
  }, [index, events, speed, done]);

  const win = battle.result === 'win';
  const bossPct = Math.max(0, Math.min(100, Math.round((bossHp / bossMaxHp) * 100)));
  const turn = Math.min(battle.totalTurns, events[Math.min(index, Math.max(0, events.length - 1))]?.turn ?? battle.totalTurns);
  const rewards = (battle.rewards ?? {}) as Record<string, number>;
  // Equipment dropped by the floor rule (category first, then a random item of that pool).
  const gear = ((battle.rewards ?? {}) as { equipment?: TowerEquipmentDrop | null }).equipment ?? null;
  const gearTone = GEAR_TONES[String(gear?.rarity ?? '').toLowerCase()] ?? GEAR_TONES.common;
  const gearSlotLabel = gear ? (GEAR_SLOTS[String(gear.slot)] ?? String(gear.slot)) : '';
  // The active pet and its buffs come from the same server-side pet system used by the Boss.
  const activePet = battle.petSummary?.activePet ?? null;
  const petBonuses = battle.petSummary?.bonuses ?? null;
  const petBuffs = activePetBonuses(petBonuses, Object.keys(petBonuses ?? {})).slice(0, 4);

  return (
    <div className="fixed inset-0 z-[120] overflow-y-auto bg-[#04070c] text-white">
      <div className="pointer-events-none fixed inset-0" style={{ background: theme.stage }} />
      <img src={theme.arena} alt="" aria-hidden className="pointer-events-none fixed inset-0 h-full w-full object-cover opacity-45" />
      <div className="forge-safe-page relative mx-auto flex min-h-full w-full max-w-[480px] flex-col px-3 pb-6 pt-4">
        <header className="text-center">
          <p className="text-[9px] font-black uppercase tracking-[.3em] text-amber-300">Tower of Eternity</p>
          <p className={`mt-1 text-[11px] font-bold ${theme.accent}`}>Floor {battle.floor} / 100 · {done ? 'Batalha encerrada' : `Turno ${turn} / ${battle.totalTurns}`}</p>
          <div className="mt-2 h-1 overflow-hidden rounded-full bg-white/10">
            <div className="h-full rounded-full bg-gradient-to-r from-amber-300 to-orange-500 transition-all duration-300" style={{ width: `${Math.round((Math.min(index, events.length) / Math.max(1, events.length)) * 100)}%` }} />
          </div>
        </header>

        <section className="mt-4">
          <div className={`relative overflow-hidden rounded-[1.5rem] border ${theme.border} bg-black/45 p-3`}>
            <div className="pointer-events-none absolute inset-0" style={{ background: theme.aura }} />
            <div className="relative flex items-center justify-between text-[10px]">
              <p className="font-black uppercase tracking-[.2em] text-slate-300">{battle.boss.name}</p>
              <p className={theme.accent}>{compact(bossHp)} / {compact(bossMaxHp)}</p>
            </div>
            <div className="relative mx-auto mt-2 grid place-items-center">
              <img
                src={theme.art}
                alt={battle.boss.name}
                className={`h-[168px] w-auto object-contain transition-all duration-200 ${bossHp <= 0 ? 'opacity-30 grayscale' : ''} ${fx?.side === 'defender' ? 'translate-y-1.5' : ''} ${fx?.targetId === 'tower-boss' && fx?.side === 'attacker' ? 'animate-[pulse_.3s_ease-in-out]' : ''}`}
                style={{ filter: theme.glow }}
              />
              {fx?.side === 'attacker' ? (
                <span key={fx.key} className="absolute top-2 animate-fade-in text-sm font-black text-rose-300 drop-shadow-[0_2px_6px_rgba(0,0,0,.9)]">-{fx.damage}</span>
              ) : null}
            </div>
            <div className="relative mt-1 h-2 overflow-hidden rounded-full bg-black/70">
              <div className="h-full rounded-full transition-all duration-300" style={{ width: `${bossPct}%`, background: theme.bar }} />
            </div>
          </div>
        </section>

        <div className="my-3 flex items-center justify-center gap-3">
          <span className="h-[1px] flex-1 bg-white/10" />
          <Swords className={`h-7 w-7 text-amber-300 ${fx ? 'animate-pulse' : ''}`} />
          <span className="h-[1px] flex-1 bg-white/10" />
        </div>

        <section>
          <p className="mb-2 text-[9px] font-black uppercase tracking-[.2em] text-slate-400">Sua equipe</p>
          {activePet ? <PetCompanion pet={activePet} buffs={petBuffs} size="sm" label="Pet Buff Active" /> : null}
          <div className="grid grid-cols-5 gap-1.5">
            {heroes.map(h => {
              const pct = Math.max(0, Math.min(100, Math.round((h.hp / h.maxHp) * 100)));
              const dead = h.hp <= 0;
              const attacking = fx?.side === 'attacker' && fx.attackerId === h.heroId;
              const hit = fx?.targetId === h.heroId ? fx : null;
              return (
                <div key={h.heroId} className={`relative overflow-hidden rounded-lg border bg-black/70 transition-all duration-200 ${dead ? 'opacity-40 grayscale' : ''} ${attacking ? '-translate-y-1.5 shadow-[0_0_18px_rgba(251,191,36,.45)]' : ''}`} style={{ borderColor: rarityColor[h.rarity] ?? '#475569' }}>
                  <div className="relative">
                    <img src={h.imageUrl} alt={h.name} className="aspect-square w-full object-cover" />
                    {hit ? <span key={hit.key} className="absolute inset-x-0 top-1 animate-fade-in text-center text-[11px] font-black text-rose-300">-{hit.damage}</span> : null}
                    {dead ? <span className="absolute inset-0 grid place-items-center bg-black/60 text-[7px] font-black tracking-widest text-rose-300">KO</span> : null}
                  </div>
                  <p className="truncate px-1 pt-0.5 text-[7px] font-bold text-slate-200">{h.name}</p>
                  <div className="mx-1 mb-1 mt-0.5 h-1 overflow-hidden rounded-full bg-white/10">
                    <div className="h-full rounded-full transition-all duration-500" style={{ width: `${pct}%`, background: pct > 50 ? '#34d399' : pct > 22 ? '#fbbf24' : '#f87171' }} />
                  </div>
                </div>
              );
            })}
          </div>
        </section>

        {!done ? (
          <div className="mt-5 flex items-center justify-center gap-2">
            {[1, 2, 3].map(s => (
              <button key={s} type="button" onClick={() => setSpeed(s)} className={`h-9 min-w-[52px] rounded-xl border px-3 text-[11px] font-black ${speed === s ? 'border-amber-300 bg-amber-400 text-black' : 'border-white/10 bg-black/50 text-white'}`}>x{s}</button>
            ))}
            <button type="button" onClick={finish} className="h-9 rounded-xl border border-white/10 bg-black/50 px-4 text-[11px] font-black text-slate-200">Skip</button>
          </div>
        ) : null}

        {done ? (
          <div className="mt-6 rounded-[1.75rem] border border-amber-300/25 bg-black/70 p-5 text-center">
            <Zap className={`mx-auto h-10 w-10 ${win ? 'text-emerald-300' : 'text-rose-300'}`} />
            <h2 className={`mt-2 text-4xl font-black ${win ? 'text-emerald-300' : 'text-rose-300'}`}>{win ? 'VITÓRIA' : 'DERROTA'}</h2>
            <p className="mt-1 text-[11px] text-slate-400">{battle.totalTurns} turnos · {win ? `Andar ${battle.floor} concluído` : `Andar ${battle.floor} não superado`}</p>
            {win ? (
              <div className="mt-3 grid grid-cols-2 gap-2 text-[10px]">
                {battle.firstClear ? <p className="col-span-2 font-black uppercase tracking-[.2em] text-amber-300">First Clear</p> : null}
                {rewards.fragments ? <div className="rounded-xl bg-black/60 p-2"><p className="text-slate-400">Fragments</p><p className="font-bold text-sky-300">x{rewards.fragments}</p></div> : null}
                {rewards.heroXp ? <div className="rounded-xl bg-black/60 p-2"><p className="text-slate-400">Hero XP</p><p className="font-bold text-amber-200">{compact(rewards.heroXp)}</p></div> : null}
                {rewards.petFood ? <div className="rounded-xl bg-black/60 p-2"><p className="text-slate-400">Pet Food</p><p className="font-bold text-emerald-300">x{rewards.petFood}</p></div> : null}
                {rewards.heroChest ? <div className="rounded-xl bg-black/60 p-2"><p className="text-slate-400">Gear Chest</p><p className="font-bold text-fuchsia-300">x{rewards.heroChest}</p></div> : null}
                {rewards.towerKey ? <div className="rounded-xl bg-black/60 p-2"><p className="text-slate-400">Eternity Key</p><p className="font-bold text-fuchsia-300">x{rewards.towerKey}</p></div> : null}
                {gear ? (
                  <div className={`col-span-2 flex items-center gap-3 rounded-xl border ${gearTone.border} ${gearTone.bg} p-2.5 text-left`}>
                    {gear.imageUrl ? <img src={gear.imageUrl} alt={gear.name} loading="lazy" className="h-12 w-12 rounded-lg object-cover" /> : null}
                    <div className="min-w-0">
                      <p className={`text-[9px] font-black uppercase tracking-[.18em] ${gearTone.text}`}>{gearSlotLabel} · {gear.rarity}</p>
                      <p className="truncate text-[12px] font-bold text-white">{gear.name}</p>
                      <p className="text-[10px] text-slate-400">
                        {gear.bonusAttack ? `ATK +${gear.bonusAttack} ` : ''}
                        {gear.bonusDefense ? `DEF +${gear.bonusDefense} ` : ''}
                        {gear.bonusHp ? `HP +${gear.bonusHp}` : ''}
                        {gear.heroClass ? ` · ${gear.heroClass}` : ''}
                      </p>
                    </div>
                  </div>
                ) : null}
              </div>
            ) : (
              <p className="mt-3 text-[11px] text-slate-400">Tentativa consumida. Reforce sua equipe e tente novamente.</p>
            )}
            <button type="button" onClick={onContinue} className="mt-5 w-full rounded-xl bg-gradient-to-b from-amber-300 to-orange-500 py-3.5 text-sm font-black text-black">Continuar</button>
          </div>
        ) : null}
      </div>
    </div>
  );
}
