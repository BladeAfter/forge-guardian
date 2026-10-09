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
export function sailToward(position: SeaPoint, target: SeaPoint, elapsed: number, speed = 240): SeaPoint {
  const distance = seaDistance(position, target);
  if (distance < 1) return { ...position };
  const step = Math.min(distance, Math.max(0, elapsed) * speed);
  const next = { x: position.x + (target.x - position.x) / distance * step, y: position.y + (target.y - position.y) / distance * step };
  return { x: Math.min(SEA_SIZE.width - 60, Math.max(60, next.x)), y: Math.min(SEA_SIZE.height - 60, Math.max(60, next.y)) };
}
export function seaClickTarget(point: SeaPoint): SeaPoint {
  const island = SEA_ISLANDS.find((i) => seaDistance(i.center, point) < i.radius);
  return island?.dock ?? point;
}