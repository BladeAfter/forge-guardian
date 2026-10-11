import {useEffect,useState} from 'react';
import {toast} from 'sonner';
import {useReferralDashboard} from '../hooks';
import {translate,type LanguageCode} from '../i18n';
import {ReferralDeckView} from '../components/ReferralDeckView';
import {buildTelegramShareUrl,type ReferralInvite} from '../referrals';

type Props={telegramInitData:string;languageCode:LanguageCode;onClose:()=>void};


export function ReferralPage({telegramInitData,languageCode,onClose}:Props){

  const t=(key:string,vars?:Record<string,unknown>)=>translate(languageCode,key,vars as Record<string,string|number>|undefined);const [level,setLevel]=useState<1|2|3|undefined>();const [offset,setOffset]=useState(0);
  const {data,isLoading,error,refetch}=useReferralDashboard(telegramInitData,true,level,offset);const [invites,setInvites]=useState<ReferralInvite[]>([]);
  useEffect(()=>{setOffset(0);setInvites([])},[level]);
  useEffect(()=>{if(data)setInvites(current=>offset===0?data.invites:[...current,...data.invites.filter(row=>!current.some(old=>old.id===row.id))])},[data,offset]);
  useEffect(()=>{if(error)console.error('[referrals] Falha ao carregar dashboard',error)},[error]);
  const copy=async(value:string,message?:string)=>{await navigator.clipboard.writeText(value);toast.success(message??t('profile.invite.linkCopied'))};
  const share=()=>{if(!data)return;const url=buildTelegramShareUrl(data.link,t('inviteShareText'));const tg=window.Telegram?.WebApp;if(tg?.openTelegramLink)tg.openTelegramLink(url);else window.open(url,'_blank','noopener,noreferrer')};

  return <ReferralDeckView data={data} invites={invites} isLoading={isLoading} failed={Boolean(error)} level={level} t={t} languageCode={languageCode} onClose={onClose} onRetry={()=>void refetch()} onCopy={(value,message)=>void copy(value,message)} onShare={share} onLevel={setLevel} onMore={()=>setOffset(x=>x+20)}/>;
}
