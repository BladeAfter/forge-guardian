import { useLocalizedText } from '../LanguageContext';
import { Shield, Swords, Ticket, Trophy } from 'lucide-react';
import { OceanControl } from './OceanControl';
import { duelArt } from '../gameAssets';

export function DuelsHeader({ league, power, tickets, trophies, onBuy }: {
  league: string; power: number; tickets: number; trophies: number; onBuy: () => void;
}) {
  const localizeText = useLocalizedText();

  return <>
    <div className="duels-deck">
      <img src={duelArt.deck} alt={localizeText("Convés de batalha no porto pirata")} />
      <div className="duels-deck-title"><span>{localizeText("MYTHIC SEAS · PVP")}</span><h2>{localizeText("Duelos do Convés")}</h2><p><Trophy size={14} />{trophies.toLocaleString('pt-BR')} {localizeText("troféus")}</p></div>
    </div>
    <div className="duels-stats">
      <div><Shield size={19} /><span>{localizeText("Liga")}<strong>{league}</strong></span></div>
      <div><Swords size={19} /><span>{localizeText("Poder")}<strong>{power.toLocaleString('pt-BR')}</strong></span></div>
      <div><Ticket size={19} /><span>{localizeText("Ingressos")}<strong>{tickets.toLocaleString('pt-BR')}</strong></span><OceanControl onClick={onBuy} aria-label={localizeText("Comprar ingressos")} title={localizeText("Comprar ingressos")}>+</OceanControl></div>
    </div>
  </>;
}