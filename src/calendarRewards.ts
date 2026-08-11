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
/** The server owns the official game day (21:00 America/Sao_Paulo). Never compute it on the client. */
export type CalendarDayStatus='CLAIMED'|'AVAILABLE'|'LOCKED';
export type CalendarDashboard={cycle:string;currentDay:number;availableDay?:number|null;dayStatuses?:Record<string,CalendarDayStatus>;claimedDays:number[];canClaim:boolean;claimedToday?:boolean;gameDay?:string;gameDayNumber?:number;nextResetAt?:string;serverTime?:string;rewards:CalendarReward[];balance:number};
/** Countdown helper: uses the server-provided reset timestamp as the only authority. */
export function nextResetCountdown(nextResetAt?:string|null,now:number=Date.now()):string{
 const target=nextResetAt?Date.parse(nextResetAt):NaN;
 if(!Number.isFinite(target))return '--h --m';
 const ms=Math.max(0,target-now),h=Math.floor(ms/3_600_000),m=Math.floor((ms%3_600_000)/60_000);
 return `${String(h).padStart(2,'0')}h ${String(m).padStart(2,'0')}m`;
}
export const GAME_TIMEZONE='America/Sao_Paulo';
export const GAME_DAY_RESET_HOUR=21;
/**
 * Offline/demo mirror of the server rule: a new game day starts at 21:00 America/Sao_Paulo.
 * The backend remains the only authority whenever it is reachable.
 */
export function officialGameDayKey(date:Date=new Date()):string{
 const parts=new Intl.DateTimeFormat('en-CA',{timeZone:GAME_TIMEZONE,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',hour12:false}).formatToParts(date);
 const get=(type:string)=>parts.find(p=>p.type===type)?.value??'00';
 const hour=Number(get('hour'))%24;
 const local=new Date(Date.UTC(Number(get('year')),Number(get('month'))-1,Number(get('day'))));
 if(hour<GAME_DAY_RESET_HOUR)local.setUTCDate(local.getUTCDate()-1);
 return local.toISOString().slice(0,10);
}


export type InventoryChest={id:string;itemCode:string;name:string;subtitle:string;quantity:number;rarityRates:Record<string,number>};
export type InventoryEgg={id:string;slug:string;name:string;image:string|null;quantity:number;rarityRates:Record<string,number>};
export type PlayerInventory={chests:InventoryChest[];eggs:InventoryEgg[]};
export type ChestOpenResult={hero:{id:string;name:string;image:string;rarity:string;level:number;baseAtk:number;baseHp:number};chest?:{code:string;name:string;subtitle:string};inventory?:PlayerInventory};
export type CalendarClaimResult={reward:CalendarReward;balance:number;inventoryItemId:string|null;inventory?:PlayerInventory;dashboard:CalendarDashboard};
/**
 * Backend is the only authority: a day is AVAILABLE only while the server says so.
 * Claiming marks the current day and never unlocks the next one.
 */
export function calendarDayStatus(dashboard:CalendarDashboard|null|undefined,day:number,fallbackCurrentDay:number,fallbackClaimed=false):CalendarDayStatus{
 if(dashboard){
  const fromServer=dashboard.dayStatuses?.[String(day)];
  if(fromServer)return fromServer;
  if(dashboard.claimedDays.includes(day))return 'CLAIMED';
  const available=dashboard.availableDay??(dashboard.canClaim?dashboard.currentDay:null);
  return day===available?'AVAILABLE':'LOCKED';
 }
 if(day<fallbackCurrentDay)return 'CLAIMED';
 if(day===fallbackCurrentDay)return fallbackClaimed?'CLAIMED':'AVAILABLE';
 return 'LOCKED';
}
