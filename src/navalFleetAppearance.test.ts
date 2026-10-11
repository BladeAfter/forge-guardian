import { describe, expect, it } from 'vitest';
import { DEFAULT_SHIP, shipStats } from './naval';
import { fleetAppearanceUrl } from './navalRendering';
import { fleetShipArt } from './gameAssets';

describe('server-selected fleet appearance', () => {
  it('uses the exact catalog artwork for each selected class', () => {
    for (const [class_id, url] of Object.entries(fleetShipArt.classes)) {
      expect(fleetAppearanceUrl({ ...DEFAULT_SHIP, class_id })).toBe(url);
    }
  });
  it('prefers the official class identifier over legacy cosmetics', () => {
    expect(fleetAppearanceUrl({ ...DEFAULT_SHIP, class_id: 'corsario', active_class: 'marinheiro', skin: 'black' })).toBe(fleetShipArt.classes.corsario);
  });
  it('supports the persisted class and safely falls back for legacy or unknown ships', () => {
    expect(fleetAppearanceUrl({ ...DEFAULT_SHIP, active_class: 'fantasma' })).toBe(fleetShipArt.classes.fantasma);
    expect(fleetAppearanceUrl(DEFAULT_SHIP)).toBeUndefined();
    expect(fleetAppearanceUrl({ ...DEFAULT_SHIP, class_id: '__proto__' })).toBeUndefined();
  });
  it('does not change movement or combat attributes', () => {
    expect(shipStats({ ...DEFAULT_SHIP, class_id: 'rei_dos_mares' })).toEqual(shipStats(DEFAULT_SHIP));
  });
});