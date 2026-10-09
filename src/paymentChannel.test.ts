import { describe, expect, it } from 'vitest';
import { eligiblePayment, paymentCaption, PAYMENT_CHANNEL } from '../supabase/functions/payment-channel/format';
describe('payment channel rules', () => {
  it('targets the requested payment channel', () => expect(PAYMENT_CHANNEL).toBe('@MythicSeasPayout'));
  it('formats a compact withdrawal with the actual transaction and game hashtags', () => {
    const caption = paymentCaption({ id: 'test', kind: 'withdrawal', amount_ton: 0.578, amount_fc: 0,
      wallet: 'UQDD123456789VgWR', tx_hash: 'actual/hash', occurred_at: '2026-10-09T23:24:00Z' });
    expect(caption).toContain('Saque pago — 0,578 TON');
    expect(caption).toContain('UQDD12…VgWR');
    expect(caption).toContain('https://tonviewer.com/transaction/actual%2Fhash');
    expect(caption).toContain('Ver na Tonviewer');
    expect(caption).toContain('#MythicSeasbot #payout');
    expect(caption).not.toContain('GRAM');
  });
  it('preserves credited BERRIES and escapes wallet text for deposits', () => {
    const caption = paymentCaption({ id: 'test', kind: 'deposit', amount_ton: 5, amount_fc: 5000,
      wallet: '<wallet>', tx_hash: 'deposit-hash', occurred_at: '2026-10-09T23:24:00Z' });
    expect(caption).toContain('Depósito confirmado — 5 TON');
    expect(caption).toContain('5.000 BERRIES creditados');
    expect(caption).not.toContain('<wallet>');
    expect(caption).toContain('#MythicSeasbot #payout');
  });
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