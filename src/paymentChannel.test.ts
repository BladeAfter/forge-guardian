import { describe, expect, it } from 'vitest';
import { eligiblePayment, PAYMENT_CHANNEL } from '../supabase/functions/payment-channel/format';
describe('payment channel rules', () => {
  it('targets the requested payment channel', () => expect(PAYMENT_CHANNEL).toBe('@MythicSeasPayout'));
  it('announces only credited deposits with a transaction', () => {
    expect(eligiblePayment('deposit', 'credited', 'chain-hash', 5)).toBe(true);
    expect(eligiblePayment('deposit', 'pending', 'chain-hash', 5)).toBe(false);
    expect(eligiblePayment('deposit', 'confirmed', null, 5)).toBe(false);
  });
  it('announces paid withdrawals, never requests or failed transfers', () => {
    expect(eligiblePayment('withdrawal', 'paid', 'chain-hash', 0.51)).toBe(true);
    expect(eligiblePayment('withdrawal', 'completed', 'chain-hash', 0.51)).toBe(true);
    for (const status of ['pending', 'processing', 'rejected', 'cancelled']) {
      expect(eligiblePayment('withdrawal', status, 'chain-hash', 0.51)).toBe(false);
    }
  });
});