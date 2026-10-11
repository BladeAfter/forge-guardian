import { useEffect, useMemo, useRef, type MutableRefObject } from 'react';
import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import { RigidBody, CuboidCollider, CylinderCollider } from '@react-three/rapier';
import { SkeletonUtils } from 'three-stdlib';
import * as THREE from 'three';
import { islandModels } from '../../gameAssets';
import { HARBOR, islandHeight, type IslandMotion } from '../../island3dWorld';
import type { IslandPalette } from './IslandTerrain';

export function IslandProp({ model, x, z, scale = 1, y, rotation = 0, collider = 'hull', wind = false, open = false }: { model: keyof typeof islandModels; x: number; z: number; scale?: number; y?: number; rotation?: number; collider?: 'hull' | 'trimesh' | 'tree' | 'none'; wind?: boolean; open?: boolean }) {
  const { scene } = useGLTF(islandModels[model]);
  const object = useMemo(() => {
    const clone = scene.clone(true);
    clone.traverse(o => { if (o instanceof THREE.Mesh) { o.castShadow = true; o.receiveShadow = true; } });
    return clone;
  }, [scene]);
  const group = useRef<THREE.Group>(null);
  const lid = useRef<THREE.Object3D | null>(null);
  useEffect(() => { lid.current = object.getObjectByName('lid') ?? null; }, [object]);
  useFrame(({ clock }, rawDelta) => {
    const dt = Math.min(rawDelta, .05);
    if (wind && group.current) group.current.rotation.z = Math.sin(clock.elapsedTime * .8 + x) * .012;
    if (lid.current && model === 'chest') lid.current.rotation.x += ((open ? -1.2 : 0) - lid.current.rotation.x) * (1 - Math.exp(-5 * dt));
  });
  const view = <group ref={group}><primitive object={object} />{model === 'chest' && open && <group position={[0, .65, 0]}>{[-.2, 0, .2].map((x, i) => <mesh key={i} position={[x, i * .025, 0]} rotation-x={Math.PI / 2} castShadow><cylinderGeometry args={[.18, .18, .06, 16]} /><meshStandardMaterial color="#efb847" metalness={.7} roughness={.25} /></mesh>)}<pointLight color="#efb847" intensity={2} distance={3} /></group>}</group>;
  const position: [number, number, number] = [x, y ?? islandHeight(x, z), z];
  if (collider === 'none') return <group position={position} rotation-y={rotation} scale={scale}>{view}</group>;
  return <RigidBody type="fixed" colliders={collider === 'tree' ? false : collider} position={position} rotation={[0, rotation, 0]} scale={scale}>
    {view}{collider === 'tree' && <CylinderCollider args={[1.4, .22]} position={[0, 1.4, 0]} />}
  </RigidBody>;
}

const clips: Record<IslandMotion, string> = { idle: 'idle', walk: 'walk', run: 'sprint', sprint: 'sprint', jump: 'jump', fall: 'fall', attack: 'attack-melee-right', interact: 'interact-right', dodge: 'island-dodge', swim: 'island-swim', climb: 'walk', descend: 'walk' };
function authoredClips(): THREE.AnimationClip[] {
  const times = [0, .25, .5, .75, 1];
  const arm = (sign: number) => times.flatMap(t => new THREE.Quaternion().setFromEuler(new THREE.Euler(-Math.PI / 2 + Math.sin(t * Math.PI * 2) * .7, 0, sign * .5)).toArray());
  const swim = new THREE.AnimationClip('island-swim', 1, [
    new THREE.QuaternionKeyframeTrack('arm-left.quaternion', times, arm(-1)),
    new THREE.QuaternionKeyframeTrack('arm-right.quaternion', times, arm(1)),
    new THREE.QuaternionKeyframeTrack('torso.quaternion', times, times.flatMap(() => new THREE.Quaternion().setFromEuler(new THREE.Euler(.8, 0, 0)).toArray())),
  ]);
  const dodge = new THREE.AnimationClip('island-dodge', .55, [
    new THREE.QuaternionKeyframeTrack('root.quaternion', [0, .14, .28, .42, .55], [0, 1, 2, 3, 4].flatMap(i => new THREE.Quaternion().setFromEuler(new THREE.Euler(i * Math.PI / 2, 0, 0)).toArray())),
    new THREE.VectorKeyframeTrack('root.position', [0, .275, .55], [0, 0, 0, 0, .25, 0, 0, 0, 0]),
  ]);
  return [swim, dodge];
}

// Prepare in-place tracks once per loaded model, not once per island encounter.
const preparedAnimations = new WeakMap<THREE.Object3D, THREE.AnimationClip[]>();
function pirateAnimations(scene: THREE.Object3D, animations: THREE.AnimationClip[]) {
  const cached = preparedAnimations.get(scene);
  if (cached) return cached;
  const prepared = [...animations, ...authoredClips()].map(original => {
    const clip = original.clone();
    for (const track of clip.tracks) if (track.name === 'root.position' && original.name !== 'island-dodge') for (let i = 0; i < track.values.length; i += 3) { track.values[i] = 0; track.values[i + 2] = 0; }
    return clip;
  });
  preparedAnimations.set(scene, prepared);
  return prepared;
}

export function IslandPirate({ style, motion, speed, palette }: { style: 'male' | 'female'; motion: MutableRefObject<IslandMotion>; speed: MutableRefObject<number>; palette: IslandPalette }) {
  const { scene, animations } = useGLTF(islandModels[style]);
  const { object, mixer, actions } = useMemo(() => {
    const object = SkeletonUtils.clone(scene);
    const box = new THREE.Box3().setFromObject(object), size = box.getSize(new THREE.Vector3());
    const factor = 1.8 / Math.max(.01, size.y);
    object.scale.setScalar(factor);
    const bounds = new THREE.Box3().setFromObject(object); object.position.y -= bounds.min.y;
    object.traverse(o => {
      if (o instanceof THREE.Mesh) { o.castShadow = true; o.receiveShadow = true; }
    });
    const mixer = new THREE.AnimationMixer(object);
    const actions: Record<string, THREE.AnimationAction> = {};
    for (const clip of pirateAnimations(scene, animations)) {
      actions[clip.name] = mixer.clipAction(clip);
    }
    return { object, mixer, actions };
  }, [scene, animations]);
  const previous = useRef('');
  useEffect(() => () => { mixer.stopAllAction(); mixer.uncacheRoot(object); }, [mixer, object]);
  useFrame((_, rawDelta) => {
    const dt = Math.min(rawDelta, .05), name = clips[motion.current], action = actions[name];
    if (action && previous.current !== name) {
      actions[previous.current]?.fadeOut(.14);
      action.reset().fadeIn(.14).play(); previous.current = name;
    }
    if (action) action.timeScale = ['walk', 'run', 'sprint', 'climb', 'descend'].includes(motion.current) ? Math.max(.45, speed.current / (name === 'walk' ? 2.3 : 5.6)) : 1;
    mixer.update(dt);
  });
  return <group><primitive object={object} /><PirateOutfit object={object} palette={palette} /></group>;
}

function PirateOutfit({ object, palette }: { object: THREE.Object3D; palette: IslandPalette }) {
  useEffect(() => {
    const head = object.getObjectByName('head');
    if (!head) return;
    const gear = new THREE.Group();
    const materials = {
      dark: new THREE.MeshStandardMaterial({ color: palette.ink, roughness: .82 }),
      red: new THREE.MeshStandardMaterial({ color: palette.pirateRed, roughness: .9 }),
      gold: new THREE.MeshStandardMaterial({ color: palette.gold, metalness: .4, roughness: .5 }),
      ivory: new THREE.MeshStandardMaterial({ color: palette.foam, roughness: .8 }),
    };
    const add = (geometry: THREE.BufferGeometry, material: THREE.Material, position: [number, number, number], scale?: [number, number, number]) => {
      const mesh = new THREE.Mesh(geometry, material); mesh.position.set(...position); if (scale) mesh.scale.set(...scale); mesh.castShadow = true; gear.add(mesh); return mesh;
    };
    // Bone-attached tricorne, red hatband and ivory insignia keep every existing animation.
    add(new THREE.CylinderGeometry(.23, .27, .09, 3), materials.dark, [0, .33, 0], [1, 1, .85]).rotation.y = Math.PI;
    add(new THREE.SphereGeometry(.17, 12, 8), materials.dark, [0, .37, 0], [1, .7, .85]);
    add(new THREE.CylinderGeometry(.173, .18, .035, 12), materials.red, [0, .335, 0]);
    add(new THREE.SphereGeometry(.035, 8, 6), materials.ivory, [0, .37, .137], [1, 1, .35]);
    for (const tilt of [-.65, .65]) { const bone = add(new THREE.CapsuleGeometry(.006, .07, 3, 6), materials.ivory, [0, .34, .145]); bone.rotation.z = tilt; }
    // Cover the casual spectacles with a dark pirate eye patch and strap.
    add(new THREE.SphereGeometry(.048, 10, 8), materials.dark, [-.083, .14, .155], [1, .8, .3]);
    const strap = add(new THREE.TorusGeometry(.175, .009, 4, 20), materials.dark, [0, .14, 0], [1, .6, 1]); strap.rotation.x = Math.PI / 2;
    head.add(gear);
    const torso = object.getObjectByName('torso');
    const sash = new THREE.Mesh(new THREE.BoxGeometry(.29, .05, .19), materials.red); sash.position.set(0, .05, 0); sash.rotation.z = -.15; torso?.add(sash);
    const buckle = new THREE.Mesh(new THREE.BoxGeometry(.044, .04, .012), materials.gold); buckle.position.set(0, .05, .102); torso?.add(buckle);
    return () => { head.remove(gear); torso?.remove(sash, buckle); gear.traverse(o => { if (o instanceof THREE.Mesh) o.geometry.dispose(); }); sash.geometry.dispose(); buckle.geometry.dispose(); Object.values(materials).forEach(m => m.dispose()); };
  }, [object, palette]);
  return null;
}

export function Dock({ palette, illustrated = false }: { palette: IslandPalette; illustrated?: boolean }) {
  const texture = useMemo(() => {
    const canvas = document.createElement('canvas'); canvas.width = canvas.height = 128;
    const ctx = canvas.getContext('2d');
    if (ctx) {
      ctx.fillStyle = palette.sand; ctx.fillRect(0, 0, 128, 128);
      ctx.strokeStyle = palette.stone;
      for (let i = 0; i < 128; i += 16) { ctx.beginPath(); ctx.moveTo(0, i); ctx.lineTo(128, i); ctx.stroke(); }
      ctx.globalAlpha = .22;
      for (let i = 0; i < 100; i++) { ctx.beginPath(); ctx.moveTo(i * 19 % 128, i * 37 % 128); ctx.lineTo((i * 19 % 128) + 15, i * 37 % 128); ctx.stroke(); }
    }
    const texture = new THREE.CanvasTexture(canvas); texture.colorSpace = THREE.SRGBColorSpace; texture.wrapS = texture.wrapT = THREE.RepeatWrapping; texture.repeat.set(1, 4); return texture;
  }, [palette]);
  useEffect(() => () => texture.dispose(), [texture]);
  return <RigidBody type="fixed" colliders={false}>
    <mesh visible={!illustrated} position={[0, HARBOR.pier.top - .12, 41.5]} receiveShadow castShadow><boxGeometry args={[3.5, .24, 23]} /><meshStandardMaterial map={texture} roughness={.85} color={palette.sand} /></mesh>
    <CuboidCollider args={[HARBOR.pier.halfWidth, .12, 11.5]} position={[0, HARBOR.pier.top - .12, 41.5]} />
    {!illustrated && [31, 36, 41, 46, 52].flatMap(z => [-1.5, 1.5].map(x => <mesh key={`${x}-${z}`} position={[x, -1, z]} castShadow><cylinderGeometry args={[.15, .2, 4.5, 8]} /><meshStandardMaterial color={palette.stone} roughness={1} /></mesh>))}
  </RigidBody>;
}