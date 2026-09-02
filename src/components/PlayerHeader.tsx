import { useEffect, useState } from 'react';
import { coin } from '../gameAssets';
import tonIcon from '../assets/ton-coin.png';
import avatarBorderMyth from '../assets/avatar-border-myth.png.asset.json';
import avatarBorderFounder from '../assets/avatar-border-founder.png.asset.json';
import avatarBorderArenaKing from '../assets/avatar-border-arena-king.png.asset.json';
import avatarBorderTopSpender from '../assets/avatar-border-top-spender.png.asset.json';
import { formatTon } from '../economy';
import { formatCurrency } from '../utils';

import { getDisplayName, getInitials, type TelegramPlayerProfile } from '../playerProfile';
import { usePremiumTitles, resolvePremiumTitle } from '../premiumTitles';
import { useT } from '../LanguageContext';


/** Exclusive cosmetic frames unlocked by rewards (MYTH SALE 100k, FOUNDER PACK, ARENA KING, TOP SPENDER). */
const AVATAR_BORDERS: Record<string, string> = {
  myth_sale_exclusive: avatarBorderMyth.url,
  founder_exclusive: avatarBorderFounder.url,
  arena_king_exclusive: avatarBorderArenaKing.url,
  top_spender_exclusive: avatarBorderTopSpender.url,
};

export function PlayerAvatar({ profile }: { profile: TelegramPlayerProfile | null }) {
  const t = useT();
  const [failed, setFailed] = useState(false);
  const name = profile ? getDisplayName(profile) : t('profile.player');
  useEffect(() => setFailed(false), [profile?.photoUrl]);
  const borderUrl = profile?.avatarBorder ? AVATAR_BORDERS[profile.avatarBorder] : undefined;
  const inner = profile?.photoUrl && !failed ? (
    <img
      src={profile.photoUrl}
      onError={() => setFailed(true)}
      alt={name}
      className="player-avatar rounded-full border-2 border-amber-400/60 bg-black object-cover"
    />
  ) : (
    <div className="player-avatar grid place-items-center rounded-full border-2 border-amber-400/60 bg-slate-900 text-[10px] font-black text-amber-100">
      {getInitials(name)}
    </div>
  );
  if (!borderUrl) return inner;
  return (
    <div className="player-avatar-frame" title="Exclusive Avatar Border">
      {inner}
      <img src={borderUrl} alt="" loading="lazy" className="player-avatar-frame-ring" />
    </div>
  );
}


export function PlayerIdentity({
  profile,
  loading,
  onRetry
}: {
  profile: TelegramPlayerProfile | null;
  loading?: boolean;
  onRetry?: () => void;
}) {
  const t = useT();
  const titles = usePremiumTitles();
  const title = profile
    ? profile.premiumTitle || resolvePremiumTitle(titles, { telegramId: profile.telegramId, username: profile.username })
    : null;
  return (
    <div className="player-identity">
      {loading && !profile ? <div className="player-avatar animate-pulse rounded-full bg-white/10" /> : <PlayerAvatar profile={profile} />}
      <div className="player-texts">
        {profile ? (
          <>
            <p className="player-name font-black text-white">{getDisplayName(profile)}</p>
            <p className={`player-username leading-tight ${title ? 'premium-title player-premium-title' : 'truncate text-[10px] text-sky-300'}`}>
              {title ? `👑 ${title}` : profile.username ? `@${profile.username}` : t('profile.noUsername')}
            </p>


            <p className="player-tgid truncate text-[9px] leading-tight text-slate-400">ID: {profile.telegramId}</p>
          </>
        ) : (
          <>
            <p className="player-name font-black text-white">{t('profile.player')}</p>
            {!loading && onRetry ? (
              <button type="button" onClick={onRetry} className="block truncate whitespace-nowrap text-[9px] text-amber-300">
                {t('profile.tryAgain')}
              </button>
            ) : null}
          </>
        )}
      </div>
    </div>
  );
}

export function BalanceChip({ balance, onClick }: { balance: number; onClick?: () => void }) {
  const t = useT();
  const value = formatCurrency(balance);
  const Tag = onClick ? 'button' : 'div';
  return (
    <Tag
      {...(onClick ? { type: 'button' as const, onClick } : {})}
      className="balance-chip flex items-center gap-1.5 rounded-xl border border-amber-400/40 bg-black/80 px-2 py-1.5 text-amber-200 shadow-[inset_0_0_18px_rgba(245,158,11,.08)]"
      aria-label={t('profile.balanceAria', { value })}
    >
      <img src={coin} alt="" className="balance-chip-coin shrink-0 object-contain drop-shadow-[0_0_6px_rgba(251,191,36,.45)]" />
      <span className="min-w-0 flex-1 text-right">
        <span className="balance-chip-value block font-black text-amber-100">{value}</span>
        <span className="balance-chip-label block uppercase tracking-[.12em] text-slate-400">FC</span>
      </span>
    </Tag>
  );
}

/** Withdrawable TON (rewards only) — never a converted FC value. */
export function TonBalanceChip({
  balance,
  onClick,
  variant = 'default'
}: {
  balance: number;
  onClick?: () => void;
  variant?: 'default' | 'villageCompact';
}) {
  const t = useT();
  const value = formatTon(balance);
  const Tag = onClick ? 'button' : 'div';
  return (
    <Tag
      {...(onClick ? { type: 'button' as const, onClick } : {})}
      className={`balance-chip ton-balance-chip flex items-center gap-1.5 rounded-xl border border-sky-400/40 bg-black/80 px-2 py-1.5 text-sky-200 shadow-[inset_0_0_18px_rgba(56,189,248,.1)] ${variant === 'villageCompact' ? 'ton-balance-chip--village-compact' : ''}`}
      aria-label={t('profile.tonBalanceAria', { value })}
    >
      <img src={tonIcon} alt="" className="balance-chip-coin ton-balance-chip-coin shrink-0 object-contain drop-shadow-[0_0_6px_rgba(56,189,248,.5)]" />
      <span className="min-w-0 flex-1 text-right">
        <span className="balance-chip-value ton-balance-chip-value block font-black text-sky-100">{value}</span>
        <span className="balance-chip-label ton-balance-chip-label block uppercase tracking-[.12em] text-slate-400">TON</span>
      </span>
    </Tag>
  );
}


export function PlayerHeader({
  profile,
  loading,
  onRetry,
  balance,
  tonBalance,
  onBalanceClick,
  actions,
  className = '',
  tonChipVariant = 'default'
}: {
  profile: TelegramPlayerProfile | null;
  loading?: boolean;
  onRetry?: () => void;
  balance: number;
  tonBalance?: number;
  onBalanceClick?: () => void;
  actions?: React.ReactNode;
  className?: string;
  tonChipVariant?: 'default' | 'villageCompact';
}) {
  return (
    <div className={`player-header ${className}`}>
      <PlayerIdentity profile={profile} loading={loading} onRetry={onRetry} />
      <div className="flex shrink-0 items-center gap-1.5">
        <BalanceChip balance={balance} onClick={onBalanceClick} />
        {typeof tonBalance === 'number' ? <TonBalanceChip balance={tonBalance} onClick={onBalanceClick} variant={tonChipVariant} /> : null}
      </div>
      {actions}
    </div>
  );
}


