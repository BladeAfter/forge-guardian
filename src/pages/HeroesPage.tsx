import { useState } from 'react';
import { Lock, Sparkles, X } from 'lucide-react';
import { useHeroFusion, usePlayerHeroes, usePvpDashboard, useRarityFusion } from '../hooks';
import { starRow } from '../heroFusion';
import { HeroFusionPanel } from '../components/HeroFusionPanel';
import { HeroRarityFusion } from '../components/HeroRarityFusion';
import type { PvpHero } from '../pvp';

const color: Record<string, string> = { common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc', legendary: '#fbbf24', ancestral: '#f472b6' };

export function HeroesPage({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const { data, isLoading, error } = usePlayerHeroes(telegramInitData, true);
  // PvP team info is optional decoration: its failure never blocks the collection.
  const { data: pvp } = usePvpDashboard(telegramInitData, true);
  // Fusion state (stars, duplicates, costs) comes from the same player_heroes rows used by PvP/Boss.
  const { data: fusion } = useHeroFusion(telegramInitData, true);
  const [tab, setTab] = useState<'collection' | 'fusion'>('collection');
  // Rarity fusion is only fetched once the player opens the tab.
  const { data: rarityFusion, isLoading: loadingRarity, error: rarityError } = useRarityFusion(telegramInitData, tab === 'fusion');
  const [fusingId, setFusingId] = useState<string | null>(null);
  const heroes: PvpHero[] = data?.heroes ?? [];
  const equipped = new Set([...(pvp?.attackTeam ?? []), ...(pvp?.defenseTeam ?? [])].map((h) => h.heroId));
  const maxStars = fusion?.config?.max_stars ?? 5;
  const fusionHero = fusion?.heroes.find((h) => h.heroId === fusingId) ?? null;
  return (
    <div className="fixed inset-0 z-[75] overflow-y-auto bg-[#04070c] text-white">
      <div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_top,#183153_0%,#060910_48%,#030508_100%)]" />
      <div className="forge-safe-page relative mx-auto min-h-full w-full max-w-[480px] overflow-x-hidden p-3 pb-10">
        <header className="mb-3 flex items-center justify-between gap-2">
          <div className="min-w-0">
            <p className="text-[9px] uppercase tracking-[.28em] text-amber-300">MYTHREON</p>
            <h1 className="truncate text-xl font-black">HERÓIS</h1>
          </div>
          <button onClick={onClose} aria-label="Fechar" className="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-amber-300/20 bg-black/60"><X /></button>
        </header>

        <nav className="mb-3 grid grid-cols-2 gap-2">
          {([['collection', 'MEUS HERÓIS'], ['fusion', 'FUSÃO DE RARIDADE']] as const).map(([key, label]) => (
            <button
              key={key}
              onClick={() => setTab(key)}
              className={`min-h-[38px] rounded-xl border text-[11px] font-black uppercase tracking-[.12em] transition-colors ${tab === key ? 'border-amber-300/60 bg-amber-300/15 text-amber-200' : 'border-white/12 bg-black/50 text-slate-300'}`}
            >
              {label}
            </button>
          ))}
        </nav>

        <div className="relative overflow-x-hidden">
          <div className="flex w-[200%] transition-transform duration-300 ease-out" style={{ transform: tab === 'fusion' ? 'translateX(-50%)' : 'translateX(0)' }}>
            <div className={`w-1/2 shrink-0 pr-1 ${tab === 'fusion' ? 'pointer-events-none' : ''}`}>
        <section className="rounded-2xl border border-white/10 bg-black/45 p-3">
          <p className="text-[10px] uppercase tracking-[.2em] text-slate-400">Coleção usada em PvP e Chefe</p>
          <p className="mt-1 text-sm font-black text-amber-200">{heroes.length} heróis conquistados</p>
          <p className="text-[10px] text-slate-400">Cópias do MESMO herói são fundidas no botão FUSE (mais estrelas, ATK, HP e Poder — a raridade não muda). Para subir de raridade, use a aba FUSÃO DE RARIDADE.</p>
        </section>

        {isLoading ? (
          <p className="py-20 text-center text-sm text-slate-300">Carregando heróis...</p>
        ) : error ? (
          <p className="py-20 text-center text-sm text-slate-300">{error instanceof Error ? error.message : 'Não foi possível carregar os heróis.'}</p>
        ) : heroes.length === 0 ? (
          <p className="py-20 text-center text-sm text-slate-300">Você ainda não possui heróis. Recrute heróis na Vila para começar.</p>
        ) : (

          <div className="mt-3 grid grid-cols-3 gap-2">
            {heroes.map((hero) => {
              const state = fusion?.heroes.find((h) => h.heroId === hero.heroId);
              const stars = state?.stars ?? hero.stars ?? 0;
              return (
                <div key={hero.heroId} className="overflow-hidden rounded-xl border bg-black/70" style={{ borderColor: color[hero.rarity] }}>
                  <div className="relative">
                    <img src={hero.imageUrl} alt={hero.name} loading="lazy" className="aspect-square w-full object-cover" />
                    {state?.locked ? <span className="absolute right-1 top-1 grid h-5 w-5 place-items-center rounded-md bg-black/70 text-amber-300"><Lock size={11} /></span> : null}
                  </div>
                  <div className="p-2 text-left">
                    <b className="block truncate text-[9px]">{hero.name}</b>
                    <p className="text-[9px] tracking-[.08em] text-amber-300">{starRow(stars, maxStars)}</p>
                    <p className="text-[8px]" style={{ color: color[hero.rarity] }}>{hero.rarity} · Nv. {hero.level}{state ? `/${state.maxLevel}` : ''}</p>
                    <p className="text-[8px] text-slate-300">ATK {hero.finalAtk} · HP {hero.finalHp}</p>
                    <p className="text-[8px] text-amber-200">Poder {hero.power}</p>
                    {equipped.has(hero.heroId) ? <p className="text-[8px] font-black text-emerald-300">EM EQUIPE</p> : null}
                    {state ? (
                      <button
                        onClick={() => setFusingId(hero.heroId)}
                        className="mt-1.5 flex min-h-[30px] w-full items-center justify-center gap-1 rounded-lg border border-amber-300/40 bg-amber-300/10 text-[8px] font-black uppercase tracking-[.12em] text-amber-200"
                      >
                        <Sparkles size={11} /> FUSE{state.duplicates > 0 ? ` (${state.duplicates})` : ''}
                      </button>
                    ) : null}
                  </div>
                </div>
              );
            })}
          </div>
        )}
            </div>
            <div className={`w-1/2 shrink-0 pl-1 ${tab === 'collection' ? 'pointer-events-none' : ''}`}>
              {loadingRarity && !rarityFusion ? (
                <p className="py-20 text-center text-sm text-slate-300">Carregando altar de fusão...</p>
              ) : rarityError ? (
                <p className="py-20 text-center text-sm text-slate-300">{rarityError instanceof Error ? rarityError.message : 'Não foi possível carregar a fusão.'}</p>
              ) : rarityFusion ? (
                <HeroRarityFusion telegramInitData={telegramInitData} data={rarityFusion} />
              ) : null}
            </div>
          </div>
        </div>
      </div>


      {fusion && fusionHero ? (
        <HeroFusionPanel telegramInitData={telegramInitData} dashboard={fusion} hero={fusionHero} onClose={() => setFusingId(null)} />
      ) : null}
    </div>
  );
}
