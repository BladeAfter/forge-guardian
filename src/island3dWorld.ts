import type { RealmExploreNode } from './realm';

export const ISLAND_3D = { size: 120, water: -0.35, dock: { x: 0, z: 40 }, spawn: { x: 0, z: 43 }, shore: { x: 0, z: 29 } };
export type IslandMotion = 'idle' | 'walk' | 'run' | 'sprint' | 'jump' | 'fall' | 'dodge' | 'attack' | 'interact' | 'swim' | 'climb' | 'descend';
export type IslandInput = { x: number; y: number; sprint: boolean; jump: boolean; dodge: boolean; attack: boolean; interact: boolean; yaw: number; pitch: number; zoom: number; blocked: boolean; boarding: boolean };
export const newIslandInput = (): IslandInput => ({ x: 0, y: 0, sprint: false, jump: false, dodge: false, attack: false, interact: false, yaw: 0, pitch: .32, zoom: 7.5, blocked: false, boarding: false });
export type IslandTelemetry = { x: number; y: number; z: number; speed: number; motion: IslandMotion; phase: 'landing' | 'exploring' | 'boarding'; heading: number };
export function islandHeight(x: number, z: number): number {
  const radius = Math.hypot(x / 1.07, z);
  const coast = Math.max(0, Math.min(1, (49 - radius) / 12));
  const hill = 8 * Math.exp(-((x + 14) ** 2 + (z + 18) ** 2) / 250);
  const ridge = 4 * Math.exp(-((x - 25) ** 2 + (z + 25) ** 2) / 200);
  const ripple = .4 * Math.sin(x * .18) * Math.cos(z * .17);
  return -1.4 + coast * (2.3 + hill + ridge + ripple);
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