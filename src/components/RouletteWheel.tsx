import { useLocalizedText } from '../LanguageContext';
import { REWARD_CATEGORIES, type RewardCategory, type RewardCategoryId } from './RouletteRewardKit';
import wheelArt from '../assets/roulette/wheel-ref.png';

/**
 * Slice layout of the wheel artwork (clockwise). Dividers sit at the top,
 * so the first slice centre is offset by half a step.
 */
export const WHEEL_ORDER: RewardCategoryId[] = ['CHEST', 'GEAR', 'MYSTERY', 'CELESTIAL', 'MYTH'];

export const WHEEL_STEP = 360 / WHEEL_ORDER.length;
const WHEEL_OFFSET = WHEEL_STEP / 2;

const bySlice = (id: RewardCategoryId) =>
  REWARD_CATEGORIES.find((entry) => entry.id === id) as RewardCategory;

const sliceCenter = (index: number) => WHEEL_OFFSET + index * WHEEL_STEP;

/** Target wheel rotation (deg) so the pointer at the top lands on `id`. */
export function rotationForSlice(currentAngle: number, id: RewardCategoryId, extraSpins = 4) {
  const index = Math.max(0, WHEEL_ORDER.indexOf(id));
  const target = (360 - sliceCenter(index)) % 360;
  const base = currentAngle + extraSpins * 360;
  const delta = (target - (base % 360) + 360) % 360;
  return base + delta;
}

export const SPIN_DURATION_MS = 5000;

export function RouletteWheel({
  angle,
  spinning,
  durationMs = SPIN_DURATION_MS,
  onSelect,
}: {
  angle: number;
  spinning: boolean;
  durationMs?: number;
  onSelect: (category: RewardCategory) => void;
}) {
  const localizeText = useLocalizedText();

  return (
    <div
      className="absolute inset-0 will-change-transform"
      style={{
        transform: `rotate(${angle}deg)`,
        transformOrigin: 'center center',
        transition: `transform ${durationMs}ms cubic-bezier(0.12, 0.8, 0.18, 1)`,
        backfaceVisibility: 'hidden',
      }}
    >
      <img
        src={wheelArt}
        alt={localizeText("Mythic Seas Global Mystery Roulette")}
        className="absolute inset-0 h-full w-full select-none object-contain drop-shadow-[0_0_48px_rgba(0,0,0,0.75)]"
        draggable={false}
      />

      {/* Invisible hit areas so tapping a slice opens its reward preview */}
      {WHEEL_ORDER.map((id, index) => {
        const category = bySlice(id);
        const rad = (sliceCenter(index) * Math.PI) / 180;
        const radius = 31;
        return (
          <button
            key={id}
            type="button"
            onClick={() => !spinning && onSelect(category)}
            aria-label={category.name}
            className="absolute h-[26%] w-[26%] -translate-x-1/2 -translate-y-1/2 rounded-full"
            style={{
              left: `${50 + Math.sin(rad) * radius}%`,
              top: `${50 - Math.cos(rad) * radius}%`,
            }}
          />
        );
      })}
    </div>
  );
}
