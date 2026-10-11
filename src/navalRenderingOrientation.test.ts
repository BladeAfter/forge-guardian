import { describe, expect, it, vi } from 'vitest';
vi.mock('./oceanPresentation', () => ({ oceanImage: () => ({ complete: true, naturalWidth: 640 }) }));
vi.mock('./shipCustomization', () => ({ customizedFleetImage: (image: unknown) => image }));
import { drawNavalShip, type NavalPalette } from './navalRendering';
import { DEFAULT_SHIP } from './naval';

describe('upright catalog ships', () => {
  it.each([0, Math.PI / 2, Math.PI, -Math.PI / 2])('cancels world rotation for broadside art at heading %s', heading => {
    const calls: Array<{ angle: number; mirrored: number }> = [];
    let angle = 0, mirrored = 1;
    const stack: Array<{ angle: number; mirrored: number }> = [];
    const ctx = new Proxy({}, { get: (_, key) => {
      if (key === 'save') return () => stack.push({ angle, mirrored });
      if (key === 'restore') return () => { const saved = stack.pop(); if (saved) { angle = saved.angle; mirrored = saved.mirrored; } };
      if (key === 'rotate') return (value: number) => { angle += value; };
      if (key === 'scale') return (value: number) => { mirrored *= value; };
      if (key === 'drawImage') return () => calls.push({ angle, mirrored });
      return vi.fn();
    } }) as CanvasRenderingContext2D;
    const palette: NavalPalette = { foam: '', gold: '', ink: '', vitality: '', ember: '', filters: {} };
    drawNavalShip(ctx, { naturalWidth: 1144, naturalHeight: 768 } as HTMLImageElement, { ...DEFAULT_SHIP, class_id: 'marinheiro', heading }, palette, 0);
    expect(calls).toEqual([{ angle: 0, mirrored: Math.sin(heading) > .01 ? -1 : 1 }]);
  });
});