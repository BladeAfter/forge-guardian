import type { CombatHero } from './combat';
export type CombatSlot=1|2|3|4|5;
export const COMBAT_SLOTS:CombatSlot[]=[1,2,3,4,5];
export function mapCombatSlots(heroes:CombatHero[]){return COMBAT_SLOTS.map(slot=>({slot,hero:heroes.find(hero=>Number(hero.slot)===slot)??null}));}
export function equipHeroInSlot(current:Array<{heroId:string;slot:CombatSlot}>,heroId:string,slot:CombatSlot){
  if(!COMBAT_SLOTS.includes(slot))throw new Error('INVALID_SLOT');
  if(!heroId)throw new Error('INVALID_HERO');
  return [...current.filter(item=>item.heroId!==heroId&&item.slot!==slot),{heroId,slot}].sort((a,b)=>a.slot-b.slot);
}
