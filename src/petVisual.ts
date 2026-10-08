/**
 * Pet visual evolution (cosmetic only).
 *
 * One visual form per 10 levels, capped at 6 forms. The artwork itself is chosen
 * by the server (`pet_visual_image`) — the client only needs the form index to
 * label the current form and to detect when a new form was unlocked.
 *
 * Nothing here touches rarity, buffs, XP, power or any pet mechanic.
 */
export const PET_VISUAL_FORMS = ['base', 'evo1', 'evo2', 'evo3', 'evo4', 'final'] as const;
export type PetVisualForm = (typeof PET_VISUAL_FORMS)[number];

/** level 1-9 -> 0, 10-19 -> 1, ... 50+ -> 5 (mirrors `pet_visual_index`). */
export function petVisualStage(level: number | null | undefined): number {
  const lvl = Number(level ?? 1);
  if (!Number.isFinite(lvl) || lvl < 10) return 0;
  return Math.min(5, Math.floor(lvl / 10));
}

/** Translation key for the current visual form, e.g. `pets.form.evo1`. */
export function petVisualFormKey(level: number | null | undefined, stage?: number | null): string {
  const index = stage == null ? petVisualStage(level) : Math.min(5, Math.max(0, Number(stage)));
  return `pets.form.${PET_VISUAL_FORMS[index]}`;
}

/** True when leveling up crossed into a new visual form (10, 20, 30, 40, 50). */
export function crossedVisualForm(previousLevel: number, newLevel: number): boolean {
  return petVisualStage(newLevel) > petVisualStage(previousLevel);
}
