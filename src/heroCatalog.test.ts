import{describe,expect,it}from'vitest';
import{HERO_CATALOG}from'./heroCatalog';

describe('expanded hero catalog',()=>{
 it('adds five new heroes to every supported rarity',()=>{
  for(const rarity of['common','uncommon','rare','epic','legendary']as const){
   expect(HERO_CATALOG.filter(hero=>hero.rarity===rarity)).toHaveLength(10);
  }
 });
 it('keeps unique ids and local art for all expanded heroes',()=>{
  expect(new Set(HERO_CATALOG.map(hero=>hero.id)).size).toBe(HERO_CATALOG.length);
  expect(HERO_CATALOG.filter(hero=>Number(hero.id.split('-')[1])>=6).every(hero=>hero.image.startsWith('/assets/game/heroes/shop/expanded/'))).toBe(true);
 });
});
