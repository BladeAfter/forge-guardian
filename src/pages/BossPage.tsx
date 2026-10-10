import { useLocalizedText } from '../LanguageContext';
import { ShieldCheck, Trophy } from 'lucide-react';
import { AvatarWithBorder } from '../components/AvatarWithBorder';
import { useEffect, useMemo, useRef, useState } from 'react';
import { toast } from 'sonner';
import type { GameState, LanguageStrings } from '../types';
import { backgrounds, dragon } from '../gameAssets';
import { translate, type LanguageCode } from '../i18n';
import { HERO_CATALOG, RARITY_COLORS, type HeroRarity } from '../heroCatalog';
import { setGlobalBossAutoAttack } from '../services';
import { calculateEstimatedSecondsRemaining, calculateHeroAttack, calculateHeroMaxHp, calculateRarityEstimatedDuration, calculateTeamDamagePerCycle, formatDuration, HERO_RARITY_STATS, type BossCombat, type CombatHero, type GlobalBossAutoAttackState } from '../combat';
import { COMBAT_SLOTS, mapCombatSlots, type CombatSlot } from '../combatSlots';
import { PirateActionArena } from '../components/PirateActionArena';
import { OceanControl } from '../components/OceanControl';
import { actionArenaArt } from '../gameAssets';
import { activePetBonuses, effectiveReviveSeconds, formatPetBonus, petBonusValue } from '../petBonuses';
import { useGlobalBossRanking, useGlobalBossRealtime } from '../hooks';
import { globalBossArt, globalBossTheme } from '../globalBossThemes';
import type { PvpHero } from '../pvp';


type OwnedHero={id:string;heroKey?:string;name:string;image?:string;rarity:HeroRarity;level:number;finalAtk?:number;finalHp?:number;power?:number;isNft?:boolean};
type Props={game:GameState;lang:LanguageStrings;languageCode:LanguageCode;combat?:BossCombat;collection?:PvpHero[];collectionLoading?:boolean;collectionError?:string|null;syncing?:boolean;backendOfficial:boolean;isEquipping:boolean;telegramInitData?:string|null;onEquipHero:(heroId:string,slot:CombatSlot)=>Promise<BossCombat|void>;onRemoveHero?:(slot:CombatSlot)=>Promise<void>|void;onAttack?:()=>Promise<void>|void;isAttacking?:boolean;onOpenSeasonPass?:()=>void;onWallet?:()=>void;onClaimReward:()=>Promise<void>|void};
const RARITY_KEYS:HeroRarity[]=['common','uncommon','rare','epic','legendary','mythic','ancestral'];
const normalizeRarity=(value?:string):HeroRarity=>{const map:Record<string,HeroRarity>={common:'common',comum:'common',uncommon:'uncommon',incomum:'uncommon',rare:'rare',raro:'rare',epic:'epic',epico:'epic','épico':'epic',legendary:'legendary',lendario:'legendary','lendário':'legendary',mythic:'mythic','mítico':'mythic',mitico:'mythic',ancestral:'ancestral',celestial:'celestial',celeste:'celestial',nft_exclusive:'nft_exclusive','nft-exclusive':'nft_exclusive',nft:'nft_exclusive','nft exclusivo':'nft_exclusive'};return map[String(value??'').trim().toLowerCase()]??'common'};
const compact=(value:number)=>Math.floor(value).toLocaleString();

export function BossPage({game,lang,languageCode,combat,collection,collectionLoading,collectionError,syncing,backendOfficial,isEquipping,telegramInitData,onEquipHero,onRemoveHero,onAttack,isAttacking,onOpenSeasonPass,onWallet,onClaimReward}:Props){
  const localizeText = useLocalizedText();

  const t=(key:string)=>translate(languageCode,key);
  const [now,setNow]=useState(Date.now()); const [selectedSlot,setSelectedSlot]=useState<CombatSlot|null>(null); const [isHeroModalOpen,setIsHeroModalOpen]=useState(false); const [filter,setFilter]=useState<HeroRarity|'all'>('all'); const [hit,setHit]=useState(false);
  const [isRankingOpen,setIsRankingOpen]=useState(false);
  // Season Pass benefit: offline Auto ATK (server-side scheduler). UI only reflects/toggles state.
  const [autoBusy,setAutoBusy]=useState(false);
  const [autoOverride,setAutoOverride]=useState<GlobalBossAutoAttackState|null>(null);
  const auto=autoOverride??combat?.autoAttack??null;
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
  const bossArt=bossNumberForArt(global?.bossNumber)===1?actionArenaArt.kraken:(globalBossArt(global?.bossKey,global?.bossNumber,global?.image)||dragon);
  const bossNumber=Number(global?.bossNumber??1); const totalBosses=Number(global?.totalBosses??10);
  const isFinalBoss=bossNumber>=totalBosses&&global?.status!=='active';
  const telegramId = (()=>{try {const user=JSON.parse(new URLSearchParams(telegramInitData??'').get('user')??'null');return user?.id?String(user.id):undefined;}catch{return undefined;}})();
  return <section className="seas-combat">
    <PirateActionArena name={global?.name??combat?.bossName??t('boss.defaultName')} image={bossArt}
      hp={hp} maxHp={maxHp} heroes={heroes} pet={activePet} telegramId={telegramId}
      hit={hit} attacking={isAttacking} active={combat?.bossActive!==false&&(!global||global.status==='active')}
      cooldown={secondsUntil(combat?.nextHeroAttackAt)} bossCountdown={combat?.bossNextAttackAt?secondsUntil(combat.bossNextAttackAt):null}
      damage={global?.yourDamage??combat?.totalDamageDealt??game.boss.playerDamage} rank={global?.yourRank??null}
      reward={Math.round((global?.estimatedReward??0)*(1+petRewardBonus/100))} status={combat?.status}
      swap={swap} onAttack={onAttack} onEquip={openHeroSelector} onRanking={()=>setIsRankingOpen(true)} />
    <div className="action-service-strip">
      {global?.lastReward?<span>{localizeText("Último tesouro:")}{compact(global.lastReward.rewardFc)} BERRIES</span>:null}
      {global&&global.minimumDamage>0?<span>{localizeText("Dano mínimo:")}{compact(global.minimumDamage)}</span>:null}
      {auto?<><span>{t('boss.autoAtk')} · {auto.active?t('boss.autoAtkOn'):t('boss.autoAtkOffLabel')}</span>
        <OceanControl disabled={autoBusy||!telegramInitData} onClick={async()=>{
          if(!auto.eligible){onOpenSeasonPass?.();return;}if(!telegramInitData)return;setAutoBusy(true);
          try{setAutoOverride(await setGlobalBossAutoAttack(telegramInitData,!auto.enabled));}
          catch(error){toast.error(error instanceof Error?error.message:t('boss.autoAtkError'));}
          finally{setAutoBusy(false);}
        }}>{auto.eligible?(auto.enabled?'Pausar automático':'Ativar automático'):t('boss.autoAtkUnlock')}</OceanControl></>:null}
      {combat?.status==='defeated'&&(!global||global.status==='active')?<OceanControl onClick={()=>void onClaimReward()}>{t('collectReward')} {combat.rewardAmount.toLocaleString()} BERRIES</OceanControl>:null}
      {isFinalBoss?<span>{t('boss.comingSoon')}</span>:null}
    </div>

    {isRankingOpen&&<div className="fixed inset-0 z-[85] flex items-end justify-center bg-black/80 p-2" onClick={()=>setIsRankingOpen(false)}><div className="forge-safe-page w-full max-w-md rounded-t-3xl border border-amber-400/30 bg-[#090c12] p-3" onClick={e=>e.stopPropagation()}>
      <div className="flex items-center justify-between"><h3 className="text-sm font-bold text-amber-300">{t('boss.rankingTitle')}</h3><button type="button" aria-label={t('close')} onClick={()=>setIsRankingOpen(false)} className="grid h-9 w-9 place-items-center rounded-xl border border-white/10 bg-black/60 text-slate-300">✕</button></div>
      <div className="mt-2 grid grid-cols-3 gap-1.5 text-[9px]"><Stat label={t('boss.totalDamage')} value={compact(ranking.data?.cycle?.totalDamage??global?.totalDamage??0)}/><Stat label={t('boss.rewardPool')} value={`${compact(ranking.data?.cycle?.rewardPoolFc??global?.rewardPoolFc??0)} BERRIES`} gold/><Stat label={t('boss.yourRank')} value={ranking.data?.you?.rank?`#${ranking.data.you.rank}`:'—'}/></div>
      {ranking.isLoading&&!ranking.data?<p className="py-8 text-center text-xs text-slate-400">{t('boss.loadingRanking')}</p>
      :!ranking.data?.top.length?<p className="py-8 text-center text-xs text-slate-400">{t('boss.noRanking')}</p>
      :<div className="mt-3 max-h-[55vh] space-y-1.5 overflow-y-auto">{ranking.data.top.map(entry=><div key={entry.userId} className={`flex items-center gap-2 rounded-2xl border p-2 ${entry.isYou?'border-amber-300/60 bg-amber-400/10':'border-white/10 bg-black/60'}`}>
        <span className="w-7 text-center text-[11px] font-black text-amber-300">#{entry.rank}</span>
        <AvatarWithBorder photoUrl={entry.photoUrl} border={entry.avatarBorder} fallback={(entry.name[0]??'?').toUpperCase()} size={entry.avatarBorder?44:32}/>
        <div className="min-w-0 flex-1"><p className="truncate text-[11px] font-bold">{entry.name}{entry.isYou?<span className="ml-1 text-[8px] text-amber-300">({t('boss.you')})</span>:null}</p><p className="text-[9px] text-slate-400">{compact(entry.damage)} · {t('boss.share')} {entry.sharePercent.toFixed(2)}%</p></div>
        <span className="text-[10px] font-bold text-amber-300">{compact(entry.estimatedReward)} BERRIES</span>
      </div>)}</div>}
    </div></div>}

    {isHeroModalOpen&&selectedSlot!==null&&<div className="fixed inset-0 z-[80] flex items-end justify-center bg-black/75 p-2" onClick={closeHeroSelector}><div className="forge-safe-page w-full max-w-md rounded-t-3xl border border-amber-400/30 bg-[#090c12] p-3" onClick={e=>e.stopPropagation()}>
      <div className="flex items-center justify-between"><h3 className="text-sm font-bold">{t('selectHero')} · {t('slot')} {selectedSlot}</h3><div className="flex items-center gap-2">{onRemoveHero&&slotted[COMBAT_SLOTS.indexOf(selectedSlot)]?<button type="button" disabled={isEquipping} onClick={async()=>{await onRemoveHero(selectedSlot);setIsHeroModalOpen(false);setSelectedSlot(null)}} className="min-h-9 rounded-xl border border-rose-400/40 bg-rose-500/10 px-3 text-[10px] font-bold text-rose-300">{t('boss.remove')}</button>:null}<button type="button" aria-label={t('close')} disabled={isEquipping} onClick={closeHeroSelector} className="grid h-9 w-9 place-items-center rounded-xl border border-white/10 bg-black/60 text-slate-300">✕</button></div></div>
      <div className="mt-3 grid grid-cols-6 gap-1">{(['all',...RARITY_KEYS] as Array<HeroRarity|'all'>).map(r=>{const active=filter===r;const count=r==='all'?owned.length:owned.filter(h=>h.rarity===r).length;return <button type="button" key={r} onClick={()=>setFilter(r)} className={`min-h-9 rounded-lg border px-1 py-1.5 text-[8px] font-bold leading-tight ${active?'border-amber-300 bg-amber-400/15 text-amber-300':'border-white/10 text-slate-400'}`}>{r==='all'?t('boss.all'):t(r)}<br/>{count}</button>})}</div>
      {collectionError?<p className="py-8 text-center text-xs text-rose-300">{collectionError}</p>
      :collectionLoading&&!owned.length?<p className="py-8 text-center text-xs text-slate-400">{t('boss.loadingHeroes')}</p>
      :!owned.length?<p className="py-8 text-center text-xs text-slate-400">{t('boss.noHeroesOwned')}</p>
      :!visibleOwned.length?<p className="py-8 text-center text-xs text-slate-400">{t('boss.noHeroesRarity')}</p>
      :<div className="mt-3 grid max-h-[52vh] grid-cols-3 gap-2 overflow-y-auto">{visibleOwned.map(h=>{const equipped=heroes.find(item=>item.heroId===h.id);const equippedHere=equipped&&Number(equipped.slot)===selectedSlot;return <button type="button" disabled={isEquipping} key={h.id} onClick={()=>handleSelectHero(h)} className={`relative overflow-hidden rounded-xl border bg-black text-left disabled:opacity-40 ${h.isNft?'nft-hero-card':''}`} style={{borderColor:h.isNft?undefined:(equippedHere?'#fbbf24':RARITY_COLORS[h.rarity])}}>{h.isNft?<div className="nft-hero-head nft-hero-head--lg"><span className="nft-hero-badge nft-hero-badge--lg">{localizeText("💎 NFT EXCLUSIVE")}</span></div>:null}<img src={h.image||HERO_CATALOG.find(x=>x.id===h.heroKey)?.image} alt={h.name} className="aspect-square w-full object-cover object-top"/><div className="p-1.5"><p className={`truncate text-[9px] font-bold ${h.isNft?'nft-hero-name':''}`}>{h.name}</p>{h.isNft?<p className="nft-hero-rarity text-[8px] font-black tracking-widest">{localizeText("NFT EXCLUSIVE ·")}{t('levelShort')}{h.level}</p>:<p className="text-[8px]" style={{color:RARITY_COLORS[h.rarity]}}>{t(h.rarity)} · {t('levelShort')}{h.level}</p>}{h.finalAtk?<p className="text-[8px] text-slate-300">ATK {h.finalAtk.toLocaleString()}</p>:null}{h.finalHp?<p className="text-[8px] text-slate-300">HP {h.finalHp.toLocaleString()}</p>:null}{h.power?<p className="text-[8px] text-amber-200">{t('boss.power')} {h.power.toLocaleString()}</p>:null}{equipped?<p className="text-[8px] text-amber-300">{equippedHere?t('boss.inThisSlot'):`${t('equippedInSlot')} ${Number(equipped.slot)}`}</p>:null}</div></button>})}</div>}
    </div></div>}
  </section>;
}
function Stat({label,value,gold=false}:{label:string;value:string;gold?:boolean}){return <div className="rounded-2xl bg-black/65 p-3"><p className="text-slate-400">{label}</p><p className={`mt-1 font-semibold ${gold?'text-amber-300':''}`}>{value}</p></div>}

function bossNumberForArt(value?:number|null){return Number(value??1);}
