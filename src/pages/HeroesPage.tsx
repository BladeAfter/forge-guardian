import { useEffect, useState } from 'react';
import { Lock, RefreshCw, Sparkles, X } from 'lucide-react';
import { useHeroFusion, usePlayerHeroes, usePvpDashboard, useRarityFusion } from '../hooks';
import { starRow } from '../heroFusion';
import { HeroFusionPanel } from '../components/HeroFusionPanel';
import { HeroRarityFusion } from '../components/HeroRarityFusion';
import type { PvpHero } from '../pvp';
import { useT, useLanguage } from '../LanguageContext';

const color: Record<string, string> = { common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc', legendary: '#fbbf24', ancestral: '#f472b6' };

export function HeroesPage({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const t = useT();
  const { tError } = useLanguage();
  // Only the collection blocks this screen. PvP team and fusion state are decoration.
  const { data, isLoading, isFetching, error, refetch } = usePlayerHeroes(telegramInitData, true);
  // PvP team info is optional decoration: its failure never blocks the collection.
  const { data: pvp } = usePvpDashboard(telegramInitData, true);
  // Fusion state (stars, duplicates, costs) comes from the same player_heroes rows used by PvP/Boss.
  const { data: fusion } = useHeroFusion(telegramInitData, true);
  const [tab, setTab] = useState<'collection' | 'fusion' | 'inventory'>('collection');
  // Rarity fusion is only fetched once the player opens the tab.
  const { data: rarityFusion, isLoading: loadingRarity, error: rarityError } = useRarityFusion(telegramInitData, tab === 'fusion');
  const [fusingId, setFusingId] = useState<string | null>(null);
  useEffect(() => { console.log('[HEROES] start'); }, []);
  useEffect(() => { if (data) console.log('[HEROES] player heroes loaded', data.heroes.length); }, [data]);
  useEffect(() => { if (error) console.error('[SCREEN ERROR]', { screen: 'heroes', step: 'player-heroes', message: error instanceof Error ? error.message : String(error) }); }, [error]);
  const heroes: PvpHero[] = data?.heroes ?? [];
  const equipped = new Set([...(pvp?.attackTeam ?? []), ...(pvp?.defenseTeam ?? [])].map((h) => h.heroId));
  const maxStars = fusion?.config?.max_stars ?? 5;
  const fusionHero = fusion?.heroes.find((h) => h.heroId === fusingId) ?? null;
  // A pending query with no in-flight request (offline flag / paused) must not spin forever.
  const stalled = isLoading && !isFetching;
  return (
    <div className="fixed inset-0 z-[75] overflow-y-auto bg-[#04070c] text-white">
      <div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_top,#183153_0%,#060910_48%,#030508_100%)]" />
      <div className="forge-safe-page relative mx-auto min-h-full w-full max-w-[480px] overflow-x-hidden p-3 pb-10">
        <header className="mb-3 flex items-center justify-between gap-2">
          <div className="min-w-0">
            <p className="text-[9px] uppercase tracking-[.28em] text-amber-300">MYTHREON</p>
            <h1 className="truncate text-xl font-black">{t('heroes.title')}</h1>
          </div>
          <button onClick={onClose} aria-label={t('heroes.close')} className="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-amber-300/20 bg-black/60"><X /></button>
        </header>

        <nav className="mb-3 grid grid-cols-3 gap-2">
          {([['collection', t('heroes.tabCollection')], ['fusion', t('heroes.tabFusion')], ['inventory', t('heroes.tabInventory')]] as const).map(([key, label]) => (
            <button
              key={key}
              onClick={() => setTab(key)}
              className={`min-h-[38px] rounded-xl border px-1 text-[10px] font-black uppercase tracking-[.08em] transition-colors ${tab === key ? 'border-amber-300/60 bg-amber-300/15 text-amber-200' : 'border-white/12 bg-black/50 text-slate-300'}`}
            >
              {label}
            </button>
          ))}
        </nav>

        <div className="relative overflow-x-hidden">
          <div className="flex w-[300%] transition-transform duration-300 ease-out" style={{ transform: tab === 'inventory' ? 'translateX(-66.6667%)' : tab === 'fusion' ? 'translateX(-33.3333%)' : 'translateX(0)' }}>
            <div className={`w-1/3 shrink-0 pr-1 ${tab !== 'collection' ? 'pointer-events-none' : ''}`}>

        <section className="rounded-2xl border border-white/10 bg-black/45 p-3">
          <p className="text-[10px] uppercase tracking-[.2em] text-slate-400">{t('heroes.collectionSubtitle')}</p>
          <p className="mt-1 text-sm font-black text-amber-200">{data ? t('heroes.collectionCount', { count: heroes.length }) : '—'}</p>
          <p className="text-[10px] text-slate-400">{t('heroes.collectionHint')}</p>
        </section>

        {error || stalled ? (
          <div className="py-20 text-center">
            <p className="text-sm text-slate-300">{error ? tError(error) || t('heroes.loadError') : t('heroes.loadError')}</p>
            <button onClick={() => void refetch()} className="mt-4 inline-flex items-center gap-2 rounded-xl border border-amber-300/40 px-4 py-2 text-xs font-black uppercase tracking-[.12em] text-amber-200">
              <RefreshCw size={13} /> {t('heroes.retry')}
            </button>
          </div>
        ) : isLoading ? (
          <p className="py-20 text-center text-sm text-slate-300">{t('heroes.loading')}</p>
        ) : heroes.length === 0 ? (
          <p className="py-20 text-center text-sm text-slate-300">{t('heroes.empty')}</p>

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
                    <p className="text-[8px]" style={{ color: color[hero.rarity] }}>{t(`rarity.${hero.rarity}`)} · {t('common.levelShort')} {hero.level}{state ? `/${state.maxLevel}` : ''}</p>
                    <p className="text-[8px] text-slate-300">ATK {hero.finalAtk} · HP {hero.finalHp}</p>
                    <p className="text-[8px] text-amber-200">{t('common.power')} {hero.power}</p>
                    {equipped.has(hero.heroId) ? <p className="text-[8px] font-black text-emerald-300">{t('heroes.inTeam')}</p> : null}
                    {state ? (
                      <button
                        onClick={() => setFusingId(hero.heroId)}
                        className="mt-1.5 flex min-h-[30px] w-full items-center justify-center gap-1 rounded-lg border border-amber-300/40 bg-amber-300/10 text-[8px] font-black uppercase tracking-[.12em] text-amber-200"
                      >
                        <Sparkles size={11} /> {t('heroes.fuse')}{state.duplicates > 0 ? ` (${state.duplicates})` : ''}
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
                <p className="py-20 text-center text-sm text-slate-300">{t('heroes.loadingFusion')}</p>
              ) : rarityError ? (
                <p className="py-20 text-center text-sm text-slate-300">{tError(rarityError) || t('heroes.fusionLoadError')}</p>
              ) : rarityFusion ? (
                <HeroRarityFusion telegramInitData={telegramInitData} data={rarityFusion} active={tab === 'fusion'} />
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
