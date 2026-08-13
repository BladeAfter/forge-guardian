import { useState } from 'react';
import { Sparkles, Loader2, Check } from 'lucide-react';
import { useTranslator } from '../LanguageContext';

/** Official art already used elsewhere in the game (no duplicated assets). */
const FC_ART = '/assets/game/ui/forge-coin.png';
const EGG_ART = '/assets/game/pet-eggs/common-egg.webp';
const CHEST_ART = '/assets/game/chests/common-chest.png';

type Props = {
  /** Server-side delivery. Must resolve only after the backend confirmed the claim. */
  onClaim: () => Promise<void>;
  /** Called after the short "claimed" animation, to close the popup. */
  onDone: () => void;
};

/**
 * Welcome / Starter Pack popup for accounts created on/after 2026-08-13 (UTC-3).
 * The rewards are ONLY granted by the backend: on failure the popup stays open
 * so the player can retry, and nothing is marked as claimed.
 */
export function StarterPackPopup({ onClaim, onDone }: Props) {
  const t = useTranslator();
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
    { art: FC_ART, glyph: '💰', label: 'FC', value: (50000).toLocaleString() },
    { art: EGG_ART, glyph: '🥚', label: t('starterEgg'), value: '×1' },
    { art: CHEST_ART, glyph: '🎁', label: t('starterChest'), value: '×2' },
  ];

  return (
    <div className="fixed inset-0 z-[200] flex items-center justify-center bg-black/85 p-4 backdrop-blur-sm">
      <div className="relative w-full max-w-sm overflow-hidden rounded-[1.9rem] border border-amber-300/50 bg-gradient-to-b from-[#0a1024] via-[#050914] to-black p-5 shadow-[0_0_60px_rgba(251,191,36,0.22)]">
        <div className="pointer-events-none absolute -top-24 left-1/2 h-48 w-48 -translate-x-1/2 rounded-full bg-amber-300/20 blur-3xl" />
        <div className="relative text-center">
          <Sparkles className="mx-auto h-8 w-8 text-amber-300" />
          <h2 className="mt-2 text-xl font-black uppercase tracking-[.12em] text-amber-300">🎁 {t('starterTitle')}</h2>
          <p className="mt-1 text-[11px] text-slate-300">{t('starterSubtitle')}</p>

          <p className="mt-4 text-[9px] font-black uppercase tracking-[.28em] text-slate-500">{t('starterRewards')}</p>
          <div className="mt-2 grid grid-cols-3 gap-2">
            {cards.map((c) => (
              <div key={c.label} className="rounded-2xl border border-amber-300/25 bg-black/60 p-2">
                <div className="mx-auto grid h-14 w-14 place-items-center overflow-hidden rounded-xl bg-black/50">
                  <img
                    src={c.art}
                    alt={c.label}
                    loading="lazy"
                    className="h-full w-full object-contain"
                    onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = 'none'; }}
                  />
                  <span className="pointer-events-none -mt-14 text-2xl">{c.glyph}</span>
                </div>
                <p className="mt-1.5 text-[13px] font-black text-amber-200">{c.value}</p>
                <p className="text-[9px] font-bold uppercase leading-tight tracking-[.1em] text-slate-400">{c.label}</p>
              </div>
            ))}
          </div>

          {error ? <p className="mt-3 rounded-xl bg-rose-500/15 p-2 text-[11px] font-semibold text-rose-300">{error}</p> : null}

          {state === 'done' ? (
            <div className="mt-5 flex items-center justify-center gap-2 rounded-xl border border-emerald-400/40 bg-emerald-500/15 py-3.5 text-sm font-black text-emerald-300">
              <Check className="h-5 w-5" /> {t('starterClaimed')}
            </div>
          ) : (
            <button
              type="button"
              onClick={claim}
              disabled={state === 'loading'}
              className="mt-5 flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-b from-amber-300 to-orange-500 py-3.5 text-sm font-black text-black disabled:opacity-70"
            >
              {state === 'loading' ? <><Loader2 className="h-4 w-4 animate-spin" /> {t('starterClaiming')}</> : t('starterClaim')}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
