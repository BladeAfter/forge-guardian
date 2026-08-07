import { useEffect, useState } from 'react';
import { coin } from '../gameAssets';
import { formatCurrency } from '../utils';
import { getDisplayName, getInitials, type TelegramPlayerProfile } from '../playerProfile';

export function PlayerAvatar({ profile }: { profile: TelegramPlayerProfile | null }) {
  const [failed, setFailed] = useState(false);
  const name = profile ? getDisplayName(profile) : 'Jogador';
  useEffect(() => setFailed(false), [profile?.photoUrl]);
  return profile?.photoUrl && !failed ? (
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
  return (
    <div className="player-identity">
      {loading && !profile ? <div className="player-avatar animate-pulse rounded-full bg-white/10" /> : <PlayerAvatar profile={profile} />}
      <div className="player-texts">
        {profile ? (
          <>
            <p className="player-name font-black text-white">{getDisplayName(profile)}</p>
            <p className="player-username truncate text-[10px] leading-tight text-sky-300">
              {profile.username ? `@${profile.username}` : 'Sem username'}
            </p>
            <p className="player-tgid truncate text-[9px] leading-tight text-slate-400">ID: {profile.telegramId}</p>
          </>
        ) : (
          <>
            <p className="player-name font-black text-white">Jogador</p>
            {!loading && onRetry ? (
              <button type="button" onClick={onRetry} className="block truncate whitespace-nowrap text-[9px] text-amber-300">
                Tentar novamente
              </button>
            ) : null}
          </>
        )}
      </div>
    </div>
  );
}

export function BalanceChip({ balance }: { balance: number }) {
  const value = formatCurrency(balance);
  return (
    <div
      className="balance-chip flex items-center gap-1.5 rounded-xl border border-amber-400/40 bg-black/80 px-2 py-1.5 text-amber-200 shadow-[inset_0_0_18px_rgba(245,158,11,.08)]"
      aria-label={`Saldo: ${value} FC`}
    >
      <img src={coin} alt="" className="balance-chip-coin shrink-0 object-contain drop-shadow-[0_0_6px_rgba(251,191,36,.45)]" />
      <span className="min-w-0 flex-1 text-right">
        <span className="balance-chip-value block font-black text-amber-100">{value}</span>
        <span className="balance-chip-label block uppercase tracking-[.12em] text-slate-400">Forge Coins</span>
      </span>
    </div>
  );
}

export function PlayerHeader({
  profile,
  loading,
  onRetry,
  balance,
  actions,
  className = ''
}: {
  profile: TelegramPlayerProfile | null;
  loading?: boolean;
  onRetry?: () => void;
  balance: number;
  actions?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={`player-header ${className}`}>
      <PlayerIdentity profile={profile} loading={loading} onRetry={onRetry} />
      <BalanceChip balance={balance} />
      {actions}
    </div>
  );
}
