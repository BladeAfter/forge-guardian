import { grandFleetArt } from '../gameAssets';
import { Plus, Shield } from 'lucide-react';
import type { ClanEmblem, ClanSummary } from '../clans';
import { useT } from '../LanguageContext';



/** Cosmetic pirate flag; existing emblem identifiers and membership stay unchanged. */
export function ClanCrest({ size = 44, initials }: { emblem?: ClanEmblem | null; size?: number; initials?: string; shape?: 'shield' | 'badge' }) {
  return <span className="fleet-crest" style={{ width: size, height: size }} aria-hidden><img src={grandFleetArt.emblem} width={1024} height={1024} loading="lazy" alt="" />{initials && size >= 34 ? <b>{initials.slice(0,5)}</b> : null}</span>;
}

/**
 * Legacy compact chip. No longer rendered in the village (the Clan Hall building is
 * the single entry point), kept exported for other screens that may reuse it.
 */
export function ClanStatusChip({ clan, onOpen }: { clan?: ClanSummary | null; onOpen: () => void }) {
  const t = useT();
  return (
    <button
      type="button"
      onClick={onOpen}
      className="clan-chip flex w-full items-center gap-2 rounded-xl border border-amber-300/25 bg-[#080c13]/85 px-2 py-1.5 text-left shadow-[0_8px_20px_rgba(0,0,0,.5)] backdrop-blur-sm transition active:scale-[.98]"
    >
      {clan ? <ClanCrest emblem={clan.emblem} size={30} /> : (
        <span className="relative grid h-[30px] w-[30px] shrink-0 place-items-center rounded-xl border border-amber-300/40 bg-black/70">
          <Shield className="h-4 w-4 text-amber-300" />
          <Plus className="absolute -bottom-0.5 -right-0.5 h-3 w-3 rounded-full bg-amber-400 text-black" />
        </span>
      )}
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[10px] font-black uppercase tracking-[.14em] text-amber-200">
          {clan ? clan.name : t('clan.chip')}
        </span>
        <span className="block truncate text-[8px] font-bold uppercase text-slate-400">
          {clan ? `Lv. ${clan.level} • ${clan.members}/${clan.memberLimit}` : t('clan.chipJoin')}
        </span>
      </span>
      {clan ? <span className="h-2 w-2 shrink-0 rounded-full bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,.9)]" /> : null}
    </button>
  );
}

/**
 * Clan Hall: accessible hotspot aligned with the building in the village artwork.
 */
export function ClanHall({ clan, onOpen }: { clan?: ClanSummary | null; onOpen: () => void }) {
  const t = useT();
  return (
    <div className="clan-scene-hit-layer">
      <div className="clan-scene-hit-art">
        <button
          type="button"
          onClick={onOpen}
          aria-label={clan ? `${t('clan.hall')}: ${clan.name}` : t('clan.hall')}
          className="clan-hall"
        />
      </div>
    </div>
  );
}
