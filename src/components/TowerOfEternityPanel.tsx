import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { RARITY_COLORS, type HeroRarity } from '../heroCatalog';
import type { PvpHero } from '../pvp';

type Props = {
  balance: number;
  collection?: PvpHero[];
  collectionLoading?: boolean;
};

const TOWER_FLOOR = 37;
const TOWER_FLOORS = 100;
const ENTRY_COST = 300000;
const RECOMMENDED_POWER = 185000;

const compact = (value: number) => Math.floor(value).toLocaleString();
const normalizeRarity = (value?: string): HeroRarity => {
  const key = String(value ?? '').trim().toLowerCase();
  return (['common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic', 'ancestral'] as HeroRarity[]).includes(key as HeroRarity)
    ? (key as HeroRarity)
    : 'common';
};

export function TowerOfEternityPanel({ balance, collection, collectionLoading }: Props) {
  const [isTeamOpen, setIsTeamOpen] = useState(false);
  const [team, setTeam] = useState<string[]>([]);

  const heroes = useMemo(
    () => (collection ?? []).slice().sort((a, b) => (b.power ?? 0) - (a.power ?? 0)),
    [collection],
  );
  const teamPower = useMemo(
    () => heroes.filter(h => team.includes(h.heroId)).reduce((sum, h) => sum + (h.power ?? 0), 0),
    [heroes, team],
  );

  const toggleHero = (heroId: string) => {
    setTeam(prev => {
      if (prev.includes(heroId)) return prev.filter(id => id !== heroId);
      if (prev.length >= 5) {
        toast.error('Equipe cheia (5 heróis)');
        return prev;
      }
      return [...prev, heroId];
    });
  };

  const enter = () => {
    if (team.length === 0) {
      toast.error('Selecione sua equipe primeiro');
      setIsTeamOpen(true);
      return;
    }
    if (balance < ENTRY_COST) {
      toast.error('FC insuficiente para entrar na masmorra');
      return;
    }
    toast.info('A Torre da Eternidade abre em breve · Andar 37');
  };

  return (
    <section className="space-y-3">
      <div className="relative overflow-hidden rounded-3xl border border-amber-400/30 bg-[#080a11] p-4 shadow-card">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(251,191,36,.18),transparent_65%)]" />
        <div className="relative text-center">
          <p className="text-[10px] uppercase tracking-[.32em] text-amber-300/80">Solo Dungeon • {TOWER_FLOORS} Floors</p>
          <h3 className="mt-1 text-xl font-black uppercase tracking-wide text-amber-200">Tower of Eternity</h3>
          <p className="mt-2 text-[11px] font-bold text-slate-200">
            Floor <span className="text-amber-300">{TOWER_FLOOR}</span> / {TOWER_FLOORS}
          </p>
          <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-black/70">
            <div className="h-full rounded-full bg-gradient-to-r from-amber-500 to-amber-200" style={{ width: `${(TOWER_FLOOR / TOWER_FLOORS) * 100}%` }} />
          </div>
        </div>

        <div className="relative mt-4 rounded-2xl border border-amber-400/20 bg-black/60 p-3 text-center">
          <p className="text-[9px] uppercase tracking-[.3em] text-slate-400">Boss do Andar</p>
          <p className="mt-1 text-base font-bold text-rose-200">Abyssal Warden</p>
        </div>

        <div className="relative mt-3 grid grid-cols-3 gap-2 text-[10px]">
          <div className="rounded-2xl bg-black/65 p-2.5">
            <p className="text-slate-400">Recommended Power</p>
            <p className="mt-1 font-semibold text-amber-300">{compact(RECOMMENDED_POWER)}</p>
          </div>
          <div className="rounded-2xl bg-black/65 p-2.5">
            <p className="text-slate-400">Entry Cost</p>
            <p className="mt-1 font-semibold text-amber-300">{compact(ENTRY_COST)} FC</p>
          </div>
          <div className="rounded-2xl bg-black/65 p-2.5">
            <p className="text-slate-400">First Clear</p>
            <p className="mt-1 font-semibold text-emerald-300">Epic Fragments x10</p>
          </div>
        </div>

        <div className="relative mt-3 grid gap-2">
          <button
            type="button"
            onClick={() => setIsTeamOpen(true)}
            className="min-h-11 rounded-2xl border border-amber-400/40 bg-amber-400/10 text-xs font-bold uppercase tracking-wide text-amber-200"
          >
            Select Team {team.length ? `· ${team.length}/5 · ${compact(teamPower)}` : ''}
          </button>
          <button
            type="button"
            onClick={enter}
            className="min-h-11 rounded-2xl bg-gradient-to-r from-amber-500 to-amber-300 text-xs font-black uppercase tracking-wide text-black"
          >
            Enter Dungeon • 300K FC
          </button>
        </div>
      </div>

      <div className="rounded-3xl border border-white/10 bg-black/50 p-3">
        <p className="text-[10px] uppercase tracking-[.28em] text-amber-300/80">Possible Rewards</p>
        <div className="mt-2 grid grid-cols-2 gap-2 text-[10px]">
          <div className="rounded-2xl bg-black/65 p-2.5"><p className="text-slate-400">Forge Coins</p><p className="mt-1 font-semibold text-amber-300">450,000 FC</p></div>
          <div className="rounded-2xl bg-black/65 p-2.5"><p className="text-slate-400">Fragments</p><p className="mt-1 font-semibold text-sky-300">Epic x10</p></div>
          <div className="rounded-2xl bg-black/65 p-2.5"><p className="text-slate-400">Pet Food</p><p className="mt-1 font-semibold text-emerald-300">x25</p></div>
          <div className="rounded-2xl bg-black/65 p-2.5"><p className="text-slate-400">Eternity Keys</p><p className="mt-1 font-semibold text-fuchsia-300">x1</p></div>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-2 text-[10px]">
        <div className="rounded-2xl border border-white/10 bg-black/55 p-2.5"><p className="text-slate-400">Deepest Floor</p><p className="mt-1 font-semibold text-amber-300">{TOWER_FLOOR - 1}</p></div>
        <div className="rounded-2xl border border-white/10 bg-black/55 p-2.5"><p className="text-slate-400">Attempts</p><p className="mt-1 font-semibold">3 / 3</p></div>
        <div className="rounded-2xl border border-white/10 bg-black/55 p-2.5"><p className="text-slate-400">Replay Reward</p><p className="mt-1 font-semibold text-slate-200">50%</p></div>
      </div>

      <div className="rounded-3xl border border-white/10 bg-black/50 p-3">
        <p className="text-[10px] uppercase tracking-[.28em] text-amber-300/80">Milestone Rewards</p>
        <div className="mt-2 space-y-1.5">
          {[
            { floor: 10, reward: '50,000 FC', done: true },
            { floor: 25, reward: 'Rare Fragments x15', done: true },
            { floor: 50, reward: 'Legendary Fragments x10', done: false },
            { floor: 75, reward: 'Mythic Egg x1', done: false },
            { floor: 100, reward: 'Ancestral Fragments x25', done: false },
          ].map(item => (
            <div key={item.floor} className={`flex items-center justify-between rounded-xl border px-2.5 py-2 text-[10px] ${item.done ? 'border-emerald-400/30 bg-emerald-500/10' : 'border-white/10 bg-black/60'}`}>
              <span className="font-bold text-slate-200">Floor {item.floor}</span>
              <span className={item.done ? 'text-emerald-300' : 'text-amber-200'}>{item.reward}</span>
            </div>
          ))}
        </div>
      </div>

      {isTeamOpen ? (
        <div className="fixed inset-0 z-[80] flex items-end justify-center bg-black/75 p-2" onClick={() => setIsTeamOpen(false)}>
          <div className="forge-safe-page w-full max-w-md rounded-t-3xl border border-amber-400/30 bg-[#090c12] p-3" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-bold">Select Team · {team.length}/5</h3>
              <button type="button" aria-label="Fechar" onClick={() => setIsTeamOpen(false)} className="grid h-9 w-9 place-items-center rounded-xl border border-white/10 bg-black/60 text-slate-300">✕</button>
            </div>
            {collectionLoading && !heroes.length ? (
              <p className="py-8 text-center text-xs text-slate-400">Carregando heróis…</p>
            ) : !heroes.length ? (
              <p className="py-8 text-center text-xs text-slate-400">Nenhum herói disponível.</p>
            ) : (
              <div className="mt-3 grid max-h-[52vh] grid-cols-3 gap-2 overflow-y-auto">
                {heroes.map(hero => {
                  const selected = team.includes(hero.heroId);
                  const rarity = normalizeRarity(hero.rarity);
                  return (
                    <button
                      type="button"
                      key={hero.heroId}
                      onClick={() => toggleHero(hero.heroId)}
                      className="overflow-hidden rounded-xl border bg-black text-left"
                      style={{ borderColor: selected ? '#fbbf24' : RARITY_COLORS[rarity] }}
                    >
                      {hero.imageUrl ? <img src={hero.imageUrl} alt={hero.name} className="aspect-square w-full object-cover" /> : null}
                      <div className="p-1.5">
                        <p className="truncate text-[9px] font-bold">{hero.name}</p>
                        <p className="text-[8px] text-amber-200">{compact(hero.power ?? 0)}</p>
                        {selected ? <p className="text-[8px] text-amber-300">Selecionado</p> : null}
                      </div>
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      ) : null}
    </section>
  );
}
