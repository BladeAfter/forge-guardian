import { petBuffShortLabel } from '../petLabels';

type Companion = { name: string; image: string; level?: number; rarity?: string } | null | undefined;

const RARITY_GLOW: Record<string, string> = {
  common: 'rgba(148,163,184,.45)',
  uncommon: 'rgba(52,211,153,.5)',
  rare: 'rgba(96,165,250,.55)',
  epic: 'rgba(192,132,252,.55)',
  legendary: 'rgba(251,191,36,.6)',
};

/**
 * The active pet is a single entity across the whole game: it is rendered as a
 * companion standing next to the player's team, never as another card.
 */
export function PetCompanion({
  pet,
  buffKey,
  buffValue,
  size = 'md',
  label = 'Companheiro em combate',
}: {
  pet: Companion;
  buffKey?: string | null;
  buffValue?: number;
  size?: 'sm' | 'md';
  label?: string;
}) {
  if (!pet) return null;
  const glow = RARITY_GLOW[pet.rarity ?? 'common'] ?? RARITY_GLOW.common;
  const box = size === 'sm' ? 'h-14 w-14' : 'h-20 w-20';
  return (
    <div className="mt-3 flex items-center gap-3 rounded-2xl border border-amber-300/25 bg-black/60 p-2">
      <div className="relative shrink-0">
        <span className="absolute inset-0 rounded-full blur-lg" style={{ background: glow }} />
        <img src={pet.image} alt={pet.name} className={`relative ${box} object-contain pet-companion-float`} />
      </div>
      <div className="min-w-0">
        <p className="text-[8px] uppercase tracking-[.25em] text-amber-300">{label}</p>
        <b className="block truncate text-sm">{pet.name}</b>
        <p className="text-[9px] text-slate-400">
          {pet.level ? `Nível ${pet.level}` : ''}
          {buffKey && buffValue ? `${pet.level ? ' · ' : ''}${petBuffShortLabel(buffKey)} +${buffValue}%` : ''}
        </p>
      </div>
    </div>
  );
}
