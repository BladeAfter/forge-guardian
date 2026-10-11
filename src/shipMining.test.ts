import { describe, expect, it } from 'vitest';
import { approvedShipMining, type ShipMiningQuote } from './shipMining';
import { translate } from './i18n';
import { readFileSync } from 'node:fs';
const paid: ShipMiningQuote = { eligible: true, roiDays: 40, continuous: true, dailyTon: .125, accruedTon: 5.125, payoutStatus: 'funding_review' };
describe('paid ship TON mining', () => {
  it('displays server accrual beyond ROI without marking it spendable', () => { expect(approvedShipMining(paid)).toEqual(paid); });
  it('rejects free, missing and invalid quotes', () => {
    expect(approvedShipMining()).toBeNull();
    for (const q of [{ ...paid, eligible: false }, { ...paid, dailyTon: 0 }, { ...paid, dailyTon: NaN }, { ...paid, accruedTon: -1 }, { ...paid, payoutStatus: 'ineligible' as const }]) expect(approvedShipMining(q)).toBeNull();
  });
  it('translates the ROI and funding state in every language', () => {
    for (const language of ['pt', 'en', 'es', 'ru', 'tr'] as const) {
      expect(translate(language, 'shipMining.roi', { days: 40 })).toContain('40');
      expect(translate(language, 'shipMining.review')).not.toContain('shipMining.');
    }
  });
  it('requires completed debit proof and excludes free ships without credits/workers', () => {
    const sql = readFileSync('drizzle/migrations/0139_paid_ship_continuous_ton_mining.sql', 'utf8');
    for (const token of ["l.status='completed'", "l.direction='debit'", 'l.amount_ton=o.price_paid', "o.class_id<>'marinheiro'", 'price_paid/40', 'greatest(mining_started_at,acquired_at)']) expect(sql).toContain(token);
    expect(sql).not.toMatch(/UPDATE\s+.*game_players|cron.schedule|INSERT INTO.*ledger/i);
  });
});
