/// <reference types="vite/client" />

declare interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string;
  readonly VITE_SUPABASE_ANON_KEY?: string;
  readonly VITE_APP_URL?: string;
  readonly VITE_TONCONNECT_MANIFEST_URL?: string;
}

declare interface ImportMeta {
  readonly env: ImportMetaEnv;
}
