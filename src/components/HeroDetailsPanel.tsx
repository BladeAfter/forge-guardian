import { X } from 'lucide-react';
import type { PvpHero } from '../pvp';
import type { FusionHero } from '../heroFusion';
import { starRow } from '../heroFusion';
import { HeroEquipmentSlots } from './HeroEquipmentSlots';
import { useT } from '../LanguageContext';

const RARITY_COLOR: Record<string, string> = {
  common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc',
  legendary: '#fbbf24', mythic: '#fb7185', ancestral: '#f472b6', nft_exclusive: '#22d3ee',
};

/** Read-only hero sheet: stats come from the same rows used by PvP/Boss. */
export function HeroDetailsPanel({ hero, state, maxStars, onClose }: { hero: PvpHero; state?: FusionHero | null; maxStars: number; onClose: () => void }) {
  const t = useT();
  const stars = state?.stars ?? hero.stars ?? 0;
  const maxLevel = state?.maxLevel ?? null;
  const accent = RARITY_COLOR[String(hero.rarity)] ?? '#94a3b8';
  const stat = (label: string, value: string | number) => (
    <div key={label} className="rounded-xl border border-white/10 bg-black/50 px-2 py-1.5 text-center">
      <p className="text-[8px] uppercase tracking-[.16em] text-slate-400">{label}</p>
      <p className="text-[12px] font-black text-white">{value}</p>
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
              <p className="text-xl font-black text-amber-200">{Number(hero.power ?? 0).toLocaleString()}</p>
            </div>
            <div className="mt-2 grid grid-cols-2 gap-2">
              {stat('ATK', Number(hero.finalAtk ?? 0).toLocaleString())}
              {stat('HP', Number(hero.finalHp ?? 0).toLocaleString())}
              {hero.defense ? stat('DEF', Number(hero.defense).toLocaleString()) : null}
              {hero.speed ? stat('SPD', Number(hero.speed).toLocaleString()) : null}
            </div>
            {hero.isNft ? (
              <p className="mt-2 rounded-lg border border-cyan-300/40 bg-cyan-300/10 py-1 text-[8px] font-black uppercase tracking-[.14em] text-cyan-200">
                NFT Exclusive #{String(hero.nftSerial ?? 0).padStart(3, '0')}
              </p>
            ) : null}
          </div>
        </div>

        <HeroEquipmentSlots />
      </div>
    </div>
  );
}
