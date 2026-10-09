import { useTexture } from '@react-three/drei';
import * as THREE from 'three';
import { grandLineArt, islandArt } from '../../gameAssets';

/** Illustrated presentation only; the existing physical world stays authoritative for movement. */
export function IllustratedIsland({ islandIndex }: { islandIndex: number }) {
  const texture = useTexture(islandArt[islandIndex] ?? islandArt[1]);
  const ocean = useTexture(grandLineArt.ocean);
  texture.colorSpace = THREE.SRGBColorSpace;
  ocean.colorSpace = THREE.SRGBColorSpace;
  return <><mesh rotation-x={-Math.PI / 2} position-y={-.45}><planeGeometry args={[2000, 2000]} /><meshBasicMaterial map={ocean} toneMapped={false} /></mesh><mesh rotation-x={-Math.PI / 2} position-y={-.38}>
    <planeGeometry args={[180, 120]} />
    <meshBasicMaterial map={texture} toneMapped={false} />
  </mesh></>;
}