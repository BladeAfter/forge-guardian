import { describe, expect, it } from 'vitest';
import { canCustomizeShip, shipCosmetics, CUSTOMIZATION_DEFAULTS, SHIP_COLORS } from './shipCustomization';
import { shipCustomizationLiteral } from './locales/shipCustomization';
describe('Purchased ship cosmetics', () => {
  it('requires the authoritative paid marker, not ownership or catalog cost', () => {
    expect(canCustomizeShip()).toBe(false);
    expect(canCustomizeShip({})).toBe(false);
    expect(canCustomizeShip({ canCustomize: false })).toBe(false);
    expect(canCustomizeShip({ canCustomize: true })).toBe(true);
  });
  it('merges per-ship appearance without mutating defaults', () => {
    const c = shipCosmetics({ flagColor: 'blue', sailColor: 'red' });
    expect(c.flagColor).toBe('blue'); expect(c.sailColor).toBe('red');
    expect(CUSTOMIZATION_DEFAULTS.flagColor).toBe('red'); expect(c.hullColor).toBe('original');
    expect(Object.keys(c)).not.toContain('atk');
  });
  it('uses server allowed colors', () => expect(SHIP_COLORS).toEqual(['original','red','blue','green','gold','black','white']));
  it('localizes the purchase lock and save action into all five languages', () => {
    for (const language of ['pt','en','es','ru','tr'] as const) {
      expect(shipCustomizationLiteral(language, 'Personalização disponível apenas nos navios comprados.')).toBeTruthy();
      expect(shipCustomizationLiteral(language, 'SALVAR APARÊNCIA')).toBeTruthy();
    }
  });
});