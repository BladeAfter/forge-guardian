import { useState } from 'react';
import { X } from 'lucide-react';
import { mythToken, mythTokenCard } from '../gameAssets';
import type { MythWallet } from '../wallet';

/**
 * MYTH Token — purely decorative for now.
 *
 * The whole supply lives with the Admin Bot: nothing here buys, sells, swaps,
 * withdraws or converts MYTH, and no price/market data is ever displayed.
 * The card only mirrors the read-only balance returned by the backend.
 */
const formatMyth = (value: number) =>
  Number(value ?? 0).toLocaleString('en-US', { maximumFractionDigits: 4 });

export function MythTokenCard({ wallet }: { wallet?: MythWallet | null }) {
  const [open, setOpen] = useState(false);
  if (!wallet || wallet.visible === false) return null;
  const name = wallet.name || 'MYTH Token';
  const symbol = wallet.symbol || 'MYTH';

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex w-full items-center gap-3 rounded-2xl border border-amber-400/30 bg-gradient-to-r from-black/80 via-indigo-950/60 to-black/80 p-3 text-left shadow-[inset_0_0_24px_rgba(129,140,248,.14)]"
      >
        <img
          src={mythToken}
          alt={name}
          loading="lazy"
          width={64}
          height={64}
          className="h-11 w-11 shrink-0 object-contain drop-shadow-[0_0_10px_rgba(251,191,36,.45)]"
        />
        <span className="min-w-0 flex-1">
          <span className="block truncate text-[11px] font-black uppercase tracking-[.14em] text-amber-100">{name}</span>
          <span className="block text-[10px] uppercase tracking-[.12em] text-indigo-300">Official Mythreon Token</span>
          {staked > 0 ? (
            <span className="block text-[9px] font-black uppercase tracking-[.14em] text-emerald-300">Staked {formatMyth(staked)} {symbol}</span>
          ) : null}
        </span>
        <span className="shrink-0 text-right">
          <span className="block text-base font-black text-white">{formatMyth(owned)}</span>
          <span className="block text-[9px] font-black uppercase tracking-[.16em] text-amber-300">{symbol}</span>
        </span>
      </button>


      {open ? (
        <div className="fixed inset-0 z-50 grid place-items-center bg-black/80 p-4" role="dialog" aria-modal="true">
          <div className="w-full max-w-sm overflow-hidden rounded-3xl border border-amber-400/30 bg-forge-surface shadow-card">
            <div className="relative">
              <img src={mythTokenCard} alt={name} loading="lazy" width={1536} height={1024} className="h-36 w-full object-cover" />
              <span className="absolute right-2 top-2 rounded-full border border-amber-400/50 bg-black/70 px-2 py-1 text-[9px] font-black uppercase tracking-[.16em] text-amber-200">
                Coming Soon
              </span>
            </div>
            <div className="space-y-3 p-4">
              <div className="flex items-center gap-3">
                <img src={mythToken} alt="" loading="lazy" width={64} height={64} className="h-12 w-12 object-contain" />
                <div>
                  <p className="text-sm font-black uppercase tracking-[.14em] text-amber-100">{name}</p>
                  <p className="text-[10px] uppercase tracking-[.12em] text-indigo-300">Official Mythreon Token · Future Utility</p>
                </div>
              </div>
              <p className="text-xs leading-relaxed text-slate-300">
                Official Mythreon token. Utility coming in future updates. Currently decorative only.
              </p>
              <div className="grid grid-cols-2 gap-2 text-center">
                <div className="rounded-xl border border-white/10 bg-black/50 p-2">
                  <p className="text-[9px] uppercase tracking-[.14em] text-slate-400">Total Supply</p>
                  <p className="text-sm font-black text-white">{formatMyth(wallet.totalSupply)}</p>
                </div>
                <div className="rounded-xl border border-white/10 bg-black/50 p-2">
                  <p className="text-[9px] uppercase tracking-[.14em] text-slate-400">Your Balance</p>
                  <p className="text-sm font-black text-white">{formatMyth(wallet.balance)} {symbol}</p>
                </div>
              </div>
              <p className="text-center text-[9px] font-black uppercase tracking-[.16em] text-slate-500">
                Decorative Only · Not Tradable Yet
              </p>
              <button
                type="button"
                onClick={() => setOpen(false)}
                className="flex w-full items-center justify-center gap-2 rounded-xl border border-amber-400/40 bg-black/70 py-2 text-xs font-black uppercase tracking-[.14em] text-amber-200"
              >
                <X className="h-4 w-4" /> Close
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}
