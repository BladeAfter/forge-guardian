/**
 * Browser-safe TON address helpers (no Node Buffer / @ton/core dependency).
 *
 * TonConnect returns the raw form ("0:<64 hex>"), which wallets like Tonkeeper reject
 * when pasted. We always persist and display the mainnet user-friendly form
 * (UQ…, non-bounceable, url-safe).
 */

const BOUNCEABLE_TAG = 0x11;
const NON_BOUNCEABLE_TAG = 0x51;
const TEST_FLAG = 0x80;

function crc16(data: Uint8Array): number {
  const poly = 0x1021;
  let reg = 0;
  const bytes = new Uint8Array(data.length + 2);
  bytes.set(data, 0);
  for (const byte of bytes) {
    let mask = 0x80;
    while (mask > 0) {
      reg <<= 1;
      if (byte & mask) reg += 1;
      mask >>= 1;
      if (reg > 0xffff) {
        reg &= 0xffff;
        reg ^= poly;
      }
    }
  }
  return reg;
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_');
}

function base64UrlToBytes(value: string): Uint8Array | null {
  try {
    const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
    const binary = atob(normalized);
    const out = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) out[i] = binary.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

function hexToBytes(hex: string): Uint8Array | null {
  if (hex.length !== 64 || !/^[0-9a-fA-F]{64}$/.test(hex)) return null;
  const out = new Uint8Array(32);
  for (let i = 0; i < 32; i += 1) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

function encodeFriendly(workchain: number, hash: Uint8Array): string {
  const payload = new Uint8Array(34);
  payload[0] = NON_BOUNCEABLE_TAG;
  payload[1] = workchain === -1 ? 0xff : workchain & 0xff;
  payload.set(hash, 2);
  const checksum = crc16(payload);
  const full = new Uint8Array(36);
  full.set(payload, 0);
  full[34] = (checksum >> 8) & 0xff;
  full[35] = checksum & 0xff;
  return bytesToBase64Url(full);
}

export function toFriendlyTonAddress(value: unknown): string | null {
  const raw = String(value ?? '').trim();
  if (!raw) return null;

  // Raw form: "0:<64 hex>" / "-1:<64 hex>"
  if (raw.includes(':')) {
    const [wcPart, hashPart] = raw.split(':');
    const workchain = Number(wcPart);
    if (!Number.isInteger(workchain)) return null;
    const hash = hexToBytes(hashPart ?? '');
    if (!hash) return null;
    return encodeFriendly(workchain, hash);
  }

  // Already friendly (base64/base64url, bounceable or not, main or testnet)
  if (raw.length === 48) {
    const bytes = base64UrlToBytes(raw);
    if (!bytes || bytes.length !== 36) return null;
    const tag = bytes[0] & ~TEST_FLAG;
    if (tag !== BOUNCEABLE_TAG && tag !== NON_BOUNCEABLE_TAG) return null;
    const expected = crc16(bytes.slice(0, 34));
    if (((expected >> 8) & 0xff) !== bytes[34] || (expected & 0xff) !== bytes[35]) return null;
    const workchain = bytes[1] === 0xff ? -1 : bytes[1];
    return encodeFriendly(workchain, bytes.slice(2, 34));
  }

  return null;
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
