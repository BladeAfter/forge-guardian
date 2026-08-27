import wheelFrame from '../assets/roulette/wheel-clean.png';
import { REWARD_CATEGORIES, type RewardCategory, type RewardCategoryId } from './RouletteRewardKit';

/** Clockwise slice order starting at the top pointer. */
export const WHEEL_ORDER: RewardCategoryId[] = ['CELESTIAL', 'MYSTERY', 'CHEST', 'GEAR', 'MYTH'];

export const WHEEL_STEP = 360 / WHEEL_ORDER.length;

const bySlice = (id: RewardCategoryId) =>
  REWARD_CATEGORIES.find((entry) => entry.id === id) as RewardCategory;

/** Sector fill colors (purely visual identity of each reward slice). */
const SLICE_FILL: Record<RewardCategoryId, string> = {
  CELESTIAL: 'rgba(214,236,255,0.30)',
  MYSTERY: 'rgba(139,92,246,0.30)',
  CHEST: 'rgba(251,191,36,0.26)',
  GEAR: 'rgba(192,110,255,0.24)',
  MYTH: 'rgba(56,140,255,0.28)',
};

/** Target wheel rotation (deg) so the pointer at the top lands on `id`. */
export function rotationForSlice(currentAngle: number, id: RewardCategoryId, extraSpins = 4) {
  const index = Math.max(0, WHEEL_ORDER.indexOf(id));
  const target = (360 - index * WHEEL_STEP) % 360;
  const base = currentAngle + extraSpins * 360;
  const delta = (target - (base % 360) + 360) % 360;
  return base + delta;
}

const sliceGradient = `conic-gradient(from ${-WHEEL_STEP / 2}deg, ${WHEEL_ORDER.map(
  (id, index) => `${SLICE_FILL[id]} ${index * WHEEL_STEP}deg ${(index + 1) * WHEEL_STEP}deg`,
).join(', ')})`;

const dividerGradient = `repeating-conic-gradient(from ${-WHEEL_STEP / 2}deg, rgba(252,211,77,0.85) 0deg 0.6deg, transparent 0.6deg ${WHEEL_STEP}deg)`;

export function RouletteWheel({
  angle,
  spinning,
  onSelect,
}: {
  angle: number;
  spinning: boolean;
  onSelect: (category: RewardCategory) => void;
}) {
  return (
    <div
      className="absolute inset-0"
      style={{ transform: `rotate(${angle}deg)`, transition: 'transform 2.6s cubic-bezier(0.16,1,0.3,1)' }}
    >
      {/* Golden frame, blue runes and crystal preserved from the original wheel art */}
      <img
        src={wheelFrame}
        alt="Roleta mística"
        className="absolute inset-0 h-full w-full select-none drop-shadow-[0_0_46px_rgba(0,0,0,0.65)]"
      />

      {/* The five REAL reward slices */}
      <div className="absolute inset-[20%] overflow-hidden rounded-full">
        <div className="absolute inset-0 rounded-full bg-[#070b16]" />
        <div className="absolute inset-0 rounded-full" style={{ background: sliceGradient }} />
        <div className="absolute inset-0 rounded-full opacity-90" style={{ background: dividerGradient }} />
        <div className="absolute inset-0 rounded-full border border-amber-300/40" />
      </div>

      {/* Reward artwork + short label, one per slice */}
      {WHEEL_ORDER.map((id, index) => {
        const category = bySlice(id);
        const rad = ((index * WHEEL_STEP) * Math.PI) / 180;
        const radius = 30;
        const grand = id === 'CELESTIAL';
        return (
          <button
            key={id}
            type="button"
            onClick={() => !spinning && onSelect(category)}
            aria-label={category.name}
            className="absolute flex w-[26%] -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-0.5"
            style={{
              left: `${50 + Math.sin(rad) * radius}%`,
              top: `${50 - Math.cos(rad) * radius}%`,
            }}
          >
            {grand ? (
              <span
                className="absolute -inset-2 rounded-full bg-[radial-gradient(circle,rgba(220,240,255,0.35),transparent_70%)] animate-[celestial-aura_3.6s_ease-in-out_infinite]"
                aria-hidden
              />
            ) : null}
            <img
              src={category.icon}
              alt=""
              className={`relative w-full object-contain drop-shadow-[0_2px_8px_rgba(0,0,0,0.85)] ${category.anim} ${
                grand ? 'scale-110' : ''
              }`}
            />
            <span
              className={`relative rounded-full bg-[#04060d]/85 px-1 text-[7px] font-black uppercase leading-[10px] tracking-[0.06em] ${category.text}`}
            >
              {category.short}
            </span>
          </button>
        );
      })}

      {/* Central Mythreon medallion */}
      <div className="pointer-events-none absolute left-1/2 top-1/2 grid h-[16%] w-[16%] -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full border border-amber-300/70 bg-[#0a0f1c] text-[13px] font-black text-amber-300 shadow-[0_0_18px_rgba(251,191,36,0.35)]">
        M
      </div>
    </div>
  );
}
