import{useEffect,useMemo,useState}from'react';
import{X}from'lucide-react';
import treasure from'../assets/spending-event-treasure.png';
import{abbreviatePoints,countdownLabel,spendingCountdown}from'../spendingEvent';
import type{SpendingEventPopup as SpendingEventPopupData}from'../spendingEvent';
import{useT}from'../LanguageContext';

/**
 * MYTHREON :: SPENDING EVENT entry highlight.
 *
 * Purely informational: it never changes the event, never blocks the game and is
 * dismissible with a single tap. The backend decides IF it should appear
 * (config + once per day/event per user); this component only renders the payload.
 */
export function SpendingEventPopup({data,onClose,onView}:{data:SpendingEventPopupData;onClose:()=>void;onView:()=>void}){
  const[visible,setVisible]=useState(false);
  useEffect(()=>{const id=window.setTimeout(()=>setVisible(true),40);return()=>window.clearTimeout(id)},[]);
  const featured=Boolean(data.firstTime);
  const points=Number(data.player?.points??0);
  const rank=data.player?.position??null;
  const reward=data.player?.estimatedReward??null;
  const ends=useMemo(()=>countdownLabel(spendingCountdown(data.event?.endsAt)),[data.event?.endsAt]);

  return (
    <div className="fixed inset-0 z-[90] grid place-items-center bg-black/80 px-5 backdrop-blur-sm" role="dialog" aria-modal="true" aria-label={t('spending.dialogLabel')}>
      <div className={`spending-popup relative w-[88%] max-w-[360px] max-h-[64dvh] overflow-y-auto rounded-3xl border border-amber-300/45 bg-gradient-to-b from-[#0b1428] via-[#070c18] to-[#0d1020] px-4 pb-4 pt-3 text-center shadow-[0_25px_60px_rgba(0,0,0,.7)] ${visible?'spending-popup-in':'opacity-0'}`}>
        <div className="pointer-events-none absolute -top-16 left-1/2 h-40 w-40 -translate-x-1/2 rounded-full bg-amber-400/20 blur-3xl"/>
        <button type="button" onClick={onClose} aria-label={t('spending.close')} className="absolute right-2.5 top-2.5 z-10 grid h-8 w-8 place-items-center rounded-full border border-white/15 bg-black/60 text-amber-100 active:scale-95">
          <X className="h-4 w-4"/>
        </button>

        <p className="relative text-[8px] font-black uppercase tracking-[.34em] text-amber-200/70">MYTHREON</p>

        <img
          src={treasure}
          alt="Spending Event"
          loading="lazy"
          width={816}
          height={816}
          className={`relative mx-auto drop-shadow-[0_12px_24px_rgba(0,0,0,.75)] ${featured?'h-[112px] w-[112px]':'h-[84px] w-[84px]'} object-contain`}
        />

        <h2 className="relative mt-1 bg-gradient-to-r from-amber-200 via-yellow-100 to-amber-300 bg-clip-text text-xl font-black uppercase tracking-[.14em] text-transparent">{t('spending.title')}</h2>
        <p className="relative mt-1 text-[9px] font-black uppercase tracking-[.28em] text-amber-100/80">{t('spending.subtitle')}</p>

        {featured?(
          <p className="relative mt-2 text-[11px] leading-snug text-slate-300">{t('spending.body')}</p>
        ):null}

        <div className="relative mt-3 flex items-center justify-center gap-2">
          <span className="rounded-full border border-emerald-300/30 bg-emerald-500/10 px-2.5 py-1 text-[8px] font-black uppercase tracking-[.16em] text-emerald-200">{t('spending.liveRankingBadge')}</span>
          <span className="rounded-full border border-amber-300/30 bg-amber-500/10 px-2.5 py-1 text-[8px] font-black uppercase tracking-[.16em] text-amber-200">{t('spending.fcTonCount')}</span>
        </div>

        <div className="relative mt-3 grid grid-cols-2 gap-2">
          <div className="rounded-2xl border border-white/10 bg-black/50 px-2 py-2">
            <p className="text-[7px] font-black uppercase tracking-[.2em] text-slate-400">{t('spending.yourScore')}</p>
            <p className="mt-0.5 text-base font-black text-amber-200">{abbreviatePoints(points)}<span className="ml-1 text-[8px] text-amber-200/60">PTS</span></p>
          </div>
          <div className="rounded-2xl border border-white/10 bg-black/50 px-2 py-2">
            <p className="text-[7px] font-black uppercase tracking-[.2em] text-slate-400">{t('spending.yourRankLabel')}</p>
            <p className="mt-0.5 text-base font-black text-sky-200">{rank?`#${rank}`:'—'}</p>
          </div>
        </div>

        {points>0?(
          reward?<p className="relative mt-2 text-[9px] font-bold uppercase tracking-[.14em] text-emerald-200">{t('spending.estReward')} · {reward}</p>:null
        ):(
          <p className="relative mt-2 text-[9px] font-black uppercase tracking-[.16em] text-amber-100/80">{t('spending.startClimbing')}</p>
        )}

        <p className="relative mt-3 text-[8px] font-black uppercase tracking-[.24em] text-slate-400">{t('spending.endsInLabel')} <span className="text-amber-200">{ends}</span></p>

        <button type="button" onClick={onView} className="relative mt-3 w-full rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-3 text-[11px] font-black uppercase tracking-[.18em] text-black active:scale-[.98]">
          {t('spending.viewEvent')}
        </button>
      </div>
    </div>
  );
}
