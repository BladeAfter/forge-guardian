import { Address } from '@ton/core';

/**
 * TonConnect returns the raw form ("0:<64 hex>"), which wallets like Tonkeeper reject when pasted.
 * We always persist and display the mainnet user-friendly form (UQ…, non-bounceable, url-safe).
 */
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

/** Short display form (never used for payments). */
export function shortTonAddress(value: unknown): string {
  const friendly = toFriendlyTonAddress(value);
  if (!friendly) return '—';
  return `${friendly.slice(0, 6)}…${friendly.slice(-6)}`;
}
