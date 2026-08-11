import { supabaseAnonKey, supabaseUrl } from './supabaseEnv';

export type ForgeResponse = { ok: boolean; status: number; json: () => Promise<unknown> };

const functionsBase = supabaseUrl ? `${supabaseUrl.replace(/\/+$/, '')}/functions/v1/game-api` : '';

/**
 * Single entry point for every game feature. All business logic lives in the
 * `game-api` edge function, which validates the signed Telegram initData
 * server-side before touching the database with the service role.
 *
 * When there is no backend configured or no Telegram session (plain browser
 * preview), it returns a synthetic 404 so callers keep their existing
 * local-preview behaviour instead of surfacing a fake backend error.
 */
export const forgeBackendUrl = functionsBase;

export type ForgeAuthProbe = {
  ok: boolean;
  telegramId?: number;
  ageSeconds?: number;
  botUsername?: string | null;
  reason?: string;
  error?: string;
};

/** Validates the Telegram session against the game bot token, without touching game data. */
export async function forgeAuthProbe(initData: string): Promise<ForgeAuthProbe> {
  if (!functionsBase || !supabaseAnonKey) return { ok: false, reason: 'backend_not_configured', error: 'Backend não configurado.' };
  if (!initData || !new URLSearchParams(initData).get('hash')) return { ok: false, reason: 'init_data_missing', error: 'Sessão do Telegram ausente. Abra o jogo pelo Telegram.' };
  const response = await fetchWithTimeout(`${functionsBase}/auth`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: supabaseAnonKey, 'X-Telegram-Init-Data': initData },
    body: JSON.stringify({ initData }),
  });
  const payload = (await response.json().catch(() => null)) as ForgeAuthProbe | null;
  return payload ?? { ok: false, reason: 'offline', error: 'Backend indisponível.' };
}

export type ForgeHealth = {
  ok: boolean;
  game_bot_username?: string | null;
  game_bot_token_source?: string;
  admin_bot_token_separated?: boolean;
  telegram_auth_max_age_seconds?: number;
  app?: string;
  backend?: string;
  database?: string;
  telegram_auth?: string;
  database_error?: string;
};

/** Public, secret-free diagnostics. Used before loading heavier systems. */
export async function forgeHealth(): Promise<ForgeHealth> {
  if (!functionsBase) return { ok: false, backend: 'not_configured' };
  try {
    const response = await fetchWithTimeout(`${functionsBase}/health`, {
      headers: supabaseAnonKey ? { apikey: supabaseAnonKey } : undefined,
    });
    const payload = (await response.json().catch(() => null)) as ForgeHealth | null;
    return payload ?? { ok: false, backend: 'offline' };
  } catch (error) {
    console.error('[FORGE REQUEST FAILED]', { endpoint: `${functionsBase}/health`, status: 0, error });
    return { ok: false, backend: 'offline' };
  }
}

const hasSignedInitData = (initData: string) => {
  if (!initData) return false;
  try {
    return Boolean(new URLSearchParams(initData).get('hash'));
  } catch {
    return false;
  }
};

/**
 * Telegram webviews (Android especially) can leave a fetch hanging forever when the
 * connection drops mid-request. Every backend call must fail loudly instead of
 * keeping a React Query in `pending` state and freezing the boot screen.
 */
export async function fetchWithTimeout(input: string, init: RequestInit = {}, timeoutMs = 12_000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } catch (error) {
    if (controller.signal.aborted) throw new Error(`Tempo excedido ao contatar o backend (${timeoutMs}ms).`);
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Same as `fetchWithTimeout`, but the deadline also covers reading the response
 * body. A Telegram webview can hand over the response headers and then stall
 * forever while streaming the body, which left React Query pending with no error.
 */
async function requestWithDeadline(input: string, init: RequestInit = {}, timeoutMs = 12_000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(input, { ...init, signal: controller.signal });
    const text = await response.text();
    return { ok: response.ok, status: response.status, text };
  } catch (error) {
    if (controller.signal.aborted) throw new Error(`Tempo excedido ao contatar o backend (${timeoutMs}ms).`);
    throw error;
  } finally {
    clearTimeout(timer);
  }
}


export async function forgeFetch(feature: string, body: Record<string, unknown>): Promise<ForgeResponse> {
  const initData = typeof body.initData === 'string' ? body.initData : '';
  if (!functionsBase || !supabaseAnonKey || !hasSignedInitData(initData)) {
    console.error('[FORGE REQUEST FAILED]', {
      endpoint: `${functionsBase || '(sem backend configurado)'}/${feature}`,
      status: 404,
      response: null,
      error: !functionsBase || !supabaseAnonKey ? 'BACKEND_NOT_CONFIGURED' : 'MISSING_TELEGRAM_INITDATA',
    });
    return { ok: false, status: 404, json: async () => null };
  }


  const endpoint = `${functionsBase}/${feature}`;
  try {
    const { ok, status, text } = await requestWithDeadline(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: supabaseAnonKey,
        // Raw, unmodified Telegram initData. Never encoded/decoded before validation.
        'X-Telegram-Init-Data': initData,
      },
      body: JSON.stringify(body),
    });
    let payload: unknown = null;
    try {
      payload = text ? JSON.parse(text) : null;
    } catch {
      payload = null;
    }
    if (!ok) {
      console.error('[FORGE API ERROR]', {
        feature,
        endpoint,
        status,
        error: (payload as { error?: string } | null)?.error ?? null,
        response: text.slice(0, 500),
      });
    }
    return { ok, status, json: async () => payload };
  } catch (error) {
    console.error('[FORGE API ERROR]', { feature, endpoint, status: 0, error, response: null });
    throw error instanceof Error ? error : new Error('Falha de rede ao contatar o backend.');
  }
}
