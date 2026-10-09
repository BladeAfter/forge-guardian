import { useCallback, useEffect, useRef, useState } from 'react';
import { Expand, Flame, Hand, LockKeyhole, Shield, Sparkles, Swords, Trophy, Wind, X, Zap } from 'lucide-react';
import { actionArenaArt } from '../gameAssets';
import { captainCharacters, readCaptainStyle } from '../captainCharacter';
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
  const { name, hp, maxHp, heroes, pet, hit, attacking, active, cooldown, onAttack } = props;
  const stage = useRef<HTMLDivElement>(null);
  const inFlight = useRef(false);
  const direction = useRef({ x: 0, y: 0 });
  const position = useRef({ x: 32, y: 76 });
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [action, setAction] = useState<'idle' | 'strike' | 'dodge'>('idle');
  const [selectedHero, setSelectedHero] = useState<string | null>(null);
  const [hits, setHits] = useState(0);
  const [flash, setFlash] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState(false);
  const ratio = Math.max(0, Math.min(100, maxHp > 0 ? hp / maxHp * 100 : 0));
  const phase = ratio > 75 ? 1 : ratio > 50 ? 2 : ratio > 25 ? 3 : 4;
  const selected = heroes.find(hero => hero.heroId === selectedHero);
  const captain = captainCharacters[readCaptainStyle(props.telegramId)];
  const actor = readCaptainStyle(props.telegramId) === 'female' ? actionArenaArt.captainFemale : actionArenaArt.captain;
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
  return <div ref={stage} className={`seas-action-arena action-phase-${phase} action-${action} ${hit ? 'action-boss-hit' : ''} ${expanded ? 'action-expanded' : ''}`} aria-label="Arena de combate pirata">
    <img className="action-world" src={actionArenaArt.harbor} width={1536} height={1024} alt="Porto da Grand Line destruído, navios e oceano" />
    <div className="action-atmosphere" aria-hidden="true" />
    <div className="action-wind" aria-hidden="true"><i /><i /><i /></div>
    <header className="action-boss-hud">
      <div className="action-boss-title"><div><small>MYTHIC SEAS · CHEFE GLOBAL</small><h2>{name}</h2></div><OceanControl onClick={props.onRanking} title="Ranking" aria-label="Ranking"><Trophy size={18} /></OceanControl><OceanControl onClick={() => setExpanded(value => !value)} title={expanded ? 'Reduzir arena' : 'Expandir arena'} aria-label={expanded ? 'Reduzir arena' : 'Expandir arena'}>{expanded ? <X size={18} /> : <Expand size={18} />}</OceanControl></div>
      <div className="action-boss-life" role="progressbar" aria-label="Vida do chefe" aria-valuenow={Math.ceil(hp)} aria-valuemax={maxHp} aria-valuemin={0}><span style={{ width: `${ratio}%` }} />{[25,50,75].map(value => <i key={value} style={{ left: `${value}%` }} />)}</div>
      <div className="action-boss-meta"><span>{Math.ceil(hp).toLocaleString('pt-BR')} / {maxHp.toLocaleString('pt-BR')}</span><b>FASE {phase} / 4</b></div>
    </header>
    <aside className="action-crew" aria-label="Tripulação">
      <OceanControl className={!selectedHero ? 'action-crew-selected' : ''} onClick={() => setSelectedHero(null)} title="Capitão do perfil" aria-label="Capitão do perfil"><img src={captain.image} alt="Capitão" /></OceanControl>
      {COMBAT_SLOTS.map(slot => { const hero = heroes.find(item => Number(item.slot) === slot); return <div key={slot}>
        <OceanControl className={selectedHero === hero?.heroId ? 'action-crew-selected' : ''} onClick={() => hero ? setSelectedHero(hero.heroId) : props.onEquip(slot)} aria-label={hero ? `Controlar ${hero.name}` : `Equipar tripulante ${slot}`} title={hero ? `${hero.name} · HP ${hero.currentHp}/${hero.maxHp}${hero.isAlive ? '' : ' · Nocauteado'}` : `Equipar tripulante ${slot}`}>
          {hero ? <><img src={hero.image} alt={hero.name} /><span className="action-crew-life"><i style={{ width: `${hero.maxHp > 0 ? hero.currentHp / hero.maxHp * 100 : 0}%` }} /></span>{!hero.isAlive && <span className="action-ko">KO</span>}</> : <span>+</span>}
        </OceanControl>{hero && <OceanControl className="action-crew-edit" onClick={() => props.onEquip(slot)} aria-label={`Trocar tripulante ${slot}`} title="Trocar tripulante">↻</OceanControl>}
      </div>; })}
    </aside>
    <div className="action-boss-ground" aria-hidden="true" />
    <img className="action-monster" src={props.image} width={1024} height={1024} alt={name} />
    {telegraph && <div className="action-telegraph" role="status"><span>GOLPE IMINENTE</span></div>}
    <div className={`action-actor ${selected && !selected.isAlive ? 'action-actor-ko' : ''}`}><span className="action-actor-shadow" /><img src={actor} alt="Pirata do perfil em postura de combate" width={1024} height={1024} /><span className="action-slash" aria-hidden="true" /></div>
    {pet && <div className="action-mascot"><img src={pet.image} alt={pet.name} /><span>{pet.name}</span></div>}
    {flash && <div className="action-combo" role="status"><strong>{hits}</strong><span>GOLPE{hits > 1 ? 'S' : ''} CONFIRMADO{hits > 1 ? 'S' : ''}</span></div>}
    {hit && <div className="action-impact" aria-hidden="true" />}
    {props.swap && <div className="action-announcement" role="status">{props.swap === 'defeated' ? 'CHEFE DERROTADO' : 'CICLO ENCERRADO'}<small>Novo adversário no horizonte</small></div>}
    {error && <p className="action-feedback" role="alert">{error}</p>}
    {!active && <p className="action-feedback">{props.status === 'defeated' ? 'Chefe derrotado' : 'Aguardando próximo chefe'}</p>}
    <div className="action-player-hud"><Swords size={13}/><span>{props.damage.toLocaleString('pt-BR')} dano</span><span>#{props.rank ?? '—'}</span><b>{props.reward.toLocaleString('pt-BR')} BERRIES</b></div>
    <IslandJoystick onDirection={value => { direction.current = value; }} disabled={false} />
    <nav className="action-controls" aria-label="Ações de combate">
      <OceanControl className="action-basic" disabled={!ready} onClick={() => void strike()} aria-label="Ataque básico" title="Ataque básico · Espaço"><Hand /><span>{attacking ? '…' : cooldown > 0 ? `${cooldown}s` : 'GOLPE'}</span></OceanControl>
      {([{key:'Q',name:'Armamento',Icon:Shield},{key:'E',name:'Poder da fruta',Icon:Flame},{key:'R',name:'Conquistador',Icon:Zap},{key:'F',name:'Ultimate',Icon:Sparkles}]).map(({key,name:label,Icon}) => <OceanControl key={key} disabled aria-label={`${label} indisponível`} title={`${label} · Ainda não disponível nas regras de combate`}><Icon/><span>{key}</span><LockKeyhole className="action-lock"/></OceanControl>)}
      <OceanControl onClick={() => animate('dodge')} aria-label="Esquiva visual" title="Esquiva visual · Shift · Não altera o dano oficial"><Wind/><span>ESQUIVA</span></OceanControl>
    </nav>
  </div>;
}