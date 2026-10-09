import type { SeaPoint } from './grandLineNavigation';
export const ISLAND_SIZE = { width: 1536, height: 1024 };
export const ISLAND_SHIP = { x: 768, y: 925 };
export const ISLAND_LANDING = { x: 768, y: 765 };
const paths = [
  [{ x: 768, y: 945 }, { x: 768, y: 690 }],
  [{ x: 145, y: 755 }, { x: 1360, y: 755 }],
  [{ x: 768, y: 755 }, { x: 745, y: 450 }],
  [{ x: 745, y: 450 }, { x: 755, y: 250 }],
  [{ x: 745, y: 450 }, { x: 1270, y: 220 }],
  [{ x: 745, y: 450 }, { x: 400, y: 430 }],
  [{ x: 1020, y: 755 }, { x: 1110, y: 525 }],
] as const;
export function islandWalkable(p: SeaPoint) {
  if (p.x < 100 || p.x > 1436 || p.y < 180 || p.y > 945) return false;
  return paths.some(([a, b]) => {
    const dx = b.x - a.x, dy = b.y - a.y;
    const t = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)));
    return Math.hypot(p.x - a.x - t * dx, p.y - a.y - t * dy) < (p.y > 675 && p.y < 805 ? 105 : 80);
  });
}
export function walkIsland(position: SeaPoint, target: SeaPoint, seconds: number): SeaPoint {
  const distance = Math.hypot(target.x - position.x, target.y - position.y);
  if (distance < 1) return position;
  const step = Math.min(distance, Math.max(0, seconds) * 190);
  const next = { x: position.x + (target.x - position.x) / distance * step, y: position.y + (target.y - position.y) / distance * step };
  if (islandWalkable(next)) return next;
  if (islandWalkable({ x: next.x, y: position.y })) return { x: next.x, y: position.y };
  if (islandWalkable({ x: position.x, y: next.y })) return { x: position.x, y: next.y };
  return position;
}