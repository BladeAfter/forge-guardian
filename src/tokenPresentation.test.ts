import { describe, expect, it } from 'vitest';
import { isMythTokenReward, isVisiblePurchaseCurrency } from './tokenPresentation';
import { miningRateLines } from './miningCurrency';
describe('MYTH presentation retirement', () => {
  it('excludes MYTH purchases', () => expect(isVisiblePurchaseCurrency('MYTH')).toBe(false));
  it('retains TON purchases', () => expect(isVisiblePurchaseCurrency('TON')).toBe(true));
  it('retains BERRIES purchases', () => expect(isVisiblePurchaseCurrency('FC')).toBe(true));
  it('identifies token rewards without hiding mythic heroes', () => {
    expect(isMythTokenReward('myth_token')).toBe(true);
    expect(isMythTokenReward('myth')).toBe(true);
    expect(isMythTokenReward('hero_mythic')).toBe(false);
  });
  it('shows only official TON rates without converting token yield', () => {
    expect(miningRateLines(0.3, 500)).toEqual([{currency:'ton',amount:0.3}]);
    expect(miningRateLines(0, 500)).toEqual([]);
  });
});
