import{useEffect,useState}from'react';
import{useMutation,useQuery,useQueryClient}from'@tanstack/react-query';
import{History,Plus,Search,Shield,Swords,Ticket,Trophy,Users,X}from'lucide-react';
import{toast}from'sonner';
import{usePetDashboard,usePvpDashboard}from'../hooks';
import{useT,useLanguage}from'../LanguageContext';
import{PetCompanion}from'../components/PetCompanion';
import{PvpBattleArena}from'../components/PvpBattleArena';
import{buyPvpTickets,pvpRequest,searchPvpOpponents,startPvpBattle}from'../services';
import type{PvpBattleResult,PvpHero,PvpOpponent,PvpTicketShop}from'../pvp';



type Team='attack'|'defense';type View='teams'|'history'|'ranking';
const color:Record<string,string>={common:'#94a3b8',uncommon:'#34d399',rare:'#60a5fa',epic:'#c084fc',legendary:'#fbbf24'};

export function PvpPage({telegramInitData,onClose}:{telegramInitData:string;onClose:()=>void}){
 const t=useT(),{tError}=useLanguage(),q=useQueryClient(),pets=usePetDashboard(telegramInitData,true),{data,isLoading,isFetching,error,refetch}=usePvpDashboard(telegramInitData,true),[view,setView]=useState<View>('teams'),[team,setTeam]=useState<Team>('attack'),[slot,setSlot]=useState<number|null>(null),[chosen,setChosen]=useState<PvpOpponent|null>(null),[arena,setArena]=useState<{battle:PvpBattleResult;opponent:PvpOpponent}|null>(null),[shop,setShop]=useState(false);
 useEffect(()=>{console.log('[PVP] start')},[]);
 useEffect(()=>{if(data)console.log('[PVP] profile + teams loaded',{attack:data.attackTeam.length,defense:data.defenseTeam.length,tickets:data.tickets})},[data]);
 useEffect(()=>{if(error)console.error('[SCREEN ERROR]',{screen:'pvp',step:'dashboard',message:error instanceof Error?error.message:String(error)})},[error]);
 // A pending query with nothing in flight (offline flag / paused) must offer a retry, never spin.
 const stalled=isLoading&&!isFetching;
 const opponents=useQuery({queryKey:['pvp-opponents',telegramInitData],queryFn:async()=>[]as PvpOpponent[],enabled:false,initialData:[]});
 const refresh=()=>Promise.all([q.invalidateQueries({queryKey:['pvp-dashboard',telegramInitData]}),q.invalidateQueries({queryKey:['player-heroes']}),q.invalidateQueries({queryKey:['community-pool']}),q.invalidateQueries({queryKey:['wallet-balance']}),q.invalidateQueries({queryKey:['game-state',telegramInitData]}),q.invalidateQueries({queryKey:['daily-quests']}),q.invalidateQueries({queryKey:['season-pass']})]);
 const search=useMutation({mutationFn:()=>searchPvpOpponents(telegramInitData),onSuccess:r=>{q.setQueryData(['pvp-opponents',telegramInitData],r.opponents);setChosen(null);if(!r.opponents.length)toast.error(t('pvp.noOpponentsFound'))},onError:e=>toast.error(tError(e))});
 const equip=useMutation({mutationFn:({heroId,targetSlot}:{heroId:string;targetSlot:number})=>pvpRequest(telegramInitData,{action:'equip',teamType:team,slot:targetSlot,heroId}),onSuccess:async d=>{q.setQueryData(['pvp-dashboard',telegramInitData],d);setSlot(null);await refresh();toast.success(t('pvp.heroEquipped'))},onError:e=>toast.error(tError(e))});
 const fight=useMutation({mutationFn:async(opponent:PvpOpponent)=>({battle:await startPvpBattle(telegramInitData,opponent.userId),opponent}),onSuccess:async r=>{setArena(r);setChosen(null);q.setQueryData(['pvp-opponents',telegramInitData],[]);await refresh()},onError:e=>toast.error(tError(e))});
 const buy=useMutation({mutationFn:(quantity:number)=>buyPvpTickets(telegramInitData,quantity,`${quantity}:${Date.now()}`),onSuccess:async(d,quantity)=>{q.setQueryData(['pvp-dashboard',telegramInitData],d);await refresh();toast.success(t('pvp.ticketsPurchased',{count:quantity}))},onError:e=>toast.error(tError(e))});

 if(arena)return<PvpBattleArena battle={arena.battle} attackTeam={data?.attackTeam??[]} defenseTeam={arena.opponent.defenseTeam} opponentName={arena.opponent.name} pet={pets.data?.activePet?{name:pets.data.activePet.name,image:pets.data.activePet.image}:null} onContinue={async()=>{setArena(null);await refresh()}}/>;
 if(isLoading)return<Shell onClose={onClose}><Center text={t('pvp.arenaLoading')}/></Shell>;
 if(error||!data)return<Shell onClose={onClose}><Center text={error?tError(error):t('pvp.genericError')}/></Shell>;
 const current=team==='attack'?data.attackTeam:data.defenseTeam;

 return <Shell onClose={onClose}>
  <section className="overflow-hidden rounded-[2rem] border border-amber-400/30 bg-gradient-to-b from-[#111b2d]/95 to-black/75 px-6 py-7 shadow-[0_18px_50px_rgba(0,0,0,.45)]">
   <div className="flex flex-col items-center justify-center text-center">
    <div className="grid h-[72px] w-[72px] place-items-center rounded-full border border-amber-300/35 bg-amber-500/10 shadow-[0_0_30px_rgba(251,191,36,.22)]"><Trophy className="h-16 w-16 text-amber-300 drop-shadow-[0_4px_12px_rgba(245,158,11,.45)]" strokeWidth={1.45}/></div>
    <h2 className="mt-4 text-[30px] font-black leading-none tracking-tight text-amber-50">{t('pvp.title')}</h2>
    <p className="mt-2 text-[13px] font-bold uppercase tracking-[.22em] text-amber-300">{t('pvp.subtitle')}</p>
    <p className="mt-2 text-[10px] font-semibold text-slate-400">{t('pvp.trophies',{count:data.trophies.toLocaleString()})}</p>
   </div>
   <div className="mt-7 grid grid-cols-3 divide-x divide-white/10 rounded-2xl border border-white/10 bg-black/35 py-4"><Stat icon={<Shield/>} label={t('pvp.league')} value={data.league}/><Stat icon={<Swords/>} label={t('pvp.power')} value={data.teamPower}/><Stat icon={<Ticket/>} label={t('pvp.ticketsLabel')} value={data.tickets} onBuy={()=>setShop(true)} buyAria={t('tickets.buyAria')}/></div>
   <div className="mt-6 grid grid-cols-3 gap-2"><Nav active={view==='teams'} onClick={()=>setView('teams')} icon={<Users/>} text={t('pvp.navTeams')}/><Nav active={view==='history'} onClick={()=>setView('history')} icon={<History/>} text={t('pvp.navHistory')}/><Nav active={view==='ranking'} onClick={()=>setView('ranking')} icon={<Trophy/>} text={t('pvp.navRanking')}/></div>
  </section>
  {view==='teams'&&<>
   <PetCompanion pet={pets.data?.activePet?{name:pets.data.activePet.name,image:pets.data.activePet.image,level:pets.data.activePet.level,rarity:pets.data.activePet.rarity}:null} buffKey={pets.data?.activePet?.primaryBuffKey} buffValue={pets.data?.activePet?.primaryBuffValue} label={t('pvp.companionLabel')} />
   <div className="mt-5 grid grid-cols-2 gap-3"><button onClick={()=>setTeam('attack')} className={teamButton(team==='attack')}>{t('pvp.teamAttack')}</button><button onClick={()=>setTeam('defense')} className={teamButton(team==='defense')}>{t('pvp.teamDefense')}</button></div>
   <section className="mt-4 rounded-2xl border border-white/10 bg-black/50 p-3"><div className="grid grid-cols-5 gap-1">{[1,2,3,4,5].map(n=><HeroSlot key={n} slot={n} hero={current.find(x=>Number(x.slot)===n)} onClick={()=>setSlot(n)}/>)}</div><p className="mt-2 text-[9px] text-slate-400">{t('pvp.teamSummary',{count:current.length,atk:current.reduce((s,h)=>s+h.finalAtk,0).toLocaleString(),hp:current.reduce((s,h)=>s+h.finalHp,0).toLocaleString()})}</p></section>
   <button type="button" disabled={search.isPending||data.attackTeam.length===0} onClick={()=>search.mutate()} className="mt-3 w-full rounded-2xl bg-gradient-to-b from-amber-300 to-orange-500 py-4 text-sm font-black text-black disabled:grayscale disabled:opacity-40"><Search className="mr-2 inline h-4 w-4"/>{search.isPending?t('pvp.searching'):t('pvp.searchPlayers')}</button>
   <div className="mt-3 space-y-3">{opponents.data.map(o=><Opponent key={o.userId} opponent={o} selected={chosen?.userId===o.userId} onSelect={()=>setChosen(o)} onFight={()=>fight.mutate(o)} pending={fight.isPending} tickets={data.tickets} onBuyTickets={()=>setShop(true)} t={t}/>)}</div>
  </>}
  {view==='history'&&<div className="mt-5 space-y-2">{data.history.length?data.history.map(h=><div key={h.id} className="flex items-center justify-between rounded-2xl border border-white/10 bg-black/55 p-3"><div><b>{h.opponentName}</b><p className="text-[9px] text-slate-400">{new Date(h.createdAt).toLocaleString()} · {h.turns} turnos</p></div><div className="text-right"><b className={h.result==='win'?'text-emerald-300':'text-rose-300'}>{h.result==='win'?t('pvp.win'):t('pvp.lose')}</b><p className="text-[9px]">{h.trophyChange>0?'+':''}{h.trophyChange} 🏆</p></div></div>):<Center text={t('pvp.noBattles')}/>}</div>}
  {view==='ranking'&&<div className="mt-5 space-y-2">{data.ranking.map(r=><div key={r.id} className="grid grid-cols-[35px_38px_1fr_auto] items-center gap-2 rounded-2xl border border-white/10 bg-black/55 p-2"><b className="text-center text-amber-300">#{r.position}</b><Avatar src={r.avatarUrl} name={r.name}/><div className="min-w-0"><b className="block truncate text-xs">{r.name}</b>{r.username?<p className="truncate text-[9px] text-amber-200/80">@{r.username}</p>:null}<p className="truncate text-[9px] text-slate-400">{r.league} · {t('pvp.wins',{count:r.wins})}</p></div><b className="text-xs">{r.trophies} 🏆</b></div>)}</div>}
  {slot!==null&&<HeroSelector slot={slot} heroes={data.ownedHeroes} current={current} pending={equip.isPending} onClose={()=>setSlot(null)} onEquip={heroId=>equip.mutate({heroId,targetSlot:slot})} t={t}/>}
  {shop&&<TicketSheet tickets={data.tickets} shop={data.ticketShop} pending={buy.isPending} onClose={()=>setShop(false)} onBuy={qty=>buy.mutate(qty)} t={t}/>}

  
 </Shell>
}

function HeroSlot({slot,hero,onClick}:{slot:number;hero?:PvpHero;onClick:()=>void}){return<button type="button" onClick={onClick} className="min-h-28 overflow-hidden rounded-xl border bg-black/70" style={{borderColor:hero?color[hero.rarity]:'#475569'}}>{hero?<><img src={hero.imageUrl} className="aspect-square w-full object-cover"/><p className="truncate px-1 text-[8px] font-bold">{hero.name}</p><p className="text-[7px]">ATK {hero.finalAtk}</p><p className="pb-1 text-[7px]">HP {hero.finalHp}</p></>:<span className="text-xl text-slate-500">＋</span>}</button>}
function HeroSelector({slot,heroes,current,pending,onClose,onEquip,t}:{slot:number;heroes:PvpHero[];current:PvpHero[];pending:boolean;onClose:()=>void;onEquip:(id:string)=>void;t:(k:string,v?:Record<string,string|number>)=>string}){return<div className="fixed inset-0 z-[90] flex items-end justify-center bg-black/80 p-3" onClick={onClose}><div className="max-h-[75dvh] w-full max-w-md overflow-y-auto rounded-t-3xl border border-amber-300/30 bg-[#080c14] p-4" onClick={e=>e.stopPropagation()}><div className="flex justify-between"><b>{t('pvp.selectHeroSlot',{slot})}</b><button onClick={onClose}><X/></button></div><div className="mt-3 grid grid-cols-3 gap-2">{heroes.map(h=>{const used=current.some(x=>x.heroId===h.heroId&&Number(x.slot)!==slot);return<button type="button" disabled={used||pending} onClick={()=>onEquip(h.heroId)} key={h.heroId} className="overflow-hidden rounded-xl border bg-black/70 disabled:opacity-35" style={{borderColor:color[h.rarity]}}><img src={h.imageUrl} className="aspect-square w-full object-cover"/><div className="p-2 text-left"><b className="block truncate text-[9px]">{h.name}</b><p className="text-[8px]" style={{color:color[h.rarity]}}>{h.rarity} · {t('levelShort')}{h.level}</p><p className="text-[8px]">{h.archetype}</p><p className="text-[8px]">ATK {h.finalAtk} · HP {h.finalHp}</p><p className="text-[8px] text-amber-200">{t('boss.power')} {h.power}</p></div></button>})}</div></div></div>}

function Shell({children,onClose}:{children:React.ReactNode;onClose:()=>void}){const t=useT();return<div className="fixed inset-0 z-[75] overflow-y-auto bg-[#04070c] text-white"><div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_top,#183153_0%,#060910_48%,#030508_100%)]"/><div className="forge-safe-page relative mx-auto min-h-full w-full max-w-[480px] p-3 pb-10"><header className="mb-4 flex items-center justify-between"><div><p className="text-[9px] uppercase tracking-[.28em] text-amber-300">MYTHREON</p><h1 className="text-xl font-black">{t('pvp.subtitle')}</h1></div><button onClick={onClose} className="grid h-10 w-10 place-items-center rounded-xl border border-amber-300/20 bg-black/60"><X/></button></header>{children}</div></div>}
function Opponent({opponent:o,selected,onSelect,onFight,pending,tickets,onBuyTickets,t}:{opponent:PvpOpponent;selected:boolean;onSelect:()=>void;onFight:()=>void;pending:boolean;tickets:number;onBuyTickets:()=>void;t:(k:string,v?:Record<string,string|number>)=>string}){const noTickets=tickets<1;return<div onClick={onSelect} className={`rounded-2xl border bg-black/60 p-3 ${selected?'border-amber-300':'border-white/10'}`}><div className="flex items-center gap-3"><Avatar src={o.avatarUrl} name={o.name}/><div className="flex-1"><b className="block truncate">{o.name}</b>{o.username?<p className="truncate text-[9px] text-amber-200/80">@{o.username}</p>:null}<p className="text-[9px] text-slate-400">{o.league} · {t('pvp.trophies',{count:o.trophies})} · {t('pvp.wins',{count:o.wins})}</p></div><b className="text-xs text-amber-200">⚔ {o.teamPower}</b></div><div className="mt-3 grid grid-cols-5 gap-1">{o.defenseTeam.map(h=><div key={h.heroId} className="overflow-hidden rounded-lg border bg-black" style={{borderColor:color[h.rarity]}}><img src={h.imageUrl} className="aspect-square w-full object-cover"/><p className="truncate px-1 text-[7px]">{h.name}</p><p className="px-1 pb-1 text-[6px]">A {h.finalAtk} · H {h.finalHp}</p></div>)}</div>{selected&&(noTickets?<div className="mt-3"><p className="text-center text-[10px] font-black uppercase tracking-[.18em] text-rose-300">{t('pvp.noTickets')}</p><button type="button" onClick={e=>{e.stopPropagation();onBuyTickets()}} className="mt-2 w-full rounded-xl bg-gradient-to-b from-amber-300 to-orange-500 py-3 text-[11px] font-black text-black">{t('pvp.buyTickets')}</button></div>:<button type="button" disabled={pending} onClick={e=>{e.stopPropagation();onFight()}} className="mt-3 w-full rounded-xl bg-gradient-to-b from-rose-400 to-red-700 py-3 font-black text-white disabled:grayscale disabled:opacity-40">{pending?t('pvp.starting'):t('pvp.battle1Ticket')}</button>)}</div>}
/** Compact bottom sheet: the arena keeps its layout, the ticket counter just gains a [+]. */
function TicketSheet({tickets,shop,pending,onClose,onBuy,t}:{tickets:number;shop?:PvpTicketShop;pending:boolean;onClose:()=>void;onBuy:(quantity:number)=>void;t:(k:string,v?:Record<string,string|number>)=>string}){
 const limit=shop?.dailyLimit??10,bought=shop?.boughtToday??0,remaining=Math.max(0,shop?.remaining??limit-bought),packs=shop?.packs?.length?shop.packs:[{tickets:1,priceFc:5000},{tickets:3,priceFc:13500},{tickets:5,priceFc:20000}];
 return<div className="fixed inset-0 z-[95] flex items-end justify-center bg-black/80" onClick={onClose}>
  <div className="forge-safe-page w-full max-w-[480px] rounded-t-3xl border border-amber-300/30 bg-[#080c14] p-4" onClick={e=>e.stopPropagation()}>
   <div className="flex items-start justify-between">
    <div><p className="text-[8px] font-black uppercase tracking-[.28em] text-amber-300">MYTHREON</p><b className="text-base font-black">{t('tickets.title')}</b></div>
    <button type="button" onClick={onClose} className="grid h-8 w-8 place-items-center rounded-lg border border-white/10 bg-black/60"><X className="h-4 w-4"/></button>
   </div>
   <div className="mt-3 grid grid-cols-2 gap-2 text-center">
    <div className="rounded-xl border border-white/10 bg-black/50 py-2"><p className="text-[8px] uppercase tracking-[.16em] text-slate-400">{t('tickets.current')}</p><b className="text-sm text-amber-200">{tickets.toLocaleString()} 🎟</b></div>
    <div className="rounded-xl border border-white/10 bg-black/50 py-2"><p className="text-[8px] uppercase tracking-[.16em] text-slate-400">{t('tickets.today')}</p><b className="text-sm">{bought} / {limit}</b></div>
   </div>
   <div className="mt-3 space-y-2">{packs.map(p=>{const blocked=pending||p.tickets>remaining;return<button key={p.tickets} type="button" disabled={blocked} onClick={()=>onBuy(p.tickets)} className={`flex w-full items-center justify-between rounded-xl border px-3 py-3 text-left ${blocked?'border-white/10 bg-black/40 opacity-45':'border-amber-300/40 bg-gradient-to-r from-amber-400/15 to-transparent'}`}>
    <b className="text-[12px] font-black">{t('tickets.packLabel',{count:p.tickets})}</b>
    <span className="text-[12px] font-black text-amber-200">{p.priceFc.toLocaleString()} FC</span>
   </button>})}</div>
   {remaining===0?<p className="mt-3 text-center text-[10px] font-bold text-rose-300">{t('tickets.dailyLimitReached')}</p>
    :remaining<Math.max(...packs.map(p=>p.tickets))?<p className="mt-3 text-center text-[10px] text-amber-200">{t('tickets.remainingToday',{count:remaining})}</p>:null}
   {shop?.hasPass
    ?<p className="mt-3 rounded-xl border border-amber-300/30 bg-amber-400/10 px-3 py-2 text-center text-[10px] font-bold text-amber-200">{t('tickets.battlePassBonus',{count:Math.max(0,(shop.passLimit??20)-(shop.freeLimit??10))})}</p>
    :<p className="mt-3 text-center text-[9px] text-slate-400">{t('tickets.passUpsell',{count:shop?.passLimit??20})}</p>}
   <button type="button" onClick={onClose} className="mt-3 w-full rounded-xl border border-white/10 bg-black/60 py-3 text-[11px] font-black text-slate-200">{t('tickets.close')}</button>
  </div>
 </div>
}

function Stat({icon,label,value,onBuy,buyAria}:{icon:React.ReactNode;label:string;value:string|number;onBuy?:()=>void;buyAria?:string}){return<div className="flex min-w-0 flex-col items-center justify-center px-2 text-center"><div className="h-7 w-7 text-amber-300 [&>svg]:h-full [&>svg]:w-full">{icon}</div><div className="mt-2 flex max-w-full items-center justify-center gap-1"><b className="block min-w-0 truncate text-[11px] text-white">{typeof value==='number'?value.toLocaleString():value}</b>{onBuy?<button type="button" onClick={onBuy} aria-label={buyAria} className="grid h-5 w-5 shrink-0 place-items-center rounded-md border border-amber-300/60 bg-amber-400/20 text-amber-200 active:scale-95"><Plus className="h-3 w-3" strokeWidth={3}/></button>:null}</div><p className="mt-1 text-[8px] uppercase tracking-[.16em] text-slate-400">{label}</p></div>}
function Nav({active,onClick,icon,text}:{active:boolean;onClick:()=>void;icon:React.ReactNode;text:string}){return<button type="button" onClick={onClick} className={`flex h-[72px] min-w-0 flex-col items-center justify-center gap-1.5 rounded-xl px-2 py-3 text-[9px] font-black transition ${active?'bg-amber-400 text-black shadow-[0_6px_18px_rgba(245,158,11,.22)]':'bg-[#101a2a] text-white'}`}><span className="h-6 w-6 [&>svg]:h-full [&>svg]:w-full">{icon}</span><span className="block truncate text-center">{text}</span></button>}
function Avatar({src,name}:{src:string|null;name:string}){return src?<img src={src} className="h-10 w-10 rounded-full object-cover"/>:<div className="grid h-10 w-10 place-items-center rounded-full bg-amber-900 font-black">{name[0]}</div>}
function Center({text}:{text:string}){return<p className="py-20 text-center text-sm text-slate-300">{text}</p>}
const teamButton=(active:boolean)=>`h-12 rounded-xl border px-2 text-center text-[10px] font-black uppercase ${active?'border-amber-300 bg-amber-400 text-black':'border-white/10 bg-[#101a2a] text-white'}`;
