import { useLocalizedText } from '../LanguageContext';
import { useCallback, useEffect, useRef, useState } from 'react';
import { ArrowLeft, Anchor, Maximize2, Minimize2, Waves, Ship, Crosshair, Zap, Swords, Flag } from 'lucide-react';
import { grandLineArt } from '../gameAssets';
import { DEFAULT_SHIP, SHIP_MODELS, SHIP_SKINS, shipMaxHp, shipStats, type NavalShip } from '../naval';
import IllustratedOcean from './IllustratedOcean';
import { useNavalOcean } from '../useNavalOcean';
import NavalShipyard from './NavalShipyard';
import { advanceSailing, seaIslandsAround, seaClickTarget, seaDistance, seaDestinationInput, type SeaIsland, type SeaDestination, type SeaPoint } from '../grandLineNavigation';
import { OceanControl } from './OceanControl';
import { approachApprovedPose } from '../navalMotion';
import { captureTelegramGameGestures } from '../telegram';
import NavalMiniMap from './NavalMiniMap';
import { frameDelta, frameDiagnostics } from '../gamePerformance';
import { useGameViewport } from '../useGameViewport';
import { useOceanChests } from '../useOceanChests';
import OceanChests from './OceanChests';

type Props = { berries: number; onBack: () => void; onDock: (destination: SeaDestination, islandIndex: number, ship?: NavalShip) => void; initialPosition?: SeaPoint; initData?: string };
export default function GrandLineOcean({ berries, onBack, onDock, initialPosition = { x: 1700, y: 1340 }, initData = '' }: Props) {
  const localizeText = useLocalizedText();

  const canvasRef = useRef<HTMLCanvasElement>(null);
  const host = useRef<HTMLElement>(null);
  useGameViewport(host);
  const drawRef = useRef<((time: number, delta: number) => void) | null>(null);
  const autopilot = useRef(false);
  const stopNavigation = () => {
    network.steer({ dx: 0, dy: 0, throttle: 0 });
    autopilot.current = false;
    state.current.target = { ...(docking.current?.dock ?? state.current.position) };
  };
  const state = useRef({ position: { ...initialPosition }, target: { ...initialPosition }, heading: 0, camera: { ...initialPosition }, scale: 0.7, keys: new Set<string>(), moving: false, velocity: { x: 0, y: 0 } });
  const docking = useRef<SeaIsland | null>(null);
  const dockCallback = useRef(onDock); dockCallback.current = onDock;
  const [dockingNow, setDockingNow] = useState(false);
  const [wide, setWide] = useState(false);
  const wideRef = useRef(false);
  const [nearby, setNearby] = useState<SeaIsland | null>(null);
  const [speed, setSpeed] = useState(0);
  const [message, setMessage] = useState('');
  const [bottleFound, setBottleFound] = useState(false);
  const [secretFound, setSecretFound] = useState(false);
  const bottleFoundRef = useRef(false);
  const secretFoundRef = useRef(false);
  const [yardOpen,setYardOpen] = useState(false);
  const yardRef = useRef(false); yardRef.current=yardOpen;
  const chestModal = useRef(false);
  const setChestModal = useCallback((open:boolean)=>{chestModal.current=open;},[]);
  const [selected,setSelected] = useState<string | null>(null);
  const [inspecting,setInspecting] = useState(false);
  const [throttle,setThrottle] = useState(1);
  const throttleRef = useRef(1); throttleRef.current=throttle;
  const networkPosition = useRef(false);
  const approvedShip = useRef<NavalShip | null>(null);
  const network = useNavalOcean(initData, () => {
    const s=state.current, k=s.keys;
    if(yardRef.current || chestModal.current || document.hidden) return {dx:0,dy:0,throttle:0};
    const dx=Number(k.has('ArrowRight') || k.has('d'))-Number(k.has('ArrowLeft') || k.has('a'));
    const dy=Number(k.has('ArrowDown') || k.has('s'))-Number(k.has('ArrowUp') || k.has('w'));
    if(dx || dy) return {dx,dy,throttle:throttleRef.current};
    if (!autopilot.current && !docking.current) return {dx:0,dy:0,throttle:0};
    const ship = approvedShip.current;
    return seaDestinationInput(ship ?? s.position, s.target, throttleRef.current, shipStats(ship ?? DEFAULT_SHIP).speed);
  });
  const currentNetwork = network.current;
  approvedShip.current = network.data?.ship ?? null;
  const oceanChests = useOceanChests(initData);
  const [chestSelection,setChestSelection] = useState<{id:string;nonce:number}|null>(null);
  const ownShip=network.data?.ship ?? DEFAULT_SHIP;
  const enemy=network.data?.others.find(s => s.user_id===selected);
  const battle=network.data?.battle?.status==='active' ? network.data.battle : null;
  const fireAction=(action:string) => void network.action(action);
  const openYard=() => { stopNavigation();state.current.keys.clear();setYardOpen(true); };

  useEffect(() => captureTelegramGameGestures(window.Telegram?.WebApp), []);

  useEffect(() => {
    // Bitmap rendering is separate from authoritative navigation and HUD.
    let frame = 0; let previous = 0; let uiTime = 0;
    const diagnose = frameDiagnostics('ocean');

    const keydown = (e: KeyboardEvent) => { if (!docking.current && !chestModal.current && ['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','w','a','s','d'].includes(e.key)) { e.preventDefault(); state.current.keys.add(e.key); } };
    const keyup = (e: KeyboardEvent) => { state.current.keys.delete(e.key); if (!state.current.keys.size && !docking.current) state.current.target = { ...state.current.position }; };
    const clear = () => { state.current.keys.clear(); stopNavigation(); };
    const visibility = () => {
      previous = 0; cancelAnimationFrame(frame); frame = 0;
      if (document.hidden) clear(); else frame = requestAnimationFrame(render);
    };
    window.addEventListener('keydown', keydown); window.addEventListener('keyup', keyup); window.addEventListener('blur', clear);
    document.addEventListener('visibilitychange', visibility);
    const render = (time: number) => {
      const rawDelta = (time - (previous || time)) / 1000;
      const dt = frameDelta(rawDelta); previous = time;
      if (document.hidden) return;
      const started = performance.now();
      const s = state.current; const k = s.keys;
      const dx = yardRef.current || chestModal.current ? 0 : Number(k.has('ArrowRight') || k.has('d')) - Number(k.has('ArrowLeft') || k.has('a'));
      const dy = yardRef.current || chestModal.current ? 0 : Number(k.has('ArrowDown') || k.has('s')) - Number(k.has('ArrowUp') || k.has('w'));
      if (dx || dy) s.target = { x: s.position.x + dx * 120, y: s.position.y + dy * 120 };
      else if (!autopilot.current && !docking.current) s.target = { ...s.position };
      const distance = seaDistance(s.position, s.target); s.moving = distance > 3;
      const live = currentNetwork.current;
      if (live) {
        if (!networkPosition.current) {
          s.position = { x: live.ship.x, y: live.ship.y }; s.heading = live.ship.heading;
          s.camera = { ...s.position }; networkPosition.current = true;
        }
        const next = approachApprovedPose(s.position, s.heading, live.ship, dt, shipStats(live.ship).speed);
        s.moving = seaDistance(s.position, { x: live.ship.x, y: live.ship.y }) > .5;
        s.position = next.position; s.heading = next.heading;
        s.velocity = { x: 0, y: 0 };
      } else if (!yardRef.current && !initData) {
        networkPosition.current = false;
        s.position = advanceSailing(s.position, s.target, s, dt, 122 * throttleRef.current);
        s.moving = Math.hypot(s.velocity.x, s.velocity.y) > .5;
      }
      if (docking.current !== null && seaDistance(live ? live.ship : s.position, s.target) < (live ? 85 : 5)) {
        const island = docking.current; docking.current = null; s.moving = false;
        if(live) { stopNavigation(); void network.action('leave').then(ok => { if(ok) dockCallback.current(island.destination,island.templateIndex,currentNetwork.current?.ship ?? live.ship);else setDockingNow(false); }); }
        else dockCallback.current(island.destination, island.templateIndex, { ...DEFAULT_SHIP, x: s.position.x, y: s.position.y, heading: s.heading });
        frame=requestAnimationFrame(render);return;
      }
      if (time - uiTime > 180) {
        uiTime = time; setSpeed(live ? Math.round(8 * live.ship.throttle) : Math.round(Math.hypot(s.velocity.x, s.velocity.y) / 122 * 8));
        const nextNearby = seaIslandsAround(s.position, 1).find(i => seaDistance(s.position, i.dock) < 190) ?? null;
        setNearby(old => old?.id === nextNearby?.id ? old : nextNearby);
        const canvas = canvasRef.current;
        if (!canvas) { frame=requestAnimationFrame(render);return; }
        canvas.dataset.shipX = s.position.x.toFixed(0); canvas.dataset.shipY = s.position.y.toFixed(0);
        canvas.dataset.cameraX = s.camera.x.toFixed(2); canvas.dataset.cameraY = s.camera.y.toFixed(2); canvas.dataset.scale = String(s.scale);
        canvas.dataset.model=live?.ship.model ?? DEFAULT_SHIP.model;canvas.dataset.skin=live?.ship.skin ?? DEFAULT_SHIP.skin;canvas.dataset.players=String(live?.others.length ?? 0);
        if (!bottleFoundRef.current && seaDistance(s.position, {x:1850,y:1470}) < 80) { bottleFoundRef.current = true; setBottleFound(true); setMessage('Uma garrafa! “Na selva, procure a praia a leste da caverna.”'); }
        if (bottleFoundRef.current && !secretFoundRef.current && seaDistance(s.position, {x:1090,y:1450}) < 80) { secretFoundRef.current = true; setSecretFound(true); setMessage('Passagem secreta descoberta — Selva dos Segredos.'); }
      }
      drawRef.current?.(time, dt);
      diagnose(rawDelta, performance.now() - started, 1 + (currentNetwork.current?.others.length ?? 0));
      frame = requestAnimationFrame(render);
    };
    frame = requestAnimationFrame(render);
    return () => { cancelAnimationFrame(frame); window.removeEventListener('keydown',keydown); window.removeEventListener('keyup',keyup); window.removeEventListener('blur',clear); document.removeEventListener('visibilitychange',visibility); };
  }, [initData]);

  const sail = (point: SeaPoint) => {
    if (docking.current !== null || yardRef.current || chestModal.current) return;
    setSelected(null); autopilot.current = true; state.current.target = seaClickTarget(point); network.refresh();
  };
  const island = nearby;
  return <section ref={host} className="grand-line-ocean" aria-label={localizeText("Grand Line — oceano navegável")}>
    <IllustratedOcean pose={state} network={currentNetwork} chests={oceanChests.current} wide={wideRef} canvasRef={canvasRef} drawRef={drawRef} onSail={sail} onSelect={id => { setSelected(id); setInspecting(false); }} onChestSelect={id=>{stopNavigation();state.current.keys.clear();setChestSelection({id,nonce:Date.now()});}} />
    {initData && <OceanChests ocean={oceanChests} selection={chestSelection} onModalChange={setChestModal} position={ownShip} unavailable={Boolean(battle) || !network.data || Boolean(network.error)} onStop={()=>{stopNavigation();state.current.keys.clear();}} />}
    <header className="ocean-hud">
      <OceanControl onClick={() => { stopNavigation(); state.current.keys.clear(); if (network.data && !battle) void network.action('leave'); onBack(); }} title={localizeText("Voltar ao porto")} aria-label={localizeText("Voltar ao porto")}><ArrowLeft size={20} /></OceanControl>
      <div className="ocean-brand"><span>MYTHIC SEAS</span><h1>{localizeText("GRAND LINE")}</h1></div>
      <div className="ocean-berries"><img src={grandLineArt.berry} alt="" width={22} height={22} /><b>{new Intl.NumberFormat('pt-BR').format(Math.floor(berries))}</b><span>BERRIES</span></div>
    </header>
    <div className="ocean-instruments"><span><Waves size={15} /> {speed} {localizeText("nós")}</span><span className="ocean-hull" title={localizeText("Casco de navegação")}>{localizeText("CASCO ")}{ownShip.hp}/{shipMaxHp(ownShip)}</span><span>{localizeText("Nv. ")}{ownShip.level}</span></div>
    <div className="naval-connection" role="status">{network.error || (network.data ? `${network.data.others.length} capitães à vista` : initData ? 'Conectando ao oceano compartilhado…' : 'Navegação local · oceano compartilhado indisponível')}</div>
    {network.data?.battle?.status==='won' && <div className="ocean-discovery" role="status"><span>{network.data.battle.winner===ownShip.user_id ? localizeText("VITÓRIA NAVAL") : localizeText("NAVIO DERROTADO")}</span><p>{network.data.battle.winner===ownShip.user_id ? `${network.data.battle.loot.berries ?? 0} BERRIES · ${Object.values(network.data.battle.loot.items ?? {}).reduce((sum,n)=>sum+n,0)} materiais recuperados` : localizeText("Retorne ao estaleiro para reparar o casco.")}</p></div>}
    <div className="naval-controls"><label className="naval-throttle">{localizeText("Velocidade · ")}{Math.round(throttle*100)}%<input aria-label={localizeText("Velocidade do navio")} type="range" min="0" max="100" value={throttle*100} onChange={e => { const value = Number(e.target.value)/100; throttleRef.current = value; setThrottle(value); network.refresh(); }}/></label>
      {battle && <><span className="naval-battle-status">{localizeText("GUERRA NAVAL")}</span><div className="naval-battle-controls"><OceanControl disabled={network.busy} aria-label={localizeText("Disparar canhões")} title={localizeText("Disparar canhões")} onClick={() => fireAction('fire')}><Crosshair size={22}/></OceanControl><OceanControl disabled={network.busy} aria-label={localizeText("Salva especial")} title={localizeText("Salva especial")} onClick={() => fireAction('skill')}><Zap size={22}/></OceanControl><OceanControl disabled={network.busy} aria-label={localizeText("Abordar navio")} title={localizeText("Abordar navio")} onClick={() => fireAction('board')}><Swords size={22}/></OceanControl><OceanControl disabled={network.busy} aria-label={localizeText("Tentar fugir")} title={localizeText("Tentar fugir")} onClick={() => fireAction('escape')}><Flag size={22}/></OceanControl></div></>}
    </div>
    {enemy && <div className="naval-enemy" role="dialog" aria-label={localizeText("Navio inimigo")}><h2>{localizeText("NAVIO INIMIGO")}</h2><p>{enemy.name} {localizeText("· Nv. ")}{enemy.level}<br/>{SHIP_MODELS.find(m=>m.id===enemy.model)?.name} · {SHIP_SKINS.find(s=>s.id===enemy.skin)?.name}</p>{inspecting && <p>{localizeText("Vida ")}{enemy.hp}/{shipMaxHp(enemy)} {localizeText("· Canhões ")}{shipStats(enemy).cannons}<br/>{localizeText("Defesa ")}{shipStats(enemy).defense} {localizeText("· Tripulação ")}{shipStats(enemy).crew}</p>}<nav><OceanControl disabled={network.busy || !network.data?.rules.pvpEnabled || Boolean(battle)} onClick={() => void network.action('attack',{target:enemy.user_id}).then(ok=>{if(ok)setSelected(null);})}><Crosshair size={15}/>{localizeText("Atacar")}</OceanControl><OceanControl onClick={()=>setInspecting(true)}>{localizeText("Inspecionar")}</OceanControl><OceanControl onClick={()=>setSelected(null)}>{localizeText("Ignorar")}</OceanControl></nav>{!network.data?.rules.pvpEnabled && <small>{localizeText("Saque e guerra naval aguardam definição das regras.")}</small>}</div>}
    {yardOpen && <NavalShipyard ship={ownShip} state={network.data} busy={network.busy} onClose={()=>setYardOpen(false)} onSave={async input => {if(await network.action('customize',input))setYardOpen(false);}} onAction={async action => {await network.action(action);}}/>}
    <NavalMiniMap pose={state} network={currentNetwork} />
    <div className="ocean-view"><OceanControl title={wide ? localizeText("Seguir navio") : localizeText("Ampliar visão do horizonte")} aria-label={wide ? localizeText("Seguir navio") : localizeText("Ampliar visão do horizonte")} onClick={() => { wideRef.current = !wide; setWide(!wide); }}>{wide ? <Minimize2 size={19} /> : <Maximize2 size={19} />}</OceanControl></div>
    {message && <div className="ocean-discovery" role="status"><span>{bottleFound && !secretFound ? localizeText("MAPA NA GARRAFA") : localizeText("DESCOBERTA")}</span><p>{message}</p></div>}
    {island && !battle && <div className="ocean-dock"><span>{island.name}</span><OceanControl disabled={dockingNow || network.busy} onClick={() => { if (nearby === null) return; stopNavigation(); state.current.keys.clear(); state.current.target = { ...island.dock }; docking.current = island; setDockingNow(true); }}><Anchor size={17} />{dockingNow ? localizeText("Atracando...") : localizeText("Atracar no porto")}</OceanControl></div>}
    <span className="ocean-coordinate">{localizeText("MAR ABERTO · ")}{secretFound ? localizeText("PASSAGEM DESCOBERTA") : bottleFound ? 'MAPA ENCONTRADO' : 'VENTO LESTE'}</span>
  </section>;
}