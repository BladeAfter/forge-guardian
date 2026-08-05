export type CalendarRewardType='fc'|'hero_chest'|'pet_egg';
export type CalendarReward={day:number;type:CalendarRewardType;amountFc?:number;itemCode?:string;title:string;subtitle?:string};
const fc=(day:number,amountFc:number):CalendarReward=>({day,type:'fc',amountFc,title:`${amountFc.toLocaleString('pt-BR')} FC`});
const item=(day:number,type:'hero_chest'|'pet_egg',itemCode:string,title:string,subtitle:string):CalendarReward=>({day,type,itemCode,title,subtitle});
export const CALENDAR_REWARDS:CalendarReward[]=[
 fc(1,2000),fc(2,3000),item(3,'hero_chest','hero_chest_common','Baú de Herói','Comum'),fc(4,2500),fc(5,4000),item(6,'pet_egg','common-egg','Ovo de Pet','Comum'),item(7,'hero_chest','hero_chest_common','Baú de Herói','Comum'),fc(8,3000),fc(9,4000),item(10,'hero_chest','hero_chest_improved','Baú de Herói','Aprimorado'),fc(11,3500),item(12,'pet_egg','common-egg','Ovo de Pet','Comum'),fc(13,5000),item(14,'hero_chest','hero_chest_common','Baú de Herói','Comum'),fc(15,6000),fc(16,3500),item(17,'hero_chest','hero_chest_improved','Baú de Herói','Aprimorado'),fc(18,4000),item(19,'pet_egg','rare-egg','Ovo de Pet','Raro'),fc(20,7000),item(21,'hero_chest','hero_chest_common','Baú de Herói','Comum'),fc(22,4500),fc(23,5000),item(24,'hero_chest','hero_chest_improved','Baú de Herói','Aprimorado'),fc(25,8000),fc(26,4500),item(27,'pet_egg','rare-egg','Ovo de Pet','Raro'),fc(28,6000),item(29,'hero_chest','hero_chest_special','Baú de Herói','Especial'),fc(30,10000)
];
export const CALENDAR_CHEST_ODDS={hero_chest_common:{common:75,uncommon:22,rare:3,epic:0,legendary:0},hero_chest_improved:{common:45,uncommon:40,rare:14,epic:1,legendary:0},hero_chest_special:{common:20,uncommon:45,rare:30,epic:5,legendary:0}} as const;
export const CALENDAR_EGG_ODDS={'common-egg':{common:75,uncommon:20,rare:5,epic:0,legendary:0},'rare-egg':{common:35,uncommon:45,rare:18,epic:2,legendary:0}} as const;
export type CalendarDashboard={cycle:string;currentDay:number;claimedDays:number[];canClaim:boolean;rewards:CalendarReward[];balance:number};
export type CalendarClaimResult={reward:CalendarReward;balance:number;inventoryItemId:string|null;dashboard:CalendarDashboard};
