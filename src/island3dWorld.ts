import type { RealmExploreNode } from './realm';

// MAR → NAVIO → PÍER → PRAIA. Ship local forward is -Z; no yaw rotation.
export const ISLAND_3D = { size: 120, water: -0.35, dock: { x: 0, z: 48 }, spawn: { x: 5.3, z: 48 }, gangway: { x: 0, z: 48 }, shore: { x: 0, z: 29 } };
export const HARBOR = { ship: { x: 7, z: 49, y: -1.65, scale: 1.25, halfWidth: 3, halfLength: 6.625, deck: .975 }, approach: { x: 11, z: 57 }, pier: { halfWidth: 1.75, start: 30, end: 53, top: .99 }, gangway: { start: 1.65, end: 4.3, z: 48, width: 1.4 }, approachSeconds: 5, deploySeconds: 1.4 };
export type HarborState = { elapsed: number; x: number; y: number; z: number; deployment: number; ready: boolean };
export const newHarborState = (): HarborState => ({ elapsed: 0, x: HARBOR.approach.x, y: HARBOR.ship.y, z: HARBOR.approach.z, deployment: 0, ready: false });
export function advanceHarbor(state: HarborState, delta: number) {
  state.elapsed += delta;
  const t = Math.min(1, state.elapsed / HARBOR.approachSeconds), eased = t * t * (3 - 2 * t);
  state.x = HARBOR.approach.x + (HARBOR.ship.x - HARBOR.approach.x) * eased;
  state.z = HARBOR.approach.z + (HARBOR.ship.z - HARBOR.approach.z) * eased;
  state.y = HARBOR.ship.y + Math.sin(state.elapsed * 1.2) * .035;
  state.deployment = Math.max(0, Math.min(1, (state.elapsed - HARBOR.approachSeconds) / HARBOR.deploySeconds));
  state.ready = state.deployment >= 1;
}
export type IslandMotion = 'idle' | 'walk' | 'run' | 'sprint' | 'jump' | 'fall' | 'dodge' | 'attack' | 'interact' | 'swim' | 'climb' | 'descend';
export type IslandInput = { x: number; y: number; sprint: boolean; jump: boolean; dodge: boolean; attack: boolean; interact: boolean; yaw: number; pitch: number; zoom: number; blocked: boolean; boarding: boolean };
export const newIslandInput = (): IslandInput => ({ x: 0, y: 0, sprint: false, jump: false, dodge: false, attack: false, interact: false, yaw: -1.1, pitch: .6, zoom: 10, blocked: false, boarding: false });
export type IslandTelemetry = { x: number; y: number; z: number; speed: number; motion: IslandMotion; phase: 'approaching' | 'deploying' | 'landing' | 'exploring' | 'boarding'; heading: number };
export function islandHeight(x: number, z: number): number {
  const radius = Math.hypot(x / 1.07, z);
  const coast = Math.max(0, Math.min(1, (49 - radius) / 12));
  const hill = 8 * Math.exp(-((x + 14) ** 2 + (z + 18) ** 2) / 250);
  const ridge = 4 * Math.exp(-((x - 25) ** 2 + (z + 25) ** 2) / 200);
  const ripple = .4 * Math.sin(x * .18) * Math.cos(z * .17);
  const natural = -1.4 + coast * (2.3 + hill + ridge + ripple);
  // Dredged water berth: the keel stays clear of the seabed, including on approach.
  const berth = Math.max(0, Math.min(1, (z - 39) / 4)) * Math.max(0, Math.min(1, (x - 2) / 2));
  return natural * (1 - berth) - 4 * berth;
}
export function nodePosition3D(node: RealmExploreNode): { x: number; z: number } {
  const spots = [{ x: 12, z: 17 }, { x: -15, z: 14 }, { x: 1, z: -3 }, { x: 21, z: -7 }, { x: -24, z: -8 }, { x: 25, z: -26 }, { x: -10, z: -28 }];
  const index = node.node_type === 'boss' ? 6 : node.node_type === 'elite' ? 5 : Math.abs(node.depth * 3 + node.lane) % 6;
  return spots[index] ?? spots[0];
}
export function cameraRelativeMotion(x: number, forward: number, yaw: number) {
  const length = Math.max(1, Math.hypot(x, forward));
  return { x: (x * Math.cos(yaw) - forward * Math.sin(yaw)) / length, z: (-x * Math.sin(yaw) - forward * Math.cos(yaw)) / length };
}