import { useEffect, useState } from 'react';
import { Loader2, Sparkle, Wallet } from 'lucide-react';
import { rewardCategory, type RewardCategoryId } from './RouletteRewardKit';
import { formatCurrency } from '../utils';

/**
 * Cinematic fullscreen reward reveal for the Global Mystery Roulette.
 * It takes over the whole screen after the spin: the wheel stays only as a
 * blurred, darkened backdrop behind this overlay. Everything shown here comes
 * from the reward the backend already granted.
 */

export type RevealReward = {
  categoryId: RewardCategoryId;
  /** Reward headline, e.g. "MYTH TOKEN" or the hero name. */
  name: string;
  /** Optional amount line, e.g. "750 MYTH". */
  amount?: string | null;
  /** Where the reward landed. */
  destination: string;
};

const AURA: Record<RewardCategoryId, { burst: string; halo: string; frame: string; label: string }> = {
  MYTH: {
    burst: 'from-amber-300/45 via-sky-500/25 to-transparent',
    halo: 'bg-amber-300/25',
    frame: 'border-amber-300/70 shadow-[0_0_60px_rgba(251,191,36,0.35)]',
    label: 'text-amber-200',
  },
  CHEST: {
    burst: 'from-amber-200/50 via-amber-500/25 to-transparent',
    halo: 'bg-amber-400/25',
    frame: 'border-amber-200/70 shadow-[0_0_60px_rgba(245,158,11,0.4)]',
    label: 'text-amber-100',
  },
  GEAR: {
    burst: 'from-fuchsia-400/45 via-violet-600/25 to-transparent',
    halo: 'bg-fuchsia-500/25',
    frame: 'border-fuchsia-300/70 shadow-[0_0_60px_rgba(192,110,255,0.4)]',
    label: 'text-fuchsia-200',
  },
  MYSTERY: {
    burst: 'from-violet-400/45 via-indigo-700/30 to-transparent',
    halo: 'bg-violet-600/30',
    frame: 'border-violet-300/70 shadow-[0_0_60px_rgba(139,92,246,0.45)]',
    label: 'text-violet-200',
  },
  CELESTIAL: {
    burst: 'from-white/60 via-sky-300/30 to-transparent',
    halo: 'bg-sky-200/30',
    frame: 'border-white/80 shadow-[0_0_80px_rgba(190,225,255,0.55)]',
    label: 'text-sky-50',
  },
};

/** Deterministic decorative particles — no layout shift, no random re-renders. */
const PARTICLES = Array.from({ length: 18 }, (_, i) => ({
  left: `${(i * 37) % 96 + 2}%`,
  top: `${(i * 61) % 88 + 6}%`,
  size: 3 + (i % 3) * 2,
  delay: `${(i % 7) * 0.32}s`,
  duration: `${2.6 + (i % 5) * 0.45}s`,
}));

export function RouletteRewardReveal({
  reward,
  cost,
  busy,
  usesWallet,
  canSpin,
  onClaim,
  onSpinAgain,
}: {
  reward: RevealReward;
  cost: number;
  busy: boolean;
  usesWallet: boolean;
  canSpin: boolean;
  onClaim: () => void;
  onSpinAgain: () => void;
}) {
  const category = rewardCategory(reward.categoryId);
  const aura = AURA[reward.categoryId];
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const id = window.setTimeout(() => setShown(true), 40);
    return () => window.clearTimeout(id);
  }, []);

  return (
    <div className="absolute inset-0 z-40 flex flex-col overflow-hidden bg-[#04060d]/92 backdrop-blur-md">
      {/* CINEMATIC BACKGROUND — reveal burst, light rays and floating particles */}
      <div className="pointer-events-none absolute inset-0">
        <div className={`absolute left-1/2 top-[42%] h-[130vw] w-[130vw] -translate-x-1/2 -translate-y-1/2 rounded-full bg-gradient-radial bg-[radial-gradient(circle,var(--tw-gradient-stops))] ${aura.burst} opacity-80 blur-2xl transition-transform duration-1000 ${shown ? 'scale-100' : 'scale-50'}`} />
        <div
          className="absolute left-1/2 top-[42%] h-[150vw] w-[150vw] -translate-x-1/2 -translate-y-1/2 opacity-25 animate-[spin_28s_linear_infinite]"
          style={{
            background:
              'repeating-conic-gradient(from 0deg, rgba(255,255,255,0.16) 0deg 3deg, transparent 3deg 15deg)',
            maskImage: 'radial-gradient(circle, black 12%, transparent 62%)',
            WebkitMaskImage: 'radial-gradient(circle, black 12%, transparent 62%)',
          }}
        />
        {PARTICLES.map((p, i) => (
          <span
            key={i}
            className="absolute rounded-full bg-sky-100/80 shadow-[0_0_10px_rgba(190,225,255,0.9)] animate-[fade-in_1s_ease-out_both,pulse_var(--d)_ease-in-out_infinite]"
            style={{
              left: p.left,
              top: p.top,
              width: p.size,
              height: p.size,
              animationDelay: p.delay,
              ['--d' as string]: p.duration,
            }}
          />
        ))}
      </div>

      <div
        className="relative mx-auto flex w-full max-w-md flex-1 flex-col items-center justify-between px-5"
        style={{
          paddingTop: 'calc(env(safe-area-inset-top, 0px) + 1.6rem)',
          paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + 1.2rem)',
        }}
      >
        {/* TITLE */}
        <div className={`text-center transition-all duration-700 ${shown ? 'translate-y-0 opacity-100' : '-translate-y-3 opacity-0'}`}>
          <p className="text-[10px] font-black uppercase tracking-[0.5em] text-amber-300/90">Mythic Seas</p>
          <h2 className="mt-1 bg-gradient-to-b from-amber-100 via-amber-300 to-amber-500 bg-clip-text text-[30px] font-black uppercase leading-none tracking-[0.14em] text-transparent drop-shadow-[0_0_22px_rgba(251,191,36,0.45)]">
            You won
          </h2>
          <p className="mt-1 text-[9px] font-bold uppercase tracking-[0.32em] text-sky-200/70">Global Mystery Roulette</p>
        </div>

        {/* CENTER PEDESTAL */}
        <div className={`relative my-4 w-full transition-all duration-700 ${shown ? 'scale-100 opacity-100' : 'scale-90 opacity-0'}`}>
          <div className={`absolute -inset-6 rounded-[40px] ${aura.halo} blur-3xl`} />
          <div className={`relative overflow-hidden rounded-[28px] border-2 bg-gradient-to-b from-[#0a1020]/95 to-[#04060d]/95 px-5 pb-6 pt-7 text-center ${aura.frame}`}>
            {/* inner gold hairline frame */}
            <span className="pointer-events-none absolute inset-[6px] rounded-[22px] border border-amber-200/20" aria-hidden />

            <span className={`pointer-events-none absolute left-1/2 top-0 h-40 w-40 -translate-x-1/2 -translate-y-1/2 rounded-full ${aura.halo} blur-2xl`} aria-hidden />

            <p className={`relative text-[10px] font-black uppercase tracking-[0.34em] ${aura.label}`}>{category.name}</p>

            <div className="relative mx-auto mt-4 grid h-40 w-40 place-items-center">
              <span className={`absolute inset-0 rounded-full ${aura.halo} blur-xl animate-pulse`} aria-hidden />
              <span className="absolute inset-2 rounded-full border border-amber-200/25" aria-hidden />
              <img
                src={category.icon}
                alt={category.name}
                className={`relative h-36 w-36 object-contain drop-shadow-[0_10px_30px_rgba(0,0,0,0.75)] ${category.anim}`}
              />
            </div>

            {/* pedestal light */}
            <div className="relative mx-auto mt-1 h-2 w-32 rounded-full bg-gradient-to-r from-transparent via-amber-200/60 to-transparent blur-[2px]" />

            <p className="relative mt-4 text-[17px] font-black uppercase leading-tight tracking-[0.08em] text-sky-50">
              {reward.name}
            </p>
            {reward.amount ? (
              <p className="relative mt-1 bg-gradient-to-r from-amber-200 via-amber-300 to-amber-100 bg-clip-text text-[26px] font-black leading-none tracking-tight text-transparent drop-shadow-[0_0_18px_rgba(251,191,36,0.35)]">
                {reward.amount}
              </p>
            ) : null}
            <p className="relative mt-3 text-[10px] font-bold uppercase tracking-[0.16em] text-slate-400">
              {reward.destination}
            </p>
          </div>
        </div>

        {/* ACTIONS */}
        <div className={`w-full space-y-2.5 transition-all duration-700 ${shown ? 'translate-y-0 opacity-100' : 'translate-y-4 opacity-0'}`}>
          <button
            type="button"
            onClick={onClaim}
            className="w-full rounded-2xl border border-amber-200/50 bg-gradient-to-r from-amber-400 via-amber-300 to-amber-400 py-4 text-[14px] font-black uppercase tracking-[0.2em] text-[#1b1204] shadow-[0_10px_30px_rgba(251,191,36,0.35)] active:scale-[0.99]"
          >
            Resgatar recompensa
          </button>
          <button
            type="button"
            onClick={onSpinAgain}
            disabled={!canSpin || busy}
            className="flex w-full items-center justify-center gap-2 rounded-2xl border border-sky-300/35 bg-sky-500/10 py-3.5 text-[12px] font-black uppercase tracking-[0.18em] text-sky-100 disabled:opacity-40"
          >
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : usesWallet ? <Wallet className="h-4 w-4" /> : <Sparkle className="h-4 w-4" />}
            Girar de novo • {cost} TON
          </button>
        </div>
      </div>
    </div>
  );
}

/** Builds the reveal payload from the granted reward (name, amount and destination). */
export function buildReveal(
  categoryId: RewardCategoryId,
  opts: { name: string; amount?: number | null },
): RevealReward {
  if (categoryId === 'MYTH') {
    return {
      categoryId,
      name: 'MYTH TOKEN',
      amount: `${formatCurrency(Number(opts.amount ?? 0))} MYTH`,
      destination: 'Adicionado ao seu saldo MYTH',
    };
  }
  return {
    categoryId,
    name: opts.name,
    amount: null,
    destination: 'Adicionado diretamente ao seu inventário',
  };
}
