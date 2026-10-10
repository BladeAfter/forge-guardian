import { useLocalizedText } from '../LanguageContext';
import { useEffect, useState } from 'react';
import { Anchor, ArrowLeft, ArrowRight, ChevronLeft, Heart, LockKeyhole, Shield, Sword, Users, X } from 'lucide-react';
import type { PvpHero } from '../pvp';
import { crewArt } from '../gameAssets';
import { captainCharacters, readCaptainStyle } from '../captainCharacter';
import { OceanControl } from './OceanControl';
import { HeroEquipmentSlots } from './HeroEquipmentSlots';

const roles: Record<PvpHero['archetype'], string> = { warrior: 'Espadachim', assassin: 'Explorador', tank: 'Lutador', mage: 'Navegador', archer: 'Atirador', support: 'Médico' };
export const crewRole = (hero: PvpHero) => roles[hero.archetype] ?? 'Tripulante';
type Props = { heroes: PvpHero[]; telegramInitData: string; telegramId?: string; onClose: () => void; loading?: boolean; error?: string; onRetry?: () => void };

/** Deck positions and role labels are cosmetic; equipment and XP remain server-owned. */
export function CrewDeck({ heroes, telegramInitData, telegramId, onClose, loading, error, onRetry }: Props) {
  const localizeText = useLocalizedText();

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const [sheet, setSheet] = useState<'train' | 'equip' | 'details' | null>(null);
  const captain = heroes[0];
  const selected = heroes.find(h => h.heroId === selectedId) ?? captain;
  const pageCount = Math.max(1, Math.ceil(Math.max(0, heroes.length - 1) / 4));
  const safePage = Math.min(page, pageCount - 1);
  const members = heroes.slice(1 + safePage * 4, 5 + safePage * 4);
  const character = captainCharacters[readCaptainStyle(telegramId)];
  useEffect(() => { setSheet(null); }, [selectedId]);
  const select = (hero: PvpHero) => { setSelectedId(hero.heroId); setSheet(null); };
  const xp = selected?.xp ?? 0;
  const need = selected?.xpToNext ?? 0;
  const maxed = selected?.maxLevel != null && selected.level >= selected.maxLevel;

  return <main className="seas-crew">
    <div className={`crew-world ${selectedId ? 'crew-world-focused' : ''}`}>
      <img className="crew-deck-background" src={crewArt.deck} alt={localizeText("Convés do navio no mar tropical")} width={1536} height={1024} />
      <div className="crew-light" />
      <div className="crew-stage">
        {captain ? <OceanControl className={`crew-person crew-captain ${selected?.heroId === captain.heroId ? 'crew-person-selected' : ''}`} aria-label={`Selecionar capitão ${captain.name}`} aria-pressed={selected?.heroId === captain.heroId} onClick={() => select(captain)}>
          <img src={captain.imageUrl} alt={captain.name} width={512} height={512} /><span><small>{localizeText("CAPITÃO")}</small><b>{captain.name}</b><em>{localizeText("Nível ")}{captain.level}</em></span>
        </OceanControl> : <div className="crew-person crew-captain crew-profile-captain"><img src={character.image} alt={localizeText("Capitão do perfil")} width={512} height={512} /><span><small>{localizeText("CAPITÃO")}</small><b>{localizeText("Seu capitão")}</b></span></div>}
        {members.map((hero, i) => <OceanControl key={hero.heroId} className={`crew-person crew-position-${i} ${selected?.heroId === hero.heroId ? 'crew-person-selected' : ''}`} aria-label={`Selecionar ${hero.name}`} aria-pressed={selected?.heroId === hero.heroId} onClick={() => select(hero)}>
          <img src={hero.imageUrl} alt={hero.name} width={512} height={512} /><span><small>{crewRole(hero)}</small><b>{hero.name}</b><em>{localizeText("Nível ")}{hero.level}</em></span>
        </OceanControl>)}
      </div>
    </div>
    <header className="crew-header"><div><span>MYTHIC SEAS</span><h1>{localizeText("TRIPULAÇÃO")}</h1><p><Anchor size={12} /> {localizeText("A bordo · ")}{heroes.length} {heroes.length === 1 ? 'membro' : 'membros'}</p></div><OceanControl onClick={onClose} aria-label={localizeText("Fechar tripulação")} title={localizeText("Voltar ao porto")}><X size={20} /></OceanControl></header>
    {pageCount > 1 ? <nav className="crew-watch" aria-label={localizeText("Turnos da tripulação")}><OceanControl aria-label={localizeText("Membros anteriores")} disabled={safePage === 0} onClick={() => {setPage(safePage - 1);setSelectedId(null);}}><ArrowLeft size={16}/></OceanControl><span><Users size={14}/> {safePage + 1} / {pageCount}</span><OceanControl aria-label={localizeText("Próximos membros")} disabled={safePage >= pageCount - 1} onClick={() => {setPage(safePage + 1);setSelectedId(null);}}><ArrowRight size={16}/></OceanControl></nav> : null}
    <section className="crew-command" aria-live="polite">
      {error ? <div className="crew-empty"><p>{error}</p><OceanControl onClick={onRetry}>{localizeText("Tentar novamente")}</OceanControl></div> : loading ? <p className="crew-empty">{localizeText("Preparando o convés…")}</p> : !selected ? <div className="crew-empty"><Anchor size={24}/><h2>{localizeText("Uma nova viagem começa")}</h2><p>{localizeText("Sua tripulação ainda está por chegar.")}</p></div> : <>
        <div className="crew-identity"><div><span>{selected.heroId === captain?.heroId ? localizeText("CAPITÃO") : crewRole(selected).toUpperCase()}</span><h2>{selected.name}</h2></div><b>{localizeText("Nível ")}{selected.level}</b></div>
        <div className="crew-vitals"><span><Heart size={15}/> <b>{selected.finalHp.toLocaleString('pt-BR')}</b> HP</span><span><Sword size={15}/> <b>{selected.power.toLocaleString('pt-BR')}</b> {localizeText("Poder")}</span><span><Shield size={15}/> <b>{selected.defense.toLocaleString('pt-BR')}</b> {localizeText("Defesa ")}</span></div>
        <div className="crew-actions"><OceanControl onClick={() => setSheet('train')}>{localizeText("Treinar")}</OceanControl><OceanControl onClick={() => setSheet('equip')}>{localizeText("Equipar")}</OceanControl><OceanControl onClick={() => setSheet('details')}>{localizeText("Detalhes")}</OceanControl></div>
      </>}
    </section>
    {sheet && selected ? <div className="crew-sheet-backdrop" onClick={() => setSheet(null)}><section role="dialog" aria-modal="true" aria-label={`${sheet === 'train' ? 'Treino' : sheet === 'equip' ? 'Equipamentos' : 'Detalhes'} de ${selected.name}`} className="crew-sheet" onClick={e => e.stopPropagation()}>
      <header><OceanControl aria-label={localizeText("Voltar ao convés")} onClick={() => setSheet(null)}><ChevronLeft size={18}/></OceanControl><div><span>{crewRole(selected)}</span><h2>{selected.name}</h2></div></header>
      {sheet === 'equip' ? <HeroEquipmentSlots key={selected.heroId} heroId={selected.heroId} telegramInitData={telegramInitData}/> : sheet === 'train' ? <div className="crew-training"><span>{localizeText("PROGRESSÃO · NÍVEL ")}{selected.level}</span><h3>{maxed ? localizeText("Nível máximo alcançado") : `${xp.toLocaleString('pt-BR')} / ${need.toLocaleString('pt-BR')} XP`}</h3><progress aria-label={localizeText("Experiência do tripulante")} value={maxed ? 100 : Math.min(100, need > 0 ? xp / need * 100 : 0)} max={100}/><p>{localizeText("Experiência conquistada em atividades e batalhas.")}</p>{selected.dailyXpCap ? <p>{localizeText("Hoje: ")}{selected.dailyXp ?? 0} / {selected.dailyXpCap} XP</p> : null}</div> : <div className="crew-profile"><div className="crew-profile-stats"><span>{localizeText("Ataque ")}<b>{selected.finalAtk}</b></span><span>{localizeText("Vida ")}<b>{selected.finalHp}</b></span><span>{localizeText("Defesa ")}<b>{selected.defense}</b></span><span>{localizeText("Velocidade ")}<b>{selected.speed}</b></span></div><h3>{localizeText("HABILIDADES")}</h3><p>{localizeText("Combate · Ataque ")}{selected.finalAtk.toLocaleString('pt-BR')}</p><div className="crew-powers">{['Haki', 'Fruta / Poder', 'Especial', 'Energia'].map(label => <span key={label}><LockKeyhole size={14}/>{label}<small>{localizeText("Indisponível")}</small></span>)}</div><OceanControl onClick={() => setSheet('equip')}><Sword size={16}/> {localizeText("Arma e equipamentos")}</OceanControl></div>}
    </section></div> : null}
  </main>;
}