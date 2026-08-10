import{useEffect,useMemo,useRef,useState}from'react';
import{Swords,Zap}from'lucide-react';
import type{PvpBattleResult,PvpHero}from'../pvp';

const rarityColor:Record<string,string>={common:'#94a3b8',uncommon:'#34d399',rare:'#60a5fa',epic:'#c084fc',legendary:'#fbbf24',ancestral:'#f472b6'};
const archetypeFx:Record<string,{icon:string;color:string}>={warrior:{icon:'⚔',color:'#fbbf24'},assassin:{icon:'✦',color:'#f472b6'},tank:{icon:'🛡',color:'#60a5fa'},mage:{icon:'✷',color:'#c084fc'},archer:{icon:'➤',color:'#34d399'},support:{icon:'✚',color:'#4ade80'}};

type Fighter={heroId:string;name:string;imageUrl:string;rarity:string;archetype?:string;maxHp:number;hp:number};
const toFighter=(h:PvpHero&{currentHp?:number}):Fighter=>({heroId:h.heroId,name:h.name,imageUrl:h.imageUrl,rarity:String(h.rarity),archetype:h.archetype,maxHp:Math.max(1,h.finalHp),hp:Math.max(1,h.finalHp)});

export function PvpBattleArena({battle,attackTeam,defenseTeam,opponentName,pet,onContinue}:{battle:PvpBattleResult;attackTeam:PvpHero[];defenseTeam:PvpHero[];opponentName:string;pet?:{name:string;image:string}|null;onContinue:()=>void}){
 const events=useMemo(()=>battle.battleLog.filter(e=>Number.isFinite(e?.damage)),[battle]);
 const baseAlly=useMemo(()=>(battle.attackerState?.length?battle.attackerState:attackTeam).map(toFighter),[battle,attackTeam]);
 const baseFoe=useMemo(()=>(battle.defenderState?.length?battle.defenderState:defenseTeam).map(toFighter),[battle,defenseTeam]);
 const[ally,setAlly]=useState<Fighter[]>(baseAlly);
 const[foe,setFoe]=useState<Fighter[]>(baseFoe);
 const[index,setIndex]=useState(0);
 const[speed,setSpeed]=useState(1);
 const[done,setDone]=useState(false);
 const[fx,setFx]=useState<{attackerId:string;targetId:string;damage:number;side:string;key:number}|null>(null);
 const timer=useRef<number|null>(null);

 const finish=()=>{setAlly(baseAlly.map((h,i)=>({...h,hp:Math.max(0,Number((battle.attackerState?.[i] as{currentHp?:number}|undefined)?.currentHp??h.hp))})));setFoe(baseFoe.map((h,i)=>({...h,hp:Math.max(0,Number((battle.defenderState?.[i] as{currentHp?:number}|undefined)?.currentHp??h.hp))})));setIndex(events.length);setFx(null);setDone(true)};

 useEffect(()=>{
  if(done)return;
  if(index>=events.length){const t=window.setTimeout(()=>setDone(true),450);return()=>window.clearTimeout(t)}
  const e=events[index];
  setFx({attackerId:e.attackerId,targetId:e.targetId,damage:e.damage,side:e.side,key:index});
  const apply=(list:Fighter[])=>list.map(h=>h.heroId===e.targetId?{...h,hp:Math.max(0,Number.isFinite(e.remainingHp)?e.remainingHp:h.hp-e.damage)}:h);
  if(e.side==='attacker')setFoe(apply);else setAlly(apply);
  timer.current=window.setTimeout(()=>{setFx(null);setIndex(i=>i+1)},820/speed);
  return()=>{if(timer.current)window.clearTimeout(timer.current)}
 },[index,events,speed,done]);

 const win=battle.result==='attacker_win';
 const turn=Math.min(battle.totalTurns,events[Math.min(index,events.length-1)]?.turn??battle.totalTurns);

 return<div className="fixed inset-0 z-[120] overflow-y-auto bg-[#04070c] text-white">
  <div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_top,#2a1533_0%,#080b12_55%,#020407_100%)]"/>
  <div className="forge-safe-page relative mx-auto flex min-h-full w-full max-w-[480px] flex-col px-3 pb-6 pt-4">
   <header className="text-center">
    <p className="text-[9px] font-black uppercase tracking-[.3em] text-amber-300">BATALHA PVP</p>
    <p className="mt-1 text-[11px] font-bold text-slate-300">{done?'Batalha encerrada':`Turno ${turn} de ${battle.totalTurns}`}</p>
    <div className="mt-2 h-1 overflow-hidden rounded-full bg-white/10"><div className="h-full rounded-full bg-gradient-to-r from-amber-300 to-orange-500 transition-all duration-300" style={{width:`${Math.round((Math.min(index,events.length)/Math.max(1,events.length))*100)}%`}}/></div>
   </header>

   <TeamRow label={`EQUIPE INIMIGA · ${opponentName}`} team={foe} fx={fx} sideKey="attacker" dim={done&&win}/>

   <div className="my-3 flex items-center justify-center gap-3">
    <span className="h-[1px] flex-1 bg-white/10"/>
    <Swords className={`h-7 w-7 text-amber-300 ${fx?'animate-pulse':''}`}/>
    <span className="h-[1px] flex-1 bg-white/10"/>
   </div>

   <TeamRow label="SUA EQUIPE" team={ally} fx={fx} sideKey="defender" dim={done&&!win} pet={pet}/>

   {!done&&<div className="mt-5 flex items-center justify-center gap-2">
    {[1,2].map(s=><button key={s} type="button" onClick={()=>setSpeed(s)} className={`h-9 min-w-[52px] rounded-xl border px-3 text-[11px] font-black ${speed===s?'border-amber-300 bg-amber-400 text-black':'border-white/10 bg-black/50 text-white'}`}>x{s}</button>)}
    <button type="button" onClick={finish} className="h-9 rounded-xl border border-white/10 bg-black/50 px-4 text-[11px] font-black text-slate-200">SKIP</button>
   </div>}

   {done&&<div className="mt-6 rounded-[1.75rem] border border-amber-300/25 bg-black/65 p-5 text-center">
    <Zap className={`mx-auto h-10 w-10 ${win?'text-emerald-300':'text-rose-300'}`}/>
    <h2 className={`mt-2 text-4xl font-black ${win?'text-emerald-300':'text-rose-300'}`}>{win?'VITÓRIA':'DERROTA'}</h2>
    <p className={`mt-1 text-sm font-black ${battle.trophyChange>=0?'text-amber-300':'text-rose-300'}`}>{battle.trophyChange>0?'+':''}{battle.trophyChange} TROFÉUS</p>
    <p className="mt-1 text-[11px] text-slate-400">{battle.totalTurns} turnos · 1 ticket</p>
    {battle.rewardFc>0&&<p className="mt-1 text-[12px] font-bold text-amber-200">+{battle.rewardFc.toLocaleString()} FC</p>}
    <button type="button" onClick={onContinue} className="mt-5 w-full rounded-xl bg-gradient-to-b from-amber-300 to-orange-500 py-3.5 text-sm font-black text-black">CONTINUAR</button>
   </div>}
  </div>
 </div>
}

function TeamRow({label,team,fx,sideKey,dim,pet}:{label:string;team:Fighter[];fx:{attackerId:string;targetId:string;damage:number;side:string;key:number}|null;sideKey:string;dim?:boolean;pet?:{name:string;image:string}|null}){
 return<section className={`mt-4 transition-opacity duration-500 ${dim?'opacity-45':'opacity-100'}`}>
  <div className="mb-2 flex items-center gap-2"><p className="truncate text-[9px] font-black uppercase tracking-[.2em] text-slate-400">{label}</p>{pet?<img src={pet.image} alt={pet.name} className="h-7 w-7 rounded-full border border-amber-300/40 object-cover"/>:null}</div>
  <div className="grid grid-cols-5 gap-1.5">{team.map(h=><FighterCard key={h.heroId} fighter={h} attacking={fx?.side===sideKey&&fx.attackerId===h.heroId} hit={fx?.targetId===h.heroId?fx:null} down={sideKey==='attacker'}/>)}</div>
 </section>
}

function FighterCard({fighter:h,attacking,hit,down}:{fighter:Fighter;attacking:boolean;hit:{damage:number;key:number}|null;down:boolean}){
 const pct=Math.max(0,Math.min(100,Math.round((h.hp/h.maxHp)*100))),dead=h.hp<=0,fxInfo=archetypeFx[String(h.archetype)]??archetypeFx.warrior;
 return<div className={`relative overflow-hidden rounded-lg border bg-black/70 transition-all duration-200 ${dead?'opacity-40 grayscale':''} ${attacking?(down?'-translate-y-1.5':'translate-y-1.5')+' shadow-[0_0_18px_rgba(251,191,36,.45)]':''} ${hit?'animate-[pulse_.3s_ease-in-out]':''}`} style={{borderColor:rarityColor[h.rarity]??'#475569'}}>
  <div className="relative"><img src={h.imageUrl} alt={h.name} className="aspect-square w-full object-cover"/>
   {attacking&&<span className="absolute inset-0 grid place-items-center text-lg" style={{color:fxInfo.color,textShadow:`0 0 12px ${fxInfo.color}`}}>{fxInfo.icon}</span>}
   {hit&&<span key={hit.key} className="absolute inset-x-0 top-1 animate-fade-in text-center text-[11px] font-black text-rose-300 drop-shadow-[0_2px_6px_rgba(0,0,0,.8)]">-{hit.damage}</span>}
   {dead&&<span className="absolute inset-0 grid place-items-center bg-black/60 text-[7px] font-black tracking-widest text-rose-300">DEFEATED</span>}
  </div>
  <p className="truncate px-1 pt-0.5 text-[7px] font-bold text-slate-200">{h.name}</p>
  <p className="px-1 text-[6px] text-slate-400">{h.hp}/{h.maxHp}</p>
  <div className="mx-1 mb-1 mt-0.5 h-1 overflow-hidden rounded-full bg-white/10"><div className="h-full rounded-full transition-all duration-500" style={{width:`${pct}%`,background:pct>50?'#34d399':pct>22?'#fbbf24':'#f87171'}}/></div>
 </div>
}
