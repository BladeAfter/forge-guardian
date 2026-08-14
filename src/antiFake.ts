import { forgeFetch } from './apiClient';

/**
 * ANTI-FAKE / ANTI-MULTIACCOUNT (client side = identity only, never the decision).
 *
 * The device identity is a SHA-256 hash of:
 *  - a persistent random installation id (localStorage, Telegram CloudStorage-safe)
 *  - low-entropy technical signals: Telegram WebApp platform + version, user agent,
 *    screen size, device pixel ratio, timezone offset, hardware concurrency
 *
 * Nothing is stored in plain text and no personal data is collected: only the final
 * hash leaves the device. The allowed/blocked decision is taken exclusively by the
 * backend (`check_device_access`), so editing this file cannot unlock the game.
 */

const STORAGE_KEY = 'mythreon.device.id';

const sha256Hex = async (input: string) => {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
};

/** Persistent installation id. Survives reloads; a reinstall/clear simply creates a new device. */
function installationId(): string {
  try {
    const existing = window.localStorage.getItem(STORAGE_KEY);
    if (existing && existing.length >= 16) return existing;
    const fresh = crypto.randomUUID().replace(/-/g, '');
    window.localStorage.setItem(STORAGE_KEY, fresh);
    return fresh;
  } catch {
    // Private mode / storage blocked: fall back to the technical signals only.
    return 'no-storage';
  }
}

export type DeviceIdentity = { deviceHash: string; platform: string; uaHash: string; tzOffset: number };

export async function buildDeviceIdentity(): Promise<DeviceIdentity> {
  const webApp = (window as unknown as { Telegram?: { WebApp?: { platform?: string; version?: string } } }).Telegram?.WebApp;
  const platform = String(webApp?.platform || 'web');
  const ua = String(navigator.userAgent || '');
  const signals = [
    installationId(),
    platform,
    String(webApp?.version || ''),
    ua,
    `${window.screen?.width ?? 0}x${window.screen?.height ?? 0}`,
    String(window.devicePixelRatio ?? 1),
    String(new Date().getTimezoneOffset()),
    String((navigator as unknown as { hardwareConcurrency?: number }).hardwareConcurrency ?? 0),
  ].join('|');
  return {
    deviceHash: await sha256Hex(`mythreon:device:${signals}`),
    platform,
    uaHash: (await sha256Hex(ua)).slice(0, 32),
    tzOffset: new Date().getTimezoneOffset(),
  };
}

export type DeviceAccess = {
  access: 'allowed' | 'blocked';
  status?: string;
  reason?: string | null;
  code?: string | null;
  pendingReview?: boolean;
};

/** Boot check. A network/backend failure never blocks the player (fail-open by design). */
export async function checkDeviceAccess(initData: string): Promise<{ result: DeviceAccess; identity: DeviceIdentity | null }> {
  try {
    const identity = await buildDeviceIdentity();
    const response = await forgeFetch('device', { initData, action: 'check', ...identity });
    const payload = (await response.json()) as DeviceAccess | null;
    if (response.status === 403) return { result: { access: 'blocked', reason: 'MULTIPLE_ACCOUNTS_DETECTED', code: 'MULTI_ACCOUNT_LIMIT' }, identity };
    if (!response.ok || !payload) return { result: { access: 'allowed', status: 'unverified' }, identity };
    return { result: { ...payload, access: payload.access === 'blocked' ? 'blocked' : 'allowed' }, identity };
  } catch (error) {
    console.error('[ANTI FAKE] device check failed', error);
    return { result: { access: 'allowed', status: 'unverified' }, identity: null };
  }
}

/** Player-initiated review request. Never unblocks automatically. */
export async function requestDeviceReview(initData: string, identity: DeviceIdentity | null, message = '') {
  if (!identity) throw new Error('DEVICE_UNKNOWN');
  const response = await forgeFetch('device', { initData, action: 'review', deviceHash: identity.deviceHash, message });
  const payload = (await response.json()) as { ok?: boolean; status?: string } | null;
  if (!response.ok || !payload?.ok) throw new Error('REVIEW_REQUEST_FAILED');
  return payload;
}
