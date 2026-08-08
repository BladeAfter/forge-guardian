export const APP_URL = import.meta.env.VITE_APP_URL || window.location.origin;

export const TONCONNECT_MANIFEST_URL =
  import.meta.env.VITE_TONCONNECT_MANIFEST_URL || `${APP_URL}/tonconnect-manifest.json`;

export const missingPublicConfig = [
  !supabaseUrl && 'VITE_SUPABASE_URL',
  !supabaseAnonKey && 'VITE_SUPABASE_PUBLISHABLE_KEY'
].filter((value): value is string => Boolean(value));

// Without backend credentials the app stays available with local demo data.
export const isDemoMode = missingPublicConfig.length > 0;


export const isProduction = import.meta.env.PROD;

// Deep link used by the "ABRIR NO TELEGRAM" gate when the app runs outside Telegram in production.
export const TELEGRAM_APP_LINK =
  import.meta.env.VITE_TELEGRAM_APP_LINK?.trim() || 'https://t.me/ForgeVillageBot/app';
