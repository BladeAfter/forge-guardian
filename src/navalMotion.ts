import type { SeaPoint } from './grandLineNavigation';

/** Animate only toward an approved position; never extrapolate gameplay. */
export function approachApprovedPose(position: SeaPoint, heading: number, approved: SeaPoint & { heading: number }, elapsed: number) {
  const blend = 1 - Math.exp(-6 * Math.min(.05, Math.max(0, elapsed)));
  const angle = Math.atan2(Math.sin(approved.heading - heading), Math.cos(approved.heading - heading));
  return { position: { x: position.x + (approved.x - position.x) * blend, y: position.y + (approved.y - position.y) * blend }, heading: heading + angle * blend };
}