import { useEffect, useRef, useState } from 'react';
import { navalCall, type NavalState } from './naval';

type NavalInput = { dx: number; dy: number; throttle: number };
export function useNavalOcean(initData: string, direction: () => NavalInput) {
  const [data,setData] = useState<NavalState | null>(null);
  const [error,setError] = useState('');
  const [busy,setBusy] = useState(false);
  const current = useRef<NavalState | null>(null);
  const input = useRef(direction); input.current = direction;
  const locked = useRef(false);
  const mounted = useRef(true);
  const pending = useRef<NavalInput[]>([]);
  const wake = useRef<(() => void) | null>(null);
  const apply = (next: NavalState) => { current.current = next; if(mounted.current) { setData(next);setError(''); } };
  useEffect(() => {
    mounted.current = true; let cancelled = false, timer: ReturnType<typeof setTimeout>;
    const tick = async () => {
      if(cancelled || !initData) return;
      if(!locked.current && !document.hidden) {
        locked.current = true;
         try { const next=await navalCall(initData,'heartbeat',pending.current.shift() ?? input.current()); if(!cancelled) apply(next); }
        catch(e) { if(!cancelled) { current.current=null;setData(null);setError(e instanceof Error ? e.message : 'Oceano indisponível.'); } }
        finally { locked.current = false; }
      }
       if(!cancelled) timer=setTimeout(tick,pending.current.length ? 100 : current.current ? 650 : 5000);
    };
    wake.current = () => { if(!cancelled && !locked.current) { clearTimeout(timer); timer=setTimeout(tick,0); } };
    void tick();
    return () => { cancelled=true;mounted.current=false;wake.current=null;pending.current=[];clearTimeout(timer); };
  }, [initData]);
  const action = async (name: string, payload: Record<string,unknown> = {}) => {
    if(!initData || locked.current) return false;
    locked.current=true;setBusy(true);
    try { apply(await navalCall(initData,name,payload));return true; }
    catch(e) { if(mounted.current) setError(e instanceof Error ? e.message : 'Ação indisponível.');return false; }
    finally { locked.current=false;if(mounted.current) setBusy(false); }
  };
   const steer = (next: NavalInput) => {
     if(!initData) return;
     // Keep a brief gesture until it is sent, even when release precedes the next poll.
     const moving = (value: NavalInput) => Math.hypot(value.dx,value.dy) > .01 && value.throttle > 0;
     const last = pending.current[pending.current.length - 1];
     if(last && moving(last) === moving(next)) pending.current[pending.current.length - 1] = next;
     else pending.current.push(next);
     if(pending.current.length > 2) pending.current.splice(0,pending.current.length - 2);
     wake.current?.();
   };
   return {data,current,error,busy,action,steer};
}