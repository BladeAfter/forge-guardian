import { useState } from 'react';
import { X } from 'lucide-react';
import type { PvpHero } from '../pvp';
import type { FusionHero } from '../heroFusion';
import { starRow } from '../heroFusion';
import { HeroEquipmentSlots } from './HeroEquipmentSlots';
import type { HeroEquipmentState } from '../heroEquipment';
import { useT } from '../LanguageContext';
import { formatMiningTon, heroDailyRate, isMiningRarity } from '../heroMining';

const RARITY_COLOR: Record<string, string> = {
  common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc',
  legendary: '#fbbf24', mythic: '#fb7185', ancestral: '#f472b6', nft_exclusive: '#22d3ee',
};

/** Hero sheet: stats come from the same rows used by PvP/Boss, equipment included. */
export function HeroDetailsPanel({ hero, state, maxStars, telegramInitData, miningRates, onClose }: { hero: PvpHero; state?: FusionHero | null; maxStars: number; telegramInitData: string; miningRates?: Record<string, number>; onClose: () => void }) {
  const t = useT();
  const [equipment, setEquipment] = useState<HeroEquipmentState | null>(null);

  const stars = state?.stars ?? hero.stars ?? 0;
  const maxLevel = state?.maxLevel ?? null;
  const accent = RARITY_COLOR[String(hero.rarity)] ?? '#94a3b8';
  // Mining depends ONLY on rarity: level and equipment never change it.
  const miningRate = heroDailyRate(miningRates, hero.rarity);
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
          <img src={hero.imageUrl} alt={hero.name} className="aspect-square w-full object-cover" />
          <div className="p-3 text-center">
            <p className="text-[10px] font-black uppercase tracking-[.18em]" style={{ color: accent }}>
              {t(`rarity.${hero.rarity}`)} · {String(hero.archetype ?? '').toUpperCase()}
            </p>
            <p className="mt-1 text-[13px] tracking-[.16em] text-amber-300">{starRow(stars, maxStars)}</p>
            <p className="mt-1 text-[10px] text-slate-300">
              {t('common.levelShort')} {hero.level}{maxLevel ? ` / ${maxLevel}` : ''}
            </p>
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
            {isMiningRarity(hero.rarity) ? (
              miningRate > 0 ? (
                <div className="mt-2 rounded-xl border border-cyan-300/30 bg-cyan-300/10 py-2">
                  <p className="text-[8px] uppercase tracking-[.24em] text-cyan-200">{t('mining.heroRate')}</p>
                  <p className="text-[13px] font-black text-cyan-100">{formatMiningTon(miningRate, 6)} {t('mining.perDay')}</p>
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
