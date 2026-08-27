import { REWARD_CATEGORIES, type RewardCategory, type RewardCategoryId } from './RouletteRewardKit';

/** Clockwise slice order starting at the top pointer. */
export const WHEEL_ORDER: RewardCategoryId[] = ['CELESTIAL', 'MYSTERY', 'CHEST', 'GEAR', 'MYTH'];

export const WHEEL_STEP = 360 / WHEEL_ORDER.length;

const bySlice = (id: RewardCategoryId) =>
  REWARD_CATEGORIES.find((entry) => entry.id === id) as RewardCategory;

/** Deep wedge fills — dark navy base with the category hue, like the reference art. */
const SLICE_FILL: Record<RewardCategoryId, [string, string]> = {
  CELESTIAL: ['#dfe9ff', '#4a6a9c'],
  MYSTERY: ['#3a1d6e', '#120a26'],
  CHEST: ['#5a3c07', '#1b1103'],
  GEAR: ['#4a1d6b', '#140a22'],
  MYTH: ['#123a63', '#08111f'],
};

/** Target wheel rotation (deg) so the pointer at the top lands on `id`. */
export function rotationForSlice(currentAngle: number, id: RewardCategoryId, extraSpins = 4) {
  const index = Math.max(0, WHEEL_ORDER.indexOf(id));
  const target = (360 - index * WHEEL_STEP) % 360;
  const base = currentAngle + extraSpins * 360;
  const delta = (target - (base % 360) + 360) % 360;
  return base + delta;
}

const CX = 100;
const CY = 100;
const R_OUT = 92;
const R_IN = 26;

const point = (deg: number, radius: number) => {
  const rad = ((deg - 90) * Math.PI) / 180;
  return [CX + Math.cos(rad) * radius, CY + Math.sin(rad) * radius];
};

/** Donut wedge path (gold-outlined, centred on the slice angle). */
function wedgePath(index: number) {
  const start = index * WHEEL_STEP - WHEEL_STEP / 2;
  const end = start + WHEEL_STEP;
  const [x1, y1] = point(start, R_OUT);
  const [x2, y2] = point(end, R_OUT);
  const [x3, y3] = point(end, R_IN);
  const [x4, y4] = point(start, R_IN);
  return `M ${x1} ${y1} A ${R_OUT} ${R_OUT} 0 0 1 ${x2} ${y2} L ${x3} ${y3} A ${R_IN} ${R_IN} 0 0 0 ${x4} ${y4} Z`;
}

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
      {/* Golden frame + blue rune ring, fully vector so there is no white plate behind the wheel */}
      <svg viewBox="0 0 200 200" className="absolute inset-0 h-full w-full drop-shadow-[0_0_48px_rgba(0,0,0,0.75)]">
        <defs>
          <linearGradient id="rw-gold" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#fde68a" />
            <stop offset="35%" stopColor="#d4a129" />
            <stop offset="65%" stopColor="#8a5d10" />
            <stop offset="100%" stopColor="#fcd34d" />
          </linearGradient>
          {WHEEL_ORDER.map((id) => (
            <radialGradient key={id} id={`rw-fill-${id}`} cx="50%" cy="50%" r="75%">
              <stop offset="0%" stopColor={SLICE_FILL[id][0]} />
              <stop offset="100%" stopColor={SLICE_FILL[id][1]} />
            </radialGradient>
          ))}
        </defs>

        <circle cx={CX} cy={CY} r="99" fill="#05070f" stroke="url(#rw-gold)" strokeWidth="3" />
        <circle cx={CX} cy={CY} r="95" fill="none" stroke="#1d3a6b" strokeWidth="5" />
        <circle
          cx={CX}
          cy={CY}
          r="95"
          fill="none"
          stroke="#5fa8ff"
          strokeWidth="3.4"
          strokeDasharray="2 4"
          opacity="0.85"
        />
        <circle cx={CX} cy={CY} r="92.5" fill="none" stroke="url(#rw-gold)" strokeWidth="2" />

        {WHEEL_ORDER.map((id, index) => (
          <path
            key={id}
            d={wedgePath(index)}
            fill={`url(#rw-fill-${id})`}
            stroke="url(#rw-gold)"
            strokeWidth="1.6"
          />
        ))}

        {/* Gold gems on the frame, one per slice divider */}
        {WHEEL_ORDER.map((id, index) => {
          const [gx, gy] = point(index * WHEEL_STEP - WHEEL_STEP / 2, 96.5);
          return <circle key={`gem-${id}`} cx={gx} cy={gy} r="3.4" fill="url(#rw-gold)" />;
        })}
      </svg>

      {/* Reward artwork + label inside each wedge */}
      {WHEEL_ORDER.map((id, index) => {
        const category = bySlice(id);
        const rad = ((index * WHEEL_STEP) * Math.PI) / 180;
        const radius = 30.5;
        const grand = id === 'CELESTIAL';
        return (
          <button
            key={id}
            type="button"
            onClick={() => !spinning && onSelect(category)}
            aria-label={category.name}
            className="absolute flex w-[30%] -translate-x-1/2 -translate-y-1/2 flex-col items-center"
            style={{
              left: `${50 + Math.sin(rad) * radius}%`,
              top: `${50 - Math.cos(rad) * radius}%`,
            }}
          >
            {grand ? (
              <span
                className="absolute -inset-3 rounded-full bg-[radial-gradient(circle,rgba(220,240,255,0.4),transparent_70%)] animate-[celestial-aura_3.6s_ease-in-out_infinite]"
                aria-hidden
              />
            ) : null}
            <img
              src={category.icon}
              alt=""
              className={`relative w-[86%] object-contain drop-shadow-[0_3px_10px_rgba(0,0,0,0.9)] ${category.anim}`}
            />
            <span className="relative -mt-0.5 max-w-full text-center text-[8px] font-black uppercase leading-[9px] tracking-[0.08em] text-white [text-shadow:0_1px_3px_rgba(0,0,0,0.95)]">
              {category.short}
            </span>
          </button>
        );
      })}

      {/* Central Mythreon medallion */}
      <div className="pointer-events-none absolute left-1/2 top-1/2 grid h-[22%] w-[22%] -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full border-2 border-amber-300/80 bg-[radial-gradient(circle,#141b30,#04060d)] shadow-[0_0_22px_rgba(251,191,36,0.4)]">
        <span className="bg-gradient-to-b from-amber-100 to-amber-500 bg-clip-text text-[18px] font-black text-transparent">
          M
        </span>
      </div>
    </div>
  );
}
