export type CalendarRewardType='fc'|'hero_chest'|'pet_egg';
export type CalendarReward={day:number;type:CalendarRewardType;amountFc?:number;itemCode?:string;title:string;subtitle?:string};
const fc=(day:number,amountFc:number):CalendarReward=>({day,type:'fc',amountFc,title:`${amountFc.toLocaleString('pt-BR')} FC`});
const item=(day:number,type:'hero_chest'|'pet_egg',itemCode:string,title:string,subtitle:string):CalendarReward=>({day,type,itemCode,title,subtitle});
export const CALENDAR_REWARDS:CalendarReward[]=[
 fc(1,2000),fc(2,3000),item(3,'hero_chest','common_chest','Baú de Herói','Comum'),fc(4,2500),fc(5,4000),item(6,'pet_egg','common-egg','Ovo de Pet','Comum'),item(7,'hero_chest','common_chest','Baú de Herói','Comum'),fc(8,3000),fc(9,4000),item(10,'hero_chest','rare_chest','Baú de Herói','Raro'),fc(11,3500),item(12,'pet_egg','common-egg','Ovo de Pet','Comum'),fc(13,5000),item(14,'hero_chest','common_chest','Baú de Herói','Comum'),fc(15,6000),fc(16,3500),item(17,'hero_chest','rare_chest','Baú de Herói','Raro'),fc(18,4000),item(19,'pet_egg','rare-egg','Ovo de Pet','Raro'),fc(20,7000),item(21,'hero_chest','common_chest','Baú de Herói','Comum'),fc(22,4500),fc(23,5000),item(24,'hero_chest','rare_chest','Baú de Herói','Raro'),fc(25,8000),fc(26,4500),item(27,'pet_egg','rare-egg','Ovo de Pet','Raro'),fc(28,6000),item(29,'hero_chest','epic_chest','Baú de Herói','Épico'),fc(30,10000)
];
/**
 * Single source of truth for chest odds, mirroring `public.chest_reward_tables`.
 * The real roll always happens in the database; this is presentation only.
 */
export const CHEST_REWARD_TABLE={
 common_chest:{common:100},
 uncommon_chest:{common:70,uncommon:30},
 rare_chest:{common:50,uncommon:35,rare:15},
 epic_chest:{common:30,uncommon:30,rare:30,epic:10},
 legendary_chest:{rare:45,epic:40,legendary:15}
} as const;
export const CHEST_LABELS:Record<string,string>={common_chest:'Baú Comum',uncommon_chest:'Baú Incomum',rare_chest:'Baú Raro',epic_chest:'Baú Épico',legendary_chest:'Baú Lendário'};
export const CALENDAR_EGG_ODDS={'common-egg':{common:75,uncommon:20,rare:5},'rare-egg':{common:35,uncommon:40,rare:20,epic:5}} as const;
export type CalendarDashboard={cycle:string;currentDay:number;claimedDays:number[];canClaim:boolean;rewards:CalendarReward[];balance:number};
export type InventoryChest={id:string;itemCode:string;name:string;subtitle:string;quantity:number;rarityRates:Record<string,number>};
export type InventoryEgg={id:string;slug:string;name:string;image:string|null;quantity:number;rarityRates:Record<string,number>};
export type PlayerInventory={chests:InventoryChest[];eggs:InventoryEgg[]};
export type ChestOpenResult={hero:{id:string;name:string;image:string;rarity:string;level:number;baseAtk:number;baseHp:number};chest?:{code:string;name:string;subtitle:string};inventory?:PlayerInventory};
export type CalendarClaimResult={reward:CalendarReward;balance:number;inventoryItemId:string|null;inventory?:PlayerInventory;dashboard:CalendarDashboard};
