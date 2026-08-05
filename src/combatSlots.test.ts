import {describe,expect,it} from 'vitest';
import {COMBAT_SLOTS,equipHeroInSlot,mapCombatSlots,type CombatSlot} from './combatSlots';
import type {CombatHero} from './combat';
const hero=(id:string,slot:CombatSlot):CombatHero=>({id:`state-${id}`,heroId:id,name:id,rarity:'common',slot,level:1,baseAtk:1.875,finalAtk:1.875,baseHp:100,maxHp:100,currentHp:100,isAlive:true,knockedOutAt:null,reviveAt:null});
describe('combat slot selection',()=>{
  it('uses slots 1 through 5',()=>expect(COMBAT_SLOTS).toEqual([1,2,3,4,5]));
  it('equips in Slot 1',()=>expect(equipHeroInSlot([],'a',1)).toEqual([{heroId:'a',slot:1}]));
  it('keeps Slot 3 instead of collapsing it',()=>expect(equipHeroInSlot([],'a',3)).toEqual([{heroId:'a',slot:3}]));
  it('replaces the selected slot',()=>expect(equipHeroInSlot([{heroId:'old',slot:1}],'new',1)).toEqual([{heroId:'new',slot:1}]));
  it('moves a hero instead of duplicating it',()=>expect(equipHeroInSlot([{heroId:'same',slot:1}],'same',4)).toEqual([{heroId:'same',slot:4}]));
  it('maps sparse rows by backend slot',()=>{const result=mapCombatSlots([hero('c',3)]);expect(result[0].hero).toBeNull();expect(result[2].hero?.heroId).toBe('c')});
  it('rejects slot zero',()=>expect(()=>equipHeroInSlot([],'a',0 as CombatSlot)).toThrow('INVALID_SLOT'));
  it('rejects an invalid hero',()=>expect(()=>equipHeroInSlot([],'',1)).toThrow('INVALID_HERO'));
});
