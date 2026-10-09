import { useMemo } from 'react';
import { RigidBody, ConvexHullCollider, CuboidCollider } from '@react-three/rapier';
import { ISLAND_MAP, islandObstacles } from '../../illustratedIslandWorld';

/** Invisible footprints share the bitmap's coordinates, not the retired 3D scenery. */
export function IslandMapCollisions({ islandIndex }: { islandIndex: number }) {
  const footprints = useMemo(() => islandObstacles(islandIndex).map(o => {
    const vertices = new Float32Array(32 * 3);
    for (let i = 0; i < 16; i++) for (let level = 0; level < 2; level++) {
      const angle = i * Math.PI / 8;
      vertices.set([Math.cos(angle) * o.rx, level * 20, Math.sin(angle) * o.rz], (i * 2 + level) * 3);
    }
    return { ...o, vertices };
  }), [islandIndex]);
  return <>
    <RigidBody type="fixed" colliders={false}><CuboidCollider args={[90, .2, 45]} position={[0, ISLAND_MAP.floor - .2, -15]} /></RigidBody>
    {footprints.map(o => <RigidBody key={o.id} type="fixed" colliders={false} position={[o.x, ISLAND_MAP.floor, o.z]}>
      <ConvexHullCollider args={[o.vertices]} />
    </RigidBody>)}
  </>;
}