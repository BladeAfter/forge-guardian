import { X } from 'lucide-react';
import { FounderPackCard } from './FounderPackCard';
import { VeteranVaultV2Card } from './VeteranVaultV2Card';
import { CelestialPackCard } from './CelestialPackCard';
import { MythicVanguardPackCard } from './MythicVanguardPackCard';
import { LegendaryAdventurerPackCard } from './LegendaryAdventurerPackCard';


/**
 * 💎 OFERTAS PREMIUM — acesso permanente aos pacotes Founder Pack (35 TON) e Veteran Vault (100 TON).
 *
 * Os cards decidem sozinhos se aparecem: o servidor manda `show` em cada estado. Assim o jogador
 * pode abrir a qualquer momento, mesmo depois de fechar o popup diário.
 */
export function PremiumOffersModal({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  return (
    <div className="fullscreen-page overflow-y-auto p-4">
      <div className="mx-auto w-full max-w-[440px] space-y-3 pb-10">
        <div className="flex items-center justify-between rounded-2xl border border-amber-300/25 bg-[#090d15]/95 px-4 py-3">
          <div>
            <p className="text-[10px] font-black uppercase tracking-[0.28em] text-amber-300">MYTHREON</p>
            <h2 className="text-lg font-black text-white">OFERTAS PREMIUM</h2>
          </div>
          <button onClick={onClose} aria-label="Fechar" className="grid h-9 w-9 place-items-center rounded-full bg-white/5">
            <X className="h-4 w-4" />
          </button>
        </div>

        <FounderPackCard telegramInitData={telegramInitData} />
        <VeteranVaultV2Card telegramInitData={telegramInitData} />
        <CelestialPackCard telegramInitData={telegramInitData} />
        <MythicVanguardPackCard telegramInitData={telegramInitData} />
        <LegendaryAdventurerPackCard telegramInitData={telegramInitData} />


        <p className="rounded-2xl border border-white/10 bg-black/50 px-4 py-3 text-center text-[10px] uppercase tracking-[0.16em] text-slate-400">
          Pacotes disponíveis enquanto houver estoque de MYTH no servidor.
        </p>
      </div>
    </div>
  );
}
