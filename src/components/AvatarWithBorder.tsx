import { useLocalizedText } from '../LanguageContext';
import { useEffect, useState } from 'react';
import avatarBorderMyth from '../assets/avatar-border-myth.png.asset.json';
import avatarBorderFounder from '../assets/avatar-border-founder.png.asset.json';
import avatarBorderTopSpender from '../assets/avatar-border-top-spender.png.asset.json';

/** Exclusive cosmetic frames unlocked by rewards (MYTH SALE 100k, FOUNDER PACK, TOP SPENDER). */
export const AVATAR_BORDERS: Record<string, string> = {
  myth_sale_exclusive: avatarBorderMyth.url,
  founder_exclusive: avatarBorderFounder.url,
  top_spender_exclusive: avatarBorderTopSpender.url,
};

export const avatarBorderUrl = (key?: string | null) => (key ? AVATAR_BORDERS[key] : undefined);

/**
 * Avatar with the exclusive frame drawn over the Telegram photo.
 * Used in the profile tab and in every ranking so the cosmetic is always visible.
 */
export function AvatarWithBorder({
  photoUrl,
  border,
  fallback,
  size = 32,
  className = '',
}: {
  photoUrl?: string | null;
  border?: string | null;
  fallback: string;
  size?: number;
  className?: string;
}) {
  const localizeText = useLocalizedText();

  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [photoUrl]);
  const ring = avatarBorderUrl(border);
  const inner = photoUrl && !failed
    ? <img src={photoUrl} alt="" loading="lazy" onError={() => setFailed(true)} className="h-full w-full rounded-full border-2 border-amber-400/60 bg-black object-cover" />
    : <div className="grid h-full w-full place-items-center rounded-full border-2 border-amber-400/60 bg-[#0b1120] text-[10px] font-black text-amber-200">{fallback}</div>;
  if (!ring) {
    return <div className={`shrink-0 ${className}`} style={{ width: size, height: size }}>{inner}</div>;
  }
  return (
    <div className={`relative grid shrink-0 place-items-center ${className}`} style={{ width: size, height: size }} title={localizeText("Exclusive Avatar Border")}>
      <div className="grid place-items-center" style={{ width: '72%', height: '72%' }}>{inner}</div>
      <img src={ring} alt="" loading="lazy" className="pointer-events-none absolute inset-0 h-full w-full object-contain" />
    </div>
  );
}
