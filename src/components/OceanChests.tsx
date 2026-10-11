import { useEffect, useState } from 'react';
import { BookOpen, Info, PackageOpen, X } from 'lucide-react';
import { useLanguage } from '../LanguageContext';
import { mascotChestArt, balanceArt } from '../gameAssets';
import { navalMaterialArt } from '../navalMaterialArt';
import { formatOceanTon, nearestOceanChest, type OceanOdds, type OceanReward } from '../oceanChests';
import type { useOceanChests } from '../useOceanChests';
import { OceanControl } from './OceanControl';
import './OceanChests.css';
export default function OceanChests({ ocean, position, unavailable, onStop, selection }: { ocean: ReturnType<typeof useOceanChests>; position: {x:number;y:number}; unavailable:boolean; onStop:()=>void; selection?:{id:string;nonce:number}|null }) {
 const {t,language}=useLanguage(); const [view,setView]=useState<'odds'|'history'|null>(null);
 useEffect(()=>{if(selection)setView('odds');},[selection]);
 const near=nearestOceanChest(ocean.data?.chests ?? [],position,ocean.data?.collectRadius ?? 100);
 const label=(r:OceanReward|OceanOdds)=>r.kind==='ton' ? `${formatOceanTon(r.amount ?? 0,language)} TON` : ('name' in r ? r.name : undefined) ?? t(`ocean.${r.kind}`);
 const odds=ocean.data?.chests.find(c=>c.id===selection?.id)?.odds ?? near?.odds ?? (ocean.data?.emission==='alternative' ? ocean.data.alternativeOdds : ocean.data?.odds) ?? [];
 const notice=ocean.error ? t(`ocean.${['OCEAN_CHEST_UNAVAILABLE','OCEAN_OUT_OF_RANGE','OCEAN_CLAIM_LIMIT','OCEAN_PAUSED','OCEAN_CATALOG_UNAVAILABLE'].includes(ocean.error) ? ocean.error : 'OCEAN_UNAVAILABLE'}`) : ocean.data && !['active','alternative'].includes(ocean.data.emission) ? t(`ocean.${ocean.data.emission}`) : '';
 const reward=ocean.reward;
 const materialKey=reward?.material as keyof typeof navalMaterialArt | undefined;
 const rewardArt=reward?.kind==='ton' ? balanceArt.ton : materialKey && navalMaterialArt[materialKey] ? navalMaterialArt[materialKey] : reward?.image ?? mascotChestArt.common;
 return <>
  <div className="ocean-chest-toolbar"><OceanControl title={t('ocean.odds')} aria-label={t('ocean.odds')} onClick={()=>{onStop();setView('odds');}}><Info size={18}/></OceanControl><OceanControl title={t('ocean.history')} aria-label={t('ocean.history')} onClick={()=>{onStop();setView('history');}}><BookOpen size={18}/></OceanControl></div>
  {notice && <div className="ocean-chest-notice" role="status">{notice}</div>}
  {near && !reward && !view && <div className="ocean-chest-indicator"><img src={mascotChestArt.common} alt=""/><OceanControl disabled={unavailable||ocean.busy} onClick={()=>{onStop();void ocean.action('claim',near.id);}}><PackageOpen size={18}/>{t(ocean.busy ? 'ocean.opening':'ocean.collect')}</OceanControl></div>}
  {(view || reward) && <div className="ocean-chest-sheet"><section className="ocean-chest-dialog" role="dialog" aria-modal="true" aria-label={t('ocean.title')}><header><h2>{t(reward ? 'ocean.title' : `ocean.${view}`)}</h2><OceanControl aria-label={t('ocean.close')} title={t('ocean.close')} onClick={()=>{setView(null);ocean.dismiss();}}><X size={18}/></OceanControl></header>
   {reward ? <><img className="ocean-reward-art" src={rewardArt} alt=""/><h2>{label(reward)}{reward.kind==='material' ? ` · ${reward.amount} ${t(`ocean.${reward.material}`)}` : ''}</h2>{reward.kind==='ton' && <small>{t('ocean.pending')}</small>}</> : view==='odds' ? <><small>{t(`ocean.${ocean.data?.emission ?? 'paused'}`)}</small><ul>{odds.map((r,i)=><li key={i}><div><span>{label(r)}</span><b>{r.weight}%</b></div></li>)}</ul></> : <><ul>{ocean.data?.history.map(h=><li key={h.chest_id}><div><span>{label(h.reward)}{h.reward.kind==='material' ? ` · ${h.reward.amount} ${t(`ocean.${h.reward.material}`)}`:''}</span><time>{new Date(h.created_at).toLocaleDateString(language)}</time></div>{h.reward.kind==='ton' && <small>{t(`ocean.${h.payment_status==='paid' ? 'paid':h.payment_status==='failed'?'failed':'pending'}`)}</small>}</li>)}</ul>{ocean.data?.equipmentQuotes.map(q=><div key={q.id}><b>{q.name}</b><small>{Object.entries(q.materials).map(([id,n])=>`${n} ${t(`ocean.${id}`)}`).join(' · ')}</small><OceanControl disabled={ocean.busy} onClick={()=>{if(window.confirm(t('ocean.confirmSalvage')))void ocean.action('salvage',q.id);}}><PackageOpen size={16}/>{t('ocean.salvage')}</OceanControl></div>)}</>}
  </section></div>}
 </>;
}