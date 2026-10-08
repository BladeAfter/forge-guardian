import { createClient } from '@supabase/supabase-js';
import { supabaseAnonKey, supabaseUrl } from './supabaseEnv';

/**
 * Realtime/browser client built from `supabaseEnv`, which carries the public
 * fallback literals. The auto-generated `integrations/supabase/client` throws
 * ("supabaseUrl is required") in the published bundle when the VITE_* variables
 * are not injected at build time, which blanked the Telegram Mini App.
 */
const client = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

/**
 * ⚠️ Realtime is intentionally DISABLED.
 *
 * Mythreon players never hold a Supabase session: every read/write goes through
 * the `game-api` Edge Function with the service role, and the game tables have no
 * client-side grants/policies on purpose (security hardening). Postgres-changes
 * subscriptions therefore can never deliver a payload — the socket only produced
 * "invalid column for filter" errors plus a constant subscribe/retry loop, which
 * added latency and stalls inside the Mini App. Every screen already polls the
 * backend (React Query `refetchInterval`), so behaviour is unchanged.
 *
 * Flip this to `true` only after the affected tables are readable by `anon`
 * through RLS policies again.
 */
export const REALTIME_ENABLED = false;

type InertChannel = { on: () => InertChannel; subscribe: () => InertChannel };

const inertChannel: InertChannel = {
  on: () => inertChannel,
  subscribe: () => inertChannel,
};

export const realtimeSupabase = REALTIME_ENABLED
  ? client
  : ({
      ...client,
      channel: () => inertChannel as unknown as ReturnType<typeof client.channel>,
      removeChannel: async () => 'ok' as const,
    } as unknown as typeof client);
