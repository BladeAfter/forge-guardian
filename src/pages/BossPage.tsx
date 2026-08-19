import { ShieldCheck, Trophy } from 'lucide-react';
import { AvatarWithBorder } from '../components/AvatarWithBorder';
import { useEffect, useMemo, useRef, useState } from 'react';
import { toast } from 'sonner';
import type { GameState, LanguageStrings } from '../types';
import { dragon } from '../gameAssets';
import { translate, type LanguageCode } from '../i18n';
import { HERO_CATALOG, RARITY_COLORS, type HeroRarity } from '../heroCatalog';
import { setGlobalBossAutoAttack } from '../services';
import { calculateEstimatedSecondsRemaining, calculateHeroAttack, calculateHeroMaxHp, calculateRarityEstimatedDuration, calculateTeamDamagePerCycle, formatDuration, HERO_RARITY_STATS, type BossCombat, type CombatHero, type GlobalBossAutoAttackState } from '../combat';
import { COMBAT_SLOTS, mapCombatSlots, type CombatSlot } from '../combatSlots';
import { PetCompanion } from '../components/PetCompanion';
import { activePetBonuses, effectiveReviveSeconds, formatPetBonus, petBonusValue } from '../petBonuses';
import { useGlobalBossRanking, useGlobalBossRealtime } from '../hooks';
import { globalBossArt, globalBossTheme } from '../globalBossThemes';
import type { PvpHero } from '../pvp';
import { TowerOfEternityPanel } from '../components/TowerOfEternityPanel';

type BossMode='global'|'tower';

type OwnedHero={id:string;heroKey?:string;name:string;image?:string;rarity:HeroRarity;level:number;finalAtk?:number;finalHp?:number;power?:number;isNft?:boolean};
type Props={game:GameState;lang:LanguageStrings;languageCode:LanguageCode;combat?:BossCombat;collection?:PvpHero[];collectionLoading?:boolean;collectionError?:string|null;syncing?:boolean;backendOfficial:boolean;isEquipping:boolean;telegramInitData?:string|null;onEquipHero:(heroId:string,slot:CombatSlot)=>Promise<BossCombat|void>;onRemoveHero?:(slot:CombatSlot)=>Promise<void>|void;onAttack?:()=>Promise<void>|void;isAttacking?:boolean;onOpenSeasonPass?:()=>void;onClaimReward:()=>Promise<void>|void};
const RARITY_KEYS:HeroRarity[]=['common','uncommon','rare','epic','legendary','mythic','ancestral'];
const normalizeRarity=(value?:string):HeroRarity=>{const map:Record<string,HeroRarity>={common:'common',comum:'common',uncommon:'uncommon',incomum:'uncommon',rare:'rare',raro:'rare',epic:'epic',epico:'epic','épico':'epic',legendary:'legendary',lendario:'legendary','lendário':'legendary',mythic:'mythic','mítico':'mythic',mitico:'mythic',ancestral:'ancestral'};return map[String(value??'').trim().toLowerCase()]??'common'};
const compact=(value:number)=>Math.floor(value).toLocaleString();

export function BossPage({game,lang,languageCode,combat,collection,collectionLoading,collectionError,syncing,backendOfficial,isEquipping,telegramInitData,onEquipHero,onRemoveHero,onAttack,isAttacking,onOpenSeasonPass,onClaimReward}:Props){
  const t=(key:string)=>translate(languageCode,key);
  const [now,setNow]=useState(Date.now()); const [selectedSlot,setSelectedSlot]=useState<CombatSlot|null>(null); const [isHeroModalOpen,setIsHeroModalOpen]=useState(false); const [filter,setFilter]=useState<HeroRarity|'all'>('all'); const [hit,setHit]=useState(false);
  const [isRankingOpen,setIsRankingOpen]=useState(false);
  // Season Pass benefit: offline Auto ATK (server-side scheduler). UI only reflects/toggles state.
  const [autoBusy,setAutoBusy]=useState(false);
  const [autoOverride,setAutoOverride]=useState<GlobalBossAutoAttackState|null>(null);
  const auto=autoOverride??combat?.autoAttack??null;
  const [bossMode,setBossMode]=useState<BossMode>('global');
  const global=combat?.globalBoss??null;
  const ranking=useGlobalBossRanking(telegramInitData??null,Boolean(telegramInitData)&&isRankingOpen);
  
  // Cycle swap banner: shows "Boss Defeated / Rewards Distributed / Next Boss Appeared".
  const [swap,setSwap]=useState<'defeated'|'expired'|null>(null);
  const lastCycle=useRef<number|null>(global?.cycleNumber??null);
  // Live cycle: reward pool, HP, ends_at, boss swap, status and ranking arrive via Realtime.
  useGlobalBossRealtime(global?.cycleId??null,Boolean(telegramInitData));

  useEffect(()=>{
    const cycle=global?.cycleNumber??null; if(cycle===null)return;
    if(lastCycle.current!==null&&cycle>lastCycle.current){
      setSwap(global?.endedReason==='expired'?'expired':'defeated');
      const timer=window.setTimeout(()=>setSwap(null),3200);
      lastCycle.current=cycle; return()=>clearTimeout(timer);
    }
    lastCycle.current=cycle;
  },[global?.cycleNumber,global?.endedReason]);

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
  const petBonuses=combat?.petSummary?.bonuses??null; const activePet=combat?.petSummary?.activePet??null;
  const petDamageBonus=petBonusValue(petBonuses,'boss_damage_percent');
  const petReviveBonus=petBonusValue(petBonuses,'revive_speed_percent');
  const petRewardBonus=petBonusValue(petBonuses,'reward_percent');
  const bossPetBonuses=activePetBonuses(petBonuses);
  const petBonusText=!activePet?t('boss.noPetActive'):bossPetBonuses.length?bossPetBonuses.map(formatPetBonus).join(' · '):t('boss.noPetEffect'); const slotted=mapCombatSlots(heroes).map(item=>item.hero??undefined); const baseDamage=calculateTeamDamagePerCycle(heroes); const damage=Number((baseDamage*(1+petDamageBonus/100)).toFixed(3)); const alive=heroes.filter(h=>h.isAlive);
  // The boss HP bar is the SHARED global cycle HP — every player hits the same bar.
  const maxHp=global?.maxHp ?? combat?.bossMaxHp ?? game.boss.maxHealth ?? 67500; const hp=global?.currentHp ?? combat?.bossCurrentHp ?? Math.ceil(maxHp*game.boss.healthPercent/100); const progress=Math.min(100,Math.max(0,hp/maxHp*100));
  const endsIn=global?.endsAt?Math.max(0,Math.ceil((new Date(global.endsAt).getTime()-now)/1000)):null;

  const remaining=calculateEstimatedSecondsRemaining(hp,damage); const totalAtk=heroes.reduce((s,h)=>s+h.finalAtk,0); const totalHp=heroes.reduce((s,h)=>s+h.currentHp,0); const totalMaxHp=heroes.reduce((s,h)=>s+h.maxHp,0);
  const secondsUntil=(date?:string|null)=>date?Math.max(0,Math.ceil((new Date(date).getTime()-now)/1000)):0;
  // Single source of truth: the player's hero collection (player_heroes) — the same
  // list used by "Meus Heróis" and PvP. Boss never keeps a separate inventory.
  const owned=useMemo<OwnedHero[]>(()=>{
    if(collection?.length)return collection.map(h=>({id:h.heroId,name:h.name,image:h.imageUrl,rarity:normalizeRarity(h.rarity),level:h.level,finalAtk:h.finalAtk,finalHp:h.finalHp,power:h.power,isNft:Boolean(h.isNft)}));
    if(combat?.ownedHeroes?.length)return combat.ownedHeroes.map(h=>({id:h.id,heroKey:h.heroKey,name:h.name,image:h.image,rarity:normalizeRarity(h.rarity),level:h.level}));
    return HERO_CATALOG.flatMap(h=>Array.from({length:game.heroInventory?.[h.id]??0},(_,i)=>({id:`${h.id}:${i}`,heroKey:h.id,name:h.name,image:h.image,rarity:normalizeRarity(h.rarity),level:1})));
  },[collection,combat?.ownedHeroes,game.heroInventory]);
  const visibleOwned=filter==='all'?owned:owned.filter(h=>h.rarity===filter);
  useEffect(()=>{if(isHeroModalOpen){if(collectionError)console.error('[BOSS HEROES ERROR]',collectionError);console.log('[BOSS HEROES]',{source:collection?.length?'player_heroes':'boss_combat',totalUserHeroes:owned.length,filter,filteredCount:visibleOwned.length})}},[isHeroModalOpen,filter,owned.length,visibleOwned.length,collection?.length,collectionError]);
  const openHeroSelector=(slotNumber:CombatSlot)=>{setSelectedSlot(slotNumber);setFilter('all');setIsHeroModalOpen(true)};
  const closeHeroSelector=()=>{if(isEquipping)return;setIsHeroModalOpen(false);setSelectedSlot(null)};
  const handleSelectHero=async(hero:{id:string})=>{
    if(equipInFlight.current)return;
    if(selectedSlot===null){toast.error(t('noSlotSelected'));return;}
    if(!hero.id){toast.error(t('invalidHero'));return;}
    equipInFlight.current=true;
    try{await onEquipHero(hero.id,selectedSlot);setIsHeroModalOpen(false);setSelectedSlot(null);}catch(error){console.error('Falha ao equipar herói',error);}finally{equipInFlight.current=false;}
  };
  const theme=globalBossTheme(global?.bossKey,global?.bossNumber);
  const bossArt=globalBossArt(global?.bossKey,global?.bossNumber,global?.image)||dragon;
  const bossNumber=Number(global?.bossNumber??1); const totalBosses=Number(global?.totalBosses??10);
  const isFinalBoss=bossNumber>=totalBosses&&global?.status!=='active';
  const modeSelector=<div className="grid grid-cols-2 gap-1 rounded-2xl border border-amber-400/25 bg-black/60 p-1">
    {([['global','🌍 GLOBAL BOSS'],['tower','🏰 TOWER']] as Array<[BossMode,string]>).map(([value,label])=>{
      const active=bossMode===value;
      return <button type="button" key={value} onClick={()=>setBossMode(value)} className={`min-h-9 rounded-xl text-[10px] font-black uppercase tracking-wide transition ${active?'border border-amber-300/70 bg-gradient-to-b from-amber-500/25 to-amber-900/40 text-amber-100':'text-slate-400'}`}>{label}</button>;
    })}
  </div>;
  if(bossMode==='tower')return <section className="space-y-3">{modeSelector}<TowerOfEternityPanel balance={game.balance} collection={collection} collectionLoading={collectionLoading} telegramInitData={telegramInitData}/></section>;
  return <section className="space-y-3">{modeSelector}<div className={`boss-arena gb-hero relative overflow-hidden rounded-3xl border ${theme.border} p-3 shadow-card ${hit?'boss-arena-hit':''}`} style={{backgroundColor:'#05070c'}}>

    <img key={`arena-${theme.key}`} src={theme.arena} alt="" aria-hidden className="gb-arena-art"/><div className="gb-arena-shade"/><div className="gb-arena-mist"/>
    {swap?<div className="gb-swap-overlay"><b>{swap==='defeated'?t('boss.swapDefeated'):t('boss.swapExpired')}</b><span>{t('boss.swapRewards')}</span><span>{t('boss.swapNext')}</span></div>:null}
    <div className="relative flex items-start justify-between gap-2"><div><p className={`text-[10px] uppercase tracking-[.3em] ${theme.accent}`}>{t('boss.globalBoss')}{global?` · ${t('boss.cycle')} #${global.cycleNumber}`:''}</p><h3 className="text-lg font-semibold leading-tight">{global?.name??combat?.bossName??t('boss.defaultName')}</h3><p className="text-[10px] text-slate-300/80">{global?.subtitle??`${t('boss.globalBoss')} · ${t('levelShort')}${global?.bossLevel??combat?.bossLevel??1}`}</p><p className="text-[10px] text-slate-300/80">{lang.boss} {bossNumber}/{totalBosses}{endsIn!==null?` · ${t('boss.endsIn')} ${formatDuration(endsIn)}`:''}</p></div><div className="text-right"><ShieldCheck className="ml-auto h-5 w-5 text-rose-400"/><p className="text-[10px] text-slate-300/80">{translate(languageCode,'kills')}: {combat?.defeats??game.boss.defeats??0}</p><button type="button" onClick={()=>setIsRankingOpen(true)} className="mt-2 inline-flex min-h-9 items-center gap-1 rounded-xl border border-amber-300/40 bg-amber-400/10 px-2.5 text-[10px] font-bold text-amber-300"><Trophy className="h-3.5 w-3.5"/>{t('boss.ranking')}</button></div></div>
    <div className="gb-stage relative mx-auto mt-2 flex w-full items-center justify-center">
      <div className="gb-arena-floor"/>
      <div className="gb-aura absolute left-1/2 top-1/2 h-32 w-32 -translate-x-1/2 -translate-y-1/2 rounded-full blur-2xl sm:h-40 sm:w-40" style={{backgroundImage:theme.aura}}/>
      <img key={`${global?.cycleId??'boss'}`} src={bossArt} alt={global?.name??combat?.bossName??t('boss.defaultName')} className="gb-boss gb-enter" style={{filter:theme.glow}}/>
    </div>

      <div className="relative mt-2 rounded-2xl border border-white/10 bg-black/70 p-3 backdrop-blur-sm"><div className="flex justify-between text-sm"><span>{t('boss.globalHp')}</span><b>{Math.ceil(hp).toLocaleString()} / {maxHp.toLocaleString()} HP</b></div><div className="mt-2 h-3 overflow-hidden rounded-full bg-white/10"><div className="h-full transition-all duration-500" style={{width:`${progress}%`,backgroundImage:theme.bar}}/></div>{global?<div className="mt-2 flex justify-between text-[9px] text-slate-400"><span>{t('boss.participants')}: {global.participants.toLocaleString()}</span><span>{t('boss.rewardPool')}: {compact(global.rewardPoolFc)} FC</span></div>:null}</div>
    </div><div className="gb-panel relative rounded-3xl border border-white/10 p-3 shadow-card">

      {global?.lastReward?<p className="mt-2 rounded-2xl border border-emerald-400/30 bg-emerald-500/10 p-2.5 text-center text-[10px] text-emerald-200">{t('boss.lastReward')}: <b>{compact(global.lastReward.rewardFc)} FC</b> · #{global.lastReward.rank}</p>:null}
      <div className="mt-3 grid grid-cols-2 gap-2 text-xs"><Stat label={t('boss.totalDamage')} value={compact(global?.totalDamage??0)}/><Stat label={t('boss.yourDamage')} value={compact(global?.yourDamage??combat?.totalDamageDealt??game.boss.playerDamage)}/><Stat label={t('boss.yourRank')} value={global?.yourRank?`#${global.yourRank}`:'—'}/><Stat label={t('boss.estReward')} value={`${compact(Math.round((global?.estimatedReward??0)*(1+petRewardBonus/100)))} FC`} gold/><Stat label={t('teamAttack')} value={Math.round(totalAtk).toLocaleString()}/><Stat label={t('teamHealth')} value={`${Math.round(totalHp).toLocaleString()}/${Math.round(totalMaxHp).toLocaleString()}`}/><Stat label={t('damagePerCycle')} value={Math.round(damage).toLocaleString()}/><Stat label={t('boss.petBonusLabel')} value={activePet?`${activePet.name} · ${petBonusText}`:petBonusText}/><Stat label={t('timeRemainingLabel')} value={alive.length?formatDuration(remaining??NaN):t('waitingRevive')}/><Stat label="Revive" value={formatDuration(effectiveReviveSeconds(petReviveBonus))}/><Stat label={t('rarityEstimate')} value={formatDuration(calculateRarityEstimatedDuration(heroes))}/><Stat label={t('nextAttacks')} value={`${t('teamLabel')} ${formatDuration(secondsUntil(combat?.nextHeroAttackAt))} · ${t('bossLabel')} ${formatDuration(secondsUntil(combat?.bossNextAttackAt))}`}/></div>
      {global&&global.minimumDamage>0?<p className="mt-2 text-center text-[9px] text-slate-400">{t('boss.minDamage')}: {compact(global.minimumDamage)}</p>:null}
      {isFinalBoss?<p className="mt-2 rounded-2xl border border-amber-300/40 bg-amber-400/10 p-2.5 text-center text-[10px] font-bold text-amber-200">{t('boss.comingSoon')}</p>:null}
      


      <PetCompanion pet={activePet} buffs={bossPetBonuses} />
      <div className="mt-4 flex items-center justify-between"><p className="text-xs font-bold uppercase tracking-[.2em]">{t('combatEquipment')}</p><span className="text-[9px] text-emerald-400">{syncing?t('syncingBackend'):backendOfficial?t('officialBackend'):t('testMode')}</span></div>
      <div className="mt-2 grid grid-cols-5 gap-1.5">{slotted.map((h,i)=>{const nft=Boolean(h&&owned.find(o=>o.id===h.heroId)?.isNft);return <button type="button" key={COMBAT_SLOTS[i]} onClick={()=>openHeroSelector(COMBAT_SLOTS[i])} className={`relative min-h-[145px] overflow-hidden rounded-xl border bg-black/65 ${nft?'nft-hero-card':''}`} style={{borderColor:h?(nft?undefined:RARITY_COLORS[h.rarity as HeroRarity]):'#64748b88'}}>{h?<>{nft?<div className="nft-hero-head"><span className="nft-hero-badge">💎 NFT</span></div>:null}<img src={h.image||HERO_CATALOG.find(x=>x.id===(combat?.ownedHeroes?.find(o=>o.id===h.heroId)?.heroKey))?.image} alt={h.name} className="aspect-square w-full object-cover object-top"/><div className="p-1 text-center"><p className={`truncate text-[8px] font-bold ${nft?'nft-hero-name':''}`}>{h.name}</p>{nft?<p className="nft-hero-rarity text-[8px] font-black tracking-widest">NFT EXCLUSIVE · {t('levelShort')}{h.level}</p>:<p className="text-[8px]" style={{color:RARITY_COLORS[h.rarity as HeroRarity]}}>{t(h.rarity)} · {t('levelShort')}{h.level}</p>}<p className="text-[8px]">ATK {Math.round(h.finalAtk).toLocaleString()}</p><p className="text-[8px]">HP {Math.round(h.currentHp).toLocaleString()}/{Math.round(h.maxHp).toLocaleString()}</p>{!h.isAlive&&<p className="text-[8px] text-rose-400">{t('defeated')}<br/>{t('revivesIn')} {formatDuration(secondsUntil(h.reviveAt))}</p>}{h.isAlive&&h.reviveProtected&&!h.reviveAttackUsed&&<p className="animate-pulse text-[8px] font-bold text-amber-300">{t('boss.revived')}<br/>{t('boss.readyToStrike')}</p>}</div></>:<span className="text-2xl text-slate-500">＋</span>}</button>})}</div>
      {/* Team building is always allowed; only attacking depends on an active boss. */}
      {combat&&combat.bossActive===false&&<p className="mt-3 rounded-2xl border border-white/10 bg-black/70 p-3 text-center text-[11px] text-slate-300">{t('boss.notActiveLine1')}<br/>{t('boss.notActiveLine2')}</p>}
      {auto?<div className={`mt-4 flex items-center justify-between gap-2 rounded-2xl border p-3 ${auto.active?'border-amber-300/50 bg-gradient-to-r from-amber-400/15 to-orange-500/10':'border-white/10 bg-black/60'}`}>
        <div className="min-w-0">
          <p className={`text-[11px] font-black uppercase tracking-[.18em] ${auto.active?'text-amber-200':'text-slate-300'}`}>{auto.eligible?'⚔️':'🔒'} {t('boss.autoAtk')}</p>
          <p className="mt-0.5 truncate text-[9px] text-slate-400">
            {!auto.eligible?t('boss.autoAtkRequired')
            :!auto.enabled?t('boss.autoAtkOff')
            :!auto.hasTeam?t('boss.autoAtkNoTeam')
            :auto.waitingRevive?`${t('boss.autoAtkOffline')} · ${t('boss.autoAtkRevive')}`
            /* one single official countdown: the server already merged cooldown + revive */
            :`${t('boss.autoAtkOffline')} · ${t('boss.autoAtkNext')} ${formatDuration(secondsUntil(auto.nextAttackAt))}`}
          </p>
        </div>
        {auto.eligible
          ?<button type="button" disabled={autoBusy||!telegramInitData} onClick={async()=>{
              if(!telegramInitData)return; setAutoBusy(true);
              try{setAutoOverride(await setGlobalBossAutoAttack(telegramInitData,!auto.enabled))}
              catch(error){toast.error(error instanceof Error?error.message:t('boss.autoAtkError'))}
              finally{setAutoBusy(false)}
            }} className={`shrink-0 rounded-full px-4 py-2 text-[10px] font-black uppercase tracking-[.14em] transition active:scale-95 disabled:opacity-50 ${auto.enabled?'bg-gradient-to-b from-amber-300 to-orange-500 text-black':'border border-white/15 bg-black/60 text-slate-300'}`}>{auto.enabled?t('boss.autoAtkOn'):t('boss.autoAtkOffLabel')}</button>
          :<button type="button" onClick={()=>onOpenSeasonPass?.()} className="shrink-0 rounded-full border border-amber-300/40 bg-black/60 px-4 py-2 text-[10px] font-black uppercase tracking-[.14em] text-amber-200 transition active:scale-95">{t('boss.autoAtkUnlock')}</button>}
      </div>:null}
      {global&&global.status!=='active'
        ?<p className="mt-4 rounded-2xl border border-amber-300/40 bg-amber-400/10 p-3 text-center text-[11px] font-bold text-amber-200">{t('boss.defeatedGlobal')}</p>
        :combat?.status==='defeated'
        ?<button onClick={onClaimReward} className="mt-4 w-full rounded-2xl bg-gradient-to-b from-amber-300 to-orange-500 py-3 font-black text-black">{t('collectReward')} {combat.rewardAmount.toLocaleString()} FC</button>
        :onAttack?<button type="button" onClick={()=>onAttack()} disabled={isAttacking||combat?.bossActive===false} className="mt-4 w-full rounded-2xl bg-gradient-to-b from-rose-400 to-rose-700 py-3 font-black text-white disabled:opacity-40">{isAttacking?t('boss.attacking'):t('boss.attack')}</button>:null}
    </div>

    {isRankingOpen&&<div className="fixed inset-0 z-[85] flex items-end justify-center bg-black/80 p-2" onClick={()=>setIsRankingOpen(false)}><div className="forge-safe-page w-full max-w-md rounded-t-3xl border border-amber-400/30 bg-[#090c12] p-3" onClick={e=>e.stopPropagation()}>
      <div className="flex items-center justify-between"><h3 className="text-sm font-bold text-amber-300">{t('boss.rankingTitle')}</h3><button type="button" aria-label={t('close')} onClick={()=>setIsRankingOpen(false)} className="grid h-9 w-9 place-items-center rounded-xl border border-white/10 bg-black/60 text-slate-300">✕</button></div>
      <div className="mt-2 grid grid-cols-3 gap-1.5 text-[9px]"><Stat label={t('boss.totalDamage')} value={compact(ranking.data?.cycle?.totalDamage??global?.totalDamage??0)}/><Stat label={t('boss.rewardPool')} value={`${compact(ranking.data?.cycle?.rewardPoolFc??global?.rewardPoolFc??0)} FC`} gold/><Stat label={t('boss.yourRank')} value={ranking.data?.you?.rank?`#${ranking.data.you.rank}`:'—'}/></div>
      {ranking.isLoading&&!ranking.data?<p className="py-8 text-center text-xs text-slate-400">{t('boss.loadingRanking')}</p>
      :!ranking.data?.top.length?<p className="py-8 text-center text-xs text-slate-400">{t('boss.noRanking')}</p>
      :<div className="mt-3 max-h-[55vh] space-y-1.5 overflow-y-auto">{ranking.data.top.map(entry=><div key={entry.userId} className={`flex items-center gap-2 rounded-2xl border p-2 ${entry.isYou?'border-amber-300/60 bg-amber-400/10':'border-white/10 bg-black/60'}`}>
        <span className="w-7 text-center text-[11px] font-black text-amber-300">#{entry.rank}</span>
        <AvatarWithBorder photoUrl={entry.photoUrl} border={entry.avatarBorder} fallback={(entry.name[0]??'?').toUpperCase()} size={entry.avatarBorder?44:32}/>
        <div className="min-w-0 flex-1"><p className="truncate text-[11px] font-bold">{entry.name}{entry.isYou?<span className="ml-1 text-[8px] text-amber-300">({t('boss.you')})</span>:null}</p><p className="text-[9px] text-slate-400">{compact(entry.damage)} · {t('boss.share')} {entry.sharePercent.toFixed(2)}%</p></div>
        <span className="text-[10px] font-bold text-amber-300">{compact(entry.estimatedReward)} FC</span>
      </div>)}</div>}
    </div></div>}

    {isHeroModalOpen&&selectedSlot!==null&&<div className="fixed inset-0 z-[80] flex items-end justify-center bg-black/75 p-2" onClick={closeHeroSelector}><div className="forge-safe-page w-full max-w-md rounded-t-3xl border border-amber-400/30 bg-[#090c12] p-3" onClick={e=>e.stopPropagation()}>
      <div className="flex items-center justify-between"><h3 className="text-sm font-bold">{t('selectHero')} · {t('slot')} {selectedSlot}</h3><div className="flex items-center gap-2">{onRemoveHero&&slotted[COMBAT_SLOTS.indexOf(selectedSlot)]?<button type="button" disabled={isEquipping} onClick={async()=>{await onRemoveHero(selectedSlot);setIsHeroModalOpen(false);setSelectedSlot(null)}} className="min-h-9 rounded-xl border border-rose-400/40 bg-rose-500/10 px-3 text-[10px] font-bold text-rose-300">{t('boss.remove')}</button>:null}<button type="button" aria-label={t('close')} disabled={isEquipping} onClick={closeHeroSelector} className="grid h-9 w-9 place-items-center rounded-xl border border-white/10 bg-black/60 text-slate-300">✕</button></div></div>
      <div className="mt-3 grid grid-cols-6 gap-1">{(['all',...RARITY_KEYS] as Array<HeroRarity|'all'>).map(r=>{const active=filter===r;const count=r==='all'?owned.length:owned.filter(h=>h.rarity===r).length;return <button type="button" key={r} onClick={()=>setFilter(r)} className={`min-h-9 rounded-lg border px-1 py-1.5 text-[8px] font-bold leading-tight ${active?'border-amber-300 bg-amber-400/15 text-amber-300':'border-white/10 text-slate-400'}`}>{r==='all'?t('boss.all'):t(r)}<br/>{count}</button>})}</div>
      {collectionError?<p className="py-8 text-center text-xs text-rose-300">{collectionError}</p>
      :collectionLoading&&!owned.length?<p className="py-8 text-center text-xs text-slate-400">{t('boss.loadingHeroes')}</p>
      :!owned.length?<p className="py-8 text-center text-xs text-slate-400">{t('boss.noHeroesOwned')}</p>
      :!visibleOwned.length?<p className="py-8 text-center text-xs text-slate-400">{t('boss.noHeroesRarity')}</p>
      :<div className="mt-3 grid max-h-[52vh] grid-cols-3 gap-2 overflow-y-auto">{visibleOwned.map(h=>{const equipped=heroes.find(item=>item.heroId===h.id);const equippedHere=equipped&&Number(equipped.slot)===selectedSlot;return <button type="button" disabled={isEquipping} key={h.id} onClick={()=>handleSelectHero(h)} className={`relative overflow-hidden rounded-xl border bg-black text-left disabled:opacity-40 ${h.isNft?'nft-hero-card':''}`} style={{borderColor:h.isNft?undefined:(equippedHere?'#fbbf24':RARITY_COLORS[h.rarity])}}>{h.isNft?<div className="nft-hero-head nft-hero-head--lg"><span className="nft-hero-badge nft-hero-badge--lg">💎 NFT EXCLUSIVE</span></div>:null}<img src={h.image||HERO_CATALOG.find(x=>x.id===h.heroKey)?.image} alt={h.name} className="aspect-square w-full object-cover object-top"/><div className="p-1.5"><p className={`truncate text-[9px] font-bold ${h.isNft?'nft-hero-name':''}`}>{h.name}</p>{h.isNft?<p className="nft-hero-rarity text-[8px] font-black tracking-widest">NFT EXCLUSIVE · {t('levelShort')}{h.level}</p>:<p className="text-[8px]" style={{color:RARITY_COLORS[h.rarity]}}>{t(h.rarity)} · {t('levelShort')}{h.level}</p>}{h.finalAtk?<p className="text-[8px] text-slate-300">ATK {h.finalAtk.toLocaleString()}</p>:null}{h.finalHp?<p className="text-[8px] text-slate-300">HP {h.finalHp.toLocaleString()}</p>:null}{h.power?<p className="text-[8px] text-amber-200">{t('boss.power')} {h.power.toLocaleString()}</p>:null}{equipped?<p className="text-[8px] text-amber-300">{equippedHere?t('boss.inThisSlot'):`${t('equippedInSlot')} ${Number(equipped.slot)}`}</p>:null}</div></button>})}</div>}
    </div></div>}
  </section>;
}
function Stat({label,value,gold=false}:{label:string;value:string;gold?:boolean}){return <div className="rounded-2xl bg-black/65 p-3"><p className="text-slate-400">{label}</p><p className={`mt-1 font-semibold ${gold?'text-amber-300':''}`}>{value}</p></div>}
