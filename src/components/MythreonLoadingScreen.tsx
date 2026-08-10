import loadingArt from '../assets/mythreon-loading.jpg.asset.json';

/**
 * Single boot screen for the Mini App: the official Mythreon art plus a real
 * progress bar driven by the initialization stages (Telegram -> auth -> data).
 */
export function MythreonLoadingScreen({ progress, note, fading }: { progress: number; note?: string | null; fading?: boolean }) {
  const value = Math.max(0, Math.min(100, Math.round(progress)));
  return (
    <div
      className={`fixed inset-0 z-[100] overflow-hidden bg-[#03060f] transition-opacity duration-500 ${fading ? 'opacity-0' : 'opacity-100'}`}
      style={{ width: '100vw', height: '100dvh' }}
    >
      <img
        src={loadingArt.url}
        alt="Mythreon"
        className="absolute inset-0 h-full w-full object-cover object-center"
        style={{ width: '100vw', height: '100dvh' }}
        fetchPriority="high"
      />
      <div
        className="absolute inset-x-0 flex flex-col items-center gap-2 px-8"
        style={{ bottom: `calc(env(safe-area-inset-bottom, 0px) + 12dvh)` }}
      >
        <div className="h-2.5 w-full max-w-[300px] overflow-hidden rounded-full border border-sky-300/40 bg-black/60 shadow-[0_0_18px_rgba(56,189,248,.35)]">
          <div
            className="h-full rounded-full bg-gradient-to-r from-sky-500 via-sky-300 to-cyan-200 shadow-[0_0_12px_rgba(125,211,252,.9)] transition-[width] duration-500 ease-out"
            style={{ width: `${value}%` }}
          />
        </div>
        <span className="text-sm font-black tracking-[.18em] text-sky-100 drop-shadow-[0_2px_6px_rgba(0,0,0,.9)]">{value}%</span>
        {note ? <span className="max-w-[320px] text-center text-[11px] font-semibold uppercase tracking-[.12em] text-amber-200 drop-shadow-[0_2px_6px_rgba(0,0,0,.9)]">{note}</span> : null}
      </div>
    </div>
  );
}
