export type SeaPoint = { x: number; y: number };
export const SEA_SIZE = { width: 3200, height: 2133 };
export type SeaDestination = 'stronghold' | 'map' | 'forge' | 'ruins' | 'bounties';
export const SEA_ISLANDS: { name: string; center: SeaPoint; dock: SeaPoint; radius: number; destination: SeaDestination; action: string }[] = [
  { name: 'Palmas do Alvorecer', center: { x: 620, y: 410 }, dock: { x: 810, y: 700 }, radius: 340, destination: 'map', action: 'Explorar a ilha' },
  { name: 'Porto dos Ventos', center: { x: 1520, y: 920 }, dock: { x: 1570, y: 1260 }, radius: 370, destination: 'stronghold', action: 'Atracar no porto' },
  { name: 'Caldeira Rubra', center: { x: 2500, y: 440 }, dock: { x: 2350, y: 850 }, radius: 400, destination: 'forge', action: 'Visitar a forja' },
  { name: 'Coroa de Gelo', center: { x: 2520, y: 1540 }, dock: { x: 2130, y: 1700 }, radius: 390, destination: 'bounties', action: 'Encontrar o vigia' },
  { name: 'Selva dos Segredos', center: { x: 680, y: 1500 }, dock: { x: 1080, y: 1500 }, radius: 370, destination: 'ruins', action: 'Entrar na caverna' },
];
export const seaDistance = (a: SeaPoint, b: SeaPoint) => Math.hypot(a.x - b.x, a.y - b.y);
/** Tap input only: the server still owns steps, speed and coast collisions.
 * Its heartbeat caps elapsed time at two seconds, so approach conservatively. */
export function seaDestinationInput(position: SeaPoint, target: SeaPoint, throttle: number, speed: number) {
  if (![position.x, position.y, target.x, target.y, throttle, speed].every(Number.isFinite)) return { dx: 0, dy: 0, throttle: 0 };
  const distance = seaDistance(position, target);
  if (!Number.isFinite(distance) || distance <= 5) return { dx: 0, dy: 0, throttle: 0 };
  return { dx: (target.x - position.x) / distance, dy: (target.y - position.y) / distance,
    throttle: Math.max(0, Math.min(1, throttle, distance / (Math.max(1, speed) * 2))) };
}
export function sailToward(position: SeaPoint, target: SeaPoint, elapsed: number, speed = 240): SeaPoint {
  const distance = seaDistance(position, target);
  if (distance < 1) return { ...position };
  const step = Math.min(distance, Math.max(0, elapsed) * speed);
  const next = { x: position.x + (target.x - position.x) / distance * step, y: position.y + (target.y - position.y) / distance * step };
  return next;
}
// SEA_SIZE describes only the original archipelago, never a movement boundary.
export const SEA_CHUNK = 2400;
export type SeaIsland = typeof SEA_ISLANDS[number] & { id: string; templateIndex: number; procedural: boolean };
export function seaRegion(x: number, y: number): SeaIsland | null {
  // Keep the original islands and their approaches untouched.
  if (x >= -1 && x <= 1 && y >= -1 && y <= 1) return null;
  const seed = ((x * 73 + y * 151) % 997 + 997) % 997;
  if (seed % 4 === 0) return null;
  const templateIndex = seed % SEA_ISLANDS.length;
  const template = SEA_ISLANDS[templateIndex];
  const radius = 180 + seed % 260;
  const center = { x: x * SEA_CHUNK + 600 + seed % 1200, y: y * SEA_CHUNK + 600 + (seed * 37) % 1200 };
  return { ...template, id: `${x}:${y}`, name: ['Atol', 'Enseada', 'Caldeira', 'Coroa', 'Refúgio'][templateIndex] + ` ${seed + 1}`, center, dock: { x: center.x, y: center.y + radius + 100 }, radius, templateIndex, procedural: true };
}
export function seaIslandsAround(position: SeaPoint, range = 2): SeaIsland[] {
  const cx = Math.floor(position.x / SEA_CHUNK), cy = Math.floor(position.y / SEA_CHUNK);
  const islands: SeaIsland[] = SEA_ISLANDS.map((island, templateIndex) => ({ ...island, id: `home:${templateIndex}`, templateIndex, procedural: false })).filter(island => seaDistance(position, island.center) < SEA_CHUNK * (range + 1));
  for (let x = cx - range; x <= cx + range; x++) for (let y = cy - range; y <= cy + range; y++) {
    const island = seaRegion(x, y);
    if (island) islands.push(island);
  }
  return islands;
}
export function seaLandAt(point: SeaPoint): boolean {
  return seaIslandsAround(point, 1).some(island => seaDistance(point, island.center) < island.radius * .7);
}
export type SailingMotion = { velocity: SeaPoint; heading: number };
export function advanceSailing(position: SeaPoint, target: SeaPoint, motion: SailingMotion, elapsed: number, maxSpeed: number): SeaPoint {
  const dt = Math.min(.05, Math.max(0, elapsed));
  const distance = seaDistance(position, target);
  const desiredSpeed = Math.min(maxSpeed, distance * 2);
  const blend = 1 - Math.exp(-2.2 * dt);
  motion.velocity.x += ((distance > 1 ? (target.x - position.x) / distance * desiredSpeed : 0) - motion.velocity.x) * blend;
  motion.velocity.y += ((distance > 1 ? (target.y - position.y) / distance * desiredSpeed : 0) - motion.velocity.y) * blend;
  if (Math.hypot(motion.velocity.x, motion.velocity.y) > .5) {
    const heading = Math.atan2(motion.velocity.x, -motion.velocity.y);
    const angle = Math.atan2(Math.sin(heading - motion.heading), Math.cos(heading - motion.heading));
    motion.heading += angle * (1 - Math.exp(-3 * dt));
  }
  const next = { x: position.x + motion.velocity.x * dt, y: position.y + motion.velocity.y * dt };
  if (seaLandAt(next)) { motion.velocity.x = 0; motion.velocity.y = 0; return position; }
  return next;
}
export function seaClickTarget(point: SeaPoint): SeaPoint {
  const island = seaIslandsAround(point, 1).find((i) => seaDistance(i.center, point) < i.radius);
  return island?.dock ?? point;
}

/** Route around the same circular coastlines enforced by the server. */
export function seaRoute(origin: SeaPoint, destination: SeaPoint): SeaPoint[] {
  if (![origin.x, origin.y, destination.x, destination.y].every(Number.isFinite)) return [];
  const islands = [...new Map([...seaIslandsAround(origin, 1), ...seaIslandsAround(destination, 1)]
    .map(island => [island.id, island])).values()];
  const clear = (a: SeaPoint, b: SeaPoint) => islands.every(island => {
    const dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy;
    const t = length ? Math.max(0, Math.min(1, ((island.center.x - a.x) * dx + (island.center.y - a.y) * dy) / length)) : 0;
    return seaDistance({ x: a.x + t * dx, y: a.y + t * dy }, island.center) >= island.radius * .7 + 8;
  });
  if (clear(origin, destination)) return [destination];
  const nodes: SeaPoint[] = [origin, destination];
  for (const island of islands) for (let i = 0; i < 16; i++) {
    const angle = i * Math.PI / 8, radius = (island.radius * .7 + 12) / Math.cos(Math.PI / 16);
    const point = { x: island.center.x + Math.cos(angle) * radius, y: island.center.y + Math.sin(angle) * radius };
    if (clear(point, point)) nodes.push(point);
  }
  const costs = nodes.map(() => Infinity), previous = nodes.map(() => -1), visited = new Set<number>();
  costs[0] = 0;
  while (visited.size < nodes.length) {
    let current = -1;
    for (let i = 0; i < nodes.length; i++) if (!visited.has(i) && (current < 0 || costs[i] < costs[current])) current = i;
    if (current < 0 || !Number.isFinite(costs[current])) break;
    if (current === 1) {
      const route: SeaPoint[] = [];
      for (let i = 1; i !== 0; i = previous[i]) { if (i < 0) return []; route.unshift(nodes[i]); }
      return route;
    }
    visited.add(current);
    for (let i = 1; i < nodes.length; i++) {
      if (visited.has(i) || !clear(nodes[current], nodes[i])) continue;
      const cost = costs[current] + seaDistance(nodes[current], nodes[i]);
      if (cost < costs[i]) { costs[i] = cost; previous[i] = current; }
    }
  }
  return [];
}