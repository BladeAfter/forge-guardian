import { Suspense, useEffect, useMemo, useRef, type MutableRefObject } from 'react';
import { Environment, Lightformer, Html } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import { Physics, RigidBody, CapsuleCollider } from '@react-three/rapier';
import * as THREE from 'three';
import { newHarborState, type IslandInput, type IslandMotion, type IslandTelemetry } from '../../island3dWorld';
import type { RealmExploreNode } from '../../realm';
import type { IslandPalette } from './IslandTerrain';
import { IslandProp, IslandPirate, Dock } from './IslandModels';
import { IslandPlayer } from './IslandPlayer';
import { IslandHarbor } from './IslandHarbor';
import { IllustratedIsland } from './IllustratedIsland';
import { IslandMapCollisions } from './IslandMapCollisions';
import { ISLAND_MAP } from '../../illustratedIslandWorld';

export type IslandEncounter3D = { id: string; x: number; z: number; name: string; kind: 'ship' | 'npc' | 'activity' | 'secret' | 'node'; node?: RealmExploreNode };
type Props = { input: MutableRefObject<IslandInput>; palette: IslandPalette; captainStyle: 'male' | 'female'; encounters: IslandEncounter3D[]; openChest: string | null; fighting: string | null; onTelemetry: (t: IslandTelemetry) => void; onReturn: () => void; islandIndex: number };
function Loader() { return <Html center><span className="island3d-loading">Preparando a ilha 3D…</span></Html>; }

export function IslandScene({ input, palette, captainStyle, encounters, openChest, fighting, onTelemetry, onReturn, islandIndex }: Props) {
  const harbor = useRef(newHarborState());
  return <>
    <color attach="background" args={[palette.sky]} /><fog attach="fog" args={[palette.sky, 65, 200]} />
    <ambientLight intensity={.55} />
    <hemisphereLight args={[palette.sky, palette.sand, .8]} />
    <directionalLight position={[25, 40, 20]} intensity={2.2} color={palette.sun} castShadow shadow-mapSize-width={512} shadow-mapSize-height={512} shadow-camera-left={-50} shadow-camera-right={50} shadow-camera-top={50} shadow-camera-bottom={-50} shadow-bias={-.0008} />
    <Environment resolution={64} frames={1}><Lightformer intensity={2} position={[0, 20, 0]} rotation-x={-Math.PI / 2} scale={[60, 60, 1]} color={palette.sky} /><Lightformer intensity={1.4} position={[30, 10, 20]} scale={[30, 20, 1]} color={palette.sun} /></Environment>
    <Suspense fallback={<Loader />}>
      <IllustratedIsland islandIndex={islandIndex} />
      <Physics timeStep={1 / 60} gravity={[0, -19, 0]}>
        <IslandMapCollisions islandIndex={islandIndex} /><Dock palette={palette} illustrated />
        <IslandHarbor harbor={harbor} palette={palette} />
        {encounters.filter(e => e.kind !== 'ship' && e.kind !== 'secret').map(e => {
          const enemy = e.node && ['combat', 'elite', 'boss'].includes(e.node.node_type);
          const humanoid = enemy || e.kind === 'npc' || e.node?.node_type === 'event';
          if (humanoid) return <EncounterPirate key={e.id} encounter={e} palette={palette} fighting={fighting === e.id} />;
          return <group key={e.id} visible={e.kind !== 'activity'}><IslandProp model={e.kind === 'activity' ? 'structure' : e.node?.node_type === 'gather' ? 'crate' : e.node?.node_type === 'rest' ? 'barrel' : 'chest'} x={e.x} z={e.z} y={ISLAND_MAP.floor} scale={e.kind === 'activity' ? 1.7 : 1} collider={e.kind === 'activity' ? 'trimesh' : 'hull'} open={openChest === e.id} /></group>;
        })}
        <IslandPlayer harbor={harbor} input={input} onTelemetry={onTelemetry} onReturn={onReturn}>{(motion, speed) => <group scale={ISLAND_MAP.pirateScale}><IslandPirate style={captainStyle} motion={motion} speed={speed} palette={palette} /></group>}</IslandPlayer>
        <IslandDust input={input} palette={palette} />
      </Physics>
    </Suspense>
    {islandIndex === 3 && <pointLight position={[25, 8, -25]} intensity={10} color={palette.gold} distance={30} />}
  </>;
}

function EncounterPirate({ encounter, palette, fighting }: { encounter: IslandEncounter3D; palette: IslandPalette; fighting: boolean }) {
  const motion = useRef<IslandMotion>('idle'), speed = useRef(0), group = useRef<THREE.Group>(null);
  const enemy = Boolean(encounter.node && ['combat', 'elite', 'boss'].includes(encounter.node.node_type));
  useFrame(({ clock }) => { motion.current = fighting && Math.sin(clock.elapsedTime * 4) > 0 ? 'attack' : 'idle'; });
  return <RigidBody type="fixed" colliders={false} position={[encounter.x, ISLAND_MAP.floor, encounter.z]}><CapsuleCollider args={[.5, .3]} position={[0, .81, 0]} /><group ref={group} scale={ISLAND_MAP.pirateScale * (encounter.node?.node_type === 'boss' ? 1.3 : 1)} rotation-y={enemy ? Math.PI : -.5}><IslandPirate style={enemy ? 'male' : 'female'} motion={motion} speed={speed} palette={palette} /></group></RigidBody>;
}

function IslandDust({ input, palette }: { input: MutableRefObject<IslandInput>; palette: IslandPalette }) {
  const mesh = useRef<THREE.Points>(null);
  const geometry = useMemo(() => {
    const g = new THREE.BufferGeometry(), p = new Float32Array(70 * 3);
    for (let i = 0; i < 70; i++) p.set([Math.sin(i * 14) * 30, 1 + i % 6, Math.cos(i * 17) * 25], i * 3);
    g.setAttribute('position', new THREE.BufferAttribute(p, 3)); return g;
  }, []);
  useFrame((_, rawDelta) => { if (mesh.current && !input.current.blocked) mesh.current.rotation.y += Math.min(rawDelta, .05) * .015; });
  useEffect(() => () => geometry.dispose(), [geometry]);
  return <points ref={mesh} geometry={geometry}><pointsMaterial color={palette.sun} size={.065} transparent opacity={.6} depthWrite={false} /></points>;
}