import { useLocalizedText } from '../LanguageContext';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Expand, Flame, Hand, LockKeyhole, Shield, Sparkles, Swords, Trophy, Wind, X, Zap } from 'lucide-react';
import { actionArenaArt, arenaCrewImage } from '../gameAssets';
import { readCaptainStyle } from '../captainCharacter';
import type { CombatHero } from '../combat';
import type { CombatSlot } from '../combatSlots';
import { COMBAT_SLOTS } from '../combatSlots';
import { OceanControl } from './OceanControl';
import { IslandJoystick } from './IslandJoystick';

type Props = {
  name: string; image: string; hp: number; maxHp: number; heroes: CombatHero[];
  pet: { name: string; image: string } | null; telegramId?: string; hit: boolean;
  attacking?: boolean; active: boolean; cooldown: number; bossCountdown: number | null;
  damage: number; rank: number | null; reward: number; status?: string;
  swap: string | null; onAttack?: () => Promise<void> | void;
  onEquip: (slot: CombatSlot) => void; onRanking: () => void;
};

/** Physical movement and effects are cosmetic; only the official attack callback changes combat. */
export function PirateActionArena(props: Props) {
  const localizeText = useLocalizedText();

  const { name, hp, maxHp, heroes, pet, hit, attacking, active, cooldown, onAttack } = props;
  const stage = useRef<HTMLDivElement>(null);
  const inFlight = useRef(false);
  const direction = useRef({ x: 0, y: 0 });
  const position = useRef({ x: 31, y: 76 });
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [action, setAction] = useState<'idle' | 'strike' | 'dodge'>('idle');
  const [selectedHero, setSelectedHero] = useState<string | null | undefined>(undefined);
  const [hits, setHits] = useState(0);
  const [flash, setFlash] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState(false);
  const ratio = Math.max(0, Math.min(100, maxHp > 0 ? hp / maxHp * 100 : 0));
  const phase = ratio > 75 ? 1 : ratio > 50 ? 2 : ratio > 25 ? 3 : 4;
  const firstHero = [...heroes].sort((a, b) => a.slot - b.slot)[0];
  const selected = selectedHero === null ? undefined : heroes.find(hero => hero.heroId === selectedHero) ?? firstHero;
  const captain = readCaptainStyle(props.telegramId) === 'female' ? actionArenaArt.captainFemale : actionArenaArt.captain;
  const actor = selected ? arenaCrewImage(selected) : captain;
  const ready = active && Boolean(onAttack) && !attacking && cooldown === 0 && heroes.some(hero => hero.isAlive);
  const telegraph = active && props.bossCountdown !== null && props.bossCountdown <= 2;

  useEffect(() => {
    let frame = 0; let previous = performance.now();
    const tick = (now: number) => {
      const delta = Math.min((now - previous) / 1000, .05); previous = now;
      position.current.x = Math.max(22, Math.min(46, position.current.x + direction.current.x * delta * 20));
      position.current.y = Math.max(69, Math.min(80, position.current.y + direction.current.y * delta * 16));
      stage.current?.style.setProperty('--actor-x', `${position.current.x}%`);
      stage.current?.style.setProperty('--actor-y', `${position.current.y}%`);
      stage.current?.classList.toggle('action-running', Math.hypot(direction.current.x, direction.current.y) > .05);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    const stop = () => { direction.current = { x: 0, y: 0 }; };
    window.addEventListener('blur', stop); document.addEventListener('visibilitychange', stop);
    return () => { cancelAnimationFrame(frame); window.removeEventListener('blur', stop); document.removeEventListener('visibilitychange', stop); if (timer.current) clearTimeout(timer.current); };
  }, []);

  const animate = useCallback((next: 'strike' | 'dodge') => {
    if (timer.current) clearTimeout(timer.current);
    setAction(next);
    timer.current = setTimeout(() => setAction('idle'), 900);
  }, []);
  const strike = useCallback(async () => {
    if (!ready || inFlight.current || !onAttack) return;
    inFlight.current = true; setError(null);
    try {
      await onAttack(); animate('strike'); setHits(count => count + 1); setFlash(true);
      setTimeout(() => setFlash(false), 1200);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Não foi possível executar o golpe.'); }
    finally { inFlight.current = false; }
  }, [ready, onAttack, animate]);
  useEffect(() => {
    const handle = (event: KeyboardEvent) => {
      if (event.repeat || event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement || document.querySelector('[role="dialog"]')) return;
      if (event.code === 'Space') { event.preventDefault(); void strike(); }
      if (event.code === 'ShiftLeft' || event.code === 'ShiftRight') animate('dodge');
    };
    window.addEventListener('keydown', handle); return () => window.removeEventListener('keydown', handle);
  }, [strike, animate]);
  return <div ref={stage} className={`seas-action-arena action-phase-${phase} action-${action} ${hit ? 'action-boss-hit' : ''} ${expanded ? 'action-expanded' : ''}`} aria-label={localizeText("Arena de combate pirata")}>
    <img className="action-world" src={actionArenaArt.harbor} width={1536} height={1376} alt={localizeText("Arena portuária da Grand Line, navio pirata e oceano")} />
    <div className="action-atmosphere" aria-hidden="true" />
    <div className="action-wind" aria-hidden="true"><i /><i /><i /></div>
    <header className="action-boss-hud">
      <img className="action-boss-emblem" src={props.image} alt="" width={64} height={64} />
      <div className="action-boss-title"><div><small>{localizeText("CHEFE GLOBAL")}</small><h2>{name}</h2></div><OceanControl onClick={props.onRanking} title={localizeText("Ranking")} aria-label={localizeText("Ranking")}><Trophy size={18} /></OceanControl><OceanControl onClick={() => setExpanded(value => !value)} title={expanded ? localizeText("Reduzir arena") : localizeText("Expandir arena")} aria-label={expanded ? localizeText("Reduzir arena") : localizeText("Expandir arena")}>{expanded ? <X size={18} /> : <Expand size={18} />}</OceanControl></div>
      <div className="action-boss-life" role="progressbar" aria-label={localizeText("Vida do chefe")} aria-valuenow={Math.ceil(hp)} aria-valuemax={maxHp} aria-valuemin={0}><span style={{ width: `${ratio}%` }} />{[25,50,75].map(value => <i key={value} style={{ left: `${value}%` }} />)}</div>
      <div className="action-boss-meta"><span>{Math.ceil(hp).toLocaleString('pt-BR')} / {maxHp.toLocaleString('pt-BR')}</span></div>
    </header>
    <aside className="action-crew" aria-label={localizeText("Tripulação")}>
      <OceanControl className={!selected ? 'action-crew-selected' : ''} aria-pressed={!selected} onClick={() => setSelectedHero(null)} title={localizeText("Capitão do perfil")} aria-label={localizeText("Capitão do perfil")}><img src={captain} alt={localizeText("Capitão")} /></OceanControl>
      {COMBAT_SLOTS.map(slot => { const hero = heroes.find(item => Number(item.slot) === slot); return <div key={slot}>
        <OceanControl className={hero && selected?.heroId === hero.heroId ? 'action-crew-selected' : ''} aria-pressed={Boolean(hero && selected?.heroId === hero.heroId)} onClick={() => hero ? setSelectedHero(hero.heroId) : props.onEquip(slot)} aria-label={hero ? `Controlar ${hero.name}` : `Equipar tripulante ${slot}`} title={hero ? `${hero.name} · HP ${hero.currentHp}/${hero.maxHp}${hero.isAlive ? '' : ' · Nocauteado'}` : `Equipar tripulante ${slot}`}>
          {hero ? <><img src={arenaCrewImage(hero)} alt={hero.name} width={768} height={1024} /><span className="action-crew-life"><i style={{ width: `${hero.maxHp > 0 ? hero.currentHp / hero.maxHp * 100 : 0}%` }} /></span>{!hero.isAlive && <span className="action-ko">{localizeText("KO")}</span>}</> : <span>+</span>}
        </OceanControl>{hero && <OceanControl className="action-crew-edit" onClick={() => props.onEquip(slot)} aria-label={`Trocar tripulante ${slot}`} title={localizeText("Trocar tripulante")}>↻</OceanControl>}
      </div>; })}
    </aside>
    <div className="action-boss-ground" aria-hidden="true" />
    <img className="action-monster" src={props.image} width={1024} height={1024} alt={name} />
    {telegraph && <div className="action-telegraph" role="status"><span>{localizeText("GOLPE IMINENTE")}</span></div>}
    <div className={`action-actor ${selected && !selected.isAlive ? 'action-actor-ko' : ''}`}><span className="action-actor-shadow" /><img src={actor} alt={selected ? `${selected.name} em postura de combate` : localizeText("Pirata do perfil em postura de combate")} width={768} height={1024} /><span className="action-slash" aria-hidden="true" /></div>
    {pet && <div className="action-mascot"><img src={pet.image} alt={pet.name} /><span>{pet.name}</span></div>}
    {flash && <div className="action-combo" role="status"><strong>{hits}</strong><span>{localizeText("GOLPE")}{hits > 1 ? 'S' : ''} {localizeText("CONFIRMADO")}{hits > 1 ? 'S' : ''}</span></div>}
    {hit && <div className="action-impact" aria-hidden="true" />}
    {props.swap && <div className="action-announcement" role="status">{props.swap === 'defeated' ? localizeText("CHEFE DERROTADO") : localizeText("CICLO ENCERRADO")}<small>{localizeText("Novo adversário no horizonte")}</small></div>}
    {error && <p className="action-feedback" role="alert">{error}</p>}
    {!active && <p className="action-feedback">{props.status === 'defeated' ? localizeText("Chefe derrotado") : localizeText("Aguardando próximo chefe")}</p>}
    <div className="action-player-hud"><Swords size={13}/><span>{props.damage.toLocaleString('pt-BR')} dano</span><span>#{props.rank ?? '—'}</span><b>{props.reward.toLocaleString('pt-BR')} BERRIES</b></div>
    <IslandJoystick onDirection={value => { direction.current = value; }} disabled={false} />
    <nav className="action-controls" aria-label={localizeText("Ações de combate")}>
      <OceanControl className="action-basic" disabled={!ready} onClick={() => void strike()} aria-label={localizeText("Ataque básico")} title={localizeText("Ataque básico")}><Hand />{(attacking || cooldown > 0) && <span>{attacking ? '…' : `${cooldown}s`}</span>}</OceanControl>
      {([{key:'Q',name:'Armamento',Icon:Shield},{key:'E',name:'Poder da fruta',Icon:Flame},{key:'R',name:'Conquistador',Icon:Zap},{key:'F',name:'Ultimate',Icon:Sparkles}]).map(({key,name:label,Icon}) => <OceanControl key={key} disabled aria-label={`${label} indisponível`} title={`${label} · Ainda não disponível nas regras de combate`}><Icon/><LockKeyhole className="action-lock"/></OceanControl>)}
      <OceanControl onClick={() => animate('dodge')} aria-label={localizeText("Esquiva visual")} title={localizeText("Esquiva visual · Não altera o dano oficial")}><Wind/></OceanControl>
    </nav>
  </div>;
}