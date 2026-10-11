import { describe, expect, it, vi } from 'vitest';
import { drawOpenWater, islandArtDiameter } from './oceanPresentation';
import { SEA_ISLANDS, seaIslandsAround, seaLandAt } from './grandLineNavigation';

describe('open sea presentation', () => {
  it('reduces island artwork without shrinking official land or moving docks', () => {
    for (const island of SEA_ISLANDS) {
      expect(islandArtDiameter(island.radius)).toBeLessThan(island.radius * 2.5);
      expect(islandArtDiameter(island.radius) / 2).toBeGreaterThan(island.radius * .7);
      expect(seaLandAt(island.center)).toBe(true);
      expect(seaLandAt(island.dock)).toBe(false);
    }
  });
  it('continues streaming islands beyond the original archipelago', () => {
    const islands = seaIslandsAround({ x: -18000, y: 24000 }, 1);
    expect(islands.length).toBeGreaterThan(0);
    expect(islands.every(island => island.procedural)).toBe(true);
  });
  it('paints wide ocean spans with one cached mirrored pattern', () => {
    const painter = { drawImage: vi.fn(), save: vi.fn(), restore: vi.fn(), translate: vi.fn(), scale: vi.fn() };
    vi.stubGlobal('document', { createElement: () => ({ getContext: () => painter }) });
    const ctx = { createPattern: vi.fn(() => ({})), fillRect: vi.fn() };
    const source = {} as HTMLImageElement;
    try {
      drawOpenWater(ctx as unknown as CanvasRenderingContext2D, source, { x: -300, y: -300 }, 4000, 6000);
      drawOpenWater(ctx as unknown as CanvasRenderingContext2D, source, { x: 4500, y: 8000 }, 4000, 6000);
      expect(ctx.createPattern).toHaveBeenCalledTimes(1);
      expect(painter.drawImage).toHaveBeenCalledTimes(5);
      expect(ctx.fillRect).toHaveBeenCalledTimes(2);
    } finally { vi.unstubAllGlobals(); }
  });
});