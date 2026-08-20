import { useEffect, useMemo, useState } from 'react';
import { Lock, LockOpen, Sparkles, X } from 'lucide-react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { fuseHeroWithFragments, fuseHeroes, setHeroLock } from '../services';
import { useMythUtility } from '../hooks';
import { MythBalanceHint } from './MythPayButton';
import { formatMyth, mythPrice } from '../mythUtility';
import { canFuse, canFuseWithFragments, pickMaterials, starRow, type FusionDashboard, type FusionHero, type FusionResult } from '../heroFusion';
import { useT, useLanguage } from '../LanguageContext';

const fmt = (value: number) => Math.round(value).toLocaleString('pt-BR');

function Stat({ label, before, after }: { label: string; before: number; after: number }) {
  return (
    <div className="flex items-center justify-between gap-2 border-b border-white/5 py-1.5 text-[11px]">
      <span className="uppercase tracking-[.18em] text-slate-400">{label}</span>
      <span className="font-black">
        <span className="text-slate-300">{fmt(before)}</span>
        <span className="mx-1 text-amber-300">→</span>
        <span className="text-emerald-300">{fmt(after)}</span>
      </span>
    </div>
  );
}

export function HeroFusionPanel({
  telegramInitData,
  dashboard,
  hero,
  onClose,
}: {
  telegramInitData: string;
  dashboard: FusionDashboard;
  hero: FusionHero;
  onClose: () => void;
}) {
  const t = useT();
  const { tError } = useLanguage();
  const queryClient = useQueryClient();
  const [result, setResult] = useState<FusionResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const maxStars = dashboard.config?.max_stars ?? 5;
  const current = useMemo(() => dashboard.heroes.find((h) => h.heroId === hero.heroId) ?? hero, [dashboard.heroes, hero]);
  const next = current.next;
  const materials = useMemo(() => pickMaterials(current, dashboard.heroes), [current, dashboard.heroes]);
  const ready = Boolean(next) && canFuse(current, dashboard.balance);
  // Option 2: universal fragments replace the required copies for the SAME step (never both).
  const universalFragments = dashboard.universalFragments ?? 0;
  const fragmentsPerFusion = next?.fragmentsRequired ?? dashboard.fragmentsPerFusion ?? 25;
  const readyWithFragments = canFuseWithFragments(current, dashboard.balance, universalFragments, fragmentsPerFusion);

  // MYTH fee: the copies/fragments requirement is unchanged, only the FC fee is replaced.
  const { data: myth } = useMythUtility(telegramInitData);
  const [feeCurrency, setFeeCurrency] = useState<'FC' | 'MYTH'>('FC');
  const mythFee = next ? mythPrice(myth, 'HERO_FUSE', { fc: next.costFc }) : null;
  const mythFeeOk = mythFee !== null && Number(myth?.available ?? 0) >= mythFee;
  const payMyth = feeCurrency === 'MYTH' && mythFee !== null;
  // NFT Exclusive heroes are 1/1: copies never exist, so they ascend only with universal fragments.
  const readyCopies = !current.isNft && (payMyth ? Boolean(next) && current.duplicates >= (next?.duplicatesRequired ?? 0) && mythFeeOk : ready);
  const readyFragments = payMyth ? Boolean(next) && universalFragments >= fragmentsPerFusion && mythFeeOk : readyWithFragments;

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ['hero-fusion'] });
    queryClient.invalidateQueries({ queryKey: ['player-heroes'] });
    queryClient.invalidateQueries({ queryKey: ['community-pool'] });
    queryClient.invalidateQueries({ queryKey: ['pvp-dashboard'] });
    queryClient.invalidateQueries({ queryKey: ['boss-combat'] });
    queryClient.invalidateQueries({ queryKey: ['wallet-summary'] });
    queryClient.invalidateQueries({ queryKey: ['game-state'] });
  };

  const fusion = useMutation({
    // Only the FEE currency changes here: copies/fragments stay mandatory either way.
    mutationFn: ({ mode, feeCurrency = 'FC' }: { mode: 'copies' | 'fragments'; feeCurrency?: 'FC' | 'MYTH' }) =>
      mode === 'fragments'
        ? fuseHeroWithFragments(telegramInitData, current.heroId, undefined, feeCurrency)
        : fuseHeroes(telegramInitData, current.heroId, materials, undefined, feeCurrency),
    onSuccess: (payload) => { setError(null); setResult(payload); refresh(); queryClient.invalidateQueries({ queryKey: ['player-inventory'] }); queryClient.invalidateQueries({ queryKey: ['pet-dashboard'] }); },
    onError: (err) => setError(tError(err) || t('fusion.defaultError')),
  });

  const lock = useMutation({
    mutationFn: (locked: boolean) => setHeroLock(telegramInitData, current.heroId, locked),
    onSuccess: refresh,
  });

  useEffect(() => { if (!result) return; const id = setTimeout(() => setResult(null), 4200); return () => clearTimeout(id); }, [result]);

  return (
    <div className="fixed inset-0 z-[90] flex items-end justify-center bg-black/80 p-3 sm:items-center">
      <div className="forge-safe-page w-full max-w-[420px] rounded-2xl border border-amber-300/25 bg-[#080c14] p-4 shadow-[0_0_60px_rgba(251,191,36,.12)]">
        <header className="mb-3 flex items-start justify-between gap-2">
          <div className="min-w-0">
            <p className="text-[9px] uppercase tracking-[.3em] text-amber-300">{t('fusion.ascension')}</p>
            <h2 className="truncate text-lg font-black">{t('fusion.title')}</h2>
          </div>
          <button onClick={onClose} aria-label={t('heroes.close')} className="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-white/10 bg-black/60"><X size={18} /></button>
        </header>

        <div className="flex items-center gap-3 rounded-xl border border-white/10 bg-black/50 p-3">
          <div className={`relative h-20 w-20 shrink-0 overflow-hidden rounded-xl border border-amber-300/30 ${fusion.isPending ? 'animate-pulse' : ''}`}>
            {current.imageUrl ? <img src={current.imageUrl} alt={current.name} className="h-full w-full object-cover" /> : null}
            {result ? <div className="absolute inset-0 animate-ping bg-amber-300/25" /> : null}
          </div>
          <div className="min-w-0">
            <b className="block truncate text-sm">{current.name}</b>
            <p className="text-[13px] tracking-[.1em] text-amber-300">{starRow(current.stars, maxStars)}</p>
            <p className="text-[10px] text-slate-300">{t('fusion.level', { level: current.level, max: current.maxLevel })}</p>
            <p className="text-[10px] text-slate-400">{t('fusion.duplicatesAvailable')} <b className="text-white">{current.duplicates}</b></p>
          </div>
        </div>

        {result ? (
          <div className="mt-3 rounded-xl border border-emerald-400/30 bg-emerald-400/10 p-3 text-center">
            <p className="text-[10px] font-black uppercase tracking-[.24em] text-emerald-300">{t('fusion.successTitle')}</p>
            <p className="mt-1 text-sm font-black text-amber-200">{t('fusion.successStars', { from: result.fromStars, to: result.toStars })}</p>
            <p className="text-[11px] text-emerald-200">{t('fusion.successBonus', { percent: result.bonusPercent })}</p>
          </div>
        ) : next ? (
          <div className="mt-3 rounded-xl border border-white/10 bg-black/40 p-3">
            <p className="text-[10px] uppercase tracking-[.24em] text-amber-300">{t('fusion.next', { stars: next.stars })}</p>
            <Stat label={t('fusion.statAtk')} before={current.finalAtk} after={next.finalAtk} />
            <Stat label={t('fusion.statHp')} before={current.finalHp} after={next.finalHp} />
            <Stat label={t('fusion.statPower')} before={current.power} after={Math.round(next.finalAtk * 2 + next.finalHp)} />
            <Stat label={t('fusion.statMaxLevel')} before={current.maxLevel} after={next.maxLevel} />
            <p className="mt-2 text-[10px] uppercase tracking-[.18em] text-slate-400">{t('fusion.requires')}</p>
            <div className="mt-1 space-y-1 rounded-lg border border-white/10 bg-black/40 p-2">
              <p className="text-[9px] uppercase tracking-[.18em] text-slate-500">{t('fusion.option1')}</p>
              <p className={`text-[11px] font-black ${current.duplicates >= next.duplicatesRequired ? 'text-emerald-300' : 'text-rose-300'}`}>
                {t('fusion.copiesRequired', { count: next.duplicatesRequired })} ({t('fusion.available', { count: current.duplicates })})
              </p>
              <p className="text-center text-[9px] font-black uppercase tracking-[.24em] text-slate-500">{t('fusion.or')}</p>
              <p className="text-[9px] uppercase tracking-[.18em] text-slate-500">{t('fusion.option2')}</p>
              <p className={`text-[11px] font-black ${universalFragments >= fragmentsPerFusion ? 'text-emerald-300' : 'text-rose-300'}`}>
                {t('fusion.fragmentsRequired', { count: fragmentsPerFusion })} ({t('fusion.available', { count: universalFragments })})
              </p>
            </div>
            <p className={`text-[11px] font-black ${dashboard.balance >= next.costFc ? 'text-emerald-300' : 'text-rose-300'}`}>
              {t('fusion.costBalance', { cost: fmt(next.costFc), balance: fmt(dashboard.balance) })}
            </p>
          </div>
        ) : (
          <p className="mt-3 rounded-xl border border-amber-300/20 bg-black/40 p-3 text-center text-[11px] font-black text-amber-200">
            {t('fusion.maxStarsReached', { stars: starRow(maxStars, maxStars) })}
          </p>
        )}

        {error ? <p className="mt-2 text-center text-[11px] font-bold text-rose-300">{error}</p> : null}

        {next && mythFee !== null ? (
          <div className="mt-3 grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={() => setFeeCurrency('FC')}
              className={`min-h-10 rounded-xl border text-[10px] font-black uppercase tracking-wide ${feeCurrency === 'FC' ? 'border-amber-300/70 bg-amber-400/20 text-amber-200' : 'border-white/10 bg-black/50 text-slate-400'}`}
            >
              {fmt(next.costFc)} FC
            </button>
            <button
              type="button"
              onClick={() => setFeeCurrency('MYTH')}
              className={`min-h-10 rounded-xl border text-[10px] font-black uppercase tracking-wide ${feeCurrency === 'MYTH' ? 'border-fuchsia-300/70 bg-fuchsia-400/20 text-fuchsia-100' : 'border-white/10 bg-black/50 text-slate-400'}`}
            >
              🔥 {formatMyth(mythFee)} MYTH
            </button>
          </div>
        ) : null}
        {payMyth ? <MythBalanceHint state={myth} /> : null}

        <div className="mt-3 grid grid-cols-2 gap-2">
          <button
            onClick={() => lock.mutate(!current.locked)}
            disabled={lock.isPending}
            className="flex min-h-[44px] items-center justify-center gap-2 rounded-xl border border-white/15 bg-black/60 text-[11px] font-black uppercase tracking-[.14em] text-slate-200 disabled:opacity-50"
          >
            {current.locked ? <Lock size={16} /> : <LockOpen size={16} />}
            {current.locked ? t('fusion.unlockHero') : t('fusion.lockHero')}
          </button>
          <button
            onClick={() => fusion.mutate({ mode: 'copies', feeCurrency: payMyth ? 'MYTH' : 'FC' })}
            disabled={!readyCopies || fusion.isPending}
            className="flex min-h-[44px] items-center justify-center gap-2 rounded-xl border border-amber-300/40 bg-gradient-to-b from-amber-300 to-amber-600 text-[11px] font-black uppercase tracking-[.14em] text-black disabled:opacity-40"
          >
            <Sparkles size={16} />
            {fusion.isPending ? t('fusion.fusing') : t('fusion.fuseWithCopies')}
          </button>
        </div>
        {next ? (
          <button
            onClick={() => fusion.mutate({ mode: 'fragments', feeCurrency: payMyth ? 'MYTH' : 'FC' })}
            disabled={!readyFragments || fusion.isPending}
            className="mt-2 flex min-h-[44px] w-full items-center justify-center gap-2 rounded-xl border border-cyan-300/40 bg-cyan-300/10 text-[11px] font-black uppercase tracking-[.14em] text-cyan-200 disabled:opacity-40"
          >
            <Sparkles size={16} />
            {t('fusion.fuseWithFragments', { count: fragmentsPerFusion })}
          </button>
        ) : null}
        <p className="mt-2 text-center text-[9px] text-slate-500">{t('fusion.lockedNote')}</p>
      </div>
    </div>
  );
}
