/**
 * Central AdsGram integration.
 *
 * The SDK (https://sad.adsgram.ai/js/sad.min.js) is loaded once, lazily, and every
 * block gets a single controller instance. Block IDs are NEVER hardcoded in
 * components: the rewarded id and the interstitial id both come from the backend
 * (`game_settings` -> PvP dashboard `adsShop`), so they can be changed without a deploy.
 */

const SDK_URL = 'https://sad.adsgram.ai/js/sad.min.js';

/** Default rewarded block, used only as a fallback when the backend value is missing. */
export const ADSGRAM_PVP_REWARD_BLOCK_ID = '42560';

export type AdsgramState = {
  enabled: boolean;
  blockId: string | null;
  dailyLimit: number;
  watchedToday: number;
  remaining: number;
  cycleDate?: string;
  interstitialEnabled: boolean;
  interstitialBlockId: string | null;
};

type AdController = { show: () => Promise<unknown>; destroy?: () => void };

declare global {
  interface Window {
    Adsgram?: { init: (options: { blockId: string; debug?: boolean }) => AdController };
  }
}

let sdkPromise: Promise<void> | null = null;

/** Loads the SDK once. Reuses an existing tag/global if another module already added it. */
function loadSdk(): Promise<void> {
  if (typeof window === 'undefined') return Promise.reject(new Error('NO_WINDOW'));
  if (window.Adsgram) return Promise.resolve();
  if (sdkPromise) return sdkPromise;
  sdkPromise = new Promise<void>((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>(`script[src="${SDK_URL}"]`);
    const script = existing ?? document.createElement('script');
    const done = () => (window.Adsgram ? resolve() : reject(new Error('ADSGRAM_SDK_UNAVAILABLE')));
    script.addEventListener('load', done, { once: true });
    script.addEventListener('error', () => reject(new Error('ADSGRAM_SDK_UNAVAILABLE')), { once: true });
    if (!existing) {
      script.src = SDK_URL;
      script.async = true;
      document.head.appendChild(script);
    } else if (window.Adsgram) resolve();
  }).catch((error) => {
    sdkPromise = null;
    throw error;
  });
  return sdkPromise;
}

const controllers = new Map<string, AdController>();

/** One controller per block id — never re-initialized on every click. */
export async function adsgramController(blockId: string): Promise<AdController> {
  const id = String(blockId || '').trim();
  if (!id) throw new Error('ADSGRAM_BLOCK_MISSING');
  const cached = controllers.get(id);
  if (cached) return cached;
  await loadSdk();
  if (!window.Adsgram) throw new Error('ADSGRAM_SDK_UNAVAILABLE');
  const controller = window.Adsgram.init({ blockId: id, debug: false });
  controllers.set(id, controller);
  return controller;
}

export type AdShowOutcome = 'completed' | 'no-ads' | 'skipped' | 'error';

const outcomeOf = (error: unknown): AdShowOutcome => {
  const raw = `${(error as { description?: string })?.description ?? ''} ${(error as Error)?.message ?? ''}`.toLowerCase();
  if (raw.includes('not found') || raw.includes('no ad') || raw.includes('banner')) return 'no-ads';
  if (raw.includes('close') || raw.includes('skip') || raw.includes('not watched')) return 'skipped';
  return 'error';
};

/**
 * Shows an ad and resolves with the real outcome. `completed` means AdsGram
 * confirmed a valid reward event — that (and only that) may trigger the backend call.
 */
export async function showAd(blockId: string): Promise<AdShowOutcome> {
  try {
    const controller = await adsgramController(blockId);
    await controller.show();
    return 'completed';
  } catch (error) {
    console.error('[adsgram] show failed', error);
    return outcomeOf(error);
  }
}

const SESSION_KEY = 'mythreon:adsgram:entry-shown';

/**
 * Entry ad (game opening): reuses the SAME rewarded block as PvP (42560) but NEVER
 * grants any reward — no ticket, BERRIES, TON, XP or item, and no backend call at all.
 * Shown at most once per real Mini App session and always resolves (never blocks boot).
 */
export async function showEntryAd(blockId: string = ADSGRAM_PVP_REWARD_BLOCK_ID, timeoutMs = 20000): Promise<AdShowOutcome | 'skipped-session'> {
  if (typeof window === 'undefined') return 'skipped-session';
  try {
    if (window.sessionStorage.getItem(SESSION_KEY)) return 'skipped-session';
    window.sessionStorage.setItem(SESSION_KEY, '1');
  } catch {
    return 'skipped-session';
  }
  const guard = new Promise<AdShowOutcome>((resolve) => window.setTimeout(() => resolve('error'), timeoutMs));
  return Promise.race([showAd(blockId), guard]);
}

/**
 * Entry interstitial: at most once per real Mini App session (sessionStorage), never
 * on tab switches, modals or re-renders. Uses a dedicated interstitial block id.
 */
export async function showEntryInterstitial(state?: AdsgramState | null): Promise<void> {
  if (typeof window === 'undefined') return;
  if (!state?.interstitialEnabled || !state.interstitialBlockId) return;
  try {
    if (window.sessionStorage.getItem(SESSION_KEY)) return;
    window.sessionStorage.setItem(SESSION_KEY, '1');
  } catch {
    return;
  }
  await showAd(state.interstitialBlockId);
}
