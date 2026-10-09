import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, Anchor, Compass, Maximize2, Minimize2, Waves, Ship, Crosshair, Zap, Swords, Flag } from 'lucide-react';
import { grandLineArt, navalArt } from '../gameAssets';
import { DEFAULT_SHIP, SHIP_MODELS, SHIP_SKINS, shipMaxHp, shipStats, type NavalShip } from '../naval';
import { drawNavalShip, navalPalette } from '../navalRendering';
import { useNavalOcean } from '../useNavalOcean';
import NavalShipyard from './NavalShipyard';
import { SEA_ISLANDS, SEA_SIZE, sailToward, seaClickTarget, seaDistance, type SeaDestination, type SeaPoint } from '../grandLineNavigation';
import { OceanControl } from './OceanControl';

type Props = { berries: number; onBack: () => void; onDock: (destination: SeaDestination, islandIndex: number) => void; initialPosition?: SeaPoint; initData?: string };
export default function GrandLineOcean({ berries, onBack, onDock, initialPosition = { x: 1700, y: 1340 }, initData = '' }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const joystickKnob = useRef<HTMLSpanElement>(null);
  const joystickPointer = useRef<number | null>(null);
  const joystickVector = useRef({ x: 0, y: 0 });
  const resetJoystick = () => {
    joystickPointer.current = null;
    joystickVector.current = { x: 0, y: 0 };
    if (joystickKnob.current) joystickKnob.current.style.transform = 'translate(0px, 0px)';
    state.current.target = { ...state.current.position };
  };
  const state = useRef({ position: { ...initialPosition }, target: { ...initialPosition }, heading: 0, camera: { ...initialPosition }, scale: 0.7, keys: new Set<string>(), moving: false });
  const docking = useRef<number | null>(null);
  const dockCallback = useRef(onDock); dockCallback.current = onDock;
  const [dockingNow, setDockingNow] = useState(false);
  const [wide, setWide] = useState(false);
  const wideRef = useRef(false);
  const [nearby, setNearby] = useState<number | null>(1);
  const [speed, setSpeed] = useState(0);
  const [message, setMessage] = useState('');
  const [bottleFound, setBottleFound] = useState(false);
  const [secretFound, setSecretFound] = useState(false);
  const bottleFoundRef = useRef(false);
  const secretFoundRef = useRef(false);
  const [yardOpen,setYardOpen] = useState(false);
  const yardRef = useRef(false); yardRef.current=yardOpen;
  const [selected,setSelected] = useState<string | null>(null);
  const [inspecting,setInspecting] = useState(false);
  const [throttle,setThrottle] = useState(1);
  const throttleRef = useRef(1); throttleRef.current=throttle;
  const networkPosition = useRef('');
  const network = useNavalOcean(initData, () => {
    const s=state.current, k=s.keys;
    if(yardRef.current || document.hidden) return {dx:0,dy:0,throttle:0};
    const dx=joystickVector.current.x || Number(k.has('ArrowRight') || k.has('d'))-Number(k.has('ArrowLeft') || k.has('a'));
    const dy=joystickVector.current.y || Number(k.has('ArrowDown') || k.has('s'))-Number(k.has('ArrowUp') || k.has('w'));
    if(dx || dy) return {dx,dy,throttle:throttleRef.current};
    const distance=seaDistance(s.position,s.target);
    return {dx:distance>5 ? (s.target.x-s.position.x)/distance : 0,dy:distance>5 ? (s.target.y-s.position.y)/distance : 0,throttle:throttleRef.current};
  });
  const currentNetwork = network.current;
  const ownShip=network.data?.ship ?? DEFAULT_SHIP;
  const enemy=network.data?.others.find(s => s.user_id===selected);
  const battle=network.data?.battle?.status==='active' ? network.data.battle : null;
  const fireAction=(action:string) => void network.action(action);
  const openYard=() => { resetJoystick();state.current.keys.clear();setYardOpen(true); };

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return;
    const ocean = new Image(); ocean.src = grandLineArt.ocean;
    const fleet = new Image(); fleet.src = navalArt.fleet;
    const navalColors = navalPalette(canvas);
    const palette = getComputedStyle(canvas);
    const color = (key: string) => `hsl(${palette.getPropertyValue(key).trim()})`;
    const foam = color('--ocean-foam'); const gold = color('--ocean-gold'); const deep = color('--ocean-deep');
    let frame = 0; let previous = 0; let uiTime = 0;
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const resize = () => { const rect = canvas.getBoundingClientRect(); canvas.width = Math.round(rect.width * Math.min(devicePixelRatio, 2)); canvas.height = Math.round(rect.height * Math.min(devicePixelRatio, 2)); };
    const observer = new ResizeObserver(resize); observer.observe(canvas); resize();
    const keydown = (e: KeyboardEvent) => { if (['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','w','a','s','d'].includes(e.key)) { e.preventDefault(); state.current.keys.add(e.key); } };
    const keyup = (e: KeyboardEvent) => state.current.keys.delete(e.key);
    const clear = () => { state.current.keys.clear(); resetJoystick(); };
    window.addEventListener('keydown', keydown); window.addEventListener('keyup', keyup); window.addEventListener('blur', clear);
    const render = (time: number) => {
      const dt = Math.min((time - (previous || time)) / 1000, .05); previous = time;
      const s = state.current; const k = s.keys;
      const dx = yardRef.current ? 0 : joystickVector.current.x || Number(k.has('ArrowRight') || k.has('d')) - Number(k.has('ArrowLeft') || k.has('a'));
      const dy = yardRef.current ? 0 : joystickVector.current.y || Number(k.has('ArrowDown') || k.has('s')) - Number(k.has('ArrowUp') || k.has('w'));
      if (dx || dy) s.target = { x: s.position.x + dx * 120, y: s.position.y + dy * 120 };
      const distance = seaDistance(s.position, s.target); s.moving = distance > 3;
      const live = currentNetwork.current;
      if (live) {
        const stamp=`${live.ship.x}:${live.ship.y}`;
        if(stamp!==networkPosition.current) { s.position={x:live.ship.x,y:live.ship.y};s.heading=live.ship.heading;networkPosition.current=stamp; }
        s.moving=live.ship.throttle>0;
      } else if (s.moving && !yardRef.current) {
        s.heading = Math.atan2(s.target.x - s.position.x, -(s.target.y - s.position.y));
        const next = sailToward(s.position, s.target, dt, 122*throttleRef.current);
        const land = SEA_ISLANDS.some(i => seaDistance(next, i.center) < i.radius * .7);
        if (!land) s.position = next;
        else s.target = { ...s.position };
      }
      if (docking.current !== null && seaDistance(s.position, s.target) < (live ? 85 : 5)) {
        const index = docking.current; docking.current = null; s.moving = false;
        if(live) { void network.action('leave').then(ok => { if(ok) dockCallback.current(SEA_ISLANDS[index].destination,index);else setDockingNow(false); }); }
        else dockCallback.current(SEA_ISLANDS[index].destination, index);
        frame=requestAnimationFrame(render);return;
      }
      const width = canvas.clientWidth, height = canvas.clientHeight;
      s.scale = wideRef.current ? Math.min(width / SEA_SIZE.width, height / SEA_SIZE.height) * .96 : Math.max(.5, Math.min(.84, width / 1450));
      const aim = wideRef.current ? { x: 1600, y: 1066 } : s.position;
      s.camera.x += (aim.x - s.camera.x) * Math.min(1, dt * 5); s.camera.y += (aim.y - s.camera.y) * Math.min(1, dt * 5);
      ctx.setTransform(canvas.width / width, 0, 0, canvas.height / height, 0, 0); ctx.fillStyle = deep; ctx.fillRect(0, 0, width, height);
      // Continue the sea beyond the authored archipelago without empty viewport bands.
      if (ocean.complete && ocean.naturalWidth) {
        ctx.drawImage(ocean, 980, 710, 110, 120, 0, 0, width, height);
      }
      ctx.save(); ctx.translate(width / 2, height / 2); ctx.scale(s.scale, s.scale); ctx.translate(-s.camera.x, -s.camera.y);
      if (ocean.complete && ocean.naturalWidth) ctx.drawImage(ocean, 0, 0, SEA_SIZE.width, SEA_SIZE.height);
      const seconds = reduced ? 0 : time / 1000;
      for(const other of live?.others ?? []) drawNavalShip(ctx,fleet,other,navalColors,reduced ? 0 : time);
      for(const event of live?.events ?? []) {
        const age=(Date.now()-Date.parse(event.created_at))/1000;
        if(age<0 || age>2) continue;
        const progress=Math.min(1,age/.65);
        const ex=event.x+(event.target_x-event.x)*progress,ey=event.y+(event.target_y-event.y)*progress;
        ctx.fillStyle=progress<1 ? deep : navalColors.ember;ctx.globalAlpha=Math.max(0,1-age/2);
        ctx.beginPath();ctx.arc(ex,ey,progress<1 ? 6 : 12+age*12,0,Math.PI*2);ctx.fill();
        ctx.strokeStyle=foam;ctx.lineWidth=2;ctx.beginPath();ctx.arc(event.target_x,event.target_y,18+age*30,0,Math.PI*2);ctx.stroke();ctx.globalAlpha=1;
      }
      // Sea spray and a passing whale, kept in world coordinates.
      if (!reduced) {
        ctx.strokeStyle = foam; ctx.globalAlpha = .16; ctx.lineWidth = 2;
        for (let i = 0; i < 30; i++) { const x = (i * 313 + seconds * 8) % 3200; const y = (i * 197) % 2133; ctx.beginPath(); ctx.ellipse(x,y,27,7,0,0,Math.PI); ctx.stroke(); }
        ctx.globalAlpha = .65 + Math.sin(seconds / 4) * .2; ctx.fillStyle = deep; ctx.beginPath(); ctx.ellipse(1940 + Math.sin(seconds / 20) * 80, 1880, 45, 16, -.4, 0, Math.PI * 2); ctx.fill(); ctx.globalAlpha = 1;
      }
      if (!bottleFoundRef.current) { ctx.save(); ctx.translate(1850,1470); ctx.rotate(Math.sin(seconds) * .2); ctx.fillStyle = gold; ctx.fillRect(-5,-13,10,26); ctx.strokeStyle = foam; ctx.strokeRect(-5,-13,10,26); ctx.restore(); }
      if (bottleFoundRef.current && !secretFoundRef.current) { ctx.fillStyle = gold; ctx.font = 'bold 20px sans-serif'; ctx.fillText('×', 1090, 1450); }
      if (s.moving) { ctx.strokeStyle = gold; ctx.globalAlpha = .6; ctx.beginPath(); ctx.ellipse(s.target.x,s.target.y,14,8,0,0,Math.PI*2); ctx.stroke(); ctx.globalAlpha = 1; }
      drawNavalShip(ctx,fleet,{...(live?.ship ?? DEFAULT_SHIP),x:s.position.x,y:s.position.y,heading:s.heading,throttle:s.moving ? throttleRef.current : 0},navalColors,reduced ? 0 : time);
      ctx.restore();
      if (time - uiTime > 180) {
        uiTime = time; setSpeed(s.moving ? Math.round(8*throttleRef.current) : 0);
        const index = SEA_ISLANDS.findIndex(i => seaDistance(s.position, i.dock) < 190); setNearby(index < 0 ? null : index);
        canvas.dataset.shipX = s.position.x.toFixed(0); canvas.dataset.shipY = s.position.y.toFixed(0);
        canvas.dataset.cameraX = s.camera.x.toFixed(2); canvas.dataset.cameraY = s.camera.y.toFixed(2); canvas.dataset.scale = String(s.scale);
        canvas.dataset.model=live?.ship.model ?? DEFAULT_SHIP.model;canvas.dataset.skin=live?.ship.skin ?? DEFAULT_SHIP.skin;canvas.dataset.players=String(live?.others.length ?? 0);
        if (!bottleFoundRef.current && seaDistance(s.position, {x:1850,y:1470}) < 80) { bottleFoundRef.current = true; setBottleFound(true); setMessage('Uma garrafa! “Na selva, procure a praia a leste da caverna.”'); }
        if (bottleFoundRef.current && !secretFoundRef.current && seaDistance(s.position, {x:1090,y:1450}) < 80) { secretFoundRef.current = true; setSecretFound(true); setMessage('Passagem secreta descoberta — Selva dos Segredos.'); }
      }
      frame = requestAnimationFrame(render);
    };
    frame = requestAnimationFrame(render);
    return () => { cancelAnimationFrame(frame); observer.disconnect(); window.removeEventListener('keydown',keydown); window.removeEventListener('keyup',keyup); window.removeEventListener('blur',clear); };
  }, []);

  const sail = (event: React.PointerEvent<HTMLCanvasElement>) => {
    if (docking.current !== null) return;
    const rect = event.currentTarget.getBoundingClientRect(); const s = state.current;
    const point={ x: (event.clientX - rect.left - rect.width / 2) / s.scale + s.camera.x, y: (event.clientY - rect.top - rect.height / 2) / s.scale + s.camera.y };
    const hit=currentNetwork.current?.others.find(other => seaDistance(point,other)<(SHIP_MODELS.find(m => m.id===other.model)?.size ?? 160) / 2);
    if(hit) { setSelected(hit.user_id);setInspecting(false);return; }
    setSelected(null);s.target = seaClickTarget(point);
  };
  const island = nearby === null ? null : SEA_ISLANDS[nearby];
  const steer = (event: React.PointerEvent<HTMLButtonElement>) => {
    if (joystickPointer.current !== event.pointerId) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const x = event.clientX - rect.left - rect.width / 2;
    const y = event.clientY - rect.top - rect.height / 2;
    const radius = rect.width * .29;
    const distance = Math.hypot(x, y);
    const ratio = distance > radius ? radius / distance : 1;
    const offset = { x: x * ratio, y: y * ratio };
    joystickVector.current = distance < 6 ? { x: 0, y: 0 } : { x: offset.x / radius, y: offset.y / radius };
    if (distance < 6) state.current.target = { ...state.current.position };
    if (joystickKnob.current) joystickKnob.current.style.transform = `translate(${offset.x}px, ${offset.y}px)`;
  };
  return <section className="grand-line-ocean" aria-label="Grand Line — oceano navegável">
    <canvas ref={canvasRef} onPointerDown={sail} aria-label="Oceano da Grand Line" role="img" />
    <header className="ocean-hud">
      <OceanControl disabled={Boolean(battle) || network.busy} onClick={() => { if(network.data) void network.action('leave').then(ok => {if(ok) onBack();});else onBack(); }} title="Voltar ao porto" aria-label="Voltar ao porto"><ArrowLeft size={20} /></OceanControl>
      <div className="ocean-brand"><span>MYTHIC SEAS</span><h1>GRAND LINE</h1></div>
      <div className="ocean-berries"><img src={grandLineArt.berry} alt="" width={22} height={22} /><b>{new Intl.NumberFormat('pt-BR').format(Math.floor(berries))}</b><span>BERRIES</span></div>
    </header>
    <div className="ocean-instruments"><span><Waves size={15} /> {speed} nós</span><span className="ocean-hull" title="Casco de navegação">CASCO {ownShip.hp}/{shipMaxHp(ownShip)}</span><span>Nv. {ownShip.level}</span></div>
    <div className="naval-connection" role="status">{network.error || (network.data ? `${network.data.others.length} capitães à vista` : initData ? 'Conectando ao oceano compartilhado…' : 'Navegação local · oceano compartilhado indisponível')}</div>
    <div className="naval-controls"><OceanControl title="Estaleiro" aria-label="Estaleiro" onClick={openYard}><Ship size={20}/></OceanControl><label className="naval-throttle">Velocidade · {Math.round(throttle*100)}%<input aria-label="Velocidade do navio" type="range" min="0" max="100" value={throttle*100} onChange={e => setThrottle(Number(e.target.value)/100)}/></label>
      {battle && <><span className="naval-battle-status">GUERRA NAVAL</span><div className="naval-battle-controls"><OceanControl disabled={network.busy} aria-label="Disparar canhões" title="Disparar canhões" onClick={() => fireAction('fire')}><Crosshair size={22}/></OceanControl><OceanControl disabled={network.busy} aria-label="Salva especial" title="Salva especial" onClick={() => fireAction('skill')}><Zap size={22}/></OceanControl><OceanControl disabled={network.busy} aria-label="Abordar navio" title="Abordar navio" onClick={() => fireAction('board')}><Swords size={22}/></OceanControl><OceanControl disabled={network.busy} aria-label="Tentar fugir" title="Tentar fugir" onClick={() => fireAction('escape')}><Flag size={22}/></OceanControl></div></>}
    </div>
    {enemy && <div className="naval-enemy" role="dialog" aria-label="Navio inimigo"><h2>NAVIO INIMIGO</h2><p>{enemy.name} · Nv. {enemy.level}<br/>{SHIP_MODELS.find(m=>m.id===enemy.model)?.name} · {SHIP_SKINS.find(s=>s.id===enemy.skin)?.name}</p>{inspecting && <p>Vida {enemy.hp}/{shipMaxHp(enemy)} · Canhões {shipStats(enemy).cannons}<br/>Defesa {shipStats(enemy).defense} · Tripulação {shipStats(enemy).crew}</p>}<nav><OceanControl disabled={network.busy || !network.data?.rules.pvpEnabled || Boolean(battle)} onClick={() => void network.action('attack',{target:enemy.user_id}).then(ok=>{if(ok)setSelected(null);})}><Crosshair size={15}/>Atacar</OceanControl><OceanControl onClick={()=>setInspecting(true)}>Inspecionar</OceanControl><OceanControl onClick={()=>setSelected(null)}>Ignorar</OceanControl></nav>{!network.data?.rules.pvpEnabled && <small>Saque e guerra naval aguardam definição das regras.</small>}</div>}
    {yardOpen && <NavalShipyard ship={ownShip} state={network.data} busy={network.busy} onClose={()=>setYardOpen(false)} onSave={async input => {if(await network.action('customize',input))setYardOpen(false);}} onAction={async action => {await network.action(action);}}/>}
    <div className="ocean-compass" aria-label="Bússola"><span>N</span><Compass size={38} strokeWidth={1} /></div>
    <div className="ocean-view"><OceanControl title={wide ? 'Seguir navio' : 'Ver o arquipélago'} aria-label={wide ? 'Seguir navio' : 'Ver o arquipélago'} onClick={() => { wideRef.current = !wide; setWide(!wide); }}>{wide ? <Minimize2 size={19} /> : <Maximize2 size={19} />}</OceanControl></div>
    {message && <div className="ocean-discovery" role="status"><span>{bottleFound && !secretFound ? 'MAPA NA GARRAFA' : 'DESCOBERTA'}</span><p>{message}</p></div>}
    {island && !battle && <div className="ocean-dock"><span>{island.name}</span><OceanControl disabled={dockingNow || network.busy} onClick={() => { if (nearby === null) return; resetJoystick(); state.current.keys.clear(); state.current.target = { ...island.dock }; docking.current = nearby; setDockingNow(true); }}><Anchor size={17} />{dockingNow ? 'Atracando...' : 'Atracar no porto'}</OceanControl></div>}
    <nav className="ocean-helm" aria-label="Direção do navio">
      <OceanControl className="ocean-joystick" title="Joystick do navio" aria-label="Joystick do navio" disabled={dockingNow}
        onPointerDown={event => { if (joystickPointer.current !== null) return; joystickPointer.current = event.pointerId; event.currentTarget.setPointerCapture(event.pointerId); steer(event); }}
        onPointerMove={steer}
        onPointerUp={event => { if (joystickPointer.current === event.pointerId) resetJoystick(); }}
        onPointerCancel={event => { if (joystickPointer.current === event.pointerId) resetJoystick(); }}
        onLostPointerCapture={event => { if (joystickPointer.current === event.pointerId) resetJoystick(); }}>
        <span className="ocean-joystick-ring" aria-hidden="true" />
        <span ref={joystickKnob} className="ocean-joystick-knob" aria-hidden="true"><Compass size={24} strokeWidth={1.5} /></span>
      </OceanControl>
    </nav>
    <span className="ocean-coordinate">MAR ABERTO · {secretFound ? 'PASSAGEM DESCOBERTA' : bottleFound ? 'MAPA ENCONTRADO' : 'VENTO LESTE'}</span>
  </section>;
}