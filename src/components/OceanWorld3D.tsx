import { Suspense, useEffect, useMemo, useRef, useState, type MutableRefObject } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { Environment, Lightformer, useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import { islandModels } from '../gameAssets';
import { type NavalState } from '../naval';
import { SEA_CHUNK, seaIslandsAround, type SeaIsland, type SeaPoint } from '../grandLineNavigation';
import { readIslandPalette, type IslandPalette } from './island3d/IslandTerrain';

export type OceanPose = { position: SeaPoint; heading: number; moving: boolean };
const UNIT = .1;
function Model({ model, scale = 1 }: { model: keyof typeof islandModels; scale?: number }) {
  const { scene } = useGLTF(islandModels[model]);
  const clone = useMemo(() => scene.clone(true), [scene]);
  return <primitive object={clone} scale={scale} />;
}

function Island({ island, origin, palette }: { island: SeaIsland; origin: SeaPoint; palette: IslandPalette }) {
  const r = island.radius * UNIT;
  const geometry = useMemo(() => {
    const geo = new THREE.PlaneGeometry(r * 2.6, r * 2.6, 24, 24); geo.rotateX(-Math.PI / 2);
    const p = geo.attributes.position;
    const colors = new Float32Array(p.count * 3);
    const sand = new THREE.Color(palette.sand), grass = new THREE.Color(palette.grass), stone = new THREE.Color(island.templateIndex === 3 ? palette.foam : palette.stone);
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i), z = p.getZ(i), d = Math.hypot(x, z) / r;
      const height = Math.max(-2, (1 - d) * r * .55 + Math.sin(x * .17) * Math.cos(z * .19) * 2);
      p.setY(i, height);
      const c = sand.clone().lerp(grass, THREE.MathUtils.smoothstep(height, 1, 5)).lerp(stone, THREE.MathUtils.smoothstep(height, r * .2, r * .5));
      c.multiplyScalar(.92 + .08 * Math.cos(x + z)); colors.set([c.r, c.g, c.b], i * 3);
    }
    geo.setAttribute('color', new THREE.BufferAttribute(colors, 3)); geo.computeVertexNormals(); return geo;
  }, [r, island.templateIndex, palette]);
  useEffect(() => () => geometry.dispose(), [geometry]);
  return <group position={[(island.center.x - origin.x) * UNIT, 0, (island.center.y - origin.y) * UNIT]}>
    <mesh geometry={geometry}><meshStandardMaterial vertexColors roughness={.95} /></mesh>
    <Suspense fallback={null}>
      {[0, 1, 2].map(i => <group key={i} position={[Math.cos(i * 2.4) * r * .46, r * .22, Math.sin(i * 2.4) * r * .46]} rotation-y={i * 2}><Model model={island.templateIndex === 3 ? 'rockB' : 'palm'} scale={island.templateIndex === 3 ? 4 : 3.5} /></group>)}
      {island.templateIndex === 1 && <group position={[0, r * .2, r * .5]}><Model model="structure" scale={4} /></group>}
    </Suspense>
  </group>;
}

function Scene({ pose, network, wide, palette, onSail, onSelect }: { pose: MutableRefObject<OceanPose>; network: MutableRefObject<NavalState | null>; wide: MutableRefObject<boolean>; palette: IslandPalette; onSail: (point: SeaPoint) => void; onSelect: (id: string) => void }) {
  const ship = useRef<THREE.Group>(null), water = useRef<THREE.Mesh>(null), wake = useRef<THREE.Group>(null);
  const [region, setRegion] = useState(() => ({ key: '', origin: { ...pose.current.position }, islands: seaIslandsAround(pose.current.position) }));
  const [others, setOthers] = useState<NavalState['others']>([]);
  const anchor = useRef(region.origin);
  const stamp = useRef('');
  const aim = useMemo(() => new THREE.Vector3(), []);
  const look = useMemo(() => new THREE.Vector3(), []);
  const normal = useMemo(() => {
    const data = new Uint8Array(64 * 64 * 4);
    for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) data.set([128 + Math.round(30 * Math.sin(x * .4 + y * .2)), 128 + Math.round(30 * Math.cos(y * .4)), 245, 255], (y * 64 + x) * 4);
    const texture = new THREE.DataTexture(data, 64, 64); texture.wrapS = texture.wrapT = THREE.RepeatWrapping; texture.repeat.set(180, 180); texture.needsUpdate = true; return texture;
  }, []);
  useEffect(() => () => normal.dispose(), [normal]);
  useFrame(({ camera, clock, gl }, rawDelta) => {
    const dt = Math.min(rawDelta, .05), p = pose.current, t = clock.elapsedTime;
    const key = `${Math.floor(p.position.x / SEA_CHUNK)}:${Math.floor(p.position.y / SEA_CHUNK)}`;
    if (stamp.current !== key) {
      const nextOrigin = { x: Math.floor(p.position.x / SEA_CHUNK) * SEA_CHUNK, y: Math.floor(p.position.y / SEA_CHUNK) * SEA_CHUNK };
      camera.position.x += (anchor.current.x - nextOrigin.x) * UNIT; camera.position.z += (anchor.current.y - nextOrigin.y) * UNIT;
      anchor.current = nextOrigin; stamp.current = key;
      setRegion({ key, origin: nextOrigin, islands: seaIslandsAround(p.position) });
    }
    const x = (p.position.x - anchor.current.x) * UNIT, z = (p.position.y - anchor.current.y) * UNIT;
    if (ship.current) {
      ship.current.position.set(x, -1.05 + Math.sin(t * 1.3) * .13, z);
      ship.current.rotation.set(Math.sin(t * .9) * .018, -p.heading, Math.cos(t * 1.1) * .025);
    }
    if (wake.current) { wake.current.position.set(x, .08, z); wake.current.rotation.y = -p.heading; wake.current.visible = p.moving; }
    if (water.current) water.current.position.set(x, -.12 + Math.sin(t * .65) * .04, z);
    normal.offset.set(p.position.x * .0002 + t * .014, p.position.y * .0002 + t * .009);
    // Fixed compass orientation keeps joystick directions aligned with the screen.
    aim.set(x, wide.current ? 65 : 27, z + (wide.current ? 85 : 42));
    camera.position.lerp(aim, 1 - Math.exp(-4 * dt)); look.set(x, 1, z - 48); camera.lookAt(look);
    gl.domElement.dataset.chunk = key; gl.domElement.dataset.regions = String(region.islands.length); gl.domElement.dataset.renderer = 'three';
    if (Math.floor(t * 2) !== Math.floor((t - dt) * 2)) setOthers(network.current?.others ?? []);
  });
  return <>
    <color attach="background" args={[palette.sky]} /><fog attach="fog" args={[palette.sky, 220, 550]} />
    <hemisphereLight args={[palette.sky, palette.sand, 1.8]} /><directionalLight position={[80, 120, 60]} intensity={2.2} color={palette.sun} />
    <Environment resolution={64}><Lightformer intensity={2} position={[0, 60, 0]} rotation-x={Math.PI / 2} scale={[200, 200, 1]} /><Lightformer intensity={1} color={palette.sky} position={[0, 20, -100]} scale={[200, 50, 1]} /></Environment>
    <mesh ref={water} rotation-x={-Math.PI / 2} onPointerDown={e => { e.stopPropagation(); onSail({ x: e.point.x / UNIT + anchor.current.x, y: e.point.z / UNIT + anchor.current.y }); }}>
      <planeGeometry args={[5000, 5000]} /><meshStandardMaterial color={palette.water} normalMap={normal} normalScale={new THREE.Vector2(.8, .8)} roughness={.26} metalness={.32} />
    </mesh>
    {region.islands.map(island => <Island key={island.id} island={island} origin={region.origin} palette={palette} />)}
    <group ref={ship}><Suspense fallback={null}><Model model="ship" scale={.8} /></Suspense></group>
    <group ref={wake}>{[0, 1, 2, 3, 4, 5].map(i => <mesh key={i} position={[0, 0, 4 + i * 2.8]} rotation-x={-Math.PI / 2} scale={[1 + i * .2, .35, 1]}><ringGeometry args={[1.8 + i * .5, 2 + i * .5, 20, 1, 0, Math.PI]} /><meshBasicMaterial color={palette.foam} transparent opacity={.5 - i * .06} depthWrite={false} side={THREE.DoubleSide} /></mesh>)}</group>
    {others.map(other => <group key={other.user_id} position={[(other.x - region.origin.x) * UNIT, -1.05, (other.y - region.origin.y) * UNIT]} rotation-y={-other.heading} onPointerDown={e => { e.stopPropagation(); onSelect(other.user_id); }}><Suspense fallback={null}><Model model="ship" scale={.8} /></Suspense></group>)}
  </>;
}

export default function OceanWorld3D(props: { pose: MutableRefObject<OceanPose>; network: MutableRefObject<NavalState | null>; wide: MutableRefObject<boolean>; canvasRef: MutableRefObject<HTMLCanvasElement | null>; onSail: (point: SeaPoint) => void; onSelect: (id: string) => void }) {
  const host = useRef<HTMLDivElement>(null);
  const [palette, setPalette] = useState<IslandPalette | null>(null);
  useEffect(() => { if (host.current) setPalette(readIslandPalette(host.current)); }, []);
  return <div ref={host} className="island3d-stage">{palette && <Canvas dpr={[1, 1.5]} camera={{ position: [0, 27, 42], fov: 58, near: .1, far: 900 }} onCreated={({ gl }) => { props.canvasRef.current = gl.domElement; gl.domElement.setAttribute('aria-label', 'Oceano da Grand Line'); gl.domElement.setAttribute('role', 'img'); }}><Scene {...props} palette={palette} /></Canvas>}</div>;
}