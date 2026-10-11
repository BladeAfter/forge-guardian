import type { SeaPoint } from './grandLineNavigation';
import { shipStats, type NavalShip } from './naval';

/** Animate only toward an approved position; never extrapolate gameplay. */
export function approachApprovedPose(position: SeaPoint, heading: number, approved: SeaPoint & { heading: number }, elapsed: number, maxSpeed = Infinity) {
  const dt = Math.min(.05, Math.max(0, elapsed));
  const distance = Math.hypot(approved.x - position.x, approved.y - position.y);
  // A late response must not turn its accumulated distance into a visible leap.
  // Cap only the presentation step; the approved target remains unchanged.
  const blend = Math.min(1 - Math.exp(-6 * dt), distance > 0 ? maxSpeed * dt / distance : 1);
  const angle = Math.atan2(Math.sin(approved.heading - heading), Math.cos(approved.heading - heading));
  return { position: { x: position.x + (approved.x - position.x) * blend, y: position.y + (approved.y - position.y) * blend }, heading: heading + angle * blend };
}

/** Presentation cache only: removed players disappear; no position is extrapolated. */
export function updateApprovedFleet(cache: Map<string, NavalShip>, ships: NavalShip[], elapsed: number) {
  const present = new Set<string>();
  for (const ship of ships) {
    present.add(ship.user_id);
    const previous = cache.get(ship.user_id);
    if (!previous) { cache.set(ship.user_id, { ...ship }); continue; }
    const next = approachApprovedPose(previous, previous.heading, ship, elapsed, shipStats(ship).speed);
    cache.set(ship.user_id, { ...ship, ...next.position, heading: next.heading });
  }
  for (const id of cache.keys()) if (!present.has(id)) cache.delete(id);
  return cache;
}