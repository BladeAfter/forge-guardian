import { Plus, Shield } from 'lucide-react';
import type { ClanEmblem, ClanSummary } from '../clans';
import { useT } from '../LanguageContext';

const BACKGROUNDS: Record<string, string> = {
  navy: 'from-[#12224a] to-[#070c18]',
  purple: 'from-[#3a1d5e] to-[#120a20]',
  crimson: 'from-[#5c1420] to-[#1b0709]',
  emerald: 'from-[#0f4034] to-[#06140f]',
};

const SYMBOLS: Record<string, string> = { dragon: '🐲', sword: '⚔️', wolf: '🐺', crown: '👑', flame: '🔥', skull: '💀' };

/** Emblem is built from saved config (shield/background/symbol/border) — no manual upload needed. */
export function ClanCrest({ emblem, size = 44 }: { emblem?: ClanEmblem | null; size?: number }) {
  const background = BACKGROUNDS[emblem?.background ?? 'navy'] ?? BACKGROUNDS.navy;
  const border = emblem?.border === 'silver' ? 'border-slate-300/70' : 'border-amber-300/70';
  return (
    <span
      style={{ width: size, height: size }}
      className={`grid shrink-0 place-items-center rounded-xl border-2 bg-gradient-to-br ${background} ${border} shadow-[0_0_14px_rgba(0,0,0,.6)]`}
    >
      <span style={{ fontSize: size * 0.5 }} className="leading-none">{SYMBOLS[emblem?.symbol ?? 'dragon'] ?? SYMBOLS.dragon}</span>
    </span>
  );
}

/**
 * Compact clan status placed right under the player header. It opens exactly the
 * same ClanHub as the Clan Hall building — one system, two entry points.
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
 * Clan Hall: a building of the village scenery (not a side card). It is anchored
 * to the centre of the map container with relative units so it survives every
 * Telegram Mini App width (360 → 430px).
 */
export function ClanHall({ clan, onOpen }: { clan?: ClanSummary | null; onOpen: () => void }) {
  const t = useT();
  const bannerFrom = clan ? 'from-purple-500/80' : 'from-slate-400/50';
  return (
    <button
      type="button"
      onClick={onOpen}
      aria-label={t('clan.hall')}
      className="clan-hall group absolute left-1/2 top-1/2 z-20 flex w-[43%] max-w-[190px] -translate-x-1/2 -translate-y-1/2 flex-col items-center outline-none"
    >
      <span className="pointer-events-none absolute inset-x-2 bottom-6 top-2 rounded-[30%_30%_18%_18%] bg-amber-300/0 blur-xl transition group-active:bg-amber-300/25 group-hover:bg-amber-300/20" />
      <span className="relative block h-[86px] w-full">
        {/* roof */}
        <span className="absolute left-1/2 top-0 h-0 w-0 -translate-x-1/2 border-x-[46px] border-b-[26px] border-x-transparent border-b-[#1d2740]" />
        {/* body */}
        <span className="absolute bottom-0 left-1/2 h-[58px] w-[78%] -translate-x-1/2 rounded-b-lg rounded-t-sm border border-amber-300/40 bg-gradient-to-b from-[#26303f] via-[#161d2b] to-[#0b111c] shadow-[0_10px_26px_rgba(0,0,0,.75)] transition group-hover:border-amber-300/80 group-active:border-amber-300/90">
          {/* warm windows */}
          <span className="absolute left-[18%] top-3 h-4 w-3 rounded-sm bg-amber-300/70 shadow-[0_0_10px_rgba(251,191,36,.7)] transition group-hover:bg-amber-200 group-active:bg-amber-200" />
          <span className="absolute right-[18%] top-3 h-4 w-3 rounded-sm bg-amber-300/70 shadow-[0_0_10px_rgba(251,191,36,.7)] transition group-hover:bg-amber-200 group-active:bg-amber-200" />
          {/* gate */}
          <span className="absolute bottom-0 left-1/2 h-6 w-7 -translate-x-1/2 rounded-t-full bg-gradient-to-b from-sky-400/70 to-sky-900/60 shadow-[0_0_14px_rgba(56,189,248,.55)]" />
          {/* crest over the gate */}
          <span className="absolute -top-3 left-1/2 -translate-x-1/2">
            <ClanCrest emblem={clan?.emblem} size={24} />
          </span>
        </span>
        {/* banners: neutral without a clan, clan colours once joined */}
        <span className={`clan-banner absolute bottom-2 left-[6%] h-9 w-3 rounded-b-sm bg-gradient-to-b ${bannerFrom} to-transparent`} />
        <span className={`clan-banner absolute bottom-2 right-[6%] h-9 w-3 rounded-b-sm bg-gradient-to-b ${bannerFrom} to-transparent`} />
      </span>
      <span className="relative mt-1 rounded-lg border border-amber-300/30 bg-black/70 px-2 py-1 text-center backdrop-blur-sm">
        <span className="block text-[9px] font-black uppercase tracking-[.14em] text-amber-200">{t('clan.hall')}</span>
        <span className="block text-[7px] font-bold uppercase text-slate-400">{t('clan.hallTap')}</span>
      </span>
    </button>
  );
}
