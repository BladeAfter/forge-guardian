import { useState } from 'react';
import { Loader2, Check } from 'lucide-react';
import { useT } from '../LanguageContext';
import EMBLEM from '../assets/starter/emblem.webp';
import PANEL_BG from '../assets/starter/panel-bg.jpg';
import COINS_ART from '../assets/starter/coins.webp';
import EGG_ART from '../assets/starter/egg.webp';
import CHEST_ART from '../assets/starter/chest.webp';

type Props = {
  /** Server-side delivery. Must resolve only after the backend confirmed the claim. */
  onClaim: () => Promise<void>;
  /** Called after the short "claimed" animation, to close the popup. */
  onDone: () => void;
};

/** Small gold diamond divider used between the ornate sections. */
const Diamond = () => (
  <span className="mx-2 inline-block h-2 w-2 rotate-45 bg-gradient-to-br from-sky-200 to-blue-600 shadow-[0_0_8px_rgba(96,165,250,.8)]" />
);

const Rule = ({ children }: { children?: React.ReactNode }) => (
  <div className="flex items-center justify-center">
    <span className="h-px flex-1 bg-gradient-to-r from-transparent via-amber-300/50 to-amber-300/70" />
    {children ?? <Diamond />}
    <span className="h-px flex-1 bg-gradient-to-l from-transparent via-amber-300/50 to-amber-300/70" />
  </div>
);

/**
 * Welcome / Starter Pack popup for accounts created on/after 2026-08-13 (UTC-3).
 * The rewards are ONLY granted by the backend: on failure the popup stays open
 * so the player can retry, and nothing is marked as claimed.
 */
export function StarterPackPopup({ onClaim, onDone }: Props) {
  const t = useT();
  const [state, setState] = useState<'idle' | 'loading' | 'done'>('idle');
  const [error, setError] = useState<string | null>(null);

  const claim = async () => {
    if (state !== 'idle') return;
    setError(null);
    setState('loading');
    try {
      await onClaim();
      setState('done');
      window.setTimeout(onDone, 1500);
    } catch {
      setState('idle');
      setError(t('starterError'));
    }
  };

  const cards = [
    { art: COINS_ART, label: 'FC', value: (50000).toLocaleString('pt-BR') },
    { art: EGG_ART, label: t('starterEgg'), value: '×1' },
    { art: CHEST_ART, label: t('starterChest'), value: '×5' },
  ];

  return (
    <div className="fixed inset-0 z-[200] flex items-center justify-center bg-black/90 p-4 backdrop-blur-sm">
      <div className="relative w-full max-w-[360px]">
        {/* Crest floating over the frame */}
        <img
          src={EMBLEM}
          alt=""
          width={816}
          height={816}
          className="pointer-events-none absolute -top-[62px] left-1/2 z-20 h-[124px] w-[124px] -translate-x-1/2 object-contain drop-shadow-[0_0_26px_rgba(251,191,36,.55)]"
        />

        {/* Ornate double frame */}
        <div className="relative rounded-[26px] bg-gradient-to-b from-amber-200/90 via-amber-500/60 to-amber-800/70 p-[2px] shadow-[0_0_70px_rgba(251,191,36,.28)]">
          <div className="relative overflow-hidden rounded-[24px] border border-amber-200/40">
            <img src={PANEL_BG} alt="" loading="lazy" className="absolute inset-0 h-full w-full object-cover opacity-90" />
            <div className="absolute inset-0 bg-gradient-to-b from-[#060b1a]/80 via-[#060b1a]/70 to-black/90" />

            <div className="relative px-5 pb-5 pt-[74px] text-center">
              <h2 className="bg-gradient-to-b from-amber-100 via-amber-300 to-amber-600 bg-clip-text font-serif text-[30px] font-black uppercase leading-[1.05] tracking-[.04em] text-transparent drop-shadow-[0_2px_0_rgba(0,0,0,.6)]">
                {t('starterTitle')}
              </h2>
              <p className="mt-2 font-serif text-[13px] text-slate-200">{t('starterSubtitle')}</p>

              <div className="mt-3">
                <Rule />
              </div>

              <p className="mt-3 flex items-center justify-center font-serif text-[11px] font-black uppercase tracking-[.3em] text-amber-300">
                <span className="mr-2 h-px w-6 bg-amber-300/60" />
                {t('starterRewards')}
                <span className="ml-2 h-px w-6 bg-amber-300/60" />
              </p>

              <div className="mt-3 grid grid-cols-3 gap-2">
                {cards.map((c) => (
                  <div
                    key={c.label}
                    className="relative rounded-[14px] border border-amber-300/45 bg-gradient-to-b from-[#0d1428]/90 to-black/80 p-2 shadow-[inset_0_0_24px_-12px_rgba(251,191,36,.7)]"
                  >
                    <img src={c.art} alt={c.label} loading="lazy" width={816} height={816} className="mx-auto h-16 w-16 object-contain drop-shadow-[0_4px_10px_rgba(0,0,0,.6)]" />
                    <p className="mt-1 font-serif text-[15px] font-black text-amber-300">{c.value}</p>
                    <p className="font-serif text-[10px] font-bold uppercase leading-tight tracking-[.06em] text-slate-200">{c.label}</p>
                    <div className="mt-1.5">
                      <Rule>
                        <span className="mx-1 inline-block h-1.5 w-1.5 rotate-45 bg-amber-300/80" />
                      </Rule>
                    </div>
                  </div>
                ))}
              </div>

              {error ? (
                <p className="mt-3 rounded-xl border border-rose-400/30 bg-rose-500/15 p-2 text-[11px] font-semibold text-rose-300">{error}</p>
              ) : null}

              {state === 'done' ? (
                <div className="mt-4 flex items-center justify-center gap-2 rounded-[12px] border border-emerald-300/60 bg-gradient-to-b from-emerald-400/25 to-emerald-800/30 py-3.5 font-serif text-base font-black uppercase tracking-[.08em] text-emerald-200">
                  <Check className="h-5 w-5" /> {t('starterClaimed')}
                </div>
              ) : (
                <button
                  type="button"
                  onClick={claim}
                  disabled={state === 'loading'}
                  className="mt-4 w-full rounded-[12px] border-2 border-amber-200/80 bg-gradient-to-b from-amber-200 via-amber-400 to-amber-600 py-3.5 font-serif text-lg font-black uppercase tracking-[.06em] text-[#3a2306] shadow-[0_0_30px_rgba(251,191,36,.45),inset_0_1px_0_rgba(255,255,255,.6)] transition active:scale-[.98] disabled:opacity-70"
                >
                  {state === 'loading' ? (
                    <span className="flex items-center justify-center gap-2">
                      <Loader2 className="h-4 w-4 animate-spin" /> {t('starterClaiming')}
                    </span>
                  ) : (
                    t('starterClaim')
                  )}
                </button>
              )}
            </div>

            {/* Bottom gem accent */}
            <span className="absolute bottom-0 left-1/2 h-3 w-3 -translate-x-1/2 translate-y-1/2 rotate-45 border border-amber-200/70 bg-gradient-to-br from-sky-200 to-blue-700 shadow-[0_0_10px_rgba(96,165,250,.8)]" />
          </div>
        </div>
      </div>
    </div>
  );
}
