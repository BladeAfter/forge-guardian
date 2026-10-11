import type { SeaPoint } from './grandLineNavigation';

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