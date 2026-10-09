import { describe, expect, it } from 'vitest';
import { cameraRelativeMotion, islandHeight, newIslandInput, nodePosition3D } from './island3dWorld';
import type { RealmExploreNode } from './realm';

describe('3D island presentation', () => {
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