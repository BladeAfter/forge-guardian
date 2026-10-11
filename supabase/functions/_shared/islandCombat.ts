import { clearEncounterPoint, islandLineClear, islandWalkable, obstacleAt } from './islandGeometry.ts';
export type IslandLootItem = {kind:'material'|'equipment'|'exclusive';code:string;quantity:number;rarity:string};
export type IslandLoot = {berries:number;items:IslandLootItem[]};
export type PirateEnemy = {id:string;nameKey:string;boss:boolean;variant:number;x:number;z:number;homeX:number;homeZ:number;hp:number;maxHp:number;damage:number;speed:number;range:number;detect:number;resistance:number;phase:number;mode:'patrol'|'chase'|'attack'|'warning'|'defeated';attackAt:number;warningAt:number;specialAt:number;heading:number;claimed:boolean;loot?:IslandLoot};
export type IslandCombatState = {island:number;player:{x:number;z:number;hp:number;maxHp:number;attackAt:number};enemies:PirateEnemy[];lastAt:number;sequence:number;lastAction:string|null;lastHit:number;lastReceived:number};
export type IslandSettings={commonHp:number;bossHp:number;commonDamage:number;bossDamage:number;speed:number;detect:number;range:number;commonBerries:number;bossBerries:number;materialWeight:number;equipmentWeight:number;trophyWeight:number};
export const defaultIslandSettings=(island:number):IslandSettings=>({commonHp:60+island*12,bossHp:300+island*45,commonDamage:5+island,bossDamage:13+island*2,speed:2.2+island*.1,detect:11,range:3.6,commonBerries:35+island*10,bossBerries:180+island*35,materialWeight:70,equipmentWeight:25,trophyWeight:5});
export function validIslandSettings(raw:Partial<IslandSettings>,island:number):IslandSettings {
 const settings={...defaultIslandSettings(island)};
 const bounds:Record<keyof IslandSettings,[number,number]>={commonHp:[20,400],bossHp:[150,3000],commonDamage:[1,20],bossDamage:[5,45],speed:[1,4],detect:[5,18],range:[2,4],commonBerries:[1,200],bossBerries:[10,1000],materialWeight:[1,100],equipmentWeight:[1,100],trophyWeight:[1,100]};
 for(const key of Object.keys(bounds) as (keyof IslandSettings)[]){const n=raw[key];if(typeof n==='number'&&Number.isFinite(n)&&n>=bounds[key][0]&&n<=bounds[key][1]) settings[key]=n;}
 return settings;
}
export function createIslandCombat(island:number,cfg:IslandSettings,now:number):IslandCombatState {
 const spots=[{x:12,z:23},{x:-10,z:8},{x:4,z:-13},{x:0,z:-35}];
 const enemies=spots.map((spot,index)=>{
  const point=clearEncounterPoint(island,spot);if(!islandWalkable(island,point))throw new Error('ISLAND_INVALID_SPAWN');
  const boss=index===3,hp=boss?cfg.bossHp:cfg.commonHp;
  return {id:`pirate-${index}`,nameKey:`islandCombat.enemy.${island}.${index}`,boss,variant:island,x:point.x,z:point.z,homeX:point.x,homeZ:point.z,hp,maxHp:hp,damage:boss?cfg.bossDamage:cfg.commonDamage,speed:boss?cfg.speed*.8:cfg.speed,range:cfg.range,detect:cfg.detect,resistance:boss?.18:0,phase:1,mode:'patrol' as const,attackAt:0,warningAt:0,specialAt:now+6000,heading:Math.PI,claimed:false};
 });
 return {island,player:{x:0,z:29,hp:100,maxHp:100,attackAt:0},enemies,lastAt:now,sequence:0,lastAction:null,lastHit:0,lastReceived:0};
}
export function advanceIslandCombat(previous:IslandCombatState, input:{x?:number;z?:number;attack?:string;actionId?:string;sequence?:number},now:number,rollLoot:(boss:boolean)=>IslandLoot):IslandCombatState {
 const s=structuredClone(previous),dt=Math.max(0,Math.min(.5,(now-s.lastAt)/1000));
 s.lastHit=0;s.lastReceived=0;
 if(input.sequence!==undefined&&input.sequence<=s.sequence) return s;
 // No offline catch-up and no client supplied damage/time/loot. Requested poses are swept from the last approved pose.
 if(s.player.hp>0&&typeof input.x==='number'&&typeof input.z==='number'&&Number.isFinite(input.x)&&Number.isFinite(input.z)){
  const goal={x:input.x,z:input.z};
  if(Math.hypot(goal.x-s.player.x,goal.z-s.player.z)<=7*dt&&islandLineClear(s.island,s.player,goal)) {s.player.x=goal.x;s.player.z=goal.z;}
 }
 for(const e of s.enemies){
  if(e.hp<=0){e.mode='defeated';continue;}
  const distance=Math.hypot(e.x-s.player.x,e.z-s.player.z),canSee=islandLineClear(s.island,e,s.player,.3);
  e.phase=e.boss?(e.hp/e.maxHp<=.3?3:e.hp/e.maxHp<=.65?2:1):1;
  if(s.player.hp<=0){e.mode='patrol';e.warningAt=0;continue;}
  if(e.warningAt){
   e.mode='warning';
   if(now>=e.warningAt){if(distance<=e.range*1.6&&canSee){const hit=Math.round(e.damage*(1+.25*e.phase));s.player.hp=Math.max(0,s.player.hp-hit);s.lastReceived+=hit;}e.warningAt=0;e.attackAt=now+1600;e.specialAt=now+6500;e.mode='attack';}
   continue;
  }
  if(e.boss&&distance<e.detect&&canSee&&now>=e.specialAt){e.warningAt=now+1600;e.mode='warning';continue;}
  if(distance<=e.range&&canSee){e.mode='attack';if(now>=e.attackAt){s.player.hp=Math.max(0,s.player.hp-e.damage);s.lastReceived+=e.damage;e.attackAt=now+1800;}continue;}
  const chasing=distance<e.detect&&canSee;
  e.mode=chasing?'chase':'patrol';
  const angle=now/4000+Number(e.id.slice(-1)),goal=chasing?s.player:{x:e.homeX+Math.cos(angle)*2,z:e.homeZ+Math.sin(angle)*2};
  const d=Math.hypot(goal.x-e.x,goal.z-e.z),step=Math.min(d,e.speed*dt);
  if(d>.01){const next={x:e.x+(goal.x-e.x)/d*step,z:e.z+(goal.z-e.z)/d*step};if(islandLineClear(s.island,e,next,.5)){e.x=next.x;e.z=next.z;e.heading=Math.atan2(goal.x-e.x,goal.z-e.z);}}
 }
 if(input.attack&&input.actionId&&input.actionId!==s.lastAction&&s.player.hp>0&&now>=s.player.attackAt){
  s.player.attackAt=now+800;s.lastAction=input.actionId;
  const e=s.enemies.find(e=>e.id===input.attack&&e.hp>0);
  if(e&&Math.hypot(e.x-s.player.x,e.z-s.player.z)<=4.1&&islandLineClear(s.island,s.player,e,.35)){
   const hit=Math.min(e.hp,Math.round(22*(1-e.resistance)));e.hp-=hit;s.lastHit=hit;
   if(e.hp<=0){e.mode='defeated';e.warningAt=0;e.loot=rollLoot(e.boss);}
  }
 }
 s.lastAt=now;s.sequence=Math.max(s.sequence,input.sequence??s.sequence+1);
 return s;
}
export const islandCombatGeometry={islandLineClear,islandWalkable,obstacleAt};
