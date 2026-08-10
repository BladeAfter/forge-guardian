import {describe,expect,it} from 'vitest';import {CALENDAR_EGG_ODDS,CALENDAR_REWARDS,CHEST_LABELS,CHEST_REWARD_TABLE} from './calendarRewards';
const total=(rates:Record<string,number>)=>Object.values(rates).reduce((a,b)=>a+b,0);
describe('calendário de 30 dias',()=>{
 it('possui 30 dias',()=>expect(CALENDAR_REWARDS).toHaveLength(30));
 it('distribui 8 baús, 4 ovos e 18 FC',()=>{expect(CALENDAR_REWARDS.filter(x=>x.type==='hero_chest')).toHaveLength(8);expect(CALENDAR_REWARDS.filter(x=>x.type==='pet_egg')).toHaveLength(4);expect(CALENDAR_REWARDS.filter(x=>x.type==='fc')).toHaveLength(18)});
 it('totaliza 85.500 FC pela tabela especificada',()=>expect(CALENDAR_REWARDS.reduce((sum,x)=>sum+(x.amountFc??0),0)).toBe(85500));
 it('entrega apenas baús configurados',()=>CALENDAR_REWARDS.filter(x=>x.type==='hero_chest').forEach(x=>{expect(CHEST_REWARD_TABLE).toHaveProperty(x.itemCode!);expect(CHEST_LABELS[x.itemCode!]).toBeTruthy()}));
 it('não entrega ovos premium',()=>expect(CALENDAR_REWARDS.filter(x=>x.type==='pet_egg').every(x=>['common-egg','rare-egg'].includes(x.itemCode??''))).toBe(true));
 it('todas as chances somam 100',()=>[...Object.values(CHEST_REWARD_TABLE),...Object.values(CALENDAR_EGG_ODDS)].forEach(rates=>expect(total(rates as Record<string,number>)).toBe(100)));
 it('baús do calendário nunca entregam lendário ou ancestral',()=>CALENDAR_REWARDS.filter(x=>x.type==='hero_chest').forEach(x=>{const rates=CHEST_REWARD_TABLE[x.itemCode as keyof typeof CHEST_REWARD_TABLE] as Record<string,number>;expect(rates.legendary??0).toBe(0);expect(rates.ancestral??0).toBe(0)}));
});
