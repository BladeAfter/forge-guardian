import { useEffect, useMemo, useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import { RigidBody } from '@react-three/rapier';
import * as THREE from 'three';
import { islandHeight, ISLAND_3D } from '../../island3dWorld';

export type IslandPalette = Record<'sky' | 'water' | 'foam' | 'sand' | 'grass' | 'stone' | 'sun' | 'ink' | 'gold' | 'pirateRed', string>;
export function readIslandPalette(element: HTMLElement): IslandPalette {
  const css = getComputedStyle(element);
  const value = (name: string) => css.getPropertyValue(`--island3d-${name}`).trim();
  return { sky: value('sky'), water: value('water'), foam: value('foam'), sand: value('sand'), grass: value('grass'), stone: value('stone'), sun: value('sun'), ink: value('ink'), gold: value('gold'), pirateRed: value('pirate-red') };
}

export function IslandTerrain({ palette }: { palette: IslandPalette }) {
  const { geometry, texture } = useMemo(() => {
    const geometry = new THREE.PlaneGeometry(ISLAND_3D.size, ISLAND_3D.size, 96, 96);
    geometry.rotateX(-Math.PI / 2);
    const positions = geometry.attributes.position;
    const colors = new Float32Array(positions.count * 3);
    const sand = new THREE.Color(palette.sand), grass = new THREE.Color(palette.grass), stone = new THREE.Color(palette.stone);
    const color = new THREE.Color();
    for (let i = 0; i < positions.count; i++) {
      const x = positions.getX(i), z = positions.getZ(i), h = islandHeight(x, z);
      positions.setY(i, h);
      const path = Math.abs(x - Math.sin(z * .1) * 3) < 2.8;
      color.copy(sand).lerp(grass, path ? .12 : THREE.MathUtils.smoothstep(h, .5, 2.8));
      color.lerp(stone, THREE.MathUtils.smoothstep(h, 5, 9));
      color.multiplyScalar(.94 + .06 * Math.sin(x * .7 + z * .9));
      colors.set([color.r, color.g, color.b], i * 3);
    }
    geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geometry.computeVertexNormals();
    const bytes = new Uint8Array(128 * 128 * 4);
    for (let i = 0; i < 128 * 128; i++) {
      const noise = 220 + Math.floor((Math.sin(i * 78.233) * 43758.5453 % 1 + 1) * 12);
      bytes.set([noise, noise, noise, 255], i * 4);
    }
    const texture = new THREE.DataTexture(bytes, 128, 128);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
    texture.repeat.set(22, 22); texture.needsUpdate = true;
    return { geometry, texture };
  }, [palette]);
  useEffect(() => () => { geometry.dispose(); texture.dispose(); }, [geometry, texture]);
  return <RigidBody type="fixed" colliders="trimesh"><mesh geometry={geometry} receiveShadow><meshStandardMaterial map={texture} vertexColors roughness={.94} /></mesh></RigidBody>;
}

export function IslandWater({ palette }: { palette: IslandPalette }) {
  const mesh = useRef<THREE.Mesh>(null);
  const { geometry, normal } = useMemo(() => {
    const geometry = new THREE.PlaneGeometry(700, 700, 72, 72); geometry.rotateX(-Math.PI / 2);
    const data = new Uint8Array(128 * 128 * 4);
    for (let y = 0; y < 128; y++) for (let x = 0; x < 128; x++) {
      const i = (y * 128 + x) * 4;
      data.set([128 + Math.round(22 * Math.sin(x * .35 + Math.sin(y * .25))), 128 + Math.round(22 * Math.cos(y * .35 + x * .1)), 245, 255], i);
    }
    const normal = new THREE.DataTexture(data, 128, 128);
    normal.wrapS = normal.wrapT = THREE.RepeatWrapping; normal.repeat.set(90, 90); normal.needsUpdate = true;
    return { geometry, normal };
  }, []);
  useFrame(({ clock }, rawDelta) => {
    const dt = Math.min(rawDelta, .05);
    normal.offset.x += dt * .016; normal.offset.y += dt * .01;
    const p = geometry.attributes.position;
    for (let i = 0; i < p.count; i++) p.setY(i, Math.sin(p.getX(i) * .12 + clock.elapsedTime * .8) * .10 + Math.cos(p.getZ(i) * .16 - clock.elapsedTime * .6) * .07);
    p.needsUpdate = true;
  });
  useEffect(() => () => { geometry.dispose(); normal.dispose(); }, [geometry, normal]);
  return <mesh ref={mesh} geometry={geometry} position-y={ISLAND_3D.water} receiveShadow><meshStandardMaterial color={palette.water} normalMap={normal} normalScale={new THREE.Vector2(.6, .6)} roughness={.2} metalness={.35} transparent opacity={.9} /></mesh>;
}