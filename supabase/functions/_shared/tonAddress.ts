// Shared TON address normalisation for edge functions.
// TonConnect hands us the raw form ("0:<64 hex>"); wallets only accept the user-friendly mainnet form.
import { Address } from 'npm:@ton/core@0.63.1';

export function toFriendlyTonAddress(value: unknown): string | null {
  const raw = String(value ?? '').trim();
  if (!raw) return null;
  try {
    return Address.parse(raw).toString({ urlSafe: true, bounceable: false, testOnly: false });
  } catch {
    return null;
  }
}

export function isValidTonAddress(value: unknown): boolean {
  return toFriendlyTonAddress(value) !== null;
}
