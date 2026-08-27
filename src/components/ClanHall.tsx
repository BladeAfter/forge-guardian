import { Plus, Shield } from 'lucide-react';
import type { ClanEmblem, ClanSummary } from '../clans';
import { useT } from '../LanguageContext';
import { buildings } from '../gameAssets';

/** Banner colours mirror the clan emblem background so the flags read as clan colours. */
const BANNER_COLORS: Record<string, { top: string; bottom: string }> = {
  navy: { top: '#3b6ad4', bottom: '#0b1631' },
  purple: { top: '#8b5cf6', bottom: '#25103f' },
  crimson: { top: '#e0435a', bottom: '#360a11' },
  emerald: { top: '#2fbd91', bottom: '#062018' },
};

const SYMBOLS: Record<string, string> = { dragon: '🐲', sword: '⚔️', wolf: '🐺', crown: '👑', flame: '🔥', skull: '💀' };

/** Heraldic palette per emblem background: gem + inner field colours of the crest. */
const CREST_COLORS: Record<string, { deep: string; mid: string; gem: string; glow: string }> = {
  navy: { deep: '#050b18', mid: '#16305f', gem: '#57c8ff', glow: 'rgba(87,200,255,.55)' },
  purple: { deep: '#0d0618', mid: '#3d1d68', gem: '#c084fc', glow: 'rgba(192,132,252,.5)' },
  crimson: { deep: '#170406', mid: '#63161f', gem: '#ff6b7f', glow: 'rgba(255,107,127,.5)' },
  emerald: { deep: '#03130e', mid: '#0f4436', gem: '#4ade9b', glow: 'rgba(74,222,155,.5)' },
};

/**
 * PREMIUM CLAN CREST — real heraldic badge instead of a flat square icon.
 * Layered gold frame + shield field + crown, magical gem, laurel wings, runes and the
 * clan initials. Rendered as inline SVG so any clan gets a unique crest from its own
 * saved emblem config (background / symbol / border) with zero assets to load.
 */
export function ClanCrest({
  emblem, size = 44, initials, shape = 'shield',
}: { emblem?: ClanEmblem | null; size?: number; initials?: string; shape?: 'shield' | 'badge' }) {
  const c = CREST_COLORS[emblem?.background ?? 'navy'] ?? CREST_COLORS.navy;
  const silver = emblem?.border === 'silver';
  const frameA = silver ? '#f1f5f9' : '#ffe89a';
  const frameB = silver ? '#7c8798' : '#b07d1c';
  const uid = `${emblem?.background ?? 'navy'}-${emblem?.symbol ?? 'dragon'}-${silver ? 's' : 'g'}-${shape}`;
  const mark = (initials ?? '').replace(/[^A-Za-z0-9]/g, '').slice(0, 3).toUpperCase();
  const symbol = SYMBOLS[emblem?.symbol ?? 'dragon'] ?? SYMBOLS.dragon;
  const outline =
    shape === 'badge'
      ? 'M50 4 90 26 90 74 50 96 10 74 10 26Z'
      : 'M50 4C68 10 80 12 92 12v40c0 24-18 38-42 48C26 90 8 76 8 52V12c12 0 24-2 42-8Z';

  return (
    <span
      style={{ width: size, height: size, filter: `drop-shadow(0 0 ${size * 0.16}px ${c.glow})` }}
      className="relative inline-block shrink-0 align-middle"
      aria-hidden
    >
      <svg viewBox="0 0 100 100" width={size} height={size}>
        <defs>
          <linearGradient id={`gold-${uid}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={frameA} />
            <stop offset="45%" stopColor={silver ? '#cbd5e1' : '#e0a52c'} />
            <stop offset="100%" stopColor={frameB} />
          </linearGradient>
          <linearGradient id={`field-${uid}`} x1="0" y1="0" x2="0.3" y2="1">
            <stop offset="0%" stopColor={c.mid} />
            <stop offset="100%" stopColor={c.deep} />
          </linearGradient>
          <radialGradient id={`gem-${uid}`} cx="0.4" cy="0.3" r="0.8">
            <stop offset="0%" stopColor="#ffffff" />
            <stop offset="35%" stopColor={c.gem} />
            <stop offset="100%" stopColor={c.deep} />
          </radialGradient>
        </defs>

        {/* outer gold frame + inner field */}
        <path d={outline} fill={`url(#gold-${uid})`} />
        <path d={outline} fill="none" stroke="#00000055" strokeWidth="1.5" />
        <g transform="translate(50 50) scale(0.87) translate(-50 -50)">
          <path d={outline} fill={`url(#field-${uid})`} stroke={frameB} strokeWidth="1.6" />
        </g>
        {/* magical runes framing the field */}
        <g opacity="0.5" fill={c.gem}>
          <circle cx="22" cy="34" r="1.3" /><circle cx="78" cy="34" r="1.3" />
          <circle cx="26" cy="58" r="1" /><circle cx="74" cy="58" r="1" />
        </g>
        {/* laurel wings */}
        <g stroke={frameA} strokeWidth="1.4" fill="none" opacity="0.7" strokeLinecap="round">
          <path d="M20 46c-5 6-5 14 0 20" /><path d="M80 46c5 6 5 14 0 20" />
        </g>
        {/* crown */}
        <g fill={`url(#gold-${uid})`} stroke="#00000044" strokeWidth="0.8">
          <path d="M32 26 38 16l6 8 6-11 6 11 6-8 6 10-3 6H35Z" />
        </g>
        <circle cx="50" cy="16" r="2.4" fill={c.gem} />
        {/* central gem + initials or symbol */}
        <ellipse cx="50" cy="45" rx="12" ry="13" fill={`url(#gem-${uid})`} opacity="0.95" />
        <ellipse cx="50" cy="45" rx="12" ry="13" fill="none" stroke={frameA} strokeWidth="1.2" opacity="0.85" />
        {mark ? (
          <text
            x="50" y="50" textAnchor="middle" fontSize={mark.length > 2 ? 12 : 15}
            fontWeight="900" fill="#0b1020" letterSpacing="0.5"
          >
            {mark}
          </text>
        ) : null}
        {/* cinematic highlight */}
        <path d={outline} fill="none" stroke="#ffffff" strokeWidth="1" opacity="0.18" />
      </svg>
      {!mark ? (
        <span
          style={{ fontSize: size * 0.28 }}
          className="pointer-events-none absolute left-1/2 top-[46%] -translate-x-1/2 -translate-y-1/2 leading-none"
        >
          {symbol}
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
