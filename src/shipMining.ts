export type ShipMiningQuote = {
  eligible: boolean;
  roiDays: number;
  continuous: boolean;
  dailyTon: number;
  accruedTon: number;
  startedAt?: string | null;
  payoutStatus: 'funding_review' | 'ineligible';
};
/** Display server quotes only; never project wallet balances or infer eligibility from catalog price. */
export function approvedShipMining(quote?: ShipMiningQuote | null): ShipMiningQuote | null {
  if (!quote?.eligible || quote.payoutStatus !== 'funding_review' || !Number.isFinite(quote.dailyTon) || quote.dailyTon <= 0 || !Number.isFinite(quote.accruedTon) || quote.accruedTon < 0) return null;
  return quote;
}
