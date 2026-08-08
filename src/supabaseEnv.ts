/**
 * Public backend configuration.
 *
 * The project URL and the publishable (anon) key are designed to ship in the
 * browser bundle — Row Level Security protects the data and every privileged
 * operation runs inside the `game-api` edge function with the service role.
 *
 * The literals below are the fallback used by the published build: `.env` is
 * git-ignored, so without them the production bundle would have no backend URL
 * and every screen would report "Backend indisponível".
 */
const FALLBACK_URL = 'https://oaivxwzrggfqhapohlht.supabase.co';
const FALLBACK_ANON_KEY = 'sb_publishable_aO2th7uGcAs84v9kR4m7Cg_6mmZVNpZ';

export const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim() || FALLBACK_URL;

export const supabaseAnonKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ||
  import.meta.env.VITE_SUPABASE_ANON_KEY?.trim() ||
  FALLBACK_ANON_KEY;
