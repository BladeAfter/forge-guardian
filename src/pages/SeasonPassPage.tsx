import React from'react';
import{useTonConnectUI,useTonWallet}from'@tonconnect/ui-react';
import{useMutation,useQueryClient}from'@tanstack/react-query';
import{ArrowLeft}from'lucide-react';
import {SeasonVoyageView} from '../components/SeasonVoyageView';
import {OceanControl} from '../components/OceanControl';
import{toast}from'sonner';
import{seasonPassRequest,buySeasonPassLevels,buySeasonPassWithInternalTon,buyLockedPassReward,verifyLockedPassRewards}from'../services';
import{useMythUtility}from'../hooks';
import{MythPayButton,MythBalanceHint}from'../components/MythPayButton';
import type{MythUtilityState}from'../mythUtility';
import{sendTonPayment,type TonTransactionRequest}from'../tonPayment';

import{purchaseBattlePass,waitForPassActivation,activatedPass,passTierLabel,reconcilePendingPassPurchases}from'../passPurchase';
import{useT,useLanguage}from'../LanguageContext';
import{useSeasonPass}from'../hooks';
import{type PassReward,type PassTier,type PassLevelPurchaseConfig,type SeasonPassDashboard}from'../seasonPass';

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
 React.useEffect(()=>{if(recovered.current)return;recovered.current=true;reconcilePendingPassPurchases(telegramInitData).then(async verification=>{if(!activatedPass(verification))return;await invalidateAll();toast.success(t('pass.activated',{tier:passTierLabel(activatedPass(verification)?.tier)}))}).catch(error=>console.error('[Mythic Seas PASS RECOVERY]',error))},[telegramInitData]);
 const claim=useMutation({mutationFn:(rewardId:string)=>seasonPassRequest(telegramInitData,'claim',{rewardId}),onSuccess:async dashboard=>{q.setQueryData(['season-pass',telegramInitData],dashboard);await invalidateAll();toast.success(t('pass.rewardClaimed'))},onError:e=>toast.error(e instanceof Error?tError(e):t('pass.claimFailed'))});
 const{data:myth}=useMythUtility(telegramInitData);
 // Alternative pass payment: burns MYTH from the available balance (TON flow untouched).
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
   try{const verification=await verifyLockedPassRewards(telegramInitData);if(verification.completed.length)return{...outcome,status:'completed' as const};}catch(error){console.error('[Mythic Seas PASS CHEST]',error)}
  }
  return{...outcome,status:'pending' as const};
 },onSuccess:async outcome=>{await invalidateAll();if(outcome.status==='completed')toast.success(t('pass.unlockSuccess'));else toast.message(t('pass.paymentPendingActivation'))},onError:e=>toast.error(e instanceof Error?tError(e):t('pass.unlockFailed'))});

 if(isLoading&&!stalled)return<Shell onClose={onClose}><div className="space-y-3 pt-12">{[1,2,3].map(x=><div key={x} className="h-24 animate-pulse rounded-2xl bg-white/5"/>)}<p className="text-center text-sm text-amber-200">{t('pass.preparingSeason')}</p></div></Shell>;
 if(error||stalled||!data)return<Shell onClose={onClose}><div className="py-24 text-center"><p>{t('pass.loadError')}</p><button onClick={()=>void refetch()} className="mt-4 rounded-xl border border-amber-300/30 px-5 py-3">{t('pass.retryButton')}</button></div></Shell>;
return <>
  <SeasonVoyageView data={data} onClose={onClose} onMissions={onMissions} onBuyLevel={()=>setBuyOpen(true)} onBuy={tier=>purchase.mutate(tier)} buying={purchase.isPending} onClaim={id=>claim.mutate(id)} claiming={claim.isPending} onUnlock={r=>unlockReward.mutate(r)} unlocking={unlockReward.isPending}/>
  {buyOpen&&data.levelPurchase?<BuyLevelSheet cfg={data.levelPurchase} level={data.player.level} levels={data.season.levels} xpIntoLevel={data.player.xpIntoLevel??data.player.xp%data.season.xpPerLevel} xpPerLevel={data.season.xpPerLevel} pending={buyLevels.isPending} onBuy={(n,currency='FC')=>buyLevels.mutate({levels:n,currency})} myth={myth} onClose={()=>setBuyOpen(false)}/>:null}
 </>;
}
function Shell({children,onClose}:{children:React.ReactNode;onClose:()=>void}){return <div className="fullscreen-page seas-season"><header className="season-topbar"><OceanControl onClick={onClose} aria-label="Voltar ao porto"><ArrowLeft/></OceanControl><div><span>MYTHIC SEAS</span><b>PASSE DE TEMPORADA</b></div></header><div className="season-inner">{children}</div></div>}

/** Compact bottom sheet: every number shown here is produced by the backend. */
function BuyLevelSheet({cfg,level,levels,xpIntoLevel,xpPerLevel,pending,onBuy,onClose,myth}:{cfg:PassLevelPurchaseConfig;level:number;levels:number;xpIntoLevel:number;xpPerLevel:number;pending:boolean;onBuy:(levels:number,currency?:'FC'|'MYTH')=>void;onClose:()=>void;myth?:MythUtilityState|null}){
 const t=useT();const packs=Object.keys(cfg.prices).map(Number).filter(n=>n>0).sort((a,b)=>a-b);
 const[sel,setSel]=React.useState(()=>packs.find(n=>n<=cfg.maxAvailable)??packs[0]??1);
 const price=Number(cfg.prices[String(sel)]??0),blocked=cfg.remainingToday<=0,tooMany=sel>cfg.maxAvailable,poor=price>cfg.balanceFc;
 return<div className="season-level-sheet fixed inset-0 flex items-end bg-black/70 backdrop-blur-sm" onClick={onClose}>
  <div className="forge-safe-page w-full rounded-t-3xl border-t border-amber-300/40 bg-gradient-to-b from-[#141d31] to-black p-4" onClick={e=>e.stopPropagation()}>
   <b className="block text-center text-sm font-black uppercase tracking-[.14em] text-amber-200">{t('pass.buyLevelTitle')}</b>
   <div className="mt-3 grid grid-cols-3 gap-2 text-center text-[10px] text-slate-300">
    <div className="rounded-xl border border-white/10 bg-black/40 p-2"><span className="block uppercase tracking-[.1em]">{t('pass.currentLevel')}</span><b className="text-base text-amber-200">{level}</b></div>
    <div className="rounded-xl border border-white/10 bg-black/40 p-2"><span className="block uppercase tracking-[.1em]">{t('pass.currentXp')}</span><b className="text-base text-amber-200">{xpIntoLevel}/{xpPerLevel}</b></div>
    <div className="rounded-xl border border-white/10 bg-black/40 p-2"><span className="block uppercase tracking-[.1em]">{t('pass.nextLevel')}</span><b className="text-base text-amber-200">{Math.min(levels,level+sel)}</b></div>
   </div>
   <div className="mt-3 grid grid-cols-3 gap-2">{packs.map(n=>{const p=Number(cfg.prices[String(n)]??0),off=n>cfg.maxAvailable;return<button key={n} disabled={off||pending} onClick={()=>setSel(n)} className={`rounded-xl border p-2 text-center ${sel===n?'border-amber-300/70 bg-amber-400/15':'border-white/10 bg-black/40'} ${off?'opacity-40':''}`}><b className="block text-sm text-amber-200">+{n}</b><span className="text-[9px] text-slate-300">{p.toLocaleString()} BERRIES</span></button>})}</div>
   <div className="mt-3 flex items-center justify-between text-[10px] text-slate-300"><span>{t('pass.buyLevelsToday')}: <b className="text-amber-200">{cfg.boughtToday}/{cfg.dailyLimit}</b></span><span>{t('pass.cost')}: <b className="text-amber-200">{price.toLocaleString()} BERRIES</b></span></div>
   {cfg.maxAvailable<Math.max(...packs)?<p className="mt-2 text-center text-[10px] text-amber-200/80">{t('pass.maxAvailable',{levels:cfg.maxAvailable})}</p>:null}
   <button disabled={pending||blocked||tooMany||poor} onClick={()=>onBuy(sel)} className="mt-3 w-full rounded-xl bg-gradient-to-r from-amber-400 to-yellow-300 py-3 text-xs font-black text-black disabled:opacity-50">{blocked?t('pass.dailyLimitReached'):t('pass.buyLevelsAction',{levels:sel})}</button>
   {!blocked&&!tooMany&&price>0?<div className="mt-2"><MythPayButton state={myth} feature="PASS_LEVELS" fc={price} disabled={pending} onPay={()=>onBuy(sel,'MYTH')}/><MythBalanceHint state={myth}/></div>:null}
   <p className="mt-2 text-center text-[9px] text-slate-400">{t('pass.levelPurchaseNote')}</p>
   <button onClick={onClose} className="mt-2 w-full rounded-xl border border-white/10 py-2 text-[10px] font-bold text-slate-300">{t('pass.close')}</button>
  </div>
 </div>
}
