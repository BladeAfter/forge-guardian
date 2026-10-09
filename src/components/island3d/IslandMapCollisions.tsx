import { RigidBody, CylinderCollider, CuboidCollider } from '@react-three/rapier';
import { ISLAND_MAP, islandObstacles } from '../../illustratedIslandWorld';

/** Invisible footprints share the bitmap's coordinates, not the retired 3D scenery. */
export function IslandMapCollisions({ islandIndex }: { islandIndex: number }) {
  return <>
    <RigidBody type="fixed" colliders={false}><CuboidCollider args={[90, .2, 45]} position={[0, ISLAND_MAP.floor - .2, -15]} /></RigidBody>
    {islandObstacles(islandIndex).map(o => <RigidBody key={o.id} type="fixed" colliders={false} position={[o.x, ISLAND_MAP.floor, o.z]}>
      <CylinderCollider args={[10, 1]} position={[0, 10, 0]} scale={[o.rx, 1, o.rz]} />
    </RigidBody>)}
  </>;
}