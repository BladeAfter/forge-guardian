import { describe, expect, it } from 'vitest';
import { advanceHarbor, cameraRelativeMotion, HARBOR, ISLAND_3D, islandHeight, newHarborState, newIslandInput, nodePosition3D } from './island3dWorld';
import type { RealmExploreNode } from './realm';

describe('3D island presentation', () => {
  it('keeps ship hull beside the pier and below water with seabed clearance', () => {
    expect(HARBOR.ship.x - HARBOR.ship.halfWidth).toBeGreaterThan(HARBOR.pier.halfWidth);
    expect(HARBOR.ship.y).toBeLessThan(ISLAND_3D.water);
    for (const x of [4, 7, 10]) for (const z of [42.5, 49, 55.5]) expect(islandHeight(x, z)).toBeLessThan(HARBOR.ship.y - .5);
    expect(HARBOR.gangway.start).toBeLessThan(HARBOR.pier.halfWidth);
    expect(HARBOR.gangway.end).toBeGreaterThan(HARBOR.ship.x - HARBOR.ship.halfWidth);
  });
  it('stops on water before deploying the gangway', () => {
    const state = newHarborState();
    advanceHarbor(state, HARBOR.approachSeconds);
    expect(state.x).toBe(HARBOR.ship.x); expect(state.z).toBe(HARBOR.ship.z);
    expect(state.deployment).toBe(0); expect(state.ready).toBe(false);
    advanceHarbor(state, HARBOR.deploySeconds);
    expect(state.deployment).toBe(1); expect(state.ready).toBe(true);
  });
  it('has shallow coast, grounded interior and raised mountains', () => {
    expect(islandHeight(0, 0)).toBeGreaterThan(0);
    expect(islandHeight(0, 55)).toBeLessThan(-.35);
    expect(islandHeight(-14, -18)).toBeGreaterThan(7);
  });
  it('transforms forward into the camera facing and right into screen right', () => {
    expect(cameraRelativeMotion(0, 1, 0)).toEqual({ x: 0, z: -1 });
    expect(cameraRelativeMotion(1, 0, 0)).toEqual({ x: 1, z: -0 });
    expect(cameraRelativeMotion(0, 1, Math.PI / 2).x).toBeCloseTo(-1);
    expect(Math.hypot(...Object.values(cameraRelativeMotion(1, 1, 0)))).toBeCloseTo(1);
  });
  it('starts safe, with no cosmetic action changing an account', () => {
    expect(newIslandInput().boarding).toBe(false);
    expect(newIslandInput().attack).toBe(false);
    expect(newIslandInput().zoom).toBeGreaterThan(3);
  });
  it('keeps encounter locations deterministic and separate from server status', () => {
    const node = { id: 'node', node_type: 'treasure', depth: 1, lane: 0, status: 'available', config: null } as RealmExploreNode;
    expect(nodePosition3D(node)).toEqual(nodePosition3D({ ...node, status: 'resolved' }));
  });
});