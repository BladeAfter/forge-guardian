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
export async function forgeFetch(feature: string, body: Record<string, unknown>): Promise<ForgeResponse> {
  const initData = typeof body.initData === 'string' ? body.initData : '';
  if (!functionsBase || !supabaseAnonKey || !initData) {
    return { ok: false, status: 404, json: async () => null };
  }

  const endpoint = `${functionsBase}/${feature}`;
  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: supabaseAnonKey },
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
