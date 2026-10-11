import {useCallback,useEffect,useRef,useState} from 'react';
import {islandPirateCall,type IslandPirateSession,type IslandPirateLoot} from './islandCombat';
import type {IslandTelemetry} from './island3dWorld';
export function useIslandPirates(initData:string|undefined,island:number,telemetry:IslandTelemetry,onBalance?:(balance:number)=>void){
 const [session,setSession]=useState<IslandPirateSession|null>(null),[error,setError]=useState(''),[reward,setReward]=useState<IslandPirateLoot|null>(null);
 const current=useRef(session),pose=useRef(telemetry),pending=useRef(false),sequence=useRef(0),attack=useRef<{attack:string;actionId:string}|null>(null);
 current.current=session;pose.current=telemetry;
 useEffect(()=>{
  if(!initData)return;
  let disposed=false;
  const update=async()=>{
   if(disposed||pending.current||document.hidden||pose.current.phase!=='exploring')return;
   pending.current=true;
   try{
    const existing=current.current;
    const action=attack.current;attack.current=null;
    const next=await islandPirateCall(initData,island,existing?'tick':'state',existing?{x:pose.current.x,z:pose.current.z,sequence:++sequence.current,...action}:undefined);
    if(disposed)return;
    sequence.current=Math.max(sequence.current,next.session.state.sequence);
    current.current=next.session;setSession(next.session);setError('');
   }catch(e){if(!disposed)setError(e instanceof Error?e.message:'ISLAND_CONFIGURATION_UNAVAILABLE');}
   finally{pending.current=false;}
  };
  const timer=window.setInterval(()=>void update(),300);void update();
  return()=>{disposed=true;window.clearInterval(timer);attack.current=null;};
 },[initData,island]);
 const strike=useCallback(()=>{
  const state=current.current?.state;if(!state||pending.current||attack.current||state.player.hp<=0)return;
  const target=state.enemies.filter(e=>e.hp>0&&Math.hypot(e.x-state.player.x,e.z-state.player.z)<=4.1).sort((a,b)=>Math.hypot(a.x-state.player.x,a.z-state.player.z)-Math.hypot(b.x-state.player.x,b.z-state.player.z))[0];
  if(target)attack.current={attack:target.id,actionId:crypto.randomUUID()};
 },[]);
 const open=useCallback(async(id:string)=>{
  if(!initData||pending.current)return;pending.current=true;
  try{const result=await islandPirateCall(initData,island,'open',undefined,id);current.current=result.session;setSession(result.session);setReward(result.reward??null);if(result.balance!==undefined)onBalance?.(result.balance);setError('');}
  catch(e){setError(e instanceof Error?e.message:'ISLAND_CHEST_UNAVAILABLE');}
  finally{pending.current=false;}
 },[initData,island,onBalance]);
 return{session,error,reward,strike,open,clearReward:()=>setReward(null)};
}