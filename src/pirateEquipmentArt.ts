import sword from './assets/equipment/sword.png';
import axe from './assets/equipment/axe.png';
import staff from './assets/equipment/staff.png';
import bow from './assets/equipment/bow.png';
import scepter from './assets/equipment/scepter.png';
import armor from './assets/equipment/armor.png';
import ring from './assets/equipment/ring.png';

export const pirateEquipmentArt = { sword, axe, staff, bow, scepter, armor, ring };

/** Stable equipment kind only; never changes rarity, ownership or bonuses. */
export function pirateEquipmentImage(key: string): string | null {
  const kind = key.match(/(?:^eq_|\/equipment\/)(sword|axe|staff|bow|scepter|armor|ring)(?:[_\-.]|$)/i)?.[1]?.toLowerCase();
  return kind && kind in pirateEquipmentArt ? pirateEquipmentArt[kind as keyof typeof pirateEquipmentArt] : null;
}