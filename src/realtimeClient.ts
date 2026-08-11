import { createClient } from '@supabase/supabase-js';
import { supabaseAnonKey, supabaseUrl } from './supabaseEnv';

/**
 * Realtime/browser client built from `supabaseEnv`, which carries the public
 * fallback literals. The auto-generated `integrations/supabase/client` throws
 * ("supabaseUrl is required") in the published bundle when the VITE_* variables
 * are not injected at build time, which blanked the Telegram Mini App.
 */
export const realtimeSupabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});
