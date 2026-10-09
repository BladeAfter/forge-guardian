import { describe, expect, it } from 'vitest';
import { isHiddenVeteranItem } from './retiredOfferPresentation';

describe('Veteran Vault presentation retirement', () => {
  it('hides Veteran Vault chests', () => { expect(isHiddenVeteranItem({ itemId: 'veteran-vault-chest' })).toBe(true); });
  it('hides Veteran heroes with premium source', () => { expect(isHiddenVeteranItem({ heroKey: 'captain', premiumSource: 'VETERAN_VAULT_V2' })).toBe(true); });
  it('hides Veteran equipment', () => { expect(isHiddenVeteranItem({ code: 'veteran-warblade' })).toBe(true); });
  it('keeps ordinary chests, heroes and gear visible', () => { for (const item of [{ itemId: 'legendary_chest' }, { heroKey: 'deckblade' }, { code: 'pirate-saber' }]) expect(isHiddenVeteranItem(item)).toBe(false); });
});