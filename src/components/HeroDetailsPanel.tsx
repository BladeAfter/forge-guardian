import { useState } from 'react';
import { X } from 'lucide-react';
import type { PvpHero } from '../pvp';
import type { FusionHero } from '../heroFusion';
import { starRow } from '../heroFusion';
import { HeroEquipmentSlots } from './HeroEquipmentSlots';
import type { HeroEquipmentState } from '../heroEquipment';
import { useT } from '../LanguageContext';
import { formatMiningTon, heroDailyRate, isMiningRarity } from '../heroMining';
import { effectiveDailyMining, formatMiningAmount, miningSymbol, useMiningConfig } from '../miningCurrency';
import { GIFT_HERO_LABEL, isGiftHero } from '../giftHeroes';
import { VETERAN_LINE_COLOR, VETERAN_LINE_LABEL, isVeteranLine } from '../veteranLine';


const RARITY_COLOR: Record<string, string> = {
  common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc',
  legendary: '#fbbf24', mythic: '#fb7185', ancestral: '#f472b6', nft_exclusive: '#22d3ee',
};

/** Hero sheet: stats come from the same rows used by PvP/Boss, equipment included. */
export function HeroDetailsPanel({ hero, state, maxStars, telegramInitData, miningRates, onClose }: { hero: PvpHero; state?: FusionHero | null; maxStars: number; telegramInitData: string; miningRates?: Record<string, number>; onClose: () => void }) {
  const mining = useMiningConfig();
  const t = useT();
  const [equipment, setEquipment] = useState<HeroEquipmentState | null>(null);

  const stars = state?.stars ?? hero.stars ?? 0;
  const maxLevel = state?.maxLevel ?? hero.maxLevel ?? null;
  // XP progress: totals come from the server so the bar can never disagree with the backend.
  const xpCurrent = Math.max(0, Number(hero.xp ?? 0));
  const xpNeed = Math.max(0, Number(hero.xpToNext ?? 0));
  const xpMaxed = maxLevel != null && hero.level >= maxLevel;
  const xpPercent = xpNeed > 0 ? Math.min(100, Math.round((xpCurrent / xpNeed) * 100)) : 0;
  const dailyXp = Math.max(0, Number(hero.dailyXp ?? 0));
  const dailyCap = Math.max(0, Number(hero.dailyXpCap ?? 0));

  // Founder/Veteran packs: SUPERIOR premium line, never mythic, never TON mining.
  const veteran = isVeteranLine(hero);
  const veteranMyth = veteran ? Math.max(0, Number(hero.miningDailyMyth ?? 0)) : 0;
  const accent = veteran ? VETERAN_LINE_COLOR : (RARITY_COLOR[String(hero.rarity)] ?? '#94a3b8');
  // Mining depends ONLY on rarity: level and equipment never change it.
  // NFT Exclusive heroes have their own server rate (nft_heroes.mining_daily_ton).
  const miningRate = veteran
    ? 0
    : Number(state?.miningDailyTon ?? 0) > 0
      ? Number(state?.miningDailyTon ?? 0)
      : heroDailyRate(miningRates, hero.rarity);
  // NFT instances can mine MYTH and TON at the same time (dual mining set server-side).
  const nftMyth = veteran ? 0 : Math.max(0, Number(state?.miningDailyMyth ?? hero.miningDailyMyth ?? 0));
  // 'mining.perDay' ships the TON word baked in; strip it so we can print the real currency once.
  const perDaySuffix = t('mining.perDay').replace(/^\s*[A-Za-z]+\s*/, '').trim() || '/ dia';

  const stat = (label: string, value: string | number, bonus?: number) => (
    <div key={label} className="rounded-xl border border-white/10 bg-black/50 px-2 py-1.5 text-center">
      <p className="text-[8px] uppercase tracking-[.16em] text-slate-400">{label}</p>
      <p className="text-[12px] font-black text-white">{value}</p>
      {bonus ? <p className="text-[8px] font-black text-emerald-300">+{Number(bonus).toLocaleString()}</p> : null}
    </div>
  );

  return (
    <div className="fixed inset-0 z-[90] overflow-y-auto bg-black/80 backdrop-blur-sm">
      <div className="forge-safe-page mx-auto min-h-full w-full max-w-[420px] p-3 pb-10">
        <header className="mb-3 flex items-center justify-between gap-2">
          <h2 className="min-w-0 truncate text-lg font-black uppercase tracking-[.06em] text-white">{hero.name}</h2>
          <button onClick={onClose} aria-label={t('heroes.close')} className="grid h-9 w-9 shrink-0 place-items-center rounded-xl border border-amber-300/20 bg-black/70 text-white"><X size={16} /></button>
        </header>

        <div className="overflow-hidden rounded-2xl border bg-black/70" style={{ borderColor: accent }}>
          <img src={hero.imageUrl} alt={hero.name} className="aspect-square w-full object-cover object-top" />
          <div className="p-3 text-center">
            <p className="text-[10px] font-black uppercase tracking-[.18em]" style={{ color: accent }}>
              {veteran ? VETERAN_LINE_LABEL : isGiftHero(hero.heroKey) ? GIFT_HERO_LABEL : t(`rarity.${hero.rarity}`)} · {String(hero.archetype ?? '').toUpperCase()}
            </p>
            <p className="mt-1 text-[13px] tracking-[.16em] text-amber-300">{starRow(stars, maxStars)}</p>
            <p className="mt-1 text-[10px] text-slate-300">
              {t('common.levelShort')} {hero.level}{maxLevel ? ` / ${maxLevel}` : ''}
            </p>
            {/* Level progression: the XP curve and the daily cap are enforced server-side. */}
            <div className="mt-3 rounded-xl border border-sky-300/25 bg-sky-400/5 p-2 text-left">
              <div className="flex items-baseline justify-between gap-2">
                <p className="text-[8px] font-black uppercase tracking-[.2em] text-sky-200">{t('heroXp.title')}</p>
                <p className="text-[9px] font-black text-sky-100">
                  {xpMaxed ? t('heroXp.maxed') : t('heroXp.toNext', { xp: xpCurrent.toLocaleString(), need: xpNeed.toLocaleString(), next: hero.level + 1 })}
                </p>
              </div>
              <div className="mt-1.5 h-2 overflow-hidden rounded-full border border-white/10 bg-black/60">
                <div className="h-full rounded-full bg-gradient-to-r from-sky-400 to-cyan-300 transition-[width] duration-500" style={{ width: `${xpMaxed ? 100 : xpPercent}%` }} />
              </div>
              {dailyCap > 0 ? (
                <p className={`mt-1 text-[8px] font-black uppercase tracking-[.14em] ${dailyXp >= dailyCap ? 'text-rose-300' : 'text-slate-400'}`}>
                  {dailyXp >= dailyCap ? t('heroXp.dailyFull') : t('heroXp.daily', { used: dailyXp.toLocaleString(), cap: dailyCap.toLocaleString() })}
                </p>
              ) : null}
            </div>
            <div className="mt-3 rounded-xl border border-amber-300/30 bg-amber-300/10 py-2">

              <p className="text-[8px] uppercase tracking-[.24em] text-amber-200">{t('common.power')}</p>
              <p className="text-xl font-black text-amber-200">
                {(equipment?.stats.power ?? Number(hero.power ?? 0)).toLocaleString()}
              </p>
              {equipment && equipment.stats.power > equipment.stats.basePower ? (
                <p className="text-[8px] font-black text-emerald-300">
                  {equipment.stats.basePower.toLocaleString()} → {equipment.stats.power.toLocaleString()}
                </p>
              ) : null}
            </div>
            {veteran ? (
              /* Veteran line: MYTH-only mining, paid by the premium pool (never TON). */
              <div className="mt-2 rounded-xl border border-amber-300/30 bg-amber-300/10 py-2">
                <p className="text-[8px] uppercase tracking-[.24em] text-amber-200">{t('mining.heroRate')}</p>
                <p className="text-[13px] font-black text-amber-100">{veteranMyth.toLocaleString()} MYTH {perDaySuffix}</p>
              </div>
            ) : isMiningRarity(hero.rarity) ? (
              miningRate > 0 || nftMyth > 0 ? (
                <div className="mt-2 rounded-xl border border-cyan-300/30 bg-cyan-300/10 py-2">
                  <p className="text-[8px] uppercase tracking-[.24em] text-cyan-200">{t('mining.heroRate')}</p>
                  {nftMyth > 0 ? (
                    <p className="text-[13px] font-black text-amber-100">{nftMyth.toLocaleString('pt-BR')} MYTH {perDaySuffix}</p>
                  ) : null}
                  {miningRate > 0 ? (
                    <p className="text-[13px] font-black text-cyan-100">{formatMiningAmount(effectiveDailyMining(miningRate, mining), mining.currency, 6)} {miningSymbol(mining.currency)} {perDaySuffix}</p>
                  ) : null}
                </div>
              ) : null

            ) : (
              /* Common/Uncommon: discreet note so the player understands why it never mines. */
              <div className="mt-2 rounded-xl border border-white/10 bg-white/5 py-2">
                <p className="text-[8px] uppercase tracking-[.24em] text-white/40">{t('mining.heroRate')}</p>
                <p className="text-[10px] font-black uppercase tracking-[.12em] text-white/50">{t('mining.unavailable')}</p>
                <p className="mt-0.5 text-[8px] text-white/35">{t('mining.requiresRare')}</p>
              </div>
            )}
            <div className="mt-2 grid grid-cols-2 gap-2">
              {stat('ATK', (equipment?.stats.atk ?? Number(hero.finalAtk ?? 0)).toLocaleString(), equipment?.stats.equipAtk)}
              {stat('HP', (equipment?.stats.hp ?? Number(hero.finalHp ?? 0)).toLocaleString(), equipment?.stats.equipHp)}
              {stat('DEF', (equipment?.stats.def ?? Number(hero.defense ?? 0)).toLocaleString(), equipment?.stats.equipDef)}
              {stat('SPD', (equipment?.stats.spd ?? Number(hero.speed ?? 0)).toLocaleString())}
            </div>
            {hero.isNft ? (
              <p className="mt-2 rounded-lg border border-cyan-300/40 bg-cyan-300/10 py-1 text-[8px] font-black uppercase tracking-[.14em] text-cyan-200">
                NFT Exclusive #{String(hero.nftSerial ?? 0).padStart(3, '0')}
              </p>
            ) : null}
          </div>
        </div>

        <HeroEquipmentSlots telegramInitData={telegramInitData} heroId={hero.heroId} onState={setEquipment} />

      </div>
    </div>
  );
}
