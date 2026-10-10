import { supabaseAnonKey, supabaseUrl } from './supabaseEnv';

export const APP_URL = import.meta.env.VITE_APP_URL || window.location.origin;


// Wallets fetch this URL from their own servers, so it must always be the public
// production manifest (name: Mythic Seas, official icon), never a preview/dev origin.
export const TONCONNECT_MANIFEST_URL =
  import.meta.env.VITE_TONCONNECT_MANIFEST_URL || 'https://mythicseas.lovable.app/tonconnect-manifest.json';

export const missingPublicConfig = [
  !supabaseUrl && 'VITE_SUPABASE_URL',
  !supabaseAnonKey && 'VITE_SUPABASE_PUBLISHABLE_KEY'
].filter((value): value is string => Boolean(value));

// Without backend credentials the app stays available with local demo data.
export const isDemoMode = missingPublicConfig.length > 0;


export const isProduction = import.meta.env.PROD;

// Deep link used by the "ABRIR NO TELEGRAM" gate and by referral links.
// The game bot is separate from the administrative bot.
export const TELEGRAM_APP_LINK =
  'https://t.me/MythicSeasbot';
