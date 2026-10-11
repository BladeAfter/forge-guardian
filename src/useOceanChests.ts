import { useEffect, useRef, useState } from 'react';
import { oceanChestCall, type OceanChestState, type OceanReward } from './oceanChests';
export function useOceanChests(initData: string) {
  const [data,setData] = useState<OceanChestState | null>(null);
  const [reward,setReward] = useState<OceanReward | null>(null);
  const [error,setError] = useState('');
  const [busy,setBusy] = useState(false);
  const current = useRef<OceanChestState | null>(null);
  const locked = useRef(false), polling = useRef(false), mounted = useRef(false), revision = useRef(0);
  const apply = (next: OceanChestState) => { current.current=next;setData(next);setError(''); };
  useEffect(() => {
    if (!initData) return;
    mounted.current=true; let timer: ReturnType<typeof setTimeout>; let cancelled=false;
    const tick=async () => {
      if (cancelled || document.hidden) return;
      if (!cancelled && !document.hidden && !locked.current && !polling.current) {
        polling.current=true;const version=revision.current;
        try { const next=await oceanChestCall(initData);if(!cancelled && version===revision.current)apply(next); }
        catch { if(!cancelled && version===revision.current)setError('OCEAN_UNAVAILABLE'); }
        finally { polling.current=false; }
      }
      if(!cancelled && !document.hidden)timer=setTimeout(tick,5000);
    };
    const resume=() => { clearTimeout(timer);if(!cancelled && !document.hidden && !polling.current)void tick(); };
    window.addEventListener('online',resume);document.addEventListener('visibilitychange',resume);void tick();
    return () => { cancelled=true;mounted.current=false;clearTimeout(timer);window.removeEventListener('online',resume);document.removeEventListener('visibilitychange',resume); };
  },[initData]);
  const action=async (name:string,id:string) => {
    if(!initData || locked.current)return false;
    locked.current=true;revision.current++;setBusy(true);
    try { const next=await oceanChestCall(initData,name,id);if(mounted.current){apply(next);if(next.reward)setReward(next.reward);}return true; }
    catch(e){ if(mounted.current)setError(e instanceof Error ? e.message : 'OCEAN_UNAVAILABLE');return false; }
    finally {locked.current=false;if(mounted.current)setBusy(false);}
  };
  return {data,current,reward,error,busy,action,dismiss:()=>setReward(null)};
}