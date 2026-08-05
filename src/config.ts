export const APP_URL = import.meta.env.VITE_APP_URL || window.location.origin;

export const TONCONNECT_MANIFEST_URL =
  import.meta.env.VITE_TONCONNECT_MANIFEST_URL || `${APP_URL}/tonconnect-manifest.json`;

export const missingPublicConfig = [
  !import.meta.env.VITE_SUPABASE_URL?.trim() && 'VITE_SUPABASE_URL',
  !import.meta.env.VITE_SUPABASE_ANON_KEY?.trim() && 'VITE_SUPABASE_ANON_KEY'
].filter((value): value is string => Boolean(value));

// Without backend credentials the app stays available with local demo data.
export const isDemoMode = missingPublicConfig.length > 0;

export const isProduction = import.meta.env.PROD;
