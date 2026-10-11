import {describe,it,expect,vi} from 'vitest';
import {readFileSync} from 'node:fs';
import {islandPirates} from '../supabase/functions/game-api/islandPirates';
import {createIslandCombat,defaultIslandSettings} from '../supabase/functions/_shared/islandCombat';
function fixture(){
 const state=createIslandCombat(0,defaultIslandSettings(0),Date.now()-300);
 const session={id:'fixture',version:0,game_day:'2026-10-11',state};
 const query:any={select:()=>query,eq:()=>query,in:()=>query,limit:()=>Promise.resolve({data:[{id:'equipment-id',rarity:'common'}],error:null}),maybeSingle:()=>Promise.resolve({data:null,error:null})};
 const rpc=vi.fn(async(name:string,args:any)=>{
  if(name==='island_pirate_begin')return {data:session,error:null};
  if(name==='island_pirate_commit'){session.state=args.p_state;session.version++;return {data:{session,conflict:false},error:null};}
  if(name==='island_pirate_open'){const e=state.enemies.find(e=>e.id===args.p_enemy);if(!e||e.hp>0)return {data:null,error:{message:'ISLAND_CHEST_UNAVAILABLE'}};return {data:{session,reward:e.loot,duplicate:e.claimed},error:null};}
  throw Error(name);
 });
 return {db:{from:()=>query,rpc},session,rpc};
}
describe('island API security and persistence',()=>{
 it('ignores browser-provided damage, deaths, loot and balance',async()=>{const f=fixture();const result=await islandPirates(f.db,'owned',{islandIndex:0,islandAction:'tick',input:{x:0,z:29,sequence:1,damage:999999,hp:0,loot:{berries:99999},balance:99999}});expect(result.session.state.enemies.every(e=>e.hp===e.maxHp)).toBe(true);expect(f.rpc).not.toHaveBeenCalledWith('island_pirate_open',expect.anything());});
 it('rejects forged action names and nonfinite poses',async()=>{const f=fixture();await expect(islandPirates(f.db,'owned',{islandIndex:0,islandAction:'grant'})).rejects.toThrow('ISLAND_INVALID_INPUT');await expect(islandPirates(f.db,'owned',{islandIndex:0,islandAction:'tick',input:{x:Infinity,z:0,sequence:1}})).rejects.toThrow('ISLAND_INVALID_INPUT');});
 it('cannot open a living enemy chest',async()=>{const f=fixture();Object.assign(f.session.state.enemies[0],{x:0,z:25});await expect(islandPirates(f.db,'owned',{islandIndex:0,islandAction:'open',enemyId:'pirate-0'})).rejects.toThrow('ISLAND_CHEST_UNAVAILABLE');});
 it('reuses official atomic claim and never passes client loot to settlement',async()=>{const f=fixture();const e=f.session.state.enemies[0];Object.assign(e,{x:0,z:25,hp:0,loot:{berries:35,items:[]}});const result=await islandPirates(f.db,'owned',{islandIndex:0,islandAction:'open',enemyId:'pirate-0',reward:{berries:999999}});expect(result.reward.berries).toBe(35);expect(f.rpc).toHaveBeenCalledWith('island_pirate_open',{p_user:'owned',p_session:'fixture',p_enemy:'pirate-0'});});
 it('keeps sessions and grants private, locked, reset-aware, and idempotent in SQL',()=>{const sql=readFileSync('drizzle/migrations/0140_island_pirate_encounters.sql','utf8');expect(sql).toContain('UNIQUE(session_id,enemy_id)');expect(sql).toContain('FOR UPDATE');expect(sql).toContain('s.version<>p_version');expect(sql).toContain('game_reset_epoch');expect(sql).toContain('FROM PUBLIC,anon,authenticated');expect(sql).toContain('ENABLE ROW LEVEL SECURITY');expect(sql).toContain('realm_material_add');expect(sql).toContain('INSERT INTO public.player_equipment');expect(sql).not.toContain('SET ton_balance');});
});
