/** Public backend configuration. The anon/publishable key is safe in the client. */
export const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim() || '';

export const supabaseAnonKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() || import.meta.env.VITE_SUPABASE_ANON_KEY?.trim() || '';
