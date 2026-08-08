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
  if (!initData) return { ok: false, reason: 'init_data_missing', error: 'Sessão do Telegram ausente. Abra o jogo pelo Telegram.' };
  const response = await fetch(`${functionsBase}/auth`, {
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
    const response = await fetch(`${functionsBase}/health`, {
      headers: supabaseAnonKey ? { apikey: supabaseAnonKey } : undefined,
    });
    const payload = (await response.json().catch(() => null)) as ForgeHealth | null;
    return payload ?? { ok: false, backend: 'offline' };
  } catch (error) {
    console.error('[FORGE REQUEST FAILED]', { endpoint: `${functionsBase}/health`, status: 0, error });
    return { ok: false, backend: 'offline' };
  }
}

export async function forgeFetch(feature: string, body: Record<string, unknown>): Promise<ForgeResponse> {
  const initData = typeof body.initData === 'string' ? body.initData : '';
  if (!functionsBase || !supabaseAnonKey || !initData) {
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
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: supabaseAnonKey,
        // Raw, unmodified Telegram initData. Never encoded/decoded before validation.
        'X-Telegram-Init-Data': initData,
      },
      body: JSON.stringify(body),
    });
    const text = await response.text();
    let payload: unknown = null;
    try {
      payload = text ? JSON.parse(text) : null;
    } catch {
      payload = null;
    }
    if (!response.ok) {
      console.error('[FORGE API ERROR]', {
        feature,
        endpoint,
        status: response.status,
        error: (payload as { error?: string } | null)?.error ?? null,
        response: text.slice(0, 500),
      });
    }
    return { ok: response.ok, status: response.status, json: async () => payload };
  } catch (error) {
    console.error('[FORGE API ERROR]', { feature, endpoint, status: 0, error, response: null });
    throw error instanceof Error ? error : new Error('Falha de rede ao contatar o backend.');
  }
}
