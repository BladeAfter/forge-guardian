import { useEffect, useMemo, useState } from 'react';
import { Lock, RefreshCw, Sparkles, X } from 'lucide-react';
import { useHeroFusion, useHeroMining, usePlayerHeroes, usePvpDashboard, useRarityFusion } from '../hooks';
import { starRow } from '../heroFusion';
import { HeroFusionPanel } from '../components/HeroFusionPanel';
import { HeroRarityFusion } from '../components/HeroRarityFusion';
import { InventoryPanel } from '../components/InventoryPanel';
import { HeroDetailsPanel } from '../components/HeroDetailsPanel';
import { HeroMiningBar } from '../components/HeroMiningBar';
import { DEFAULT_HERO_FILTERS, HERO_FILTER_CLASSES, HERO_FILTER_RARITIES, applyHeroFilters, isDefaultHeroFilters, type HeroFilters, type SortDir } from '../heroFilters';
import type { PvpHero } from '../pvp';
import { useT, useLanguage } from '../LanguageContext';


const color: Record<string, string> = { common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc', legendary: '#fbbf24', mythic: '#fb7185', ancestral: '#f472b6', nft_exclusive: '#22d3ee' };


export function HeroesPage({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const t = useT();
  const { tError } = useLanguage();
  // Only the collection blocks this screen. PvP team and fusion state are decoration.
  const { data, isLoading, isFetching, error, refetch } = usePlayerHeroes(telegramInitData, true);
  // PvP team info is optional decoration: its failure never blocks the collection.
  const { data: pvp } = usePvpDashboard(telegramInitData, true);
  // Fusion state (stars, duplicates, costs) comes from the same player_heroes rows used by PvP/Boss.
  const { data: fusion } = useHeroFusion(telegramInitData, true);
  // Passive TON mining (rarity based). Rates and accrual are server-owned.
  const { data: mining } = useHeroMining(telegramInitData, true);
  const [tab, setTab] = useState<'collection' | 'fusion' | 'inventory'>('collection');
  // Rarity fusion is only fetched once the player opens the tab.
  const { data: rarityFusion, isLoading: loadingRarity, error: rarityError } = useRarityFusion(telegramInitData, tab === 'fusion');
  const [fusingId, setFusingId] = useState<string | null>(null);
  const [detailsId, setDetailsId] = useState<string | null>(null);
  const [filters, setFilters] = useState<HeroFilters>(DEFAULT_HERO_FILTERS);
  useEffect(() => { console.log('[HEROES] start'); }, []);
  useEffect(() => { if (data) console.log('[HEROES] player heroes loaded', data.heroes.length); }, [data]);
  useEffect(() => { if (error) console.error('[SCREEN ERROR]', { screen: 'heroes', step: 'player-heroes', message: error instanceof Error ? error.message : String(error) }); }, [error]);
  const heroes: PvpHero[] = data?.heroes ?? [];
  // Filters are purely visual: they never touch ownership, stats or teams.
  const visibleHeroes = useMemo(() => applyHeroFilters(heroes, filters), [heroes, filters]);
  const equipped = new Set([...(pvp?.attackTeam ?? []), ...(pvp?.defenseTeam ?? [])].map((h) => h.heroId));
  const maxStars = fusion?.config?.max_stars ?? 5;
  const fusionHero = fusion?.heroes.find((h) => h.heroId === fusingId) ?? null;
  const detailsHero = heroes.find((h) => h.heroId === detailsId) ?? null;
  // A pending query with no in-flight request (offline flag / paused) must not spin forever.
  const stalled = isLoading && !isFetching;
  const selectClass = 'min-w-0 flex-1 appearance-none truncate rounded-lg border border-white/12 bg-black/70 px-1.5 py-1.5 text-[9px] font-black uppercase tracking-[.06em] text-slate-200';
  const sortOptions: Array<[SortDir, string]> = [['default', t('heroes.filterDefault')], ['desc', t('heroes.filterDesc')], ['asc', t('heroes.filterAsc')]];

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

        <HeroMiningBar telegramInitData={telegramInitData} state={mining} />

        <section className="mt-2 rounded-2xl border border-white/10 bg-black/45 p-2.5">
          <div className="flex items-center justify-between gap-2">
            <p className="truncate text-[11px] font-black uppercase tracking-[.14em] text-amber-200">
              {data ? t('heroes.collectionCount', { count: heroes.length }) : '—'}
            </p>
            {!isDefaultHeroFilters(filters) ? (
              <button onClick={() => setFilters(DEFAULT_HERO_FILTERS)} className="flex shrink-0 items-center gap-1 rounded-lg border border-white/15 px-2 py-1 text-[8px] font-black uppercase tracking-[.12em] text-slate-300">
                <X size={10} /> {t('heroes.filterClear')}
              </button>
            ) : null}
          </div>
          <div className="mt-2 grid grid-cols-2 gap-1.5">
            <select aria-label={t('heroes.filterRarity')} value={filters.rarity} onChange={(e) => setFilters((f) => ({ ...f, rarity: e.target.value }))} className={selectClass}>
              {HERO_FILTER_RARITIES.map((r) => (
                <option key={r} value={r}>{`${t('heroes.filterRarity')}: ${r === 'all' ? t('heroes.filterAll') : t(`rarity.${r}`)}`}</option>
              ))}
            </select>
            <select aria-label={t('heroes.filterClass')} value={filters.archetype} onChange={(e) => setFilters((f) => ({ ...f, archetype: e.target.value }))} className={selectClass}>
              {HERO_FILTER_CLASSES.map((c) => (
                <option key={c} value={c}>{`${t('heroes.filterClass')}: ${c === 'all' ? t('heroes.filterAll') : c.toUpperCase()}`}</option>
              ))}
            </select>
            <select aria-label={t('heroes.filterPower')} value={filters.power} onChange={(e) => setFilters((f) => ({ ...f, power: e.target.value as SortDir, level: 'default' }))} className={selectClass}>
              {sortOptions.map(([value, label]) => (<option key={value} value={value}>{`${t('heroes.filterPower')}: ${label}`}</option>))}
            </select>
            <select aria-label={t('heroes.filterLevel')} value={filters.level} onChange={(e) => setFilters((f) => ({ ...f, level: e.target.value as SortDir, power: 'default' }))} className={selectClass}>
              {sortOptions.map(([value, label]) => (<option key={value} value={value}>{`${t('heroes.filterLevel')}: ${label}`}</option>))}
            </select>
          </div>
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
            {visibleHeroes.length === 0 ? (
              <p className="col-span-3 py-16 text-center text-xs text-slate-300">{t('heroes.noResults')}</p>
            ) : null}
            {visibleHeroes.map((hero) => {
              const state = fusion?.heroes.find((h) => h.heroId === hero.heroId);
              const stars = state?.stars ?? hero.stars ?? 0;
              return (
                <div key={hero.heroId} role="button" tabIndex={0} onClick={() => setDetailsId(hero.heroId)} onKeyDown={(e) => { if (e.key === 'Enter') setDetailsId(hero.heroId); }} className={`cursor-pointer overflow-hidden rounded-xl border bg-black/70 text-left ${hero.isNft ? 'nft-hero-card' : ''}`} style={{ borderColor: color[hero.rarity] }}>

                  <div className="relative">
                    <img src={hero.imageUrl} alt={hero.name} loading="lazy" className="aspect-square w-full object-cover" />
                    {hero.isNft ? (
                      <>
                        <span className="nft-hero-tag absolute left-1 top-1 rounded-md px-1.5 py-0.5 text-[7px] font-black uppercase tracking-[.14em]">NFT Exclusive</span>
                        <span className="absolute bottom-1 left-1 rounded-md bg-black/75 px-1.5 py-0.5 text-[7px] font-black tracking-[.1em] text-cyan-200">#{String(hero.nftSerial ?? 0).padStart(3, '0')}</span>
                      </>
                    ) : null}
                    {state?.locked && !hero.isNft ? <span className="absolute right-1 top-1 grid h-5 w-5 place-items-center rounded-md bg-black/70 text-amber-300"><Lock size={11} /></span> : null}
                  </div>
                  <div className="p-2 text-left">
                    <b className="block truncate text-[9px]">{hero.name}</b>
                    <p className="text-[9px] tracking-[.08em] text-amber-300">{starRow(stars, maxStars)}</p>
                    <p className="text-[8px]" style={{ color: color[hero.rarity] }}>{t(`rarity.${hero.rarity}`)} · {t('common.levelShort')} {hero.level}{state ? `/${state.maxLevel}` : ''}</p>
                    <p className="text-[8px] text-slate-300">ATK {hero.finalAtk} · HP {hero.finalHp}</p>
                    <p className="text-[8px] text-amber-200">{t('common.power')} {hero.power}</p>
                    {equipped.has(hero.heroId) ? <p className="text-[8px] font-black text-emerald-300">{t('heroes.inTeam')}</p> : null}
                    {hero.isNft ? (
                      <p className="mt-1.5 rounded-lg border border-cyan-300/40 bg-cyan-300/10 py-1 text-center text-[7px] font-black uppercase tracking-[.1em] text-cyan-200">{t('heroes.nftLocked')}</p>
                    ) : state ? (
                      <button
                        onClick={(e) => { e.stopPropagation(); setFusingId(hero.heroId); }}
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
            <div className={`w-1/3 shrink-0 px-1 ${tab !== 'fusion' ? 'pointer-events-none' : ''}`}>
              {loadingRarity && !rarityFusion ? (
                <p className="py-20 text-center text-sm text-slate-300">{t('heroes.loadingFusion')}</p>
              ) : rarityError ? (
                <p className="py-20 text-center text-sm text-slate-300">{tError(rarityError) || t('heroes.fusionLoadError')}</p>
              ) : rarityFusion ? (
                <HeroRarityFusion telegramInitData={telegramInitData} data={rarityFusion} active={tab === 'fusion'} />
              ) : null}
            </div>
            <div className={`w-1/3 shrink-0 pl-1 ${tab !== 'inventory' ? 'pointer-events-none' : ''}`}>
              <InventoryPanel telegramInitData={telegramInitData} active={tab === 'inventory'} />
            </div>

          </div>
        </div>
      </div>


      {detailsHero ? (
        <HeroDetailsPanel
          telegramInitData={telegramInitData}
          hero={detailsHero}

          state={fusion?.heroes.find((h) => h.heroId === detailsHero.heroId) ?? null}
          miningRates={mining?.rates}
          maxStars={maxStars}
          onClose={() => setDetailsId(null)}
        />
      ) : null}

      {fusion && fusionHero ? (
        <HeroFusionPanel telegramInitData={telegramInitData} dashboard={fusion} hero={fusionHero} onClose={() => setFusingId(null)} />
      ) : null}

    </div>
  );
}
