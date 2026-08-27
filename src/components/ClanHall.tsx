import { Plus, Shield } from 'lucide-react';
import type { ClanEmblem, ClanSummary } from '../clans';
import { useT } from '../LanguageContext';
import { buildings } from '../gameAssets';
import crestNavy from '../assets/clan-crest-navy.png';
import crestPurple from '../assets/clan-crest-purple.png';
import crestCrimson from '../assets/clan-crest-crimson.png';
import crestEmerald from '../assets/clan-crest-emerald.png';


/** Banner colours mirror the clan emblem background so the flags read as clan colours. */
const BANNER_COLORS: Record<string, { top: string; bottom: string }> = {
  navy: { top: '#3b6ad4', bottom: '#0b1631' },
  purple: { top: '#8b5cf6', bottom: '#25103f' },
  crimson: { top: '#e0435a', bottom: '#360a11' },
  emerald: { top: '#2fbd91', bottom: '#062018' },
};



/** Heraldic palette per emblem background: gem + inner field colours of the crest. */
const CREST_COLORS: Record<string, { deep: string; mid: string; gem: string; glow: string }> = {
  navy: { deep: '#050b18', mid: '#16305f', gem: '#57c8ff', glow: 'rgba(87,200,255,.55)' },
  purple: { deep: '#0d0618', mid: '#3d1d68', gem: '#c084fc', glow: 'rgba(192,132,252,.5)' },
  crimson: { deep: '#170406', mid: '#63161f', gem: '#ff6b7f', glow: 'rgba(255,107,127,.5)' },
  emerald: { deep: '#03130e', mid: '#0f4436', gem: '#4ade9b', glow: 'rgba(74,222,155,.5)' },
};

/**
 * Plaque geometry of each rendered crest artwork (percentages of the image box),
 * so the clan initials sit exactly inside the engraved nameplate of the art.
 */
const CREST_ART: Record<string, { src: string; x: number; y: number; w: number; ink: string; shadow: string }> = {
  navy: { src: crestNavy, x: 50, y: 76.5, w: 27, ink: '#bfe4ff', shadow: 'rgba(0,0,0,.85)' },
  purple: { src: crestPurple, x: 50, y: 63, w: 22, ink: '#2b1405', shadow: 'rgba(255,236,170,.55)' },
  crimson: { src: crestCrimson, x: 50, y: 70, w: 33, ink: '#2b1a02', shadow: 'rgba(255,236,170,.55)' },
  emerald: { src: crestEmerald, x: 50, y: 63.5, w: 26, ink: '#d8ffe9', shadow: 'rgba(0,0,0,.8)' },
};

/**
 * PREMIUM CLAN CREST — AAA rendered heraldic emblem artwork (gold shield, crown,
 * dragon, laurels and arcane gem) instead of a flat icon. The clan initials are
 * typeset into the engraved nameplate of the artwork for each colour variant.
 */
export function ClanCrest({
  emblem, size = 44, initials,
}: { emblem?: ClanEmblem | null; size?: number; initials?: string; shape?: 'shield' | 'badge' }) {
  const key = emblem?.background ?? 'navy';
  const c = CREST_COLORS[key] ?? CREST_COLORS.navy;
  const art = CREST_ART[key] ?? CREST_ART.navy;
  const mark = (initials ?? '').replace(/[^A-Za-z0-9]/g, '').slice(0, 3).toUpperCase();

  return (
    <span
      style={{ width: size, height: size, filter: `drop-shadow(0 0 ${size * 0.18}px ${c.glow})` }}
      className="relative inline-block shrink-0 align-middle"
      aria-hidden
    >
      <img
        src={art.src}
        alt=""
        width={1024}
        height={1024}
        loading="lazy"
        className="absolute inset-0 h-full w-full select-none object-contain"
        draggable={false}
      />
      {mark && size >= 34 ? (
        <span
          className="absolute font-black leading-none"
          style={{
            left: `${art.x}%`,
            top: `${art.y}%`,
            width: `${art.w}%`,
            transform: 'translate(-50%,-50%)',
            fontSize: size * (art.w / 100) * (mark.length > 2 ? 0.42 : 0.56),
            letterSpacing: '0.02em',
            textAlign: 'center',
            color: art.ink,
            textShadow: `0 1px 1px ${art.shadow}`,
            fontFamily: 'ui-sans-serif, system-ui, sans-serif',
          }}
        >
          {mark}
        </span>
      ) : null}
    </span>
  );
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
 * Clan Hall: a real building of the village scenery — painted asset with a transparent
 * silhouette, torch flames, clan banners and a tiny wooden sign. No card, no panel:
 * the background behind it stays the city itself.
 */
export function ClanHall({ clan, onOpen }: { clan?: ClanSummary | null; onOpen: () => void }) {
  const t = useT();
  const banner = BANNER_COLORS[clan?.emblem?.background ?? ''] ?? { top: '#1f3a63', bottom: '#07101f' };
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onOpen}
      onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onOpen(); } }}
      aria-label={t('clan.hall')}
      className="clan-hall"
    >
      {/* ground contact: the building base melts into the street */}
      <span className="clan-hall-ground" aria-hidden />
      <span className="clan-hall-shape" aria-hidden>
        <img src={buildings['clan-hall']} alt="" width={1024} height={1024} loading="lazy" className="clan-hall-art" />
        <span className="clan-hall-window-glow" />
        <span className="clan-hall-torch clan-hall-torch--left"><i /></span>
        <span className="clan-hall-torch clan-hall-torch--right"><i /></span>
        <span className="clan-hall-smoke"><i /><i /></span>
        <span className="clan-hall-motes"><i /><i /><i /><i /></span>
        <span className="clan-hall-flag clan-hall-flag--left" style={{ ['--flag-top' as string]: banner.top, ['--flag-bottom' as string]: banner.bottom }}>
          <b />
        </span>
        <span className="clan-hall-flag clan-hall-flag--right" style={{ ['--flag-top' as string]: banner.top, ['--flag-bottom' as string]: banner.bottom }}>
          <b />
        </span>
        {!clan ? (
          <span className="clan-hall-invite" aria-hidden>
            <Shield />
            <Plus />
          </span>
        ) : null}
      </span>

      {/* tiny medieval sign — part of the scenery, not a card */}
      <span className="clan-hall-sign">
        {clan ? <ClanCrest emblem={clan.emblem} size={16} /> : null}
        <span className="clan-hall-sign-text">
          <b>{clan ? clan.name : t('clan.hall')}</b>
          <i>{clan ? `Lv. ${clan.level}` : t('clan.chipJoin')}</i>
        </span>
      </span>
    </div>
  );
}
