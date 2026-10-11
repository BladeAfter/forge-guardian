import { useEffect, type RefObject } from 'react';
/** Stable sheet dimensions never affect logical game coordinates. */
export function useGameViewport(host: RefObject<HTMLElement>) {
  useEffect(() => {
    const app = window.Telegram?.WebApp;
    if (!app) return;
    let last = 0;
    const update = (event?: { isStateStable?: boolean }) => {
      if (event?.isStateStable === false) return;
      const height = app.viewportStableHeight;
      if (!height || height === last || !host.current) return;
      last = height; host.current.style.height = `${height}px`;
    };
    update(); app.onEvent?.('viewportChanged', update);
    const resume = () => update();
    window.addEventListener('pageshow', resume);
    return () => { app.offEvent?.('viewportChanged', update); window.removeEventListener('pageshow', resume); host.current?.style.removeProperty('height'); };
  }, [host]);
}