import iconMyth from '../assets/roulette/icon-myth.png';
import iconChest from '../assets/roulette/icon-chest.png';
import iconGear from '../assets/roulette/icon-gear.png';
import iconMystery from '../assets/roulette/icon-mystery.png';
import iconCelestial from '../assets/roulette/icon-celestial.png';

export type RewardCategoryId = 'MYTH' | 'CHEST' | 'GEAR' | 'MYSTERY' | 'CELESTIAL';

export type RewardCategory = {
  id: RewardCategoryId;
  icon: string;
  short: string;
  name: string;
  blurb: string;
  /** Category color language — used for rings, glows and labels. */
  ring: string;
  glow: string;
  text: string;
  chip: string;
  /** Subtle signature micro-animation. */
  anim: string;
};

export const REWARD_CATEGORIES: RewardCategory[] = [
  {
    id: 'MYTH',
    icon: iconMyth,
    short: 'MYTH',
    name: 'MYTH TOKEN',
    blurb: 'Bônus instantâneo de tokens MYTH direto na sua conta, disponível em qualquer giro.',
    ring: 'border-sky-300/60',
    glow: 'shadow-[0_0_18px_rgba(56,140,255,0.45)]',
    text: 'text-sky-200',
    chip: 'from-sky-500/25 to-amber-400/20',
    anim: 'animate-[myth-shine_2.8s_ease-in-out_infinite]',
  },
  {
    id: 'CHEST',
    icon: iconChest,
    short: 'CHEST',
    name: 'LEGENDARY CHEST',
    blurb: 'Baú lendário com loot raro do Mythic Seas.',
    ring: 'border-amber-300/60',
    glow: 'shadow-[0_0_18px_rgba(251,191,36,0.45)]',
    text: 'text-amber-200',
    chip: 'from-amber-500/25 to-amber-300/15',
    anim: 'animate-[chest-glow_3.2s_ease-in-out_infinite]',
  },
  {
    id: 'GEAR',
    icon: iconGear,
    short: 'NFT GEAR',
    name: 'NFT EQUIPMENT',
    blurb: 'Armas e armaduras NFT com mineração própria.',
    ring: 'border-fuchsia-300/55',
    glow: 'shadow-[0_0_18px_rgba(192,110,255,0.45)]',
    text: 'text-fuchsia-200',
    chip: 'from-fuchsia-500/25 to-amber-300/15',
    anim: 'animate-[rune-pulse_3s_ease-in-out_infinite]',
  },
  {
    id: 'MYSTERY',
    icon: iconMystery,
    short: 'MYSTERY',
    name: 'MYSTERY HERO',
    blurb: 'Contém uma recompensa de herói de alto valor.',
    ring: 'border-violet-300/60',
    glow: 'shadow-[0_0_20px_rgba(139,92,246,0.5)]',
    text: 'text-violet-200',
    chip: 'from-violet-600/30 to-amber-300/15',
    anim: 'animate-[mystery-pulse_2.4s_ease-in-out_infinite]',
  },
  {
    id: 'CELESTIAL',
    icon: iconCelestial,
    short: 'CELESTIAL',
    name: 'CELESTIAL HERO',
    blurb: 'Um herói celestial raro e especial.',
    ring: 'border-white/70',
    glow: 'shadow-[0_0_24px_rgba(190,225,255,0.55)]',
    text: 'text-sky-50',
    chip: 'from-white/25 via-sky-300/20 to-amber-300/20',
    anim: 'animate-[celestial-aura_3.6s_ease-in-out_infinite]',
  },
];

export const rewardCategory = (id: RewardCategoryId) =>
  REWARD_CATEGORIES.find((entry) => entry.id === id) ?? REWARD_CATEGORIES[0];

/** Small medallion used in the wheel legend ring and in the rewards strip. */
export function RewardMedallion({
  category,
  size = 34,
  onClick,
}: {
  category: RewardCategory;
  size?: number;
  onClick?: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={category.name}
      className={`relative grid shrink-0 place-items-center rounded-full border bg-[#05070f]/85 ${category.ring} ${category.glow} ${category.anim}`}
      style={{ width: size, height: size }}
    >
      <span
        className={`absolute inset-0 rounded-full bg-gradient-to-br ${category.chip} opacity-70`}
        aria-hidden
      />
      <img
        src={category.icon}
        alt=""
        loading="lazy"
        className="relative h-[76%] w-[76%] object-contain drop-shadow-[0_0_6px_rgba(0,0,0,0.8)]"
      />
    </button>
  );
}

/** Compact single-line "POSSIBLE REWARDS" caption — the wheel is the protagonist. */
export function PossibleRewards({ onSelect }: { onSelect: (category: RewardCategory) => void }) {
  return (
    <div className="w-full">
      <p className="text-center text-[9px] font-black uppercase tracking-[0.3em] text-slate-400">
        Possible rewards
      </p>
      <div className="mt-1 flex flex-wrap items-center justify-center gap-x-1.5 gap-y-1">
        {REWARD_CATEGORIES.map((category, index) => (
          <span key={category.id} className="flex items-center gap-1.5">
            {index ? <span className="text-[8px] text-slate-600">•</span> : null}
            <button
              type="button"
              onClick={() => onSelect(category)}
              className={`text-[9px] font-black uppercase tracking-[0.08em] ${category.text}`}
            >
              {category.short}
            </button>
          </span>
        ))}
      </div>
    </div>
  );
}


/** Elegant tap preview — no odds, no unlock rules. */
export function RewardPreviewPopup({
  category,
  onClose,
}: {
  category: RewardCategory;
  onClose: () => void;
}) {
  return (
    <div
      className="absolute inset-0 z-30 flex items-center justify-center bg-black/80 px-6"
      onClick={onClose}
      role="presentation"
    >
      <div
        className={`w-full max-w-[280px] rounded-2xl border bg-[#070b14] p-4 text-center ${category.ring} ${category.glow}`}
        onClick={(event) => event.stopPropagation()}
        role="presentation"
      >
        <div className={`mx-auto grid h-24 w-24 place-items-center rounded-2xl ${category.anim}`}>
          <span className={`absolute h-24 w-24 rounded-2xl bg-gradient-to-br ${category.chip} opacity-60`} aria-hidden />
          <img src={category.icon} alt={category.name} loading="lazy" className="relative h-24 w-24 object-contain" />
        </div>
        <p className={`mt-3 text-[12px] font-black uppercase tracking-[0.16em] ${category.text}`}>{category.name}</p>
        <p className="mt-1.5 text-[11px] leading-snug text-slate-400">{category.blurb}</p>
        <button
          type="button"
          onClick={onClose}
          className="mt-4 w-full rounded-xl border border-white/10 bg-white/5 py-2 text-[10px] font-black uppercase tracking-[0.16em] text-slate-300"
        >
          Fechar
        </button>
      </div>
    </div>
  );
}
