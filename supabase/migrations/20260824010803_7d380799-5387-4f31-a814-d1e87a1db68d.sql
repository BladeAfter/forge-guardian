-- 1. Column-level exposure for boss tables (hide internal tuning/balancing fields)
REVOKE SELECT ON public.global_boss_cycles FROM anon, authenticated;
GRANT SELECT (
  id, cycle_number, boss_key, boss_name, boss_image, boss_level,
  max_hp, current_hp, reward_pool_fc, total_damage, participants,
  status, starts_at, ends_at, defeated_at, distributed_at,
  created_at, updated_at, template_id, boss_number, boss_subtitle,
  boss_theme, boss_background, ended_reason, rotation_number
) ON public.global_boss_cycles TO anon, authenticated;
GRANT ALL ON public.global_boss_cycles TO service_role;

REVOKE SELECT ON public.global_boss_templates FROM anon, authenticated;
GRANT SELECT (
  id, boss_number, code, name, subtitle, theme, image_url,
  background_url, boss_level, enabled, sort_order, created_at, updated_at
) ON public.global_boss_templates TO anon, authenticated;
GRANT ALL ON public.global_boss_templates TO service_role;

REVOKE SELECT ON public.clan_boss_templates FROM anon, authenticated;
GRANT SELECT (
  id, cycle_number, boss_key, name, subtitle, theme, image_url,
  background_url, enabled, sort_order, created_at, updated_at
) ON public.clan_boss_templates TO anon, authenticated;
GRANT ALL ON public.clan_boss_templates TO service_role;

-- 2. Revoke EXECUTE on SECURITY DEFINER functions from client roles (server-only by default)
DO $$
DECLARE
  fn record;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND p.proname NOT IN ('get_game_state', 'list_premium_titles')
      AND p.prokind = 'f'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon, authenticated', fn.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn.sig);
  END LOOP;
END $$;

-- Keep the two functions the game client actually calls
DO $$
DECLARE
  fn record;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('get_game_state', 'list_premium_titles')
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated, service_role', fn.sig);
  END LOOP;
END $$;

-- 3. Scope pet-images public read to the catalog folder only
DROP POLICY IF EXISTS "Pet catalog art is readable" ON storage.objects;
CREATE POLICY "Pet catalog art is readable"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (bucket_id = 'pet-images' AND (storage.foldername(name))[1] = 'pets');