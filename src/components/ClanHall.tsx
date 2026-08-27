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
      <svg viewBox="0 0 100 104" width={size} height={size} style={{ overflow: 'visible' }}>
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
          <radialGradient id={`gem-${uid}`} cx="0.35" cy="0.25" r="0.9">
            <stop offset="0%" stopColor="#ffffff" />
            <stop offset="55%" stopColor={c.gem} />
            <stop offset="100%" stopColor={silver ? '#64748b' : '#8c5f10'} />
          </radialGradient>
        </defs>

        {/* outer frame + inner field */}
        <path d={outline} fill={`url(#gold-${uid})`} />
        <path d={outline} fill="none" stroke="#00000066" strokeWidth="1.6" />
        <g transform="translate(50 52) scale(0.86) translate(-50 -52)">
          <path d={outline} fill={`url(#field-${uid})`} stroke={frameB} strokeWidth="1.5" />
        </g>

        {/* laurel sprigs framing the lower field */}
        <g stroke={frameA} fill="none" opacity="0.5" strokeLinecap="round" strokeWidth="1.1">
          <path d="M23 55c-3 9-1 17 5 23" />
          <path d="M77 55c3 9 1 17-5 23" />
          <g fill={frameA} opacity="0.7" stroke="none">
            <ellipse cx="20.5" cy="60" rx="2.5" ry="1.3" transform="rotate(-28 20.5 60)" />
            <ellipse cx="21.5" cy="68" rx="2.4" ry="1.3" transform="rotate(-12 21.5 68)" />
            <ellipse cx="25" cy="76" rx="2.3" ry="1.2" transform="rotate(14 25 76)" />
            <ellipse cx="79.5" cy="60" rx="2.5" ry="1.3" transform="rotate(28 79.5 60)" />
            <ellipse cx="78.5" cy="68" rx="2.4" ry="1.3" transform="rotate(12 78.5 68)" />
            <ellipse cx="75" cy="76" rx="2.3" ry="1.2" transform="rotate(-14 75 76)" />
          </g>
        </g>

        {/* magical runes */}
        <g opacity="0.45" fill={c.gem}>
          <circle cx="31" cy="40" r="1.1" /><circle cx="69" cy="40" r="1.1" />
        </g>

        {/* central gem plaque with the clan initials */}
        <ellipse cx="50" cy="52" rx="18" ry="13" fill={`url(#gem-${uid})`} />
        <ellipse cx="50" cy="52" rx="18" ry="13" fill="none" stroke={frameA} strokeWidth="1.3" />
        <ellipse cx="50" cy="47" rx="12.5" ry="5" fill="#ffffff" opacity="0.26" />
        {mark ? (
          <text
            x="50" y="57.5" textAnchor="middle" fontSize={mark.length > 2 ? 15 : 18}
            fontWeight="900" fill="#0b1020" letterSpacing="0.4"
            fontFamily="ui-sans-serif, system-ui, sans-serif"
          >
            {mark}
          </text>
        ) : null}

        {/* crown, drawn above the frame so its points stay crisp */}
        <g fill={`url(#gold-${uid})`} stroke="#00000055" strokeWidth="0.9" strokeLinejoin="round">
          <path d="M31 26 36 12l7 9 7-13 7 13 7-9 5 14-4 5H35Z" />
          <rect x="33" y="29" width="34" height="5" rx="2" />
        </g>
        <circle cx="50" cy="12" r="2.6" fill={c.gem} stroke={frameA} strokeWidth="0.7" />
        <circle cx="36" cy="12.5" r="1.5" fill={c.gem} opacity="0.9" />
        <circle cx="64" cy="12.5" r="1.5" fill={c.gem} opacity="0.9" />

        {/* heraldic seal under the plaque */}
        <g transform="translate(50 76)">
          <path d="M0 -5 4.5 0 0 5 -4.5 0Z" fill={`url(#gold-${uid})`} stroke="#00000055" strokeWidth="0.6" />
          <circle cx="0" cy="0" r="1.5" fill={c.gem} />
        </g>

        {/* cinematic rim light */}
        <path d={outline} fill="none" stroke="#ffffff" strokeWidth="1" opacity="0.16" />
      </svg>

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
