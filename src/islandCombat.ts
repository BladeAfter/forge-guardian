import { realmCall } from './realm';
export type IslandPirateLoot={berries:number;items:{kind:string;code:string;quantity:number;rarity:string}[]};
export type IslandPirateEnemy={id:string;nameKey:string;boss:boolean;variant:number;x:number;z:number;hp:number;maxHp:number;phase:number;mode:string;warningAt:number;heading:number;claimed:boolean;loot?:IslandPirateLoot};
export type IslandPirateSession={id:string;version:number;day:string;state:{island:number;player:{x:number;z:number;hp:number;maxHp:number;attackAt:number};enemies:IslandPirateEnemy[];sequence:number;lastHit:number;lastReceived:number}};
export type IslandPirateResponse={session:IslandPirateSession;reward?:IslandPirateLoot;balance?:number;duplicate?:boolean;conflict?:boolean};
export const islandPirateCall=(initData:string,islandIndex:number,islandAction:string,input?:Record<string,unknown>,enemyId?:string)=>realmCall<IslandPirateResponse>(initData,{action:'island-pirates',islandIndex,islandAction,input,enemyId});