import { useEffect, useRef, useState } from 'react';
import { Anchor, Footprints, Swords, Compass } from 'lucide-react';
import { captainCharacters, type CaptainStyle } from '../captainCharacter';
import { grandLineArt, islandArt, mascotChestArt, realmArt } from '../gameAssets';
import { SEA_ISLANDS, seaDistance, type SeaDestination, type SeaPoint } from '../grandLineNavigation';
import { ISLAND_SIZE, ISLAND_SHIP, ISLAND_LANDING, walkIsland } from '../islandNavigation';
import type { RealmExploreNode, RealmState } from '../realm';
import { OceanControl } from './OceanControl';
import { IslandJoystick } from './IslandJoystick';

type Props = {
  islandIndex: number; captainStyle: CaptainStyle; data?: RealmState; loading: boolean; error?: string;
  busy: boolean; notice?: string | null;
  onStart: (regionId: string) => Promise<RealmState | null>;
  onEnter: (node: RealmExploreNode) => Promise<RealmState | null>;
  onChoose: (option: string) => Promise<RealmState | null>;
  onExtract: () => Promise<RealmState | null>;
  onActivity: (destination: SeaDestination) => void; onReturn: () => void;
};
type Encounter = { id: string; position: SeaPoint; name: string; art: string; node?: RealmExploreNode; kind: 'ship' | 'npc' | 'activity' | 'node' | 'secret' };
const labels: Record<string, string> = { treasure: 'Baú escondido', gather: 'Suprimentos', combat: 'Pirata inimigo', elite: 'Capitão inimigo', boss: 'Chefe da ilha', event: 'Náufrago', trap: 'Areia remexida', shrine: 'Relíquia antiga', rest: 'Acampamento' };
const options: Record<string, string> = { safe: 'Examinar com cuidado', force: 'Forçar passagem', help: 'Ajudar', fight: 'Lutar', flee: 'Recuar', open: 'Abrir', leave: 'Deixar', accept: 'Aceitar', decline: 'Recusar', investigate: 'Investigar', explore: 'Explorar', take: 'Recolher', ignore: 'Ignorar', pray: 'Investigar a relíquia', rest: 'Descansar' };
function nodePosition(node: RealmExploreNode): SeaPoint {
  const spots = [{ x: 970, y: 745 }, { x: 500, y: 755 }, { x: 775, y: 560 }, { x: 1050, y: 520 }, { x: 405, y: 455 }, { x: 1240, y: 255 }, { x: 760, y: 275 }];
  const index = node.node_type === 'boss' ? 6 : node.node_type === 'elite' ? 5 : Math.abs(node.depth * 3 + node.lane) % 6;
  return spots[index];
}
function nodeArt(node: RealmExploreNode) {
  if (['treasure', 'trap'].includes(node.node_type)) return mascotChestArt[node.node_type === 'trap' ? 'rare' : 'common'];
  if (['combat', 'elite', 'boss'].includes(node.node_type)) return node.node_type === 'boss' ? realmArt.foes.abyss : realmArt.party[0];
  return node.node_type === 'event' ? realmArt.party[2] : node.node_type === 'gather' ? realmArt.supplies : realmArt.mystery;
}

/** Physical presentation only: nodes, fees, encounters and rewards come from RealmState. */
export default function IslandExploration(props: Props) {
  const { islandIndex, captainStyle, data, busy, onReturn } = props;
  const island = SEA_ISLANDS[islandIndex] ?? SEA_ISLANDS[1];
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const world = useRef({ position: { ...ISLAND_SHIP }, target: { ...ISLAND_LANDING }, direction: { x: 0, y: 0 }, keys: new Set<string>(), phase: 'landing', camera: { ...ISLAND_SHIP }, flip: false });
  const [phase, setPhase] = useState('landing');
  const [nearest, setNearest] = useState<string | null>(null);
  const [talk, setTalk] = useState(false);
  const [secret, setSecret] = useState(false);
  const secretRef = useRef(false);
  const pendingRef = useRef(false);
  const activeRun = data?.exploreRun?.status === 'running' ? data.exploreRun : null;
  const region = activeRun ? data?.regions.find(r => r.id === activeRun.region_id) : data?.regions[Math.min(islandIndex === 1 ? 0 : islandIndex === 2 ? 1 : islandIndex === 3 ? 2 : 0, (data?.regions.length ?? 1) - 1)];
  const meta = data?.regionMeta.find(m => m.regionId === region?.id);
  const cost = meta?.stats.entryCost;
  const encounters: Encounter[] = [
    { id: 'ship', position: ISLAND_SHIP, name: 'Seu navio', art: grandLineArt.ship, kind: 'ship' },
    { id: 'npc', position: { x: 745, y: 680 }, name: 'Vigia do porto', art: realmArt.party[2], kind: 'npc' },
    { id: 'activity', position: { x: 405, y: 450 }, name: island.destination === 'forge' ? 'Oficina Naval' : island.destination === 'bounties' ? 'Vigia dos contratos' : island.destination === 'ruins' ? 'Entrada das ruínas' : 'Posto da Frota', art: realmArt.party[1], kind: 'activity' },
    { id: 'secret', position: { x: 1120, y: 540 }, name: 'Passagem entre as árvores', art: realmArt.mystery, kind: 'secret' },
    ...(activeRun ? (data?.exploreNodes ?? []).filter(n => ['available', 'active'].includes(n.status)).map(node => ({ id: node.id, position: nodePosition(node), name: labels[node.node_type] ?? 'Descoberta', art: nodeArt(node), node, kind: 'node' as const })) : []),
  ];
  const encounterRef = useRef(encounters); encounterRef.current = encounters;
  const selected = encounters.find(e => e.id === nearest);

  useEffect(() => {
    const canvas = canvasRef.current, ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return;
    const background = new Image(); background.src = islandArt[islandIndex] ?? islandArt[1];
    const pirate = new Image(); pirate.src = captainCharacters[captainStyle].image;
    const images = new Map<string, HTMLImageElement>();
    const css = getComputedStyle(canvas);
    const color = (token: string) => `hsl(${css.getPropertyValue(token).trim()})`;
    const ink = color('--ocean-shadow'), foam = color('--ocean-foam'), gold = color('--ocean-gold');
    const resize = () => { const r = canvas.getBoundingClientRect(); canvas.width = r.width * Math.min(devicePixelRatio, 2); canvas.height = r.height * Math.min(devicePixelRatio, 2); };
    const observer = new ResizeObserver(resize); observer.observe(canvas); resize();
    const keys = ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'w', 'a', 's', 'd'];
    const down = (e: KeyboardEvent) => { if (keys.includes(e.key)) { e.preventDefault(); world.current.keys.add(e.key); } };
    const up = (e: KeyboardEvent) => world.current.keys.delete(e.key);
    const clear = () => { const s = world.current; s.keys.clear(); s.direction = { x: 0, y: 0 }; if (s.phase === 'exploring') s.target = { ...s.position }; };
    window.addEventListener('keydown', down); window.addEventListener('keyup', up); window.addEventListener('blur', clear);
    let frame = 0, last = 0, hudTime = 0;
    const render = (time: number) => {
      const dt = Math.min((time - (last || time)) / 1000, .05); last = time;
      const s = world.current;
      if (s.phase === 'exploring') {
        const dx = s.direction.x || Number(s.keys.has('ArrowRight') || s.keys.has('d')) - Number(s.keys.has('ArrowLeft') || s.keys.has('a'));
        const dy = s.direction.y || Number(s.keys.has('ArrowDown') || s.keys.has('s')) - Number(s.keys.has('ArrowUp') || s.keys.has('w'));
        if (dx || dy) s.target = { x: s.position.x + dx * 100, y: s.position.y + dy * 100 };
      }
      const before = s.position; s.position = walkIsland(s.position, s.target, dt);
      const moving = seaDistance(before, s.position) > .1;
      if (moving && Math.abs(s.position.x - before.x) > .2) s.flip = s.position.x < before.x;
      if (s.phase === 'landing' && seaDistance(s.position, ISLAND_LANDING) < 5) { s.phase = 'exploring'; setPhase('exploring'); }
      if (s.phase === 'boarding' && seaDistance(s.position, ISLAND_SHIP) < 5) { s.phase = 'departed'; onReturn(); return; }
      const w = canvas.clientWidth, h = canvas.clientHeight, scale = w < 600 ? .9 : Math.max(.8, Math.min(1.15, w / 1536));
      s.camera.x += (s.position.x - s.camera.x) * Math.min(1, dt * 7); s.camera.y += (s.position.y - s.camera.y) * Math.min(1, dt * 7);
      const cameraX = Math.min(ISLAND_SIZE.width - Math.min(w / scale / 2, 768), Math.max(Math.min(w / scale / 2, 768), s.camera.x));
      const cameraY = Math.min(ISLAND_SIZE.height - Math.min(h / scale / 2, 512), Math.max(Math.min(h / scale / 2, 512), s.camera.y));
      ctx.setTransform(canvas.width / w, 0, 0, canvas.height / h, 0, 0); ctx.fillStyle = ink; ctx.fillRect(0, 0, w, h);
      ctx.save(); ctx.translate(w / 2, h / 2); ctx.scale(scale, scale); ctx.translate(-cameraX, -cameraY);
      if (background.complete && background.naturalWidth) ctx.drawImage(background, 0, 0, 1536, 1024);
      const visible = encounterRef.current.filter(e => e.kind === 'ship' || e.kind === 'activity' || e.kind === 'npc' || seaDistance(s.position, e.position) < (e.node?.node_type === 'trap' ? 100 : 360));
      for (const e of visible.sort((a, b) => a.position.y - b.position.y)) {
        if (e.kind === 'secret' && !secretRef.current && seaDistance(s.position, e.position) > 120) continue;
        let image = images.get(e.art); if (!image) { image = new Image(); image.src = e.art; images.set(e.art, image); }
        const size = e.kind === 'ship' ? 105 : e.node?.node_type === 'boss' ? 95 : e.kind === 'node' && ['treasure', 'trap'].includes(e.node?.node_type ?? '') ? 42 : 62;
        if (image.complete && image.naturalWidth) ctx.drawImage(image, e.position.x - size / 2, e.position.y - size, size, size);
        if (seaDistance(s.position, e.position) < 100) { ctx.font = 'bold 12px sans-serif'; ctx.textAlign = 'center'; ctx.strokeStyle = ink; ctx.lineWidth = 4; ctx.strokeText(e.name, e.position.x, e.position.y - size - 8); ctx.fillStyle = gold; ctx.fillText(e.name, e.position.x, e.position.y - size - 8); }
      }
      ctx.save(); ctx.translate(s.position.x, s.position.y); ctx.fillStyle = ink; ctx.globalAlpha = .3; ctx.beginPath(); ctx.ellipse(0, 0, 17, 6, 0, 0, Math.PI * 2); ctx.fill(); ctx.globalAlpha = 1;
      if (s.flip) ctx.scale(-1, 1);
      if (pirate.complete && pirate.naturalWidth) ctx.drawImage(pirate, -32, -78 + (moving ? Math.sin(time / 90) * 2 : 0), 64, 80);
      ctx.restore(); ctx.restore();
      canvas.dataset.pirateX = s.position.x.toFixed(0); canvas.dataset.pirateY = s.position.y.toFixed(0); canvas.dataset.phase = s.phase;
      canvas.dataset.cameraX = String(cameraX); canvas.dataset.cameraY = String(cameraY); canvas.dataset.scale = String(scale);
      if (time - hudTime > 120) {
        hudTime = time;
        const near = encounterRef.current.filter(e => seaDistance(s.position, e.position) < 100).sort((a, b) => seaDistance(s.position, a.position) - seaDistance(s.position, b.position))[0];
        setNearest(near?.id ?? null);
        if (!secretRef.current && seaDistance(s.position, { x: 1120, y: 540 }) < 100) { secretRef.current = true; setSecret(true); }
      }
      frame = requestAnimationFrame(render);
    };
    frame = requestAnimationFrame(render);
    return () => { cancelAnimationFrame(frame); observer.disconnect(); window.removeEventListener('keydown', down); window.removeEventListener('keyup', up); window.removeEventListener('blur', clear); };
  }, [islandIndex, captainStyle, onReturn]);

  const returnToSea = async () => {
    if (pendingRef.current || busy) return;
    pendingRef.current = true;
    if (activeRun) { const next = await props.onExtract(); if (!next) { pendingRef.current = false; return; } }
    const s = world.current; s.direction = { x: 0, y: 0 }; s.keys.clear(); s.target = { ...ISLAND_SHIP }; s.phase = 'boarding'; setPhase('boarding'); pendingRef.current = false;
  };
  const interact = async () => {
    if (!selected || busy || pendingRef.current) return;
    if (selected.kind === 'ship') { await returnToSea(); return; }
    if (selected.kind === 'npc') { setTalk(true); return; }
    if (selected.kind === 'activity') { props.onActivity(island.destination); return; }
    if (selected.node) { pendingRef.current = true; try { await props.onEnter(selected.node); } finally { pendingRef.current = false; } }
  };
  return <section className="island-exploration" aria-label={`Exploração de ${island.name}`}>
    <canvas ref={canvasRef} role="img" aria-label={`Ilha explorável: ${island.name}`} onPointerDown={e => { if (world.current.phase !== 'exploring' || talk || activeRun?.pending) return; const rect = e.currentTarget.getBoundingClientRect(); const scale = Number(e.currentTarget.dataset.scale); world.current.target = { x: (e.clientX - rect.left - rect.width / 2) / scale + Number(e.currentTarget.dataset.cameraX), y: (e.clientY - rect.top - rect.height / 2) / scale + Number(e.currentTarget.dataset.cameraY) }; }} />
    <header className="ocean-hud"><div className="ocean-brand"><span>MYTHIC SEAS</span><h1>{island.name}</h1></div><div className="ocean-berries"><img src={grandLineArt.berry} alt="" width={22} height={22} /><b>{Math.floor(data?.fc ?? 0).toLocaleString('pt-BR')}</b></div></header>
    <div className="ocean-instruments"><span><Footprints size={15} />{phase === 'landing' ? 'Desembarcando' : phase === 'boarding' ? 'Embarcando' : 'Em terra'}</span>{activeRun && <span><Swords size={15} />{activeRun.hp} HP</span>}</div>
    {(props.notice || props.error || secret) && <div className="island-notice" role="status">{props.notice || props.error || 'Passagem secreta descoberta entre as árvores.'}</div>}
    <IslandJoystick disabled={phase !== 'exploring' || talk || Boolean(activeRun?.pending)} onDirection={point => { const s = world.current; s.direction = point; if (!point.x && !point.y && s.phase === 'exploring') s.target = { ...s.position }; }} />
    {selected && phase === 'exploring' && !talk && !activeRun?.pending && selected.kind !== 'secret' && <div className="ocean-dock"><span>{selected.name}</span><OceanControl disabled={busy} onClick={() => void interact()}>{selected.kind === 'ship' ? <Anchor size={17} /> : <Compass size={17} />}{selected.kind === 'ship' ? 'Voltar ao mar' : selected.kind === 'node' ? selected.node?.node_type === 'treasure' ? 'Examinar baú' : 'Investigar' : selected.kind === 'npc' ? 'Conversar' : 'Entrar'}</OceanControl></div>}
    {talk && <div className="island-dialog" role="dialog" aria-label="Vigia do porto"><h2>Vigia do porto</h2><p>{activeRun ? 'Há rastros de piratas e objetos escondidos pelos caminhos. Volte ao seu navio para recolher o espólio.' : 'Há uma trilha de aventura além da praia. Posso preparar a sua jornada.'}</p>{props.loading ? <p>Consultando o diário de bordo...</p> : props.error ? <p>{props.error}</p> : !activeRun && region && cost !== undefined && <OceanControl disabled={busy || Number(data?.fc ?? 0) < cost || Number(data?.profile?.stronghold_level ?? 0) < region.unlock_stronghold_level} onClick={async () => { if (pendingRef.current) return; pendingRef.current = true; try { const next = await props.onStart(region.id); if (next) setTalk(false); } finally { pendingRef.current = false; } }}>Iniciar aventura · {cost.toLocaleString('pt-BR')} BERRIES</OceanControl>}<OceanControl onClick={() => setTalk(false)}>Continuar caminhando</OceanControl></div>}
    {activeRun?.pending && <div className="island-dialog" role="dialog" aria-label="Encontro da ilha"><h2>{labels[activeRun.pending.nodeType] ?? 'Encontro'}</h2>{activeRun.pending.options.map(option => <OceanControl key={option} disabled={busy} onClick={async () => { if (pendingRef.current) return; pendingRef.current = true; try { await props.onChoose(option); } finally { pendingRef.current = false; } }}>{options[option] ?? option.replace(/_/g, ' ')}</OceanControl>)}</div>}
    <span className="ocean-coordinate">{secret ? 'PASSAGEM DESCOBERTA' : 'GRAND LINE · EM TERRA'}</span>
  </section>;
}