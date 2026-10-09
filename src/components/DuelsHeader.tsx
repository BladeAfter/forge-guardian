import { Shield, Swords, Ticket, Trophy } from 'lucide-react';
import { OceanControl } from './OceanControl';
import { duelArt } from '../gameAssets';

export function DuelsHeader({ league, power, tickets, trophies, onBuy }: {
  league: string; power: number; tickets: number; trophies: number; onBuy: () => void;
}) {
  return <>
    <div className="duels-deck">
      <img src={duelArt.deck} alt="Convés de batalha no porto pirata" />
      <div className="duels-deck-title"><span>MYTHIC SEAS · PVP</span><h2>Duelos do Convés</h2><p><Trophy size={14} />{trophies.toLocaleString('pt-BR')} troféus</p></div>
    </div>
    <div className="duels-stats">
      <div><Shield size={19} /><span>Liga<strong>{league}</strong></span></div>
      <div><Swords size={19} /><span>Poder<strong>{power.toLocaleString('pt-BR')}</strong></span></div>
      <div><Ticket size={19} /><span>Ingressos<strong>{tickets.toLocaleString('pt-BR')}</strong></span><OceanControl onClick={onBuy} aria-label="Comprar ingressos" title="Comprar ingressos">+</OceanControl></div>
    </div>
  </>;
}