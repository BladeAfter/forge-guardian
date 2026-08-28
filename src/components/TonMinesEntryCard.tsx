import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { ChevronRight, Pickaxe } from 'lucide-react';
import { fetchTonMines, type TonMinesState } from '../services';
import { TonMinesOverlay } from './TonMinesOverlay';
import minesArt from '../assets/mines/mines-entrance.png.asset.json';

const ton = (value: number) => Number(value || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 4 });

/**
 * Entrada das MINAS DE TON na Vila. A visibilidade é decidida pelo servidor
 * (`visible`), então enquanto o sistema estiver restrito ao administrador nenhum
 * outro jogador vê o prédio — sem flags no cliente.
 */
export function TonMinesEntryCard({ telegramInitData }: { telegramInitData: string }) {
  const [open, setOpen] = useState(false);
  const { data: state } = useQuery<TonMinesState>({
    queryKey: ['ton-mines'],
    queryFn: () => fetchTonMines(telegramInitData),
    enabled: Boolean(telegramInitData),
    retry: false,
  });

  if (!state?.visible) return null;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="relative w-full overflow-hidden rounded-3xl border border-primary/30 bg-forge-black/80 text-left shadow-card"
      >
        <img src={minesArt.url} alt="Entrada das Minas de TON" loading="lazy" className="absolute -right-4 top-0 h-full w-40 object-contain opacity-90" />
        <div className="relative space-y-2 p-4 pr-36">
          <p className="flex items-center gap-1.5 text-[10px] uppercase tracking-[0.3em] text-primary/80">
            <Pickaxe className="h-3 w-3" /> Novo
          </p>
          <h3 className="text-lg font-black uppercase tracking-wide text-foreground">Minas de TON</h3>
          <p className="text-[11px] text-muted-foreground">Compre minas permanentes e receba TON todos os dias, mesmo offline.</p>
          <div className="flex flex-wrap items-center gap-2 text-[10px] font-bold uppercase tracking-wider">
            <span className="rounded-full bg-emerald-500/15 px-2 py-1 text-emerald-300">{ton(state.summary.dailyTon)} TON / dia</span>
            <span className="rounded-full bg-white/10 px-2 py-1 text-muted-foreground">{state.summary.activeMines} ativas</span>
            {state.summary.unclaimedTon > 0 ? (
              <span className="rounded-full bg-amber-400/20 px-2 py-1 text-amber-200">{ton(state.summary.unclaimedTon)} TON prontos</span>
            ) : null}
          </div>
          <span className="inline-flex items-center gap-1 text-[11px] font-black uppercase tracking-wider text-primary">
            Entrar nas minas <ChevronRight className="h-3.5 w-3.5" />
          </span>
        </div>
      </button>
      {open ? <TonMinesOverlay telegramInitData={telegramInitData} onClose={() => setOpen(false)} /> : null}
    </>
  );
}
