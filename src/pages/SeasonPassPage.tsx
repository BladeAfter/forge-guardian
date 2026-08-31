import React from'react';
import{useTonConnectUI,useTonWallet}from'@tonconnect/ui-react';
import{useMutation,useQueryClient}from'@tanstack/react-query';
import{ArrowLeft,Check,Gem,Lock,ScrollText,Shield,Star,Sword,Ticket}from'lucide-react';
import{toast}from'sonner';
import{seasonPassRequest,buySeasonPassLevels,buySeasonPassWithMyth,buySeasonPassWithInternalTon,buyLockedPassReward,verifyLockedPassRewards}from'../services';
import{useMythUtility}from'../hooks';
import{MythPayButton,MythBalanceHint}from'../components/MythPayButton';
import type{MythUtilityState}from'../mythUtility';
import{sendTonPayment,type TonTransactionRequest}from'../tonPayment';

import{purchaseBattlePass,waitForPassActivation,activatedPass,passTierLabel,reconcilePendingPassPurchases}from'../passPurchase';
import{useT,useLanguage}from'../LanguageContext';
import{formatTon}from'../economy';
import{useSeasonPass}from'../hooks';
import{mainScreenArt}from'../gameAssets';
import{type PassReward,type PassTier,type PassLevelPurchaseConfig,type SeasonPassDashboard}from'../seasonPass';
import mythicEggAsset from'../assets/season-1-mythic-egg-transparent.webp.asset.json';
import petSilhouetteAsset from'../assets/pets/draviel.png.asset.json';

const art:Record<string,string>={fc:'/assets/game/coins/forge-coin.png',myth:'/assets/game/coins/myth-token.png',pet_food:'/assets/game/ui/season-pet-food.png',fragments:'/assets/game/ui/season-fragments.png',pvp_ticket:'/assets/game/ui/season-pvp-ticket.png',skin:'/assets/game/ui/season-skin.png',pet_egg:'/assets/game/pet-eggs/rare-egg.webp','rare-egg':'/assets/game/pet-eggs/rare-egg.webp','epic-egg':'/assets/game/pet-eggs/epic-egg.webp','ancestral-egg':'/assets/game/pet-eggs/ancestral-egg.webp','mythic-egg':'/assets/game/pet-eggs/mythic-egg.webp','dragon-egg':'/assets/game/pet-eggs/dragon-egg.webp',hero_chest:'/assets/game/chests/epic-chest.png',chest:'/assets/game/chests/rare-chest.png',rare_chest:'/assets/game/chests/rare-chest.png',epic_chest:'/assets/game/chests/epic-chest.png',legendary_chest:'/assets/game/chests/legendary-chest.png','legend-chest':'/assets/game/chests/legend-chest.png',common_chest:'/assets/game/chests/common-chest.png',exclusive_chest:'/assets/game/chests/legend-chest.png',equipment:'/assets/game/equipment/axe-legendary.png',nft_equipment:'/assets/game/equipment/axe-legendary.png',nft_pet:'/assets/game/pet-eggs/mythic-egg.webp',pet_random:'/assets/game/pet-eggs/ancestral-egg.webp','season-1-aldren':'/assets/game/heroes/season-1-aldren.png','season-1-mythic-egg':mythicEggAsset.url};
// Equipment/NFT gear always shows the real rarity artwork instead of a generic icon.
const equipArt:Record<string,string>={weapon:'/assets/game/equipment/axe-legendary.png',armor:'/assets/game/equipment/armor-legendary.png',ring:'/assets/game/equipment/ring-legendary.png',common:'/assets/game/equipment/axe-common.png',uncommon:'/assets/game/equipment/axe-uncommon.png',rare:'/assets/game/equipment/axe-rare.png',epic:'/assets/game/equipment/axe-epic.png',legendary:'/assets/game/equipment/axe-legendary.png'};
// Mystery rewards never reveal the art: the silhouette below is what the player sees before claiming.
const silhouette:Record<string,string>={'season-1-aldren':'/assets/game/heroes/season-1-aldren.png','season-1-mythic-egg':petSilhouetteAsset.url,hero_random:'/assets/game/heroes/legendary-dragon-knight.png'};
const rewardImage=(r:PassReward)=>r.imageUrl||(r.code?equipArt[r.code]&&(r.type==='equipment'||r.type==='nft_equipment')?equipArt[r.code]:art[r.code]:undefined)||art[r.type]||art.fragments;


export function SeasonPassPage({telegramInitData,onClose,onMissions}:{telegramInitData:string;onClose:()=>void;onMissions:()=>void}){
 const t=useT(),{tError}=useLanguage();
 const[tonUI]=useTonConnectUI(),wallet=useTonWallet(),q=useQueryClient(),{data,isLoading,isFetching,error,refetch}=useSeasonPass(telegramInitData,true);
 const stalled=isLoading&&!isFetching;
 React.useEffect(()=>{console.log('[PASS] start')},[]);
 React.useEffect(()=>{if(data)console.log('[PASS] active season + player progress loaded',{level:data.player?.level,rewards:data.rewards?.length??0})},[data]);
 React.useEffect(()=>{if(error)console.error('[SCREEN ERROR]',{screen:'season-pass',step:'dashboard',message:error instanceof Error?error.message:String(error)})},[error]);
 const invalidateAll=async()=>{await Promise.all([['season-pass'],['season-pass-rewards'],['season-pass-profile'],['wallet-summary'],['wallet-history'],['notifications'],['missions'],['community-pool'],['pet-dashboard'],['player-inventory'],['player-heroes'],['reward-history'],['game']].map(queryKey=>q.invalidateQueries({queryKey})))};
 // Ownership only ever comes from the backend: pay → server confirms on-chain → pass activated.
 // One-tap: the internal TON balance pays the FULL price when it covers it, otherwise TonConnect
 // is opened for the FULL amount. The payment is never split between the two.
 const purchase=useMutation({mutationFn:async(tier:PassTier)=>{
  try{await buySeasonPassWithInternalTon(telegramInitData,tier as'adventurer'|'legendary');return{internal:true as const}}
  catch(e){const reason=e instanceof Error?e.message:String(e);if(!/INSUFFICIENT_TON_BALANCE/i.test(reason))throw e}
  if(!wallet){await tonUI.openModal();throw Error(t('pass.connectWallet'))}
  await purchaseBattlePass({telegramInitData,tier,sendTransaction:tx=>tonUI.sendTransaction(tx)});toast.message(t('pass.paymentSent'));
  return await waitForPassActivation(telegramInitData)},
  onSuccess:async result=>{await invalidateAll();if((result as{internal?:boolean}).internal){toast.success(t('pass.activated',{tier:''}));return}
   const activated=activatedPass(result as never);if(activated)toast.success(t('pass.activated',{tier:passTierLabel(activated.tier)}));else toast.message(t('pass.paymentPendingActivation'))},
  onError:e=>toast.error(e instanceof Error?tError(e):t('pass.buyFailed'))});

 // A payment made with the app closed is finished here, exactly once.
 const recovered=React.useRef(false);
 React.useEffect(()=>{if(recovered.current)return;recovered.current=true;reconcilePendingPassPurchases(telegramInitData).then(async verification=>{if(!activatedPass(verification))return;await invalidateAll();toast.success(t('pass.activated',{tier:passTierLabel(activatedPass(verification)?.tier)}))}).catch(error=>console.error('[MYTHREON PASS RECOVERY]',error))},[telegramInitData]);
 const claim=useMutation({mutationFn:(rewardId:string)=>seasonPassRequest(telegramInitData,'claim',{rewardId}),onSuccess:async dashboard=>{q.setQueryData(['season-pass',telegramInitData],dashboard);await invalidateAll();toast.success(t('pass.rewardClaimed'))},onError:e=>toast.error(e instanceof Error?tError(e):t('pass.claimFailed'))});
 const{data:myth}=useMythUtility(telegramInitData);
 // Alternative pass payment: burns MYTH from the available balance (TON flow untouched).
 const purchaseMyth=useMutation({mutationFn:(tier:PassTier)=>buySeasonPassWithMyth(telegramInitData,tier as 'adventurer'|'legendary'),onSuccess:async()=>{await invalidateAll();await q.invalidateQueries({queryKey:['myth-utility']});toast.success(t('pass.activated',{tier:''}))},onError:e=>toast.error(e instanceof Error?tError(e):t('pass.buyFailed'))});
 const[buyOpen,setBuyOpen]=React.useState(false);
 // Level purchase: the client only sends how many levels; price/limits/new level come back from the server.
 const buyLevels=useMutation({mutationFn:({levels,currency}:{levels:number;currency:'FC'|'MYTH'})=>buySeasonPassLevels(telegramInitData,levels,currency) as Promise<SeasonPassDashboard>,onSuccess:async dashboard=>{q.setQueryData(['season-pass',telegramInitData],dashboard);await invalidateAll();await q.invalidateQueries({queryKey:['myth-utility']});const p=dashboard.purchase;setBuyOpen(false);if(p&&p.levelsBought>1)toast.success(t('pass.levelsBoughtToast',{levels:p.levelsBought}));else if(p)toast.success(t('pass.levelUpToast',{from:p.levelBefore,to:p.levelAfter}));},onError:e=>toast.error(e instanceof Error?tError(e):t('pass.buyLevelFailed'))});
 /**
  * Locked reward unlock (fixed TON price). The backend decides the method:
  * internal TON balance pays instantly, otherwise it returns a TonConnect intent and the
  * server reconciles the on-chain payment before the exclusive chest is delivered.
  */
 const unlockReward=useMutation({mutationFn:async(reward:PassReward)=>{
  const outcome=await buyLockedPassReward(telegramInitData,reward.id,wallet?.account?.address??null);
  if(outcome.status==='completed')return outcome;
  if(!wallet){await tonUI.openModal();throw Error(t('pass.connectWallet'))}
  await sendTonPayment({paymentAddress:String(outcome.paymentAddress),paymentComment:String(outcome.paymentComment),amountNano:String(outcome.amountNano)},(tx:TonTransactionRequest)=>tonUI.sendTransaction(tx));
  toast.message(t('pass.paymentSent'));
  for(let attempt=1;attempt<=8;attempt+=1){
   await new Promise(resolve=>window.setTimeout(resolve,attempt===1?6000:7000));
   try{const verification=await verifyLockedPassRewards(telegramInitData);if(verification.completed.length)return{...outcome,status:'completed' as const};}catch(error){console.error('[MYTHREON PASS CHEST]',error)}
  }
  return{...outcome,status:'pending' as const};
 },onSuccess:async outcome=>{await invalidateAll();if(outcome.status==='completed')toast.success(t('pass.unlockSuccess'));else toast.message(t('pass.paymentPendingActivation'))},onError:e=>toast.error(e instanceof Error?tError(e):t('pass.unlockFailed'))});

 if(isLoading&&!stalled)return<Shell onClose={onClose}><div className="space-y-3 pt-12">{[1,2,3].map(x=><div key={x} className="h-24 animate-pulse rounded-2xl bg-white/5"/>)}<p className="text-center text-sm text-amber-200">{t('pass.preparingSeason')}</p></div></Shell>;
 if(error||stalled||!data)return<Shell onClose={onClose}><div className="py-24 text-center"><p>{t('pass.loadError')}</p><button onClick={()=>void refetch()} className="mt-4 rounded-xl border border-amber-300/30 px-5 py-3">{t('pass.retryButton')}</button></div></Shell>;
const remaining=Math.max(0,new Date(data.season.endsAt).getTime()-Date.now()),days=Math.floor(remaining/86400000),hours=Math.floor(remaining%86400000/3600000),currentXp=data.player.xpIntoLevel??data.player.xp%data.season.xpPerLevel,maxed=data.player.maxed??false,barPercent=maxed?100:Math.round(currentXp/data.season.xpPerLevel*100);
 const levelCfg=data.levelPurchase;
 const multipliers=data.xpMultipliers??{},xpMultiplier=data.player.xpMultiplier??1,xpBonus=data.player.xpBonusPercent??Math.round((xpMultiplier-1)*100),adventurerBonus=Math.round(((multipliers.adventurer??1.2)-1)*100),legendaryBonus=Math.round(((multipliers.legendary??1.4)-1)*100);
 return<Shell onClose={onClose}>
  <section className="rounded-3xl border border-amber-300/25 bg-gradient-to-br from-[#17223a] to-black p-4"><div className="flex items-center gap-3"><img src={mainScreenArt.seasonPass} className="h-20 w-20 object-contain"/><div><p className="text-[10px] uppercase tracking-[.25em] text-amber-300">{data.season.name}</p><h2 className="text-2xl font-black">{t('pass.title')}</h2><p className="text-xs text-slate-400">{t('pass.timeRemaining',{days,hours})}</p></div></div><div className="mt-3 flex justify-between text-xs"><b>{t('pass.level',{level:data.player.level})}{maxed?` · ${t('pass.maxLevel')}`:''}</b><span>{maxed?t('pass.max'):`${currentXp}/${data.season.xpPerLevel} XP`}</span></div><div className="mt-1 h-3 overflow-hidden rounded-full bg-black/60"><div className="h-full bg-gradient-to-r from-amber-500 to-yellow-200 transition-all" style={{width:`${barPercent}%`}}/></div>
   <div className="mt-2 flex flex-wrap items-center gap-2"><span className={`rounded-full border px-2 py-1 text-[9px] font-black uppercase tracking-[.12em] ${xpBonus>0?'border-amber-300/60 bg-amber-400/15 text-amber-200':'border-white/15 bg-white/5 text-slate-300'}`}>{xpBonus>0?t('pass.xpBoost',{percent:xpBonus}):t('pass.xpRate',{rate:xpMultiplier.toFixed(1)})}</span>{data.xpToday?<span className="rounded-full border border-white/10 bg-black/40 px-2 py-1 text-[9px] text-slate-300">{t('pass.xpToday',{xp:data.xpToday})}</span>:null}</div>
   <div className="mt-3 flex items-center justify-between gap-2"><button onClick={onMissions} className="rounded-xl border border-amber-300/30 px-4 py-2 text-xs font-bold">{t('pass.missions')}</button>{levelCfg?.enabled&&!maxed?<button onClick={()=>setBuyOpen(true)} className="rounded-xl border border-amber-300/60 bg-gradient-to-r from-amber-500/25 to-yellow-300/15 px-4 py-2 text-xs font-black text-amber-100 shadow-[0_0_14px_rgba(251,191,36,.25)]">{t('pass.buyLevel')}</button>:null}</div></section>
   {buyOpen&&levelCfg?<BuyLevelSheet cfg={levelCfg} level={data.player.level} levels={data.season.levels} xpIntoLevel={currentXp} xpPerLevel={data.season.xpPerLevel} pending={buyLevels.isPending} onBuy={(n:number,currency:'FC'|'MYTH'='FC')=>buyLevels.mutate({levels:n,currency})} myth={myth} onClose={()=>setBuyOpen(false)}/>:null}
  {/* Entitlement display: adventurer alone stays adventurer; legendary includes adventurer. */}
  <div className="mt-3 grid grid-cols-2 gap-2"><Pass tier="adventurer" owned={data.player.adventurerOwned&&!data.player.legendaryOwned} included={data.player.legendaryOwned} price={data.season.adventurerPriceTon} bonus={adventurerBonus} pending={purchase.isPending||purchaseMyth.isPending} onBuy={()=>purchase.mutate('adventurer')} myth={myth} onBuyMyth={()=>purchaseMyth.mutate('adventurer')}/><Pass tier="legendary" owned={data.player.legendaryOwned} price={data.player.adventurerOwned?data.season.upgradePriceTon:data.season.legendaryPriceTon} bonus={legendaryBonus} upgrade={data.player.adventurerOwned&&!data.player.legendaryOwned} pending={purchase.isPending||purchaseMyth.isPending} onBuy={()=>purchase.mutate('legendary')} myth={myth} onBuyMyth={()=>purchaseMyth.mutate('legendary')}/></div>
  <p className="mt-3 rounded-xl border border-amber-300/15 bg-black/40 p-3 text-center text-[10px] text-amber-100">O Passe Lendário também libera todas as recompensas do Passe Aventureiro.</p>{data.player.tier==='none'?<p className="mt-2 text-center text-xs text-slate-300">Compre um passe para liberar as recompensas da temporada.</p>:null}
  <section className="mt-4 overflow-hidden rounded-3xl border border-amber-300/30 bg-gradient-to-b from-[#0b1220] to-black shadow-[0_0_30px_rgba(0,0,0,.6)]">
   <div className="sticky top-0 z-20 grid grid-cols-[68px_1fr_1fr] items-end gap-1 border-b border-amber-300/20 bg-[#080d16]/95 px-2 py-3 backdrop-blur">
    <div className="text-center"><b className="block text-[11px] font-black uppercase tracking-[.14em] text-amber-300">{t('pass.levelHeader')}</b><span className="mx-auto mt-1 block h-px w-8 bg-amber-300/50"/></div>
    <div className="border-l border-amber-300/15 text-center"><b className="block text-[10px] font-black uppercase leading-tight tracking-[.1em] text-emerald-300">{t('pass.adventurerPassLine1')}<br/>{t('pass.adventurerPassLine2')}</b><span className="mx-auto mt-1 block h-px w-10 bg-emerald-300/50"/></div>
    <div className="border-l border-amber-300/15 text-center"><b className="block text-[10px] font-black uppercase leading-tight tracking-[.1em] text-violet-300">{t('pass.legendaryPassLine1')}<br/>{t('pass.legendaryPassLine2')}</b><span className="mx-auto mt-1 block h-px w-10 bg-violet-300/50"/></div>
   </div>
   <div className="divide-y divide-white/5">
     {/* Track length always follows the server (V2 pass = 50 levels), never a hardcoded number. */}
     {Array.from({length:Math.max(data.season.levels||0,...data.rewards.map(r=>r.level))},(_,i)=>{const level=i+1;const reached=data.player.level>=level;return<div key={level} className={`grid grid-cols-[68px_1fr_1fr] items-stretch gap-1 px-2 py-2 ${reached?'bg-amber-400/[.04]':''}`}>
     <div className="grid place-items-center text-center"><span className={`grid h-9 w-9 place-items-center rounded-full border text-[11px] font-black ${reached?'border-amber-300/70 bg-amber-400/15 text-amber-200':'border-white/10 bg-black/40 text-slate-500'}`}>{level}</span></div>
     {(['adventurer','legendary'] as PassTier[]).map(tier=><Reward key={tier} reward={data.rewards.find(x=>x.level===level&&x.tier===tier)} pending={claim.isPending} onClaim={id=>claim.mutate(id)} onUnlock={r=>unlockReward.mutate(r)} unlocking={unlockReward.isPending}/>)}
    </div>})}
   </div>
  </section>
 </Shell>
}

function Reward({reward:r,pending,onClaim,onUnlock,unlocking}:{reward?:PassReward;pending:boolean;onClaim:(id:string)=>void;onUnlock:(r:PassReward)=>void;unlocking?:boolean}){
 const t=useT();
 const code=r?.code??'',mysteryArt=silhouette[code]??(r?.type==='hero_random'?silhouette.hero_random:undefined);
 const equipment=r?.type==='equipment',rare=equipment,mystery=Boolean(mysteryArt),premium=Boolean(code&&silhouette[code]);
 const Icon=equipment?(equipIcon[code]??Sword):r?.type==='pvp_ticket'?Ticket:null;
 const frame=premium?'border-amber-300/70 bg-gradient-to-b from-violet-950/80 via-black/60 to-amber-950/30 shadow-[0_0_20px_rgba(251,191,36,.28)]'
  :mystery?'border-violet-300/60 bg-gradient-to-b from-violet-950/70 to-black/70 shadow-[0_0_16px_rgba(167,139,250,.25)]'
  :rare?'border-sky-300/55 bg-gradient-to-b from-sky-950/60 to-black/60 shadow-[0_0_14px_rgba(96,165,250,.22)]'
  :r?.claimed?'border-emerald-400/35 bg-emerald-500/10':r?.unlocked?'border-amber-300/35 bg-amber-500/10':'border-white/5 bg-white/[.02] text-slate-600';
 const versionLocked=Boolean(r?.versionLocked);
 // Locked rewards can be bought for the fixed TON price the backend publishes on the reward itself.
 const buyable=Boolean(versionLocked&&r?.purchasable&&!r?.claimed&&Number(r?.priceTon??0)>0);
 return<button disabled={buyable?Boolean(unlocking):(!r?.unlocked||r.claimed||pending||versionLocked)} onClick={()=>{if(!r)return;if(buyable)onUnlock(r);else if(!versionLocked)onClaim(r.id)}} className={`relative flex min-h-[76px] flex-col items-center justify-center gap-1 overflow-hidden rounded-xl border p-2 text-center text-[9px] ${frame}`}>
  {premium||r?.type==='exclusive_chest'?<span className="absolute left-1 top-1 rounded-full border border-amber-200/40 bg-black/70 px-1.5 py-0.5 text-[5px] font-black text-amber-200">{t('pass.exclusive')}</span>:null}
  {mystery&&!premium?<span className="absolute left-1 top-1 rounded-full border border-violet-200/40 bg-black/70 px-1.5 py-0.5 text-[5px] font-black text-violet-200">?</span>:null}
  {r?.claimed?<Check className="h-6 w-6 text-emerald-300"/>:r?<>
   {mystery
    ?<span className="relative grid h-11 w-11 place-items-center"><span className="absolute inset-0 rounded-full bg-[radial-gradient(circle,rgba(251,191,36,.28),transparent_70%)] blur-[2px]"/><img src={mysteryArt} alt={r.title} className={`relative h-10 w-10 object-contain [filter:brightness(0)_saturate(0)] drop-shadow-[0_0_7px_rgba(251,191,36,.55)] ${r.unlocked?'':'opacity-40'}`}/></span>
    :Icon
     ?<span className="relative grid h-11 w-11 place-items-center"><span className="absolute inset-0 rounded-full bg-[radial-gradient(circle,rgba(96,165,250,.25),transparent_70%)] blur-[2px]"/><Icon className={`relative h-8 w-8 ${equipment?'text-black drop-shadow-[0_0_7px_rgba(125,211,252,.7)]':'text-amber-200'} ${r.unlocked?'':'opacity-40'}`} strokeWidth={2.5}/></span>
     :<img src={art[code]??art[r.type]??art.fragments} alt={r.title} className={`h-10 w-10 object-contain drop-shadow-[0_0_8px_rgba(251,191,36,.35)] ${r.unlocked?'':'grayscale opacity-35'}`}/>}
   {!r.unlocked?<Lock className="absolute right-1 top-1 h-3 w-3 text-slate-500"/>:null}
  </>:null}
  <span className={`block leading-tight ${rare?'font-black uppercase tracking-[.06em] text-sky-200':mystery?'font-black uppercase tracking-[.06em] text-amber-200':''}`}>{r?.title??'—'}</span>
  {r&&!r.unlocked&&!versionLocked?<span className="block text-[7px] text-slate-500">{t('pass.buyPassPrompt')}</span>:null}
  {versionLocked?<span className="absolute inset-0 z-10 flex flex-col items-center justify-center gap-1 bg-black/75 px-1 text-center">
   <span className="rounded-md border border-amber-300/50 bg-black/80 px-1 py-0.5 text-[6px] font-black leading-tight text-amber-300">{t('pass.newPassRequired')}</span>
   {buyable?<span className="rounded-md border border-cyan-300/60 bg-cyan-400/15 px-1.5 py-0.5 text-[8px] font-black leading-tight text-cyan-100">{unlocking?'…':`${formatTon(Number(r?.priceTon??0))} TON`}</span>:null}
   {buyable?<span className="text-[6px] font-black uppercase tracking-[.1em] text-cyan-200/80">{t('pass.unlockTap')}</span>:null}
  </span>:null}
 </button>}


function Shell({children,onClose}:{children:React.ReactNode;onClose:()=>void}){const t=useT();return<div className="fullscreen-page text-white"><div className="forge-safe-page mx-auto min-h-full w-full max-w-[480px] p-3"><header className="flex items-center justify-between"><button onClick={onClose} className="grid h-10 w-10 place-items-center rounded-xl border border-amber-300/25 bg-black/50"><ArrowLeft/></button><div className="text-center"><p className="text-[9px] tracking-[.28em] text-amber-300">MYTHREON</p><b>{t('pass.title')}</b></div><ScrollText className="text-amber-300"/></header>{children}</div></div>}
function Pass({tier,owned,included=false,upgrade=false,price,bonus=0,pending,onBuy,myth,onBuyMyth}:{tier:'adventurer'|'legendary';owned:boolean;included?:boolean;upgrade?:boolean;price:number;bonus?:number;pending:boolean;onBuy:()=>void;myth?:MythUtilityState|null;onBuyMyth?:()=>void}){const t=useT();const held=owned||included;return<div className={`rounded-2xl border p-3 text-center ${tier==='adventurer'?'border-emerald-400/30 bg-emerald-950/20':'border-violet-400/35 bg-violet-950/25'}`}><Star className={`mx-auto ${tier==='adventurer'?'text-emerald-300':'text-amber-300'}`}/><b className="mt-1 block text-xs">{tier==='adventurer'?`${t('pass.adventurerPassLine1')} ${t('pass.adventurerPassLine2')}`:`${t('pass.legendaryPassLine1')} ${t('pass.legendaryPassLine2')}`}</b><p className="text-lg font-black">{held?<span className="text-emerald-300">{included?t('pass.includedCheck'):t('pass.activeCheck')}</span>:`${formatTon(price)} TON`}</p>{bonus>0?<p className="mt-1 rounded-lg border border-amber-300/30 bg-amber-400/10 px-1 py-0.5 text-[8px] font-black text-amber-200">{t('pass.benefitXp',{percent:bonus})}</p>:null}<button disabled={held||pending} onClick={onBuy} className="mt-2 w-full rounded-xl bg-amber-400 py-2 text-[9px] font-black text-black disabled:bg-emerald-500">{held?t('pass.acquired'):upgrade?t('pass.buyLegendary'):t('pass.buyPass')}</button>{!held&&onBuyMyth?<div className="mt-2"><MythPayButton state={myth} feature="PASS_PURCHASE" ton={price} disabled={pending} onPay={()=>onBuyMyth()}/></div>:null}</div>}

/** Compact bottom sheet: every number shown here is produced by the backend. */
function BuyLevelSheet({cfg,level,levels,xpIntoLevel,xpPerLevel,pending,onBuy,onClose,myth}:{cfg:PassLevelPurchaseConfig;level:number;levels:number;xpIntoLevel:number;xpPerLevel:number;pending:boolean;onBuy:(levels:number,currency?:'FC'|'MYTH')=>void;onClose:()=>void;myth?:MythUtilityState|null}){
 const t=useT();const packs=Object.keys(cfg.prices).map(Number).filter(n=>n>0).sort((a,b)=>a-b);
 const[sel,setSel]=React.useState(()=>packs.find(n=>n<=cfg.maxAvailable)??packs[0]??1);
 const price=Number(cfg.prices[String(sel)]??0),blocked=cfg.remainingToday<=0,tooMany=sel>cfg.maxAvailable,poor=price>cfg.balanceFc;
 return<div className="fixed inset-0 z-50 flex items-end bg-black/70 backdrop-blur-sm" onClick={onClose}>
  <div className="forge-safe-page w-full rounded-t-3xl border-t border-amber-300/40 bg-gradient-to-b from-[#141d31] to-black p-4" onClick={e=>e.stopPropagation()}>
   <b className="block text-center text-sm font-black uppercase tracking-[.14em] text-amber-200">{t('pass.buyLevelTitle')}</b>
   <div className="mt-3 grid grid-cols-3 gap-2 text-center text-[10px] text-slate-300">
    <div className="rounded-xl border border-white/10 bg-black/40 p-2"><span className="block uppercase tracking-[.1em]">{t('pass.currentLevel')}</span><b className="text-base text-amber-200">{level}</b></div>
    <div className="rounded-xl border border-white/10 bg-black/40 p-2"><span className="block uppercase tracking-[.1em]">{t('pass.currentXp')}</span><b className="text-base text-amber-200">{xpIntoLevel}/{xpPerLevel}</b></div>
    <div className="rounded-xl border border-white/10 bg-black/40 p-2"><span className="block uppercase tracking-[.1em]">{t('pass.nextLevel')}</span><b className="text-base text-amber-200">{Math.min(levels,level+sel)}</b></div>
   </div>
   <div className="mt-3 grid grid-cols-3 gap-2">{packs.map(n=>{const p=Number(cfg.prices[String(n)]??0),off=n>cfg.maxAvailable;return<button key={n} disabled={off||pending} onClick={()=>setSel(n)} className={`rounded-xl border p-2 text-center ${sel===n?'border-amber-300/70 bg-amber-400/15':'border-white/10 bg-black/40'} ${off?'opacity-40':''}`}><b className="block text-sm text-amber-200">+{n}</b><span className="text-[9px] text-slate-300">{p.toLocaleString()} FC</span></button>})}</div>
   <div className="mt-3 flex items-center justify-between text-[10px] text-slate-300"><span>{t('pass.buyLevelsToday')}: <b className="text-amber-200">{cfg.boughtToday}/{cfg.dailyLimit}</b></span><span>{t('pass.cost')}: <b className="text-amber-200">{price.toLocaleString()} FC</b></span></div>
   {cfg.maxAvailable<Math.max(...packs)?<p className="mt-2 text-center text-[10px] text-amber-200/80">{t('pass.maxAvailable',{levels:cfg.maxAvailable})}</p>:null}
   <button disabled={pending||blocked||tooMany||poor} onClick={()=>onBuy(sel)} className="mt-3 w-full rounded-xl bg-gradient-to-r from-amber-400 to-yellow-300 py-3 text-xs font-black text-black disabled:opacity-50">{blocked?t('pass.dailyLimitReached'):t('pass.buyLevelsAction',{levels:sel})}</button>
   {!blocked&&!tooMany&&price>0?<div className="mt-2"><MythPayButton state={myth} feature="PASS_LEVELS" fc={price} disabled={pending} onPay={()=>onBuy(sel,'MYTH')}/><MythBalanceHint state={myth}/></div>:null}
   <p className="mt-2 text-center text-[9px] text-slate-400">{t('pass.levelPurchaseNote')}</p>
   <button onClick={onClose} className="mt-2 w-full rounded-xl border border-white/10 py-2 text-[10px] font-bold text-slate-300">{t('pass.close')}</button>
  </div>
 </div>
}
