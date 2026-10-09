import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Canvas } from '@react-three/fiber';
import { Anchor, Footprints, Swords, Compass, ArrowUp, Wind, RotateCcw, Plus, Minus, X } from 'lucide-react';
import type { CaptainStyle } from '../captainCharacter';
import { grandLineArt } from '../gameAssets';
import type { NavalShip } from '../naval';
import { SEA_ISLANDS, type SeaDestination } from '../grandLineNavigation';
import { newIslandInput, nodePosition3D, ISLAND_3D, type IslandTelemetry } from '../island3dWorld';
import type { RealmExploreNode, RealmExploreLog, RealmState } from '../realm';
import { OceanControl } from './OceanControl';
import { IslandJoystick } from './IslandJoystick';
import { IslandScene, type IslandEncounter3D } from './island3d/IslandScene';
import { readIslandPalette, type IslandPalette } from './island3d/IslandTerrain';

type Props = {
  ship?: NavalShip; islandIndex: number; captainStyle: CaptainStyle; data?: RealmState; loading: boolean; error?: string;
  busy: boolean; notice?: string | null;
  onStart: (regionId: string) => Promise<RealmState | null>;
  onEnter: (node: RealmExploreNode) => Promise<RealmState | null>;
  onChoose: (option: string) => Promise<RealmState | null>;
  onExtract: () => Promise<RealmState | null>;
  onActivity: (destination: SeaDestination) => void; onReturn: () => void;
};
const labels: Record<string, string> = { treasure: 'Baú escondido', gather: 'Suprimentos', combat: 'Pirata inimigo', elite: 'Capitão inimigo', boss: 'Chefe da ilha', event: 'Náufrago', trap: 'Areia remexida', shrine: 'Relíquia antiga', rest: 'Acampamento' };
const options: Record<string, string> = { safe: 'Examinar com cuidado', force: 'Forçar passagem', help: 'Ajudar', fight: 'Lutar', flee: 'Recuar', open: 'Abrir baú', leave: 'Deixar', accept: 'Aceitar', decline: 'Recusar', investigate: 'Investigar', explore: 'Explorar', take: 'Recolher', ignore: 'Ignorar', pray: 'Investigar a relíquia', rest: 'Descansar' };
const motionLabels: Record<string, string> = { idle: 'Em terra', walk: 'Caminhando', run: 'Correndo', sprint: 'Sprint', jump: 'Pulando', fall: 'No ar', dodge: 'Esquivando', attack: 'Atacando', interact: 'Interagindo', swim: 'Nadando', climb: 'Subindo', descend: 'Descendo' };

/** 3D movement is cosmetic; every rewarding encounter stays server-authoritative. */
export default function IslandExploration(props: Props) {
  const { islandIndex, captainStyle, data, busy } = props;
  const island = SEA_ISLANDS[islandIndex] ?? SEA_ISLANDS[1];
  const host = useRef<HTMLElement>(null), stage = useRef<HTMLDivElement>(null);
  const input = useRef(newIslandInput()), pending = useRef(false);
  const mapCameraReady = useRef(false);
  if (!mapCameraReady.current) { input.current.yaw = 0; input.current.pitch = 1.15; input.current.zoom = 48; mapCameraReady.current = true; }
  const [palette, setPalette] = useState<IslandPalette | null>(null);
  const [telemetry, setTelemetry] = useState<IslandTelemetry>({ x: ISLAND_3D.spawn.x, y: 1, z: ISLAND_3D.spawn.z, speed: 0, motion: 'idle', phase: 'approaching', heading: Math.PI });
  const [talk, setTalk] = useState(false), [secret, setSecret] = useState(false);
  const [log, setLog] = useState<RealmExploreLog | null>(null), [openChest, setOpenChest] = useState<string | null>(null), [fighting, setFighting] = useState<string | null>(null);
  const [sprinting, setSprinting] = useState(false);
  const activeRun = data?.exploreRun ?? null;
  const region = activeRun ? data?.regions.find(r => r.id === activeRun.region_id) : data?.regions[Math.min(islandIndex === 2 ? 1 : islandIndex === 3 ? 2 : 0, (data?.regions.length ?? 1) - 1)];
  const cost = data?.regionMeta.find(m => m.regionId === region?.id)?.stats.entryCost;
  const encounters = useMemo<IslandEncounter3D[]>(() => [
    { id: 'ship', ...ISLAND_3D.dock, name: props.ship?.name ?? 'Seu navio', kind: 'ship' },
    { id: 'npc', x: 1.8, z: 27, name: 'Vigia do porto', kind: 'npc' },
    { id: 'activity', x: -16, z: 17, name: island.destination === 'forge' ? 'Oficina Naval' : island.destination === 'bounties' ? 'Vigia dos contratos' : island.destination === 'ruins' ? 'Entrada das ruínas' : 'Posto da Frota', kind: 'activity' },
    { id: 'secret', x: 24, z: -10, name: 'Passagem escondida', kind: 'secret' },
    ...(activeRun ? (data?.exploreNodes ?? []).filter(n => !['locked', 'skipped'].includes(n.status)).map(node => ({ id: node.id, ...nodePosition3D(node), name: labels[node.node_type] ?? 'Descoberta', node, kind: 'node' as const })) : []),
  ], [props.ship?.name, island.destination, activeRun?.id, data?.exploreNodes]);
  const selected = encounters.filter(e => (!e.node || ['available', 'active'].includes(e.node.status)) && Math.hypot(e.x - telemetry.x, e.z - telemetry.z) < (e.kind === 'ship' ? 3.5 : 3.1)).sort((a, b) => Math.hypot(a.x - telemetry.x, a.z - telemetry.z) - Math.hypot(b.x - telemetry.x, b.z - telemetry.z))[0];
  const locked = talk || Boolean(activeRun?.pending) || busy || Boolean(log && fighting);
  input.current.blocked = locked; input.current.sprint = sprinting;
  const report = useCallback((value: IslandTelemetry) => {
    setTelemetry(value);
    if (stage.current) { stage.current.dataset.pirateX = String(value.x); stage.current.dataset.pirateY = String(value.y); stage.current.dataset.pirateZ = String(value.z); stage.current.dataset.phase = value.phase; stage.current.dataset.motion = value.motion; }
  }, []);

  useEffect(() => { if (host.current) setPalette(readIslandPalette(host.current)); }, []);
  useEffect(() => {
    const keys = new Set<string>();
    const update = () => {
      input.current.x = Number(keys.has('KeyD') || keys.has('ArrowRight')) - Number(keys.has('KeyA') || keys.has('ArrowLeft'));
      input.current.y = Number(keys.has('KeyS') || keys.has('ArrowDown')) - Number(keys.has('KeyW') || keys.has('ArrowUp'));
      input.current.jump = keys.has('Space'); setSprinting(keys.has('ShiftLeft') || keys.has('ShiftRight'));
    };
    const down = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement)?.closest('input,textarea,select')) return;
      if (['KeyW','KeyA','KeyS','KeyD','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Space','ShiftLeft','ShiftRight','KeyQ','KeyF'].includes(e.code)) {
        e.preventDefault(); keys.add(e.code); if (!e.repeat && e.code === 'KeyQ') input.current.dodge = true; if (!e.repeat && e.code === 'KeyF') input.current.attack = true; update();
      }
    };
    const up = (e: KeyboardEvent) => { keys.delete(e.code); update(); };
    const clear = () => { keys.clear(); input.current.x = 0; input.current.y = 0; input.current.jump = false; input.current.dodge = false; input.current.attack = false; setSprinting(false); };
    const visibility = () => { if (document.hidden) clear(); };
    window.addEventListener('keydown', down); window.addEventListener('keyup', up); window.addEventListener('blur', clear); document.addEventListener('visibilitychange', visibility);
    return () => { clear(); window.removeEventListener('keydown', down); window.removeEventListener('keyup', up); window.removeEventListener('blur', clear); document.removeEventListener('visibilitychange', visibility); };
  }, []);
  useEffect(() => { if (Math.hypot(telemetry.x - 24, telemetry.z + 10) < 4) setSecret(true); }, [telemetry.x, telemetry.z]);
  const returnToSea = async () => {
    if (pending.current || busy) return;
    pending.current = true;
    try { if (activeRun && !await props.onExtract()) return; input.current.x = 0; input.current.y = 0; input.current.boarding = true; }
    finally { pending.current = false; }
  };
  const encounterResult = (next: RealmState | null, id?: string) => {
    if (!next?.lastNode) return;
    if (next.lastNode.rounds?.length && id) { setFighting(id); setLog(next.lastNode); input.current.attack = true; }
    else if (next.lastNode.fc || next.lastNode.fragments || next.lastNode.materialQty) setLog(next.lastNode);
  };
  const interact = async () => {
    if (!selected || pending.current || busy) return;
    input.current.interact = true;
    if (selected.kind === 'ship') { await returnToSea(); return; }
    if (selected.kind === 'npc') { setTalk(true); return; }
    if (selected.kind === 'activity') { props.onActivity(island.destination); return; }
    if (selected.node) {
      pending.current = true;
      try { const next = await props.onEnter(selected.node); if (next && selected.node.node_type === 'treasure' && !next.exploreRun?.pending) setOpenChest(selected.id); encounterResult(next, selected.id); }
      finally { pending.current = false; }
    }
  };
  const pointer = useRef<{ id: number; x: number; y: number } | null>(null);
  return <section ref={host} className="island-exploration" aria-label={`Exploração 3D de ${island.name}`}>
    <div ref={stage} className="island3d-stage" role="img" aria-label={`Ilha 3D explorável: ${island.name}`}
      onPointerDown={e => { if (pointer.current) return; pointer.current = { id: e.pointerId, x: e.clientX, y: e.clientY }; e.currentTarget.setPointerCapture(e.pointerId); }}
      onPointerMove={e => { const p = pointer.current; if (!p || p.id !== e.pointerId) return; input.current.zoom = Math.max(18, Math.min(55, input.current.zoom + (e.clientY - p.y) * .04)); p.x = e.clientX; p.y = e.clientY; }}
      onPointerUp={() => { pointer.current = null; }} onPointerCancel={() => { pointer.current = null; }} onLostPointerCapture={() => { pointer.current = null; }}
      onWheel={e => { input.current.zoom = Math.max(18, Math.min(55, input.current.zoom + e.deltaY * .02)); }}>
      {palette && <Canvas orthographic shadows dpr={[1, 1.5]} camera={{ position: [0, 65, 70], zoom: 20, near: .1, far: 350 }} gl={{ antialias: true }}><IslandScene palette={palette} input={input} captainStyle={captainStyle} islandIndex={islandIndex} encounters={encounters} openChest={openChest} fighting={fighting} onTelemetry={report} onReturn={props.onReturn} /></Canvas>}
    </div>
    <header className="ocean-hud"><div className="ocean-brand"><span>MYTHIC SEAS · GRAND LINE</span><h1>{island.name}</h1></div><div className="ocean-berries"><img src={grandLineArt.berry} alt="" width={22} height={22} /><b>{Math.floor(data?.fc ?? 0).toLocaleString('pt-BR')}</b></div></header>
    <div className="ocean-instruments"><span><Footprints size={15} />{telemetry.phase === 'approaching' ? 'Atracando' : telemetry.phase === 'deploying' ? 'Preparando passarela' : telemetry.phase === 'landing' ? 'Desembarcando' : telemetry.phase === 'boarding' ? 'Embarcando' : motionLabels[telemetry.motion]}</span>{activeRun && <span><Swords size={15} />{activeRun.hp} HP</span>}</div>
    {(props.notice || props.error) && <div className="island-notice" role="status">{props.notice || props.error}</div>}
    <IslandJoystick disabled={telemetry.phase !== 'exploring' || locked} onDirection={point => { input.current.x = point.x; input.current.y = point.y; }} />
    <nav className="island3d-actions" aria-label="Ações do pirata">
      <OceanControl aria-label="Pular" title="Pular" disabled={locked} onPointerDown={e => { e.currentTarget.setPointerCapture(e.pointerId); input.current.jump = true; }} onPointerUp={() => { input.current.jump = false; }} onPointerCancel={() => { input.current.jump = false; }} onLostPointerCapture={() => { input.current.jump = false; }}><ArrowUp size={20} /></OceanControl>
      <OceanControl aria-label="Sprint" title="Sprint" aria-pressed={sprinting} disabled={locked} onClick={() => setSprinting(v => !v)}><Wind size={20} /></OceanControl>
      <OceanControl aria-label="Esquivar" title="Esquivar" disabled={locked} onClick={() => { input.current.dodge = true; }}><RotateCcw size={20} /></OceanControl>
      <OceanControl aria-label="Golpe" title="Golpe" disabled={locked} onClick={() => { input.current.attack = true; }}><Swords size={20} /></OceanControl>
    </nav>
    <nav className="island3d-camera" aria-label="Câmera"><OceanControl aria-label="Aproximar câmera" title="Aproximar câmera" onClick={() => { input.current.zoom = Math.max(18, input.current.zoom - 4); }}><Plus size={16} /></OceanControl><OceanControl aria-label="Afastar câmera" title="Afastar câmera" onClick={() => { input.current.zoom = Math.min(55, input.current.zoom + 4); }}><Minus size={16} /></OceanControl><OceanControl aria-label="Centralizar câmera" title="Centralizar câmera" onClick={() => { input.current.yaw = 0; input.current.pitch = 1.15; input.current.zoom = 48; }}><Compass size={16} /></OceanControl></nav>
    {selected && telemetry.phase === 'exploring' && !locked && selected.kind !== 'secret' && <div className="ocean-dock"><span>{selected.name}</span><OceanControl disabled={busy} onClick={() => void interact()}>{selected.kind === 'ship' ? <Anchor size={17} /> : <Compass size={17} />}{selected.kind === 'ship' ? 'Voltar ao mar' : selected.kind === 'node' ? selected.node?.node_type === 'treasure' ? 'Abrir baú' : 'Investigar' : selected.kind === 'npc' ? 'Conversar' : 'Entrar'}</OceanControl></div>}
    {talk && <div className="island-dialog" role="dialog" aria-label="Vigia do porto"><h2>Vigia do porto</h2><p>{activeRun ? 'Há rastros de piratas e objetos escondidos na ilha. Retorne ao seu navio para guardar o espólio.' : 'Posso preparar sua jornada além da praia.'}</p>{props.loading ? <p>Consultando o diário de bordo...</p> : props.error ? <p>{props.error}</p> : !activeRun && region && cost !== undefined && <OceanControl disabled={busy || Number(data?.fc ?? 0) < cost || Number(data?.profile?.stronghold_level ?? 0) < region.unlock_stronghold_level} onClick={async () => { if (pending.current) return; pending.current = true; try { if (await props.onStart(region.id)) setTalk(false); } finally { pending.current = false; } }}>Iniciar aventura · {cost.toLocaleString('pt-BR')} BERRIES</OceanControl>}<OceanControl onClick={() => setTalk(false)}>Continuar caminhando</OceanControl></div>}
    {activeRun?.pending && <div className="island-dialog" role="dialog" aria-label="Encontro da ilha"><h2>{labels[activeRun.pending.nodeType] ?? 'Encontro'}</h2>{activeRun.pending.options.map(option => <OceanControl key={option} disabled={busy} onClick={async () => { if (pending.current) return; pending.current = true; input.current.interact = true; try { const next = await props.onChoose(option); if (next && ['open','take'].includes(option)) setOpenChest(activeRun.pending?.nodeId ?? null); encounterResult(next, activeRun.pending?.nodeId); } finally { pending.current = false; } }}>{options[option] ?? option.replace(/_/g, ' ')}</OceanControl>)}</div>}
    {log && <div className="island3d-log" role="status"><span>{log.rounds?.length ? `Encontro resolvido · ${log.rounds.length} rodadas · ${log.damage ?? 0} dano recebido` : `Espólio encontrado${log.fc ? ` · ${log.fc.toLocaleString('pt-BR')} BERRIES` : ''}${log.fragments ? ` · ${log.fragments} fragmentos` : ''}${log.materialQty ? ` · ${log.materialQty} materiais` : ''}`}</span><OceanControl aria-label="Continuar exploração" title="Continuar exploração" onClick={() => { setLog(null); setFighting(null); }}><X size={16} /></OceanControl></div>}
    <span className="ocean-coordinate">{secret ? 'PASSAGEM DESCOBERTA' : island.name.toLocaleUpperCase('pt-BR')}</span>
  </section>;
}
