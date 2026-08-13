import { pvpRequest } from './services';

/** One equipment instance owned by the player (weapon / armor / ring). */
export type HeroEquipmentItem = {
  instanceId: string;
  code: string;
  name: string;
  slot: 'weapon' | 'armor' | 'ring';
  kind: string | null;
  rarity: string | null;
  image: string | null;
  level: number;
  heroClass: string | null;
  bonusAttack: number;
  bonusDefense: number;
  bonusHp: number;
  listed?: boolean;
  /** Server-side verdict: weapons only fit the class they were created for. */
  classOk?: boolean;
};

export type HeroEquipmentState = {
  heroId: string;
  archetype: string | null;
  stats: {
    atk: number; hp: number; def: number; spd: number; crit: number; power: number;
    baseAtk: number; baseHp: number; baseDef: number; basePower: number;
    equipAtk: number; equipHp: number; equipDef: number;
  };
  equipped: Partial<Record<'weapon' | 'armor' | 'ring', HeroEquipmentItem>>;
  available: HeroEquipmentItem[];
};

const ERRORS: Record<string, string> = {
  EQUIPMENT_NOT_OWNED: 'Este equipamento não pertence a você.',
  EQUIPMENT_IN_USE: 'Este equipamento já está equipado em outro herói.',
  EQUIPMENT_LISTED: 'Este equipamento está anunciado no mercado.',
  EQUIPMENT_NOT_AVAILABLE: 'Equipamento indisponível.',
  EQUIPMENT_NOT_EQUIPPED: 'Nenhum equipamento neste slot.',
  INVALID_EQUIPMENT_SLOT: 'Slot de equipamento inválido.',
  WRONG_CLASS: 'Esta arma não é compatível com a classe deste herói.',
  HERO_NOT_OWNED: 'Este herói não pertence a você.',
};

const wrap = async <T>(run: () => Promise<T>): Promise<T> => {
  try {
    return await run();
  } catch (error) {
    const raw = error instanceof Error ? error.message : '';
    throw new Error(ERRORS[raw] || raw || 'Não foi possível atualizar o equipamento.');
  }
};

export const fetchHeroEquipment = (initData: string, heroId: string) =>
  wrap(() => pvpRequest<HeroEquipmentState>(initData, { action: 'hero-equipment', heroId } as never));

export const equipHeroItem = (initData: string, heroId: string, instanceId: string) =>
  wrap(() => pvpRequest<HeroEquipmentState>(initData, { action: 'equip-item', heroId, instanceId } as never));

export const unequipHeroItem = (initData: string, heroId: string, slot: 'weapon' | 'armor' | 'ring') =>
  wrap(() => pvpRequest<HeroEquipmentState>(initData, { action: 'unequip-item', heroId, slot } as never));

/** Short "ATK +45 · HP +500" summary used in slots and pickers. */
export function equipmentBonusLabel(item: HeroEquipmentItem): string {
  const parts: string[] = [];
  if (item.bonusAttack) parts.push(`ATK +${item.bonusAttack}`);
  if (item.bonusDefense) parts.push(`DEF +${item.bonusDefense}`);
  if (item.bonusHp) parts.push(`HP +${item.bonusHp}`);
  return parts.join(' · ');
}
