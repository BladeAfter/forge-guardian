import {ArrowLeft,Copy,RefreshCw,Share2,Users} from 'lucide-react';
import {useEffect,useState} from 'react';
import {toast} from 'sonner';
import {useReferralDashboard} from '../hooks';
import {translate,type LanguageCode} from '../i18n';
import {mainScreenArt} from '../gameAssets';
import {buildTelegramShareUrl,type ReferralInvite} from '../referrals';

type Props={telegramInitData:string;languageCode:LanguageCode;onClose:()=>void};
const money=(value:number)=>Number(value||0).toLocaleString('pt-BR',{maximumFractionDigits:3});

export function ReferralPage({telegramInitData,languageCode,onClose}:Props){
  const t=(key:string,vars?:Record<string,unknown>)=>translate(languageCode,key,vars as Record<string,string|number>|undefined);const [level,setLevel]=useState<1|2|3|undefined>();const [offset,setOffset]=useState(0);
  const {data,isLoading,error,refetch}=useReferralDashboard(telegramInitData,true,level,offset);const [invites,setInvites]=useState<ReferralInvite[]>([]);
  useEffect(()=>{setOffset(0);setInvites([])},[level]);
  useEffect(()=>{if(data)setInvites(current=>offset===0?data.invites:[...current,...data.invites.filter(row=>!current.some(old=>old.id===row.id))])},[data,offset]);
  useEffect(()=>{if(error)console.error('[referrals] Falha ao carregar dashboard',error)},[error]);
  const copy=async(value:string,message?:string)=>{await navigator.clipboard.writeText(value);toast.success(message??t('profile.invite.linkCopied'))};
  const share=()=>{if(!data)return;const url=buildTelegramShareUrl(data.link,t('inviteShareText'));window.Telegram?.WebApp?.openTelegramLink?.(url)??window.open(url,'_blank','noopener,noreferrer')};

  return <div className="fixed inset-0 z-[70] overflow-y-auto bg-[#05080e]/96 text-white"><div className="relative forge-safe-page mx-auto min-h-screen max-w-[480px] px-4 pb-12 pt-3">
    <header className="flex items-center justify-between"><button type="button" onClick={onClose} className="grid h-10 w-10 place-items-center rounded-xl border border-amber-400/30 bg-black/60"><ArrowLeft/></button><div className="text-center"><p className="text-[9px] uppercase tracking-[.3em] text-amber-300">MYTHREON</p><h1 className="font-black">{t('profile.invite.title')}</h1></div><img src={mainScreenArt.invite} alt="" className="h-11 w-11 object-contain"/></header>
    {isLoading&&offset===0?<div className="mt-8 space-y-3">{[1,2,3].map(x=><div key={x} className="h-28 animate-pulse rounded-3xl bg-white/5"/>)}</div>:error||!data?<div className="mt-16 rounded-2xl border border-rose-400/30 bg-rose-950/30 p-6 text-center"><p>{t('profile.invite.loadError')}</p><button type="button" onClick={()=>void refetch()} className="mt-4 inline-flex items-center gap-2 rounded-xl border border-amber-300/40 px-4 py-2 text-amber-200"><RefreshCw className="h-4 w-4"/>{t('profile.invite.retry')}</button></div>:<main className="mt-5 space-y-3">
      <Card><p className="label">{t('profile.invite.myLink')}</p><p className="mt-2 truncate rounded-xl bg-black/50 px-3 py-2 text-[11px] text-sky-200">{data.link}</p><div className="mt-3 grid grid-cols-2 gap-2"><Button icon={<Copy/>} text={t('profile.invite.copyLink')} onClick={()=>void copy(data.link)}/><Button icon={<Share2/>} text={t('profile.invite.share')} onClick={share}/></div><button type="button" onClick={()=>void copy(String(data.telegramId),t('profile.invite.idCopied'))} className="mt-3 text-[10px] text-slate-300">{t('profile.invite.myInviteId',{id:data.telegramId})}</button></Card>
      <div className="grid grid-cols-2 gap-2"><Stat label={t('profile.invite.totalInvited')} value={String(data.counts.total)}/><Stat label={t('profile.invite.commissionsReceived')} value={`${formatTon(data.earningsTon?.total??0)} TON`}/></div>
      <Card><p className="label">{t('profile.invite.commissionLevels')}</p><div className="mt-3 grid grid-cols-3 gap-2">{(data.commissionLevels??[{level:1,percent:10,invitedCount:data.counts.lv1,totalEarnedFc:0},{level:2,percent:4,invitedCount:data.counts.lv2,totalEarnedFc:0},{level:3,percent:1,invitedCount:data.counts.lv3,totalEarnedFc:0}]).map(row=><div key={row.level} className="rounded-xl bg-white/[.04] p-2 text-center"><b className="text-amber-200">Lv{row.level} · {row.percent}%</b><p className="text-[9px] text-slate-400">{t('profile.invite.invitedCount',{count:row.invitedCount})}</p><p className="text-[9px] text-emerald-300">{formatTon(row.totalEarnedTon??0)} TON</p></div>)}</div>
        <p className="mt-3 text-[9px] leading-relaxed text-slate-400">{t('profile.invite.tonRule')}</p></Card>
      {data.commissionHistory?.length?<Card><p className="label">{t('profile.invite.commissionHistory')}</p><div className="mt-3 space-y-2">{data.commissionHistory.slice(0,10).map(row=><div key={row.id} className="flex items-center justify-between rounded-xl border border-white/10 bg-black/40 p-2 text-[10px]"><div className="min-w-0"><p className="truncate font-bold">{row.name}</p><p className="text-[9px] text-slate-400">Lv{row.level} · {row.sourceType} · {formatTon(row.sourceAmountTon)} TON</p></div><p className="font-black text-emerald-300">+{formatTon(row.commissionTon)} TON</p></div>)}</div></Card>:null}
      <Card>
        <div className="flex items-center gap-2"><Users className="h-4 w-4 text-amber-300"/><p className="label">{t('profile.invite.myInvited')}</p></div>
        <div className="mt-3 grid grid-cols-4 gap-1">{([undefined,1,2,3] as const).map(value=><button type="button" key={value??'all'} onClick={()=>setLevel(value)} className={`rounded-lg border py-2 text-[9px] font-bold ${level===value?'border-amber-300 text-amber-200':'border-white/10 text-slate-400'}`}>{value?`LV${value}`:t('profile.invite.all')}</button>)}</div>
        <div className="mt-3 space-y-2">{invites.length?invites.map(person=><Invite key={person.id} person={person} t={t}/>):<div className="rounded-xl border border-dashed border-white/10 p-6 text-center"><p className="text-xs">{t('profile.invite.noInvitesYet')}</p><p className="mt-2 text-[10px] text-slate-500">{t('profile.invite.shareHint')}</p><button type="button" onClick={()=>void copy(data.link)} className="mt-3 text-xs font-bold text-amber-200">{t('profile.invite.copyLink')}</button></div>}</div>
        {data.pagination?.hasMore&&<button type="button" disabled={isLoading} onClick={()=>setOffset(x=>x+20)} className="mt-3 w-full rounded-xl border border-amber-300/30 py-3 text-xs font-bold text-amber-200">{isLoading?t('profile.invite.loading'):t('profile.invite.loadMore')}</button>}
      </Card>
    </main>}
  </div></div>;
}

function Card({children}:{children:React.ReactNode}){return <section className="rounded-3xl border border-amber-400/20 bg-gradient-to-br from-[#101a2c]/95 to-black/90 p-4">{children}</section>}
function Button({icon,text,onClick}:{icon:React.ReactNode;text:string;onClick:()=>void}){return <button type="button" onClick={onClick} className="flex items-center justify-center gap-2 rounded-xl border border-amber-300/20 bg-black/40 py-3 text-[10px] font-bold text-amber-100"><span className="[&>svg]:h-4 [&>svg]:w-4">{icon}</span>{text}</button>}
function Stat({label,value}:{label:string;value:string}){return <div className="rounded-2xl border border-white/10 bg-black/60 p-3 text-center"><p className="text-[9px] text-slate-400">{label}</p><p className="mt-1 font-black text-amber-200">{value}</p></div>}
function Invite({person,t}:{person:ReferralInvite;t:(key:string,params?:Record<string,unknown>)=>string}){return <div className="flex items-center gap-3 rounded-xl border border-white/10 bg-black/40 p-3">{person.avatar?<img src={person.avatar} alt="" className="h-10 w-10 rounded-full object-cover"/>:<div className="grid h-10 w-10 place-items-center rounded-full bg-amber-900/30">{person.name[0]}</div>}<div className="min-w-0 flex-1"><p className="truncate text-xs font-bold">{person.name}</p><p className="text-[9px] text-slate-400">{person.username?`@${person.username} · `:''}Lv{person.level} · {person.online?t('profile.invite.online'):t('profile.invite.offline')}</p><p className="text-[8px] text-slate-500">{t('profile.invite.joinedOn',{date:new Date(person.joinedAt).toLocaleDateString('pt-BR')})}</p></div><div className="text-right text-[9px]"><p>{t('profile.invite.generated',{amount:money(person.generated)})}</p><p className="text-emerald-300">+{money(person.commission)} FC</p></div></div>}
