import { describe, expect, it } from 'vitest';
import { COMMUNITY_POOL_PERCENT, poolContributionTon } from './communityPool';

describe('community pool contribution', () => {
  it('books 15% of confirmed TON revenue', () => {
    expect(COMMUNITY_POOL_PERCENT).toBe(15);
    expect(poolContributionTon(1)).toBeCloseTo(0.15, 9);
    expect(poolContributionTon(3)).toBeCloseTo(0.45, 9);
    expect(poolContributionTon(10)).toBeCloseTo(1.5, 9);
    expect(poolContributionTon(20)).toBeCloseTo(3, 9);
  });
  it('ignores non-TON revenue (FC spending)', () => {
    expect(poolContributionTon(0)).toBe(0);
    expect(poolContributionTon(-5)).toBe(0);
  });
  it('supports a configurable rate', () => {
    expect(poolContributionTon(10, 20)).toBeCloseTo(2, 9);
  });
});
