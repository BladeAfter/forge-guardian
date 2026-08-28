import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { fetchTonMines, type TonMinesState } from '../services';
import { TonMinesOverlay } from './TonMinesOverlay';
import mineArt from '../assets/mines/mine-building.png.asset.json';

const ton = (value: number) => Number(value || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/**
 * MINAS DE TON como prédio real do cenário da vila (mesma linguagem visual do
 * Salão do Clã): arte recortada com sombra no chão, tochas, brilho de cristal e
 * uma pequena placa de madeira. Nada de card flutuante.
 * A visibilidade continua decidida pelo servidor (`visible`).
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
  const ready = (state.summary?.unclaimedTon ?? 0) > 0;

  return (
    <>
      <div
        role="button"
        tabIndex={0}
        onClick={() => setOpen(true)}
        onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); setOpen(true); } }}
        aria-label="Minas de TON"
        className="ton-mine"
      >
        <span className="ton-mine-ground" aria-hidden />
        <span className="ton-mine-shape" aria-hidden>
          <img src={mineArt.url} alt="" width={1024} height={1024} loading="lazy" className="ton-mine-art" />
          <span className="ton-mine-glow" />
          <span className="ton-mine-torch ton-mine-torch--left"><i /></span>
          <span className="ton-mine-torch ton-mine-torch--right"><i /></span>
          <span className="ton-mine-motes"><i /><i /><i /></span>
          {ready ? <span className="ton-mine-ready">{ton(state.summary.unclaimedTon)} TON</span> : null}
        </span>

        <span className="ton-mine-sign">
          <span className="ton-mine-sign-text">
            <b>Minas de TON</b>
            <i>{state.summary.activeMines > 0 ? `${ton(state.summary.dailyTon)} TON / dia` : 'Investir agora'}</i>
          </span>
        </span>
      </div>
      {open ? <TonMinesOverlay telegramInitData={telegramInitData} onClose={() => setOpen(false)} /> : null}
    </>
  );
}
