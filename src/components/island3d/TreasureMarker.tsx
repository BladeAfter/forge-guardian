import type { IslandPalette } from './IslandTerrain';
import { ISLAND_MAP } from '../../illustratedIslandWorld';

/** Ground marks carry no collision or rewards. */
export function TreasureMarker({ x, z, palette, clue = false }: { x: number; z: number; palette: IslandPalette; clue?: boolean }) {
  return <group position={[x, ISLAND_MAP.floor + .035, z]}>
    {clue ? <group rotation-x={-Math.PI / 2}>
      <mesh><planeGeometry args={[1.35, 1]} /><meshBasicMaterial color={palette.foam} /></mesh>
      {[-.65, .65].map(angle => <mesh key={angle} position={[0, 0, .01]} rotation-z={angle}><planeGeometry args={[.75, .14]} /><meshBasicMaterial color={palette.pirateRed} /></mesh>)}
    </group> : [-Math.PI / 4, Math.PI / 4].map(angle => <mesh key={angle} rotation-y={angle}><boxGeometry args={[2, .025, .3]} /><meshBasicMaterial color={palette.pirateRed} /></mesh>)}
  </group>;
}