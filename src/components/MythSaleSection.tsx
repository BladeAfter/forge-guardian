import { useState } from 'react';
import { MythTokenSalePanel } from './MythTokenSalePanel';
import { MythTokenEventPanel } from './MythTokenEventPanel';

/**
 * MYTH TOKEN SALE screen wrapper: keeps the original sale panel untouched and adds the
 * premium TOKEN EVENT sub-tab beside it.
 */
export function MythSaleSection({ telegramInitData, onGoToWallet }: { telegramInitData: string; onGoToWallet?: () => void }) {
  const [view, setView] = useState<'sale' | 'event'>('sale');
  return (
    <div>
      <div className="mb-3 grid grid-cols-2 gap-1.5 rounded-2xl border border-amber-300/25 bg-black/55 p-1">
        <button onClick={() => setView('sale')} className={`rounded-xl py-2 text-[9px] font-black uppercase tracking-[.14em] ${view === 'sale' ? 'bg-gradient-to-r from-amber-400 to-yellow-200 text-black' : 'text-amber-200/70'}`}>MYTH SALE</button>
        <button onClick={() => setView('event')} className={`rounded-xl py-2 text-[9px] font-black uppercase tracking-[.14em] ${view === 'event' ? 'bg-gradient-to-r from-amber-500 to-yellow-300 text-black shadow-[0_0_18px_rgba(245,158,11,.4)]' : 'text-amber-200/70'}`}>✦ TOKEN EVENT</button>
      </div>
      {view === 'sale'
        ? <MythTokenSalePanel telegramInitData={telegramInitData} />
        : <MythTokenEventPanel telegramInitData={telegramInitData} onGoToSale={() => setView('sale')} onGoToWallet={onGoToWallet} />}
    </div>
  );
}
