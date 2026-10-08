import { describe, expect, it } from 'vitest';
import { formatTon } from './economy';

describe('formatTon', () => {
  it('drops trailing zeros on whole amounts', () => {
    expect(formatTon(2)).toBe('2');
    expect(formatTon(2.000000000)).toBe('2');
    expect(formatTon('10.000000000')).toBe('10');
  });
  it('keeps real decimals', () => {
    expect(formatTon(2.2)).toBe('2.2');
    expect(formatTon(1.5)).toBe('1.5');
    expect(formatTon(0.9)).toBe('0.9');
    expect(formatTon(2.125)).toBe('2.125');
  });
  it('never breaks on invalid input', () => {
    expect(formatTon(null)).toBe('0');
    expect(formatTon(NaN)).toBe('0');
  });
});
