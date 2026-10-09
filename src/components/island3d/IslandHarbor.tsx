import { useEffect, useMemo, useRef, type MutableRefObject } from 'react';
import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import { CuboidCollider, RigidBody, useBeforePhysicsStep, type RapierRigidBody } from '@react-three/rapier';
import * as THREE from 'three';
import { islandModels } from '../../gameAssets';
import { advanceHarbor, HARBOR, ISLAND_3D, type HarborState } from '../../island3dWorld';
import type { IslandPalette } from './IslandTerrain';

export function IslandHarbor({ harbor, palette }: { harbor: MutableRefObject<HarborState>; palette: IslandPalette }) {
  const { scene } = useGLTF(islandModels.ship);
  const ship = useRef<RapierRigidBody>(null), bridge = useRef<RapierRigidBody>(null);
  const reflectionGroup = useRef<THREE.Group>(null), wake = useRef<THREE.Group>(null);
  const { object, reflection } = useMemo(() => {
    const object = scene.clone(true), reflection = scene.clone(true);
    object.traverse(o => { if (o instanceof THREE.Mesh) { o.castShadow = true; o.receiveShadow = true; } });
    reflection.traverse(o => { if (o instanceof THREE.Mesh) {
      const materials = (Array.isArray(o.material) ? o.material : [o.material]).map(m => {
        const copy = m.clone(); copy.transparent = true; copy.opacity = .16; copy.depthWrite = false; return copy;
      }); o.material = Array.isArray(o.material) ? materials : materials[0];
    } });
    return { object, reflection };
  }, [scene]);
  useEffect(() => () => { reflection.traverse(o => { if (o instanceof THREE.Mesh) for (const m of Array.isArray(o.material) ? o.material : [o.material]) m.dispose(); }); }, [reflection]);
  useBeforePhysicsStep(() => {
    advanceHarbor(harbor.current, 1 / 60);
    const h = harbor.current;
    ship.current?.setNextKinematicTranslation({ x: h.x, y: h.y, z: h.z });
    const length = HARBOR.gangway.end - HARBOR.gangway.start;
    bridge.current?.setNextKinematicTranslation({ x: (HARBOR.gangway.start + HARBOR.gangway.end) / 2, y: HARBOR.pier.top - .1 + (1 - h.deployment) * length / 2, z: HARBOR.gangway.z });
    bridge.current?.setNextKinematicRotation(new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, (1 - h.deployment) * Math.PI / 2)));
  });
  useFrame(() => {
    const h = harbor.current;
    if (reflectionGroup.current) reflectionGroup.current.position.set(h.x, 2 * ISLAND_3D.water - h.y, h.z);
    if (wake.current) {
      wake.current.position.set(h.x, ISLAND_3D.water + .19, h.z);
      wake.current.children.forEach((o, i) => {
        const t = (h.elapsed * .3 + i / 3) % 1;
        o.scale.set(3.1 * (1 + t * .18), 6.7 * (1 + t * .08), 1);
        if (o instanceof THREE.Mesh && o.material instanceof THREE.MeshBasicMaterial) o.material.opacity = .28 * (1 - t);
      });
    }
  });
  const length = HARBOR.gangway.end - HARBOR.gangway.start;
  return <>
    <RigidBody ref={ship} type="kinematicPosition" colliders={false} position={[HARBOR.approach.x, HARBOR.ship.y, HARBOR.approach.z]} scale={HARBOR.ship.scale}>
      <primitive object={object} />
      <CuboidCollider args={[2.35, .1, 4.3]} position={[0, 2, 0]} />
      <CuboidCollider args={[.1, .3, 4.3]} position={[2.3, 2.4, 0]} />
      <CuboidCollider args={[.1, .3, 1.4]} position={[-2.3, 2.4, -2.9]} />
      <CuboidCollider args={[.1, .3, 2.2]} position={[-2.3, 2.4, 2.1]} />
      <CuboidCollider args={[2.3, .3, .1]} position={[0, 2.4, 4.3]} />
      <CuboidCollider args={[2.3, .3, .1]} position={[0, 2.4, -4.3]} />
    </RigidBody>
    <group ref={reflectionGroup} scale={[HARBOR.ship.scale, -HARBOR.ship.scale, HARBOR.ship.scale]}><primitive object={reflection} /></group>
    <group ref={wake}>{[0, 1, 2].map(i => <mesh key={i} rotation-x={-Math.PI / 2}>
      <ringGeometry args={[1, 1.025, 48]} /><meshBasicMaterial color={palette.foam} transparent opacity={.2} depthWrite={false} />
    </mesh>)}</group>
    <HullShadow harbor={harbor} palette={palette} />
    <RigidBody ref={bridge} type="kinematicPosition" colliders={false} position={[(HARBOR.gangway.start + HARBOR.gangway.end) / 2, 2.2, HARBOR.gangway.z]}>
      <CuboidCollider args={[length / 2, .1, HARBOR.gangway.width / 2]} />
      <mesh receiveShadow castShadow><boxGeometry args={[length, .2, HARBOR.gangway.width]} /><meshStandardMaterial color={palette.sand} roughness={.86} /></mesh>
      {Array.from({ length: 9 }, (_, i) => <mesh key={i} position={[-length / 2 + .15 + i * .29, .105, 0]} receiveShadow><boxGeometry args={[.018, .015, HARBOR.gangway.width]} /><meshStandardMaterial color={palette.stone} /></mesh>)}
    </RigidBody>
    {[-3, 3].map(offset => <Mooring key={offset} offset={offset} harbor={harbor} palette={palette} />)}
  </>;
}

function HullShadow({ harbor, palette }: { harbor: MutableRefObject<HarborState>; palette: IslandPalette }) {
  const mesh = useRef<THREE.Mesh>(null);
  useFrame(() => { mesh.current?.position.set(harbor.current.x, ISLAND_3D.water + .18, harbor.current.z); });
  return <mesh ref={mesh} rotation-x={-Math.PI / 2} scale={[3.1, 6.4, 1]}><circleGeometry args={[1, 40]} /><meshBasicMaterial color={palette.ink} transparent opacity={.16} depthWrite={false} /></mesh>;
}
function Mooring({ offset, harbor, palette }: { offset: number; harbor: MutableRefObject<HarborState>; palette: IslandPalette }) {
  const mesh = useRef<THREE.Mesh>(null);
  const geometry = useMemo(() => new THREE.TubeGeometry(new THREE.CatmullRomCurve3([new THREE.Vector3(), new THREE.Vector3(1, -.3, 0), new THREE.Vector3(2, 0, 0)]), 12, .035, 5), []);
  const lastUpdate = useRef(-1);
  useEffect(() => () => geometry.dispose(), [geometry]);
  useFrame(() => {
    const h = harbor.current, m = mesh.current;
    if (!m) return;
    m.visible = h.deployment > 0;
    if (h.elapsed - lastUpdate.current < .1) return;
    lastUpdate.current = h.elapsed;
    // Update only the short rope strip; endpoints track ship heave and dock bollards.
    const curve = new THREE.CatmullRomCurve3([new THREE.Vector3(1.6, 1.25, 49 + offset), new THREE.Vector3((1.6 + h.x - 2.8) / 2, 1.05, (49 + h.z) / 2 + offset), new THREE.Vector3(h.x - 2.8, h.y + 2.625, h.z + offset)]);
    const next = new THREE.TubeGeometry(curve, 12, .035, 5);
    m.geometry.dispose(); m.geometry = next;
  });
  return <mesh ref={mesh} geometry={geometry} castShadow><meshStandardMaterial color={palette.stone} roughness={1} /></mesh>;
}