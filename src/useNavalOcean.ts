import { useEffect, useRef, useState } from 'react';
import { navalCall, type NavalState } from './naval';

export function useNavalOcean(initData: string, direction: () => { dx: number; dy: number; throttle: number }) {
  const [data,setData] = useState<NavalState | null>(null);
  const [error,setError] = useState('');
  const [busy,setBusy] = useState(false);
  const current = useRef<NavalState | null>(null);
  const input = useRef(direction); input.current = direction;
  const locked = useRef(false);
  const mounted = useRef(true);
  const apply = (next: NavalState) => { current.current = next; if(mounted.current) { setData(next);setError(''); } };
  useEffect(() => {
    mounted.current = true; let cancelled = false, timer: ReturnType<typeof setTimeout>;
    const tick = async () => {
      if(cancelled || !initData) return;
      if(!locked.current && !document.hidden) {
        locked.current = true;
        try { const next=await navalCall(initData,'heartbeat',input.current()); if(!cancelled) apply(next); }
        catch(e) { if(!cancelled) { current.current=null;setData(null);setError(e instanceof Error ? e.message : 'Oceano indisponível.'); } }
        finally { locked.current = false; }
      }
      if(!cancelled) timer=setTimeout(tick,current.current ? 650 : 5000);
    };
    void tick();
    return () => { cancelled=true;mounted.current=false;clearTimeout(timer); };
  }, [initData]);
  const action = async (name: string, payload: Record<string,unknown> = {}) => {
    if(!initData || locked.current) return false;
    locked.current=true;setBusy(true);
    try { apply(await navalCall(initData,name,payload));return true; }
    catch(e) { if(mounted.current) setError(e instanceof Error ? e.message : 'Ação indisponível.');return false; }
    finally { locked.current=false;if(mounted.current) setBusy(false); }
  };
  return {data,current,error,busy,action};
}