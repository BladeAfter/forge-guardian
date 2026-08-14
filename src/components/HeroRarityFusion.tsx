import { useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useQueryClient } from '@tanstack/react-query';
import { Check, Lock, ShieldAlert, Sparkles, X } from 'lucide-react';
import { fuseHeroesByRarity } from '../services';
import { RARITY_COLOR, getHeroUsageStatus, heroLockLabel, type RarityFusionDashboard, type RarityFusionHero, type RarityFusionResult } from '../heroFusion';
import { useT, useLanguage } from '../LanguageContext';

const fmt = (value: number) => new Intl.NumberFormat('pt-BR').format(Math.round(value || 0));
const SLOTS = [0, 1, 2, 3, 4];
const FILTERS = ['common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic', 'ancestral'];

/** Compact 48px slot used in the horizontal selection bar. */
function SlotChip({ hero, index, onClear }: { hero: RarityFusionHero | null; index: number; onClear: () => void }) {
  const t = useT();
  if (!hero) {
    return (
      <div className="grid h-12 w-12 shrink-0 place-items-center rounded-xl border border-dashed border-amber-300/35 bg-[#070d18]/80 text-[10px] font-black text-amber-300/60">
        {index + 1}
      </div>
    );
  }
  return (
    <button
      onClick={onClear}
      aria-label={t('fusion.remove', { name: hero.name })}
      className="relative h-12 w-12 shrink-0 overflow-hidden rounded-xl border bg-black/70"
      style={{ borderColor: RARITY_COLOR[hero.rarity] }}
    >
      {hero.imageUrl ? <img src={hero.imageUrl} alt={hero.name} loading="lazy" className="h-full w-full object-cover" /> : null}
      <span className="absolute inset-x-0 bottom-0 h-1" style={{ background: RARITY_COLOR[hero.rarity] }} />
      <span className="absolute right-0 top-0 grid h-4 w-4 place-items-center bg-black/75 text-white"><X size={9} /></span>
    </button>
  );
}

/** Compact selection card: image + name + rarity + level + copies. Nothing else. */
function FusionHeroCard({
  hero, copies, selectedCount, available, blocked, lockLabel, onToggle,
}: {
  hero: RarityFusionHero;
  copies: number;
  selectedCount: number;
  available: number;
  blocked: boolean;
  lockLabel?: string | null;
  onToggle: () => void;
}) {
  const t = useT();
  const active = selectedCount > 0;
  return (
    <button
      disabled={blocked || (available === 0 && !active)}
      onClick={onToggle}
      className={`relative flex w-full flex-col overflow-hidden rounded-xl border bg-black/70 text-left transition-shadow disabled:opacity-40 ${active ? 'shadow-[0_0_0_2px_rgba(251,191,36,.85),0_0_14px_rgba(251,191,36,.45)]' : ''}`}
      style={{ borderColor: active ? '#fbbf24' : RARITY_COLOR[hero.rarity], aspectRatio: '0.72 / 1' }}
    >
      <div className="relative w-full" style={{ aspectRatio: '1 / 1' }}>
        {hero.imageUrl ? <img src={hero.imageUrl} alt={hero.name} loading="lazy" className="h-full w-full object-cover" /> : null}
        {active ? (
          <span className="absolute inset-0 grid place-items-center bg-amber-300/20">
            <span className="grid h-6 w-6 place-items-center rounded-full bg-amber-300 text-black"><Check size={14} /></span>
          </span>
        ) : null}
        {blocked ? (
          <span className="absolute inset-x-0 bottom-0 flex items-center justify-center gap-1 bg-black/80 px-1 py-0.5 text-[7px] font-black uppercase tracking-[.04em] text-amber-300">
            <Lock size={8} />{lockLabel ?? 'IN USE'}
          </span>
        ) : null}
        {copies > 1 ? <span className="absolute left-1 top-1 rounded bg-black/80 px-1 text-[8px] font-black text-amber-200">x{copies}</span> : null}
      </div>
      <div className="flex-1 px-1 py-1 leading-tight">
        <b className="block truncate text-[8px]">{hero.name}</b>
        <p className="text-[7px] font-black uppercase" style={{ color: RARITY_COLOR[hero.rarity] }}>{t(`rarity.${hero.rarity}`)}</p>
        <p className="text-[7px] text-slate-400">{t('common.levelShort')}{hero.level}{copies > 1 ? t('fusion.freeCopies', { count: available }) : ''}</p>
      </div>
    </button>
  );
}

export function HeroRarityFusion({ telegramInitData, data, active = true }: { telegramInitData: string; data: RarityFusionDashboard; active?: boolean }) {
  const t = useT();
  const { tError } = useLanguage();
  const queryClient = useQueryClient();
  const [selected, setSelected] = useState<string[]>([]);
  const [filter, setFilter] = useState<string>('common');
  const [confirming, setConfirming] = useState(false);
  const [phase, setPhase] = useState<'idle' | 'fusing' | 'result'>('idle');
  const [result, setResult] = useState<RarityFusionResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const busy = useRef(false);

  const config = data.config;
  const tiers = config?.tiers ?? {};
  const required = config?.required_heroes ?? 5;
  const heroes = data.heroes ?? [];
  const byId = useMemo(() => new Map(heroes.map((h) => [h.heroId, h])), [heroes]);
  const chosen = selected.map((id) => byId.get(id) ?? null).filter(Boolean) as RarityFusionHero[];
  const sourceRarity = chosen[0]?.rarity ?? null;
  const tier = sourceRarity ? tiers[sourceRarity] : null;
  const cost = tier?.cost_fc ?? 0;
  const complete = selected.length === required;
  const notEnoughFc = complete && data.balance < cost;
  const fusionEnabled = config?.enabled !== false;

  useEffect(() => {
    setSelected((prev) => prev.filter((id) => byId.has(id)));
  }, [byId]);

  // Overlays are portaled to <body>, so the page scroll must be frozen while one is open.
  const overlayOpen = confirming || phase === 'fusing' || phase === 'result';
  useEffect(() => {
    if (!overlayOpen) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => { document.body.style.overflow = previous; };
  }, [overlayOpen]);

  const activeRarity = sourceRarity ?? filter;

  // Group copies of the same hero into a single compact card.
  const groups = useMemo(() => {
    const map = new Map<string, RarityFusionHero[]>();
    heroes
      .filter((hero) => hero.rarity === activeRarity)
      .forEach((hero) => {
        const list = map.get(hero.heroKey) ?? [];
        list.push(hero);
        map.set(hero.heroKey, list);
      });
    return [...map.values()].map((list) => list.sort((a, b) => a.power - b.power));
  }, [heroes, activeRarity]);

  function toggleGroup(list: RarityFusionHero[]) {
    const picked = list.filter((h) => selected.includes(h.heroId));
    const free = list.filter((h) => !selected.includes(h.heroId) && getHeroUsageStatus(h).canFuse);
    setSelected((prev) => {
      if (free.length === 0 || prev.length >= required) {
        // nothing free -> remove the last selected copy
        const last = picked[picked.length - 1];
        return last ? prev.filter((id) => id !== last.heroId) : prev;
      }
      return [...prev, free[0].heroId].slice(0, required);
    });
  }

  async function runFusion() {
    if (busy.current || !complete || notEnoughFc) return;
    busy.current = true;
    setConfirming(false);
    setError(null);
    setPhase('fusing');
    const key = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
    const started = Date.now();
    try {
      const payload = await fuseHeroesByRarity(telegramInitData, selected, key);
      const wait = Math.max(0, 3200 - (Date.now() - started));
      await new Promise((resolve) => setTimeout(resolve, wait));
      setResult(payload);
      setPhase('result');
      setSelected([]);
      queryClient.setQueryData(['rarity-fusion', telegramInitData], payload.dashboard);
      queryClient.invalidateQueries({ queryKey: ['player-heroes'] });
      queryClient.invalidateQueries({ queryKey: ['community-pool'] });
      queryClient.invalidateQueries({ queryKey: ['hero-fusion'] });
      queryClient.invalidateQueries({ queryKey: ['player-inventory'] });
      queryClient.invalidateQueries({ queryKey: ['reward-history'] });
      queryClient.invalidateQueries({ queryKey: ['game-state'] });
      queryClient.invalidateQueries({ queryKey: ['wallet-summary'] });
    } catch (err) {
      setPhase('idle');
      setError(tError(err) || t('fusion.defaultError'));
    } finally {
      busy.current = false;
    }
  }

  return (
    <section className="pb-2">
      <div className="rounded-xl border border-amber-300/20 bg-[radial-gradient(circle_at_top,#12224a_0%,#060b16_70%)] px-3 py-2">
        <h2 className="text-[13px] font-black">{t('fusion.rarityTitle')}</h2>
        <p className="text-[9px] text-slate-300">{t('fusion.combineHeroes', { count: required })}</p>
        {!fusionEnabled ? <p className="mt-1 rounded-lg border border-rose-400/40 bg-rose-500/10 px-2 py-0.5 text-[9px] font-black text-rose-200">{t('fusion.disabled')}</p> : null}
      </div>

      {/* Compact slot bar */}
      <div className="sticky top-0 z-10 mt-2 rounded-xl border border-white/10 bg-[#04070d]/95 p-2 backdrop-blur">
        <div className="flex items-center justify-center gap-1.5">
          {SLOTS.slice(0, required).map((index) => (
            <SlotChip
              key={index}
              index={index}
              hero={chosen[index] ?? null}
              onClear={() => setSelected((p) => p.filter((_, i) => i !== index))}
            />
          ))}
        </div>
        <p className="mt-1 text-center text-[9px] font-black uppercase tracking-[.16em] text-amber-200">{t('fusion.selectedCount', { selected: selected.length, required })}</p>
      </div>

      {/* Rarity filters */}
      <div className="mt-2 grid grid-cols-5 gap-1">
        {FILTERS.map((option) => {
          const active = activeRarity === option;
          const disabled = Boolean(sourceRarity) && sourceRarity !== option;
          return (
            <button
              key={option}
              disabled={disabled}
              onClick={() => setFilter(option)}
              className={`min-h-[28px] truncate rounded-lg border px-0.5 text-[8px] font-black uppercase tracking-[.04em] disabled:opacity-30 ${active ? 'border-amber-300/60 bg-amber-300/15 text-amber-200' : 'border-white/12 bg-black/50 text-slate-300'}`}
            >
              {t(`rarity.${option}`)}
            </button>
          );
        })}
      </div>

      {/* Grid */}
      <p className="mt-2 text-[9px] uppercase tracking-[.2em] text-slate-400">{t('fusion.selectHeroes')}</p>
      {groups.length === 0 ? (
        <p className="py-10 text-center text-[11px] text-slate-400">{t('fusion.noHeroesRarity')}</p>
      ) : (
        <div className="mt-1 grid grid-cols-3 gap-2 sm:grid-cols-4 lg:grid-cols-6">
          {groups.map((list) => {
            const head = list[0];
            const selectedCount = list.filter((h) => selected.includes(h.heroId)).length;
            const available = list.filter((h) => !selected.includes(h.heroId) && getHeroUsageStatus(h).canFuse).length;
            const blocked = list.every((h) => !getHeroUsageStatus(h).canFuse) || !tiers[head.rarity];
            const lockLabel = heroLockLabel(getHeroUsageStatus(list[0]).reason)?.replace('🔒 ', '');
            return (
              <FusionHeroCard
                key={head.heroKey}
                hero={head}
                copies={list.length}
                selectedCount={selectedCount}
                available={available}
                blocked={blocked}
                lockLabel={lockLabel}
                onToggle={() => toggleGroup(list)}
              />
            );
          })}
        </div>
      )}

      {error ? <p className="mt-2 rounded-lg border border-rose-400/40 bg-rose-500/10 px-2 py-1.5 text-[10px] text-rose-200">{error}</p> : null}

      {/* Fusion action bar — portaled so parent transforms cannot offset or clip it */}
      {active && createPortal(
        <div className="fixed inset-x-0 bottom-0 z-[95] mx-auto w-full max-w-[480px] rounded-t-xl border-t border-amber-300/25 bg-[#04070d]/95 px-2 pt-2 backdrop-blur" style={{ paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + 8px)' }}>
        <div className="flex items-center justify-between gap-2 text-[9px]">
          <span className="font-black uppercase tracking-[.12em] text-amber-200">{t('fusion.selectedCount', { selected: selected.length, required })}</span>
          <span className={notEnoughFc ? 'font-black text-rose-300' : 'text-slate-300'}>{t('fusion.cost', { cost: tier ? `${fmt(cost)} FC` : t('fusion.costNA') })}</span>
        </div>
        <p className="text-[9px] text-slate-400">
          {tier && sourceRarity ? (
            <>
              <b style={{ color: RARITY_COLOR[sourceRarity] }}>{t(`rarity.${sourceRarity}`)}</b> → <b style={{ color: RARITY_COLOR[tier.target] }}>{t(`rarity.${tier.target}`)}</b> · {t('fusion.chanceFail', { chance: tier.chance, fragments: fmt(tier.fragments) })}
            </>
          ) : (
            <>{t('fusion.balance', { balance: fmt(data.balance) })}</>
          )}
        </p>
        <button
          disabled={!complete || notEnoughFc || !fusionEnabled || phase === 'fusing'}
          onClick={() => setConfirming(true)}
          className="mt-1.5 min-h-[42px] w-full rounded-xl border border-amber-300/50 bg-gradient-to-b from-amber-300/25 to-amber-500/10 text-[11px] font-black uppercase tracking-[.16em] text-amber-100 disabled:opacity-40"
        >
          {phase === 'fusing' ? t('fusion.fusing') : notEnoughFc ? t('fusion.insufficientBalance') : complete ? t('fusion.fuseHeroes') : t('fusion.selectN', { count: required })}
        </button>
        </div>,
        document.body,
      )}
      {/* Spacer so the last row is never hidden behind the fixed bar */}
      <div aria-hidden className="h-[132px]" />

      {data.history?.length ? (
        <div className="mt-3 rounded-xl border border-white/10 bg-black/40 p-2">
          <p className="text-[9px] uppercase tracking-[.2em] text-slate-400">{t('fusion.historyTitle')}</p>
          <ul className="mt-1 space-y-1">
            {data.history.slice(0, 6).map((entry) => (
              <li key={entry.id} className="flex items-center justify-between gap-2 text-[9px]">
                <span className="truncate text-slate-300">
                  {t(`rarity.${entry.sourceRarity}`)} → {t(`rarity.${entry.targetRarity}`)}
                </span>
                <b className={entry.success ? 'text-emerald-300' : 'text-rose-300'}>
                  {entry.success ? entry.rewardHero ?? t('fusion.success') : t('fusion.fragmentsShort', { count: entry.fragments })}
                </b>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      {/* Confirmation */}
      {confirming && tier ? createPortal(
        <div className="fixed inset-0 z-[96] grid place-items-center overflow-y-auto bg-black/85 p-3">
          <div className="forge-safe-page my-auto max-h-[92vh] w-full max-w-[420px] overflow-y-auto rounded-2xl border border-amber-300/30 bg-[#060b14] p-3">
            <h3 className="text-sm font-black">{t('fusion.confirmTitle')}</h3>
            <p className="mt-1 text-[10px] text-slate-300">{t('fusion.confirmSubtitle', { count: required })}</p>
            <div className="mt-2 grid grid-cols-5 gap-1">
              {chosen.map((hero) => (
                <div key={hero.heroId} className="overflow-hidden rounded-lg border" style={{ borderColor: RARITY_COLOR[hero.rarity] }}>
                  {hero.imageUrl ? <img src={hero.imageUrl} alt={hero.name} className="aspect-square w-full object-cover" /> : null}
                </div>
              ))}
            </div>
            <div className="mt-2 space-y-1 text-[11px]">
              <Row label={t('fusion.currentRarity')} value={sourceRarity ? t(`rarity.${sourceRarity}`) : ''} />
              <Row label={t('fusion.possibleResult')} value={t(`rarity.${tier.target}`)} color={RARITY_COLOR[tier.target]} />
              <Row label={t('fusion.chance')} value={`${tier.chance}%`} />
              <Row label={t('fusion.costLabel')} value={`${fmt(cost)} FC`} />
              <Row label={t('fusion.compensation')} value={t('fusion.universalFragments', { count: fmt(tier.fragments) })} />
            </div>
            <p className="mt-2 flex items-center gap-1 text-[10px] font-black text-rose-300"><ShieldAlert size={12} /> {t('fusion.undoWarning')}</p>
            <div className="mt-3 grid grid-cols-2 gap-2">
              <button onClick={() => setConfirming(false)} className="min-h-[42px] rounded-xl border border-white/15 bg-black/60 text-[11px] font-black uppercase">{t('common.cancel')}</button>
              <button onClick={runFusion} className="min-h-[42px] rounded-xl border border-amber-300/50 bg-amber-300/20 text-[11px] font-black uppercase text-amber-100">{t('common.confirm')}</button>
            </div>
          </div>
        </div>,
        document.body,
      ) : null}

      {/* Ritual animation */}
      {phase === 'fusing' ? createPortal(
        <div className="fixed inset-0 z-[97] grid place-items-center bg-black/92">
          <div className="relative grid h-52 w-52 place-items-center">
            <div className="absolute inset-0 animate-spin rounded-full border-2 border-dashed border-amber-300/40" style={{ animationDuration: '3.4s' }} />
            <div className="absolute inset-6 animate-pulse rounded-full border border-blue-300/40 bg-[radial-gradient(circle,rgba(96,165,250,.35),transparent_65%)]" />
            {SLOTS.map((index) => (
              <span
                key={index}
                className="absolute h-2.5 w-2.5 rounded-full bg-amber-200 shadow-[0_0_12px_rgba(251,191,36,.9)]"
                style={{
                  transform: `rotate(${index * 72}deg) translateY(-88px)`,
                  animation: 'fade-in .6s ease-out both',
                  animationDelay: `${index * 0.18}s`,
                }}
              />
            ))}
            <Sparkles size={40} className="animate-pulse text-amber-200" />
          </div>
          <p className="mt-4 text-[11px] font-black uppercase tracking-[.28em] text-amber-200">{t('fusion.fusing')}</p>
        </div>,
        document.body,
      ) : null}

      {/* Result */}
      {phase === 'result' && result ? createPortal(
        <div className="fixed inset-0 z-[98] grid place-items-center overflow-y-auto bg-black/92 p-4">
          <div className="animate-scale-in my-auto max-h-[92vh] w-full max-w-[380px] overflow-y-auto rounded-2xl border p-4 text-center" style={{ borderColor: result.success ? RARITY_COLOR[result.targetRarity] : '#f43f5e', background: '#050a12' }}>
            {result.success && result.hero ? (
              <>
                <p className="text-[10px] uppercase tracking-[.3em] text-amber-300">{t('fusion.resultSuccessTitle')}</p>
                {result.hero.imageUrl ? (
                  <img src={result.hero.imageUrl} alt={result.hero.name} className="mx-auto mt-2 aspect-square w-40 rounded-xl border object-cover" style={{ borderColor: RARITY_COLOR[result.hero.rarity] }} />
                ) : null}
                <h3 className="mt-2 text-lg font-black">{result.hero.name}</h3>
                <p className="text-[11px] font-black" style={{ color: RARITY_COLOR[result.hero.rarity] }}>{t(`rarity.${result.hero.rarity}`)}</p>
                <p className="text-[9px] uppercase tracking-[.2em] text-emerald-300">{t('fusion.newHero')}</p>
                <div className="mt-2 grid grid-cols-3 gap-1 text-[10px]">
                  <Stat label={t('fusion.statAtk')} value={fmt(result.hero.finalAtk)} />
                  <Stat label={t('fusion.statHp')} value={fmt(result.hero.finalHp)} />
                  <Stat label={t('fusion.statPowerCaps')} value={fmt(result.hero.power)} />
                </div>
              </>
            ) : (
              <>
                <p className="text-[10px] uppercase tracking-[.3em] text-rose-300">{t('fusion.resultFailedTitle')}</p>
                <h3 className="mt-2 text-base font-black">{t('fusion.unstable')}</h3>
                <p className="mt-2 text-[10px] uppercase tracking-[.2em] text-slate-400">{t('fusion.compensation')}</p>
                <p className="text-lg font-black text-amber-200">{t('fusion.universalFragments', { count: fmt(result.fragments) })}</p>
              </>
            )}
            <p className="mt-2 text-[10px] text-slate-400">{t('fusion.balance', { balance: fmt(result.balance) })}</p>
            <button onClick={() => { setPhase('idle'); setResult(null); }} className="mt-3 min-h-[44px] w-full rounded-xl border border-amber-300/50 bg-amber-300/20 text-[11px] font-black uppercase text-amber-100">
              {t('common.continue')}
            </button>
          </div>
        </div>,
        document.body,
      ) : null}
    </section>
  );
}

const Row = ({ label, value, color }: { label: string; value: string; color?: string }) => (
  <div className="flex items-start justify-between gap-3">
    <span className="shrink-0 text-[9px] uppercase tracking-[.14em] text-slate-400">{label}</span>
    <b className="text-right text-[11px] font-black" style={color ? { color } : undefined}>{value}</b>
  </div>
);

const Stat = ({ label, value }: { label: string; value: string }) => (
  <div className="rounded-lg border border-white/10 bg-black/50 p-1.5">
    <p className="text-[8px] uppercase tracking-[.14em] text-slate-400">{label}</p>
    <b className="text-[11px]">{value}</b>
  </div>
);
