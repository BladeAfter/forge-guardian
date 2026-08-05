import { ShieldCheck } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { toast } from 'sonner';
import type { GameState, LanguageStrings } from '../types';
import { backgrounds, dragon } from '../gameAssets';
import { translate, type LanguageCode } from '../i18n';
import { HERO_CATALOG, RARITY_COLORS, type HeroRarity } from '../heroCatalog';
import { calculateEstimatedSecondsRemaining, calculateHeroAttack, calculateHeroMaxHp, calculateRarityEstimatedDuration, calculateTeamDamagePerCycle, formatDuration, HERO_RARITY_STATS, type BossCombat, type CombatHero } from '../combat';
import { COMBAT_SLOTS, mapCombatSlots, type CombatSlot } from '../combatSlots';

type Props={game:GameState;lang:LanguageStrings;languageCode:LanguageCode;combat?:BossCombat;syncing?:boolean;backendOfficial:boolean;isEquipping:boolean;onEquipHero:(heroId:string,slot:CombatSlot)=>Promise<BossCombat|void>;onClaimReward:()=>Promise<void>|void};
const labels:Record<HeroRarity,string>={common:'Comum',uncommon:'Incomum',rare:'Raro',epic:'Épico',legendary:'Lendário'};

export function BossPage({game,lang,languageCode,combat,syncing,backendOfficial,isEquipping,onEquipHero,onClaimReward}:Props){
  const t=(key:string)=>translate(languageCode,key);
  const [now,setNow]=useState(Date.now()); const [selectedSlot,setSelectedSlot]=useState<CombatSlot|null>(null); const [isHeroModalOpen,setIsHeroModalOpen]=useState(false); const [filter,setFilter]=useState<HeroRarity>('common'); const [hit,setHit]=useState(false);
  const previous=useRef(combat?.bossCurrentHp ?? game.boss.healthPercent);
  const equipInFlight=useRef(false);
  useEffect(()=>{const timer=window.setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(timer)},[]);
  useEffect(()=>{const hp=combat?.bossCurrentHp ?? game.boss.healthPercent;if(hp<previous.current){setHit(true);const timer=window.setTimeout(()=>setHit(false),500);previous.current=hp;return()=>clearTimeout(timer)}previous.current=hp},[combat?.bossCurrentHp,game.boss.healthPercent]);
  const heroes=useMemo<CombatHero[]>(()=>{
    if(combat?.heroes)return combat.heroes as CombatHero[];
    const localHeroes:CombatHero[]=[];
    (game.bossTeam??[]).forEach((instanceId,index)=>{
      if(!instanceId)return;
      const heroKey=instanceId.split(':')[0]; const catalogHero=HERO_CATALOG.find(hero=>hero.id===heroKey);
      if(!catalogHero)return;
      const stats=HERO_RARITY_STATS[catalogHero.rarity]; const maxHp=calculateHeroMaxHp(stats.baseHp,1);
      localHeroes.push({id:`demo-${instanceId}`,heroId:instanceId,name:catalogHero.name,image:catalogHero.image,rarity:catalogHero.rarity,slot:index+1,level:1,baseAtk:stats.baseAtk,finalAtk:calculateHeroAttack(stats.baseAtk,1),baseHp:stats.baseHp,maxHp,currentHp:maxHp,isAlive:true,knockedOutAt:null,reviveAt:null});
    });
    return localHeroes;
  },[combat?.heroes,game.bossTeam]);
  const petDamageBonus=combat?.petSummary?.bonuses?.boss_damage_percent??0; const slotted=mapCombatSlots(heroes).map(item=>item.hero??undefined); const baseDamage=calculateTeamDamagePerCycle(heroes); const damage=Number((baseDamage*(1+petDamageBonus/100)).toFixed(3)); const alive=heroes.filter(h=>h.isAlive);
  const maxHp=combat?.bossMaxHp ?? game.boss.maxHealth ?? 67500; const hp=combat?.bossCurrentHp ?? Math.ceil(maxHp*game.boss.healthPercent/100); const progress=Math.min(100,Math.max(0,hp/maxHp*100));
  const remaining=calculateEstimatedSecondsRemaining(hp,damage); const totalAtk=heroes.reduce((s,h)=>s+h.finalAtk,0); const totalHp=heroes.reduce((s,h)=>s+h.currentHp,0); const totalMaxHp=heroes.reduce((s,h)=>s+h.maxHp,0);
  const secondsUntil=(date?:string|null)=>date?Math.max(0,Math.ceil((new Date(date).getTime()-now)/1000)):0;
  const owned=combat?.ownedHeroes ?? HERO_CATALOG.flatMap(h=>Array.from({length:game.heroInventory?.[h.id]??0},(_,i)=>({id:`${h.id}:${i}`,heroKey:h.id,name:h.name,image:h.image,rarity:h.rarity,level:1})));
  const openHeroSelector=(slotNumber:CombatSlot)=>{setSelectedSlot(slotNumber);setIsHeroModalOpen(true)};
  const closeHeroSelector=()=>{if(isEquipping)return;setIsHeroModalOpen(false);setSelectedSlot(null)};
  const handleSelectHero=async(hero:{id:string})=>{
    if(equipInFlight.current)return;
    if(selectedSlot===null){toast.error(t('noSlotSelected'));return;}
    if(!hero.id){toast.error(t('invalidHero'));return;}
    equipInFlight.current=true;
    try{await onEquipHero(hero.id,selectedSlot);setIsHeroModalOpen(false);setSelectedSlot(null);}catch(error){console.error('Falha ao equipar herói',error);}finally{equipInFlight.current=false;}
  };
  return <section className="space-y-4"><div className={`boss-arena relative overflow-hidden rounded-3xl border border-white/10 bg-forge-black/80 p-4 shadow-card ${hit?'boss-arena-hit':''}`}>
    <img src={backgrounds.boss} alt="" className="absolute inset-0 h-full w-full object-cover opacity-70"/><div className="absolute inset-0 bg-gradient-to-b from-[#07090d]/20 via-[#07090d]/50 to-[#07090d]/95"/>
    <img src={dragon} alt="Dragão Ancestral" className="boss-dragon relative mx-auto mt-8 h-64 w-full object-contain"/><div className="relative">
      <div className="flex justify-between"><div><p className="text-xs uppercase tracking-[.3em] text-slate-400">{lang.boss} · Nv. {combat?.bossLevel??1}</p><h3 className="text-lg font-semibold">{combat?.bossName??'Dragão Ancestral'}</h3></div><div className="text-right"><ShieldCheck className="ml-auto h-5 w-5 text-rose-400"/><p className="text-[10px] text-slate-400">{translate(languageCode,'kills')}: {combat?.defeats??game.boss.defeats??0}</p></div></div>
      <div className="mt-3 rounded-2xl bg-black/65 p-3"><div className="flex justify-between text-sm"><span>{lang.bossHealth}</span><b>{Math.ceil(hp).toLocaleString()} / {maxHp.toLocaleString()} HP</b></div><div className="mt-2 h-3 overflow-hidden rounded-full bg-white/10"><div className="h-full bg-gradient-to-r from-rose-500 via-orange-500 to-amber-400" style={{width:`${progress}%`}}/></div></div>
      <div className="mt-3 grid grid-cols-2 gap-2 text-xs"><Stat label={t('bossTotalDamage')} value={Math.floor(combat?.totalDamageDealt??game.boss.playerDamage).toLocaleString()}/><Stat label={t('bossReward')} value={`${(combat?.rewardAmount??game.boss.rewards).toLocaleString()} FC`} gold/><Stat label={t('teamAttack')} value={totalAtk.toFixed(3)}/><Stat label={t('teamHealth')} value={`${totalHp}/${totalMaxHp}`}/><Stat label={t('damagePerCycle')} value={damage.toFixed(3)}/><Stat label="Bônus do pet" value={combat?.petSummary?.activePet?`${combat.petSummary.activePet.name} +${petDamageBonus}%`:'Nenhum'}/><Stat label={t('timeRemainingLabel')} value={alive.length?formatDuration(remaining??NaN):t('waitingRevive')}/><Stat label={t('rarityEstimate')} value={formatDuration(calculateRarityEstimatedDuration(heroes))}/><Stat label={t('nextAttacks')} value={`${t('teamLabel')} ${formatDuration(secondsUntil(combat?.nextHeroAttackAt))} · ${t('bossLabel')} ${formatDuration(secondsUntil(combat?.bossNextAttackAt))}`}/></div>
      <div className="mt-4 flex items-center justify-between"><p className="text-xs font-bold uppercase tracking-[.2em]">{t('combatEquipment')}</p><span className="text-[9px] text-emerald-400">{syncing?t('syncingBackend'):backendOfficial?t('officialBackend'):t('testMode')}</span></div>
      <div className="mt-2 grid grid-cols-5 gap-1.5">{slotted.map((h,i)=><button type="button" key={COMBAT_SLOTS[i]} onClick={()=>{openHeroSelector(COMBAT_SLOTS[i]);if(h)setFilter(h.rarity as HeroRarity)}} className="min-h-[145px] overflow-hidden rounded-xl border bg-black/65" style={{borderColor:h?RARITY_COLORS[h.rarity as HeroRarity]:'#64748b88'}}>{h?<><img src={h.image||HERO_CATALOG.find(x=>x.id===(combat?.ownedHeroes?.find(o=>o.id===h.heroId)?.heroKey))?.image} alt={h.name} className="aspect-square w-full object-cover"/><div className="p-1 text-center"><p className="truncate text-[8px] font-bold">{h.name}</p><p className="text-[8px]" style={{color:RARITY_COLORS[h.rarity as HeroRarity]}}>{t(h.rarity)} · {t('levelShort')}{h.level}</p><p className="text-[8px]">ATK {h.finalAtk.toFixed(3)}</p><p className="text-[8px]">HP {h.currentHp}/{h.maxHp}</p>{!h.isAlive&&<p className="text-[8px] text-rose-400">{t('defeated')}<br/>{t('revivesIn')} {formatDuration(secondsUntil(h.reviveAt))}</p>}</div></>:<span className="text-2xl text-slate-500">＋</span>}</button>)}</div>
      {combat?.status==='defeated'&&<button onClick={onClaimReward} className="mt-4 w-full rounded-2xl bg-gradient-to-b from-amber-300 to-orange-500 py-3 font-black text-black">{t('collectReward')} {combat.rewardAmount.toLocaleString()} FC</button>}
    </div></div>
    {isHeroModalOpen&&selectedSlot!==null&&<div className="fixed inset-0 z-[80] flex items-end justify-center bg-black/75 p-3" onClick={closeHeroSelector}><div className="w-full max-w-md rounded-t-3xl border border-amber-400/30 bg-[#090c12] p-4" onClick={e=>e.stopPropagation()}><div className="flex justify-between"><h3 className="font-bold">{t('selectHero')} · {t('slot')} {selectedSlot}</h3><button type="button" disabled={isEquipping} onClick={closeHeroSelector}>✕</button></div><div className="mt-3 grid grid-cols-5 gap-1">{(Object.keys(labels) as HeroRarity[]).map(r=><button type="button" key={r} onClick={()=>setFilter(r)} className="rounded-lg border p-2 text-[8px]" style={{borderColor:RARITY_COLORS[r],color:RARITY_COLORS[r]}}>{t(r)}</button>)}</div><div className="mt-3 grid max-h-[48vh] grid-cols-3 gap-2 overflow-y-auto">{owned.filter(h=>h.rarity===filter).map(h=>{const equipped=heroes.find(item=>item.heroId===h.id);const equippedElsewhere=equipped&&Number(equipped.slot)!==selectedSlot;return <button type="button" disabled={Boolean(equippedElsewhere)||isEquipping} key={h.id} onClick={()=>handleSelectHero(h)} className="overflow-hidden rounded-xl border bg-black disabled:cursor-not-allowed disabled:opacity-40" style={{borderColor:RARITY_COLORS[h.rarity]}}><img src={h.image||HERO_CATALOG.find(x=>x.id===h.heroKey)?.image} alt={h.name} className="aspect-square w-full object-cover"/><p className="truncate px-2 pt-2 text-[9px]">{h.name} · {t('levelShort')}{h.level}</p>{equippedElsewhere&&<p className="px-2 pb-2 text-[8px] text-amber-300">{t('equippedInSlot')} {Number(equipped.slot)}</p>}</button>})}</div></div></div>}
  </section>;
}
function Stat({label,value,gold=false}:{label:string;value:string;gold?:boolean}){return <div className="rounded-2xl bg-black/65 p-3"><p className="text-slate-400">{label}</p><p className={`mt-1 font-semibold ${gold?'text-amber-300':''}`}>{value}</p></div>}
