/** Footprints traced in normalized coordinates of the actual illustrated maps. */
import { HARBOR, ISLAND_3D } from './island3dWorld';

export const ISLAND_MAP = { width: 180, depth: 120, floor: .99, pirateScale: 2, cameraSpan: 36 };
type WalkPoint = { x: number; z: number };
const coast: WalkPoint[] = [
  { x: -72, z: -58 }, { x: 72, z: -58 }, { x: 78, z: 15 },
  { x: 69, z: 26 }, { x: 18, z: 28 }, { x: 0, z: 29.5 },
  { x: -18, z: 28 }, { x: -69, z: 25 }, { x: -78, z: 10 },
];
const portCoast = [...coast.slice(0, 8), { x: -40, z: -8 }, { x: -50, z: -23 }, { x: -74, z: -36 }];
export function islandWalkable(index: number, { x, z }: WalkPoint, boarding = false) {
  if (!Number.isFinite(x) || !Number.isFinite(z)) return false;
  const polygon = index === 1 ? portCoast : coast;
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const a = polygon[i], b = polygon[j];
    if ((a.z > z) !== (b.z > z) && x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x) inside = !inside;
  }
  const pier = Math.abs(x) <= HARBOR.pier.halfWidth - .35 && z >= ISLAND_3D.shore.z && z <= HARBOR.pier.end - .35;
  const bridge = boarding && x >= 1.3 && x <= HARBOR.ship.x && Math.abs(z - HARBOR.gangway.z) <= HARBOR.gangway.width / 2 - .35;
  const deck = boarding && Math.abs(x - HARBOR.ship.x) <= 2 && Math.abs(z - HARBOR.ship.z) <= 3.9;
  return inside || pier || bridge || deck;
}
/** Sweep airborne moves too; slide along edges rather than crossing water. */
export function safeIslandStep(index: number, from: WalkPoint, to: WalkPoint, boarding = false): WalkPoint {
  if (!islandWalkable(index, from, boarding)) return { ...ISLAND_3D.shore };
  const sweep = (goal: WalkPoint) => {
    if (!Number.isFinite(goal.x) || !Number.isFinite(goal.z)) return from;
    const steps = Math.max(1, Math.ceil(Math.hypot(goal.x - from.x, goal.z - from.z) / .15));
    let safe = from;
    for (let step = 1; step <= steps; step++) {
      const t = step / steps, next = { x: from.x + (goal.x - from.x) * t, z: from.z + (goal.z - from.z) * t };
      if (!islandWalkable(index, next, boarding)) break;
      safe = next;
    }
    return safe;
  };
  const direct = sweep(to);
  if (direct.x === to.x && direct.z === to.z) return direct;
  const slideX = sweep({ x: to.x, z: from.z }), slideZ = sweep({ x: from.x, z: to.z });
  return [direct, slideX, slideZ].sort((a, b) => Math.hypot(a.x - to.x, a.z - to.z) - Math.hypot(b.x - to.x, b.z - to.z))[0];
}
type Footprint = { id: string; u: number; v: number; rx: number; rz: number };
const port: Footprint[] = [
  { id: 'port-village', u: .22, v: .35, rx: .16, rz: .16 },
  { id: 'shore-house', u: .34, v: .59, rx: .055, rz: .06 },
  { id: 'shore-palms-west', u: .42, v: .65, rx: .055, rz: .07 },
  { id: 'shore-palms-east', u: .58, v: .66, rx: .05, rz: .075 },
  { id: 'west-forest', u: .31, v: .65, rx: .1, rz: .09 },
  { id: 'east-forest', u: .7, v: .56, rx: .13, rz: .14 },
  { id: 'upper-east-forest', u: .68, v: .33, rx: .14, rz: .13 },
  { id: 'west-temple-trees', u: .43, v: .38, rx: .045, rz: .09 },
  { id: 'temple-left-wall', u: .44, v: .15, rx: .055, rz: .12 },
  { id: 'temple-right-wall', u: .54, v: .15, rx: .04, rz: .12 },
  { id: 'eastern-cliffs', u: .94, v: .52, rx: .055, rz: .24 },
  { id: 'western-cliffs', u: .04, v: .68, rx: .04, rz: .1 },
];
const jungle: Footprint[] = [
  { id: 'west-palm', u: .23, v: .65, rx: .055, rz: .09 },
  { id: 'east-palm', u: .69, v: .64, rx: .06, rz: .09 },
  { id: 'west-forest', u: .34, v: .5, rx: .12, rz: .095 },
  { id: 'east-forest', u: .75, v: .53, rx: .14, rz: .07 },
  { id: 'hut', u: .14, v: .38, rx: .095, rz: .1 },
  { id: 'temple-left', u: .43, v: .24, rx: .075, rz: .15 },
  { id: 'temple-right', u: .59, v: .23, rx: .075, rz: .15 },
  { id: 'central-grove', u: .58, v: .41, rx: .055, rz: .07 },
  { id: 'right-grove', u: .79, v: .29, rx: .09, rz: .08 },
];
const volcano: Footprint[] = [
  { id: 'forge', u: .26, v: .29, rx: .12, rz: .13 },
  { id: 'central-rocks', u: .52, v: .4, rx: .08, rz: .115 },
  { id: 'west-rocks', u: .23, v: .5, rx: .08, rz: .07 },
  { id: 'east-rocks', u: .67, v: .55, rx: .065, rz: .04 },
  { id: 'east-lava', u: .88, v: .27, rx: .1, rz: .16 },
];
const ice: Footprint[] = [
  { id: 'village', u: .28, v: .47, rx: .17, rz: .16 },
  { id: 'east-pines', u: .73, v: .56, rx: .16, rz: .095 },
  { id: 'upper-pines', u: .78, v: .37, rx: .15, rz: .13 },
  { id: 'temple-west', u: .43, v: .15, rx: .045, rz: .14 },
  { id: 'temple-east', u: .56, v: .15, rx: .045, rz: .14 },
];
const pirates: Footprint[] = [
  { id: 'west-village', u: .2, v: .41, rx: .16, rz: .23 },
  { id: 'east-houses', u: .4, v: .5, rx: .06, rz: .12 },
  { id: 'east-jungle', u: .73, v: .43, rx: .19, rz: .19 },
  { id: 'fort-left', u: .45, v: .14, rx: .06, rz: .13 },
  { id: 'fort-right', u: .56, v: .14, rx: .04, rz: .13 },
];
const maps = [jungle, port, volcano, ice, pirates];
export function mapPoint(u: number, v: number) { return { x: (u - .5) * ISLAND_MAP.width, z: (v - .5) * ISLAND_MAP.depth }; }
export function islandObstacles(index: number) {
  return (maps[index] ?? port).map(o => ({ id: o.id, ...mapPoint(o.u, o.v), rx: o.rx * ISLAND_MAP.width, rz: o.rz * ISLAND_MAP.depth }));
}
export function obstacleAt(index: number, x: number, z: number, clearance = .3) {
  return islandObstacles(index).find(o => ((x - o.x) / (o.rx + clearance)) ** 2 + ((z - o.z) / (o.rz + clearance)) ** 2 < 1);
}
export function clearEncounterPoint(index: number, point: { x: number; z: number }) {
  if (!obstacleAt(index, point.x, point.z, 1.2)) return point;
  for (let radius = 1; radius <= 35; radius++) for (let step = 0; step < 32; step++) {
    const angle = step * Math.PI / 16, x = point.x + Math.cos(angle) * radius, z = point.z + Math.sin(angle) * radius;
    if (!obstacleAt(index, x, z, 1.2)) return { x, z };
  }
  return point;
}