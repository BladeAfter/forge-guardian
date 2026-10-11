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
    mounted.current = true; let cancelled = false, scheduled = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const schedule = (delay: number) => {
      if (cancelled) return;
      clearTimeout(timer);
      scheduled = true;
      timer = setTimeout(tick, delay);
    };
    const tick = async () => {
      scheduled = false;
      if(cancelled || !initData) return;
      const started = performance.now();
      if(!locked.current && !document.hidden) {
        locked.current = true;
         try { const next=await navalCall(initData,'heartbeat',pending.current.shift() ?? input.current()); if(!cancelled) apply(next); }
         catch(e) { if(!cancelled) setError(e instanceof Error ? e.message : 'Oceano indisponível.'); }
        finally { locked.current = false; }
      }
      // A gesture arriving during a request must run as soon as it finishes.
      // Count the round trip inside the cadence, rather than adding it on top.
      if(!cancelled) schedule(pending.current.length ? 0 : Math.max(0, (current.current ? 650 : 5000) - (performance.now() - started)));
    };
    wake.current = () => {
      if(cancelled || locked.current) return;
      // Do not let successive drag events keep postponing an urgent send.
      if (scheduled) clearTimeout(timer);
      if (!scheduled || timer !== undefined) { schedule(0); }
    };
    const resume = () => { if(!document.hidden) wake.current?.(); };
    document.addEventListener('visibilitychange',resume);
    window.addEventListener('online',resume);
    void tick();
    return () => { cancelled=true;mounted.current=false;wake.current=null;pending.current=[];clearTimeout(timer); document.removeEventListener('visibilitychange',resume);window.removeEventListener('online',resume); };
  }, [initData]);
  const action = async (name: string, payload: Record<string,unknown> = {}) => {
    if(!initData || locked.current) return false;
    locked.current=true;setBusy(true);
    try { apply(await navalCall(initData,name,payload));return true; }
    catch(e) { if(mounted.current) setError(e instanceof Error ? e.message : 'Ação indisponível.');return false; }
    finally { locked.current=false;if(mounted.current) { setBusy(false);wake.current?.(); } }
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