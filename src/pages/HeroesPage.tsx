import { X } from 'lucide-react';
import { usePlayerHeroes, usePvpDashboard } from '../hooks';
import type { PvpHero } from '../pvp';

const color: Record<string, string> = { common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc', legendary: '#fbbf24' };

export function HeroesPage({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const { data, isLoading, error } = usePlayerHeroes(telegramInitData, true);
  // PvP team info is optional decoration: its failure never blocks the collection.
  const { data: pvp } = usePvpDashboard(telegramInitData, true);
  const heroes: PvpHero[] = data?.heroes ?? [];
  const equipped = new Set([...(pvp?.attackTeam ?? []), ...(pvp?.defenseTeam ?? [])].map((h) => h.heroId));
  return (
    <div className="fixed inset-0 z-[75] overflow-y-auto bg-[#04070c] text-white">
      <div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_top,#183153_0%,#060910_48%,#030508_100%)]" />
      <div className="forge-safe-page relative mx-auto min-h-full w-full max-w-[480px] p-3 pb-10">
        <header className="mb-4 flex items-center justify-between gap-2">
          <div className="min-w-0">
            <p className="text-[9px] uppercase tracking-[.28em] text-amber-300">Forge Village</p>
            <h1 className="truncate text-xl font-black">MEUS HERÓIS</h1>
          </div>
          <button onClick={onClose} aria-label="Fechar" className="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-amber-300/20 bg-black/60"><X /></button>
        </header>

        <section className="rounded-2xl border border-white/10 bg-black/45 p-3">
          <p className="text-[10px] uppercase tracking-[.2em] text-slate-400">Coleção usada em PvP e Chefe</p>
          <p className="mt-1 text-sm font-black text-amber-200">{heroes.length} heróis conquistados</p>
        </section>

        {isLoading ? (
          <p className="py-20 text-center text-sm text-slate-300">Carregando heróis...</p>
        ) : error ? (
          <p className="py-20 text-center text-sm text-slate-300">{error instanceof Error ? error.message : 'Não foi possível carregar os heróis.'}</p>
        ) : heroes.length === 0 ? (
          <p className="py-20 text-center text-sm text-slate-300">Você ainda não possui heróis. Recrute heróis na Vila para começar.</p>
        ) : (
          <div className="mt-3 grid grid-cols-3 gap-2">
            {heroes.map((hero) => (
              <div key={hero.heroId} className="overflow-hidden rounded-xl border bg-black/70" style={{ borderColor: color[hero.rarity] }}>
                <img src={hero.imageUrl} alt={hero.name} loading="lazy" className="aspect-square w-full object-cover" />
                <div className="p-2 text-left">
                  <b className="block truncate text-[9px]">{hero.name}</b>
                  <p className="text-[8px]" style={{ color: color[hero.rarity] }}>{hero.rarity} · Nv. {hero.level}</p>
                  <p className="text-[8px] text-slate-300">{hero.archetype}</p>
                  <p className="text-[8px] text-slate-300">ATK {hero.finalAtk} · HP {hero.finalHp}</p>
                  <p className="text-[8px] text-amber-200">Poder {hero.power}</p>
                  {equipped.has(hero.heroId) ? <p className="text-[8px] font-black text-emerald-300">EM EQUIPE</p> : null}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
