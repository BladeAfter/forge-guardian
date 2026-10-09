import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, Anchor, Compass, Maximize2, Minimize2, Waves } from 'lucide-react';
import { grandLineArt } from '../gameAssets';
import { SEA_ISLANDS, SEA_SIZE, sailToward, seaClickTarget, seaDistance, type SeaDestination, type SeaPoint } from '../grandLineNavigation';
import { OceanControl } from './OceanControl';

type Props = { berries: number; onBack: () => void; onDock: (destination: SeaDestination) => void };
export default function GrandLineOcean({ berries, onBack, onDock }: Props) {
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
  const state = useRef({ position: { x: 1700, y: 1340 }, target: { x: 1700, y: 1340 }, heading: 0, camera: { x: 1700, y: 1340 }, scale: 0.7, keys: new Set<string>(), moving: false });
  const [wide, setWide] = useState(false);
  const wideRef = useRef(false);
  const [nearby, setNearby] = useState<number | null>(1);
  const [speed, setSpeed] = useState(0);
  const [message, setMessage] = useState('');
  const [bottleFound, setBottleFound] = useState(false);
  const [secretFound, setSecretFound] = useState(false);
  const bottleFoundRef = useRef(false);
  const secretFoundRef = useRef(false);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return;
    const ocean = new Image(); ocean.src = grandLineArt.ocean;
    const ship = new Image(); ship.src = grandLineArt.ship;
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
      const dx = joystickVector.current.x || Number(k.has('ArrowRight') || k.has('d')) - Number(k.has('ArrowLeft') || k.has('a'));
      const dy = joystickVector.current.y || Number(k.has('ArrowDown') || k.has('s')) - Number(k.has('ArrowUp') || k.has('w'));
      if (dx || dy) s.target = { x: s.position.x + dx * 120, y: s.position.y + dy * 120 };
      const distance = seaDistance(s.position, s.target); s.moving = distance > 3;
      if (s.moving) {
        s.heading = Math.atan2(s.target.x - s.position.x, -(s.target.y - s.position.y));
        const next = sailToward(s.position, s.target, dt);
        const land = SEA_ISLANDS.some(i => seaDistance(next, i.center) < i.radius * .7);
        if (!land) s.position = next;
        else s.target = { ...s.position };
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
      const sprite = (p: SeaPoint, angle: number, size: number, enemy = false) => {
        ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(angle);
        ctx.globalAlpha = .5; ctx.strokeStyle = foam; ctx.lineWidth = 3;
        ctx.beginPath(); ctx.moveTo(-13, 38); ctx.lineTo(-32, 115); ctx.moveTo(13,38); ctx.lineTo(32,115); ctx.stroke();
        ctx.globalAlpha = 1; if (enemy) ctx.filter = 'brightness(.65)';
        if (ship.complete && ship.naturalWidth) ctx.drawImage(ship, -size / 2, -size / 2, size, size);
        ctx.restore();
      };
      const seconds = reduced ? 0 : time / 1000;
      sprite({ x: 1900 + Math.sin(seconds / 14) * 280, y: 450 + Math.cos(seconds / 14) * 110 }, Math.PI / 2 - seconds / 14, 90, true);
      sprite({ x: 1250 + Math.cos(seconds / 19) * 130, y: 1730 + Math.sin(seconds / 19) * 90 }, -seconds / 19, 74);
      sprite({ x: 2840 + Math.cos(seconds / 13) * 90, y: 1020 + Math.sin(seconds / 13) * 160 }, seconds / 13, 84, true);
      // Sea spray and a passing whale, kept in world coordinates.
      if (!reduced) {
        ctx.strokeStyle = foam; ctx.globalAlpha = .16; ctx.lineWidth = 2;
        for (let i = 0; i < 30; i++) { const x = (i * 313 + seconds * 8) % 3200; const y = (i * 197) % 2133; ctx.beginPath(); ctx.ellipse(x,y,27,7,0,0,Math.PI); ctx.stroke(); }
        ctx.globalAlpha = .65 + Math.sin(seconds / 4) * .2; ctx.fillStyle = deep; ctx.beginPath(); ctx.ellipse(1940 + Math.sin(seconds / 20) * 80, 1880, 45, 16, -.4, 0, Math.PI * 2); ctx.fill(); ctx.globalAlpha = 1;
      }
      if (!bottleFoundRef.current) { ctx.save(); ctx.translate(1850,1470); ctx.rotate(Math.sin(seconds) * .2); ctx.fillStyle = gold; ctx.fillRect(-5,-13,10,26); ctx.strokeStyle = foam; ctx.strokeRect(-5,-13,10,26); ctx.restore(); }
      if (bottleFoundRef.current && !secretFoundRef.current) { ctx.fillStyle = gold; ctx.font = 'bold 20px sans-serif'; ctx.fillText('×', 1090, 1450); }
      if (s.moving) { ctx.strokeStyle = gold; ctx.globalAlpha = .6; ctx.beginPath(); ctx.ellipse(s.target.x,s.target.y,14,8,0,0,Math.PI*2); ctx.stroke(); ctx.globalAlpha = 1; }
      sprite(s.position, s.heading, 115);
      ctx.restore();
      if (time - uiTime > 180) {
        uiTime = time; setSpeed(s.moving ? 8 : 0);
        const index = SEA_ISLANDS.findIndex(i => seaDistance(s.position, i.dock) < 190); setNearby(index < 0 ? null : index);
        canvas.dataset.shipX = s.position.x.toFixed(0); canvas.dataset.shipY = s.position.y.toFixed(0);
        canvas.dataset.cameraX = s.camera.x.toFixed(2); canvas.dataset.cameraY = s.camera.y.toFixed(2); canvas.dataset.scale = String(s.scale);
        if (!bottleFoundRef.current && seaDistance(s.position, {x:1850,y:1470}) < 80) { bottleFoundRef.current = true; setBottleFound(true); setMessage('Uma garrafa! “Na selva, procure a praia a leste da caverna.”'); }
        if (bottleFoundRef.current && !secretFoundRef.current && seaDistance(s.position, {x:1090,y:1450}) < 80) { secretFoundRef.current = true; setSecretFound(true); setMessage('Passagem secreta descoberta — Selva dos Segredos.'); }
      }
      frame = requestAnimationFrame(render);
    };
    frame = requestAnimationFrame(render);
    return () => { cancelAnimationFrame(frame); observer.disconnect(); window.removeEventListener('keydown',keydown); window.removeEventListener('keyup',keyup); window.removeEventListener('blur',clear); };
  }, []);

  const sail = (event: React.PointerEvent<HTMLCanvasElement>) => {
    const rect = event.currentTarget.getBoundingClientRect(); const s = state.current;
    s.target = seaClickTarget({ x: (event.clientX - rect.left - rect.width / 2) / s.scale + s.camera.x, y: (event.clientY - rect.top - rect.height / 2) / s.scale + s.camera.y });
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
      <OceanControl onClick={onBack} title="Voltar ao porto" aria-label="Voltar ao porto"><ArrowLeft size={20} /></OceanControl>
      <div className="ocean-brand"><span>MYTHIC SEAS</span><h1>GRAND LINE</h1></div>
      <div className="ocean-berries"><img src={grandLineArt.berry} alt="" width={22} height={22} /><b>{new Intl.NumberFormat('pt-BR').format(Math.floor(berries))}</b><span>BERRIES</span></div>
    </header>
    <div className="ocean-instruments"><span><Waves size={15} /> {speed} nós</span><span className="ocean-hull" title="Casco de navegação">CASCO <i /></span></div>
    <div className="ocean-compass" aria-label="Bússola"><span>N</span><Compass size={38} strokeWidth={1} /></div>
    <div className="ocean-view"><OceanControl title={wide ? 'Seguir navio' : 'Ver o arquipélago'} aria-label={wide ? 'Seguir navio' : 'Ver o arquipélago'} onClick={() => { wideRef.current = !wide; setWide(!wide); }}>{wide ? <Minimize2 size={19} /> : <Maximize2 size={19} />}</OceanControl></div>
    {message && <div className="ocean-discovery" role="status"><span>{bottleFound && !secretFound ? 'MAPA NA GARRAFA' : 'DESCOBERTA'}</span><p>{message}</p></div>}
    {island && <div className="ocean-dock"><span>{island.name}</span><OceanControl onClick={() => onDock(island.destination)}><Anchor size={17} />{island.action}</OceanControl></div>}
    <nav className="ocean-helm" aria-label="Direção do navio">
      <OceanControl className="ocean-joystick" title="Joystick do navio" aria-label="Joystick do navio"
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