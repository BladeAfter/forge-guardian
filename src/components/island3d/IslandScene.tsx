import { Suspense, useEffect, useMemo, useRef, type MutableRefObject } from 'react';
import { Environment, Lightformer, Html } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import { Physics, RigidBody, CapsuleCollider } from '@react-three/rapier';
import * as THREE from 'three';
import { islandHeight, newHarborState, type IslandInput, type IslandMotion, type IslandTelemetry } from '../../island3dWorld';
import type { RealmExploreNode } from '../../realm';
import { IslandTerrain, type IslandPalette } from './IslandTerrain';
import { IslandProp, IslandPirate, Dock } from './IslandModels';
import { IslandPlayer } from './IslandPlayer';
import { IslandHarbor } from './IslandHarbor';
import { IllustratedIsland } from './IllustratedIsland';

export type IslandEncounter3D = { id: string; x: number; z: number; name: string; kind: 'ship' | 'npc' | 'activity' | 'secret' | 'node'; node?: RealmExploreNode };
type Props = { input: MutableRefObject<IslandInput>; palette: IslandPalette; captainStyle: 'male' | 'female'; encounters: IslandEncounter3D[]; openChest: string | null; fighting: string | null; onTelemetry: (t: IslandTelemetry) => void; onReturn: () => void; islandIndex: number };
function Loader() { return <Html center><span className="island3d-loading">Preparando a ilha 3D…</span></Html>; }

export function IslandScene({ input, palette, captainStyle, encounters, openChest, fighting, onTelemetry, onReturn, islandIndex }: Props) {
  const harbor = useRef(newHarborState());
  const palms = useMemo(() => Array.from({ length: 24 }, (_, index) => {
    const angle = index * 2.399963;
    const radius = 12 + (index * 13 % 24);
    return { x: Math.cos(angle) * radius, z: Math.sin(angle) * radius - 3, scale: 1.1 + index % 3 * .22 };
  }).filter(p => Math.abs(p.x - Math.sin(p.z * .1) * 3) > 4 && !encounters.some(e => Math.hypot(e.x - p.x, e.z - p.z) < 3.5)), [encounters]);
  return <>
    <color attach="background" args={[palette.sky]} /><fog attach="fog" args={[palette.sky, 65, 200]} />
    <ambientLight intensity={.55} />
    <hemisphereLight args={[palette.sky, palette.sand, .8]} />
    <directionalLight position={[25, 40, 20]} intensity={2.2} color={palette.sun} castShadow shadow-mapSize-width={512} shadow-mapSize-height={512} shadow-camera-left={-50} shadow-camera-right={50} shadow-camera-top={50} shadow-camera-bottom={-50} shadow-bias={-.0008} />
    <Environment resolution={64} frames={1}><Lightformer intensity={2} position={[0, 20, 0]} rotation-x={-Math.PI / 2} scale={[60, 60, 1]} color={palette.sky} /><Lightformer intensity={1.4} position={[30, 10, 20]} scale={[30, 20, 1]} color={palette.sun} /></Environment>
    <Suspense fallback={<Loader />}>
      <IllustratedIsland islandIndex={islandIndex} />
      <Physics timeStep={1 / 60} gravity={[0, -19, 0]}>
        <group visible={false}><IslandTerrain palette={palette} /></group><Dock palette={palette} />
        <IslandHarbor harbor={harbor} palette={palette} />
        <group visible={false}>
        <IslandProp model="flag" x={-1.4} z={43} y={1} scale={1.2} collider="none" />
        {palms.map((p, i) => <IslandProp key={`palm-${i}`} model={i % 3 ? 'palm' : 'palmStraight'} {...p} rotation={i * 1.3} collider="tree" wind />)}
        {[-1, 1].flatMap(side => Array.from({ length: 5 }, (_, i) => <IslandProp key={`rock-${side}-${i}`} model={i % 2 ? 'rock' : 'rockB'} x={side * (19 + i * 4)} z={8 - i * 7} scale={.6 + i * .12} rotation={i * 2} />))}
        <IslandProp model="gate" x={-10} z={-27} scale={1.5} collider="trimesh" />
        <IslandProp model="wall" x={-16} z={-29} scale={1.5} rotation={.3} collider="trimesh" />
        <IslandProp model="wall" x={-4} z={-29} scale={1.5} rotation={-.3} collider="trimesh" />
        <IslandProp model="rock" x={21} z={-10} scale={1.8} />
        <IslandProp model="rockB" x={27} z={-11} scale={1.6} />
        <IslandProp model="rock" x={24} z={-14} scale={1.7} y={islandHeight(24, -14) + 4.1} collider="trimesh" />
        <IslandProp model="structure" x={-21} z={11} scale={2} collider="trimesh" />
        <IslandProp model="barrel" x={-18} z={13} scale={1.3} />
        <IslandProp model="crate" x={-23} z={15} scale={1.3} />
        <IslandProp model="cannon" x={-17} z={9} scale={1.3} rotation={1.3} />
        </group>
        {encounters.filter(e => e.kind !== 'ship' && e.kind !== 'secret').map(e => {
          const enemy = e.node && ['combat', 'elite', 'boss'].includes(e.node.node_type);
          const humanoid = enemy || e.kind === 'npc' || e.node?.node_type === 'event';
          if (humanoid) return <EncounterPirate key={e.id} encounter={e} palette={palette} fighting={fighting === e.id} />;
          return <group key={e.id} visible={e.kind !== 'activity'}><IslandProp model={e.kind === 'activity' ? 'structure' : e.node?.node_type === 'gather' ? 'crate' : e.node?.node_type === 'rest' ? 'barrel' : 'chest'} x={e.x} z={e.z} scale={e.kind === 'activity' ? 1.7 : 1} collider={e.kind === 'activity' ? 'trimesh' : 'hull'} open={openChest === e.id} /></group>;
        })}
        <IslandPlayer harbor={harbor} input={input} onTelemetry={onTelemetry} onReturn={onReturn}>{(motion, speed) => <IslandPirate style={captainStyle} motion={motion} speed={speed} palette={palette} />}</IslandPlayer>
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
  return <RigidBody type="fixed" colliders={false} position={[encounter.x, islandHeight(encounter.x, encounter.z), encounter.z]} scale={encounter.node?.node_type === 'boss' ? 1.6 : 1}><CapsuleCollider args={[.5, .3]} position={[0, .81, 0]} /><group ref={group} rotation-y={enemy ? Math.PI : -.5}><IslandPirate style={enemy ? 'male' : 'female'} motion={motion} speed={speed} palette={palette} /></group></RigidBody>;
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