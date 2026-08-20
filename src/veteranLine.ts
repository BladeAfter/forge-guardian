/**
 * VETERAN LINE (Founder Pack 35 TON + Veteran Vault 100 TON).
 *
 * These heroes/pets/dragons are NOT part of the normal rarity ladder: they are a
 * SUPERIOR premium line and must always show the VETERAN tag instead of MÍTICO.
 * They never mine TON — the server pays them exclusively in MYTH per day.
 */
export const VETERAN_LINE_LABEL = 'VETERAN';
export const VETERAN_LINE_COLOR = '#f59e0b';

type VeteranLike = {
  veteranLine?: boolean | null;
  veteran_line?: boolean | null;
  premiumSource?: string | null;
  premium_source?: string | null;
};

/** True when the item came from the Founder Pack or the Veteran Vault. */
export function isVeteranLine(item?: VeteranLike | null): boolean {
  if (!item) return false;
  if (item.veteranLine === true || item.veteran_line === true) return true;
  const source = String(item.premiumSource ?? item.premium_source ?? '').toUpperCase();
  return source === 'FOUNDER' || source === 'VETERAN' || source === 'VETERAN_VAULT_V2';
}
