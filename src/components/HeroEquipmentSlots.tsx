import { Lock } from 'lucide-react';
import { useT } from '../LanguageContext';

/**
 * Visual-only equipment slots for a hero.
 *
 * The instance ids are already part of the contract so the future "equip" update
 * can fill them in, but while they are null nothing is selectable and no stat is
 * ever changed by this component.
 */
export type HeroEquipmentSlotsProps = {
  weaponInstanceId?: string | null;
  armorInstanceId?: string | null;
  ringInstanceId?: string | null;
};

const SLOTS = [
  { key: 'weapon', glyph: '⚔' },
  { key: 'armor', glyph: '🛡' },
  { key: 'ring', glyph: '💍' },
] as const;

export function HeroEquipmentSlots({ weaponInstanceId = null, armorInstanceId = null, ringInstanceId = null }: HeroEquipmentSlotsProps) {
  const t = useT();
  const filled: Record<string, string | null> = { weapon: weaponInstanceId, armor: armorInstanceId, ring: ringInstanceId };
  return (
    <section className="mt-3">
      <p className="mb-2 text-[10px] font-black uppercase tracking-[.24em] text-amber-300">{t('heroes.equipment')}</p>
      <div className="grid grid-cols-3 gap-2">
        {SLOTS.map((slot) => (
          <div
            key={slot.key}
            aria-disabled="true"
            className="rounded-xl border border-dashed border-amber-300/25 bg-black/50 p-2 text-center"
          >
            <p className="text-[8px] font-black uppercase tracking-[.14em] text-slate-300">
              {slot.glyph} {t(`heroes.slot.${slot.key}`)}
            </p>
            <div className="mt-2 grid aspect-square w-full place-items-center rounded-lg border border-white/10 bg-black/60">
              <Lock size={14} className="text-amber-300/70" />
            </div>
            <p className="mt-1.5 text-[8px] font-black uppercase tracking-[.12em] text-slate-400">
              {filled[slot.key] ? '—' : t('heroes.slotEmpty')}
            </p>
          </div>
        ))}
      </div>
      <p className="mt-2 text-center text-[8px] uppercase tracking-[.14em] text-slate-500">{t('heroes.slotComingSoon')}</p>
    </section>
  );
}
