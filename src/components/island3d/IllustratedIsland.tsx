import { useTexture } from '@react-three/drei';
import { useEffect, useMemo } from 'react';
import * as THREE from 'three';
import { islandArt } from '../../gameAssets';
import { ISLAND_MAP } from '../../illustratedIslandWorld';

/** Illustrated presentation only; the existing physical world stays authoritative for movement. */
export function IllustratedIsland({ islandIndex }: { islandIndex: number }) {
  const texture = useTexture(islandArt[islandIndex] ?? islandArt[1]);
  texture.colorSpace = THREE.SRGBColorSpace;
  // Keep map scale and collider alignment; extend its own edge pixels.
  const geometry = useMemo(() => {
    const plane = new THREE.PlaneGeometry(2000, 2000);
    const positions = plane.getAttribute('position');
    const uv = plane.getAttribute('uv');
    for (let index = 0; index < uv.count; index++) {
      uv.setXY(index, positions.getX(index) / ISLAND_MAP.width + .5, positions.getY(index) / ISLAND_MAP.depth + .5);
    }
    return plane;
  }, []);
  useEffect(() => () => geometry.dispose(), [geometry]);
  return <mesh geometry={geometry} rotation-x={-Math.PI / 2} position-y={-.38}>
    <meshBasicMaterial map={texture} toneMapped={false} />
  </mesh>;
}