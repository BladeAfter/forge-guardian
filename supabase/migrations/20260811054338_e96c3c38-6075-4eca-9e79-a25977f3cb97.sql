-- 1. Fixed search_path on remaining functions
ALTER FUNCTION public.pet_evolution_cost(integer,text) SET search_path = public;
ALTER FUNCTION public.normalize_pet_rarity(text) SET search_path = public;
ALTER FUNCTION public.pet_rarity_multiplier(text) SET search_path = public;
ALTER FUNCTION public.pet_xp_required(integer) SET search_path = public;
ALTER FUNCTION public.clan_role_rank(text) SET search_path = public;
ALTER FUNCTION public.clan_member_limit(integer) SET search_path = public;
ALTER FUNCTION public.pet_evolution_stage(integer) SET search_path = public;

-- 2. Revoke direct EXECUTE on SECURITY DEFINER functions from public API roles.
--    All gameplay/admin logic is invoked server-side through edge functions using
--    the service role, so anon/authenticated never need direct RPC access.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $$;

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

-- 3. Boss participants: hide telegram_id via column-level grants
REVOKE SELECT ON public.global_boss_participants FROM anon, authenticated;
GRANT SELECT (id, boss_cycle_id, user_id, damage_total, attacks, reward_amount, reward_claimed, final_rank, last_attack_at, created_at, updated_at)
  ON public.global_boss_participants TO authenticated;
GRANT ALL ON public.global_boss_participants TO service_role;

DROP POLICY IF EXISTS "global boss ranking is public read" ON public.global_boss_participants;
CREATE POLICY "boss ranking readable by players"
ON public.global_boss_participants FOR SELECT TO authenticated USING (true);

-- 4. Boss cycles: signed-in players only, display columns only
REVOKE SELECT ON public.global_boss_cycles FROM anon, authenticated;
GRANT SELECT (id, cycle_number, boss_key, boss_name, boss_image, boss_level, max_hp, current_hp, reward_pool_fc, total_damage, participants, status, starts_at, ends_at, defeated_at, created_at, updated_at)
  ON public.global_boss_cycles TO authenticated;
GRANT ALL ON public.global_boss_cycles TO service_role;

DROP POLICY IF EXISTS "global boss cycles are public read" ON public.global_boss_cycles;
CREATE POLICY "boss cycles readable by players"
ON public.global_boss_cycles FOR SELECT TO authenticated USING (true);