import {createIslandCombat,advanceIslandCombat,validIslandSettings,type IslandCombatState,type IslandLoot,type IslandSettings} from '../_shared/islandCombat.ts';
type Db={rpc:(name:string,args:Record<string,unknown>)=>PromiseLike<{data:any;error:any}>;from:(name:string)=>any};
const cleanSession=(session:any)=>{
 const state=structuredClone(session.state as IslandCombatState);
 for(const e of state.enemies) if(e.hp>0)delete e.loot;
 return {id:session.id,version:session.version,day:session.game_day,state};
};
export async function islandPirates(db:Db,user:string,body:Record<string,any>){
 const island=body.islandIndex,action=String(body.islandAction??'state');
 if(!Number.isInteger(island)||island<0||island>4||!['state','tick','open'].includes(action))throw new Error('ISLAND_INVALID_INPUT');
 const [configured,equipment]=await Promise.all([
  db.from('island_pirate_config').select('settings').eq('island_index',island).maybeSingle(),
  db.from('equipment_templates').select('id,rarity').eq('is_active',true).eq('is_nft',false).eq('veteran_line',false).eq('founder_line',false).in('rarity',['common','rare']).limit(1000)
 ]);
 if(configured.error||equipment.error)throw new Error('ISLAND_CONFIGURATION_UNAVAILABLE');
 const cfg=validIslandSettings((configured.data?.settings??{}) as Partial<IslandSettings>,island);
 const begin=await db.rpc('island_pirate_begin',{p_user:user,p_island:island,p_state:createIslandCombat(island,cfg,Date.now())});
 if(begin.error)throw new Error(begin.error.message);
 let session=begin.data;
 if(action==='open'){
  if(typeof body.enemyId!=='string'||!/^pirate-[0-3]$/.test(body.enemyId))throw new Error('ISLAND_INVALID_INPUT');
  const e=(session.state as IslandCombatState).enemies.find(e=>e.id===body.enemyId);
  const {islandLineClear}=await import('../_shared/islandGeometry.ts');
  if(!e||!islandLineClear(island,session.state.player,e))throw new Error('ISLAND_OUT_OF_RANGE');
  const opened=await db.rpc('island_pirate_open',{p_user:user,p_session:session.id,p_enemy:body.enemyId});
  if(opened.error)throw new Error(opened.error.message);
  return {...opened.data,session:cleanSession(opened.data.session)};
 }
 if(action==='state')return {session:cleanSession(session)};
 const input=body.input??{};
 if(typeof input!=='object'||Array.isArray(input)||!Number.isInteger(input.sequence)||input.sequence<1||input.sequence>2147483647)throw new Error('ISLAND_INVALID_INPUT');
 for(const key of ['x','z'])if(typeof input[key]!=='number'||!Number.isFinite(input[key])||Math.abs(input[key])>180)throw new Error('ISLAND_INVALID_INPUT');
 if(input.attack!==undefined&&(!/^pirate-[0-3]$/.test(input.attack)||typeof input.actionId!=='string'||input.actionId.length>80))throw new Error('ISLAND_INVALID_INPUT');
 const rollLoot=(boss:boolean):IslandLoot=>{
  const draw=crypto.getRandomValues(new Uint32Array(1))[0]/4294967296;
  const material=['magic_wood','rope','iron_ore','nails','crystal_shard'][island];
  const total=cfg.materialWeight+cfg.equipmentWeight+(boss?cfg.trophyWeight:0),n=draw*total;
  const loot:IslandLoot={berries:boss?cfg.bossBerries:cfg.commonBerries,items:[]};
  if(n<cfg.materialWeight)loot.items.push({kind:'material',code:material,quantity:boss?3:1,rarity:island===4?'rare':'common'});
  else if(n<cfg.materialWeight+cfg.equipmentWeight){
   const pool=(equipment.data??[]).filter((e:any)=>e.rarity===(boss?'rare':'common'));
   if(!pool.length)throw new Error('ISLAND_EQUIPMENT_UNAVAILABLE');
   const index=crypto.getRandomValues(new Uint32Array(1))[0]%pool.length;
   loot.items.push({kind:'equipment',code:pool[index].id,quantity:1,rarity:boss?'rare':'common'});
  }else loot.items.push({kind:'exclusive',code:`island_trophy_${island}`,quantity:1,rarity:'rare'});
  return loot;
 };
 // Optimistic compare-and-swap; conflicts return approved truth, never replay an attack automatically.
 const next=advanceIslandCombat(session.state,input,Date.now(),rollLoot);
 const committed=await db.rpc('island_pirate_commit',{p_user:user,p_session:session.id,p_version:session.version,p_state:next});
 if(committed.error)throw new Error(committed.error.message);
 session=committed.data.session;
 return {session:cleanSession(session),conflict:committed.data.conflict,rates:{common:{material:cfg.materialWeight,equipment:cfg.equipmentWeight},rare:{material:cfg.materialWeight,equipment:cfg.equipmentWeight,trophy:cfg.trophyWeight}}};
}
