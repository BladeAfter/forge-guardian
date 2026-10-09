import { useEffect, useMemo, useRef, type MutableRefObject } from 'react';
import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import { RigidBody, CuboidCollider, CylinderCollider } from '@react-three/rapier';
import { SkeletonUtils } from 'three-stdlib';
import * as THREE from 'three';
import { islandModels } from '../../gameAssets';
import { islandHeight, type IslandMotion } from '../../island3dWorld';
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
  const view = <group ref={group}><primitive object={object} /></group>;
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
    for (const original of [...animations, ...authoredClips()]) {
      const clip = original.clone();
      // Imported locomotion is in-place; strip root X/Z travel to avoid visual drift.
      for (const track of clip.tracks) if (track.name === 'root.position' && original.name !== 'island-dodge') for (let i = 0; i < track.values.length; i += 3) { track.values[i] = 0; track.values[i + 2] = 0; }
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
  return <group><primitive object={object} /><PirateBandana object={object} palette={palette} /></group>;
}

function PirateBandana({ object, palette }: { object: THREE.Object3D; palette: IslandPalette }) {
  useEffect(() => {
    const head = object.getObjectByName('head');
    if (!head) return;
    // Original volumetric head/hair remains; pirate sash is a custom cosmetic accessory.
    const box = new THREE.Box3().setFromObject(object), h = box.getSize(new THREE.Vector3()).y / object.scale.y;
    const material = new THREE.MeshStandardMaterial({ color: palette.gold, roughness: .8 });
    const band = new THREE.Mesh(new THREE.TorusGeometry(h * .12, h * .024, 6, 16), material);
    band.rotation.x = Math.PI / 2; band.position.y = h * .045; band.castShadow = true;
    head.add(band);
    return () => { head.remove(band); band.geometry.dispose(); material.dispose(); };
  }, [object, palette]);
  return null;
}

export function Dock({ palette }: { palette: IslandPalette }) {
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
    <mesh position={[0, .87, 38]} receiveShadow castShadow><boxGeometry args={[3.5, .24, 16]} /><meshStandardMaterial map={texture} roughness={.85} color={palette.sand} /></mesh>
    <CuboidCollider args={[1.75, .12, 8]} position={[0, .87, 38]} />
    {[31, 36, 41, 45].flatMap(z => [-1.5, 1.5].map(x => <mesh key={`${x}-${z}`} position={[x, -.25, z]} castShadow><cylinderGeometry args={[.15, .2, 3, 8]} /><meshStandardMaterial color={palette.stone} roughness={1} /></mesh>))}
    <mesh position={[2.6, 1.1, 43]} receiveShadow castShadow><boxGeometry args={[5.2, .2, 1.4]} /><meshStandardMaterial map={texture} /></mesh>
    <CuboidCollider args={[2.6, .1, .7]} position={[2.6, 1.1, 43]} />
  </RigidBody>;
}