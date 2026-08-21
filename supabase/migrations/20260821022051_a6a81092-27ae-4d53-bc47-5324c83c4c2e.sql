DO $$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_src FROM pg_proc
   WHERE proname = 'start_pvp_battle' AND pronamespace = 'public'::regnamespace;
  v_src := replace(v_src, 'coaleske(v_fc_after,0)', 'coalesce(v_xp,0)');
  EXECUTE v_src;
END $$;

REVOKE ALL ON FUNCTION public.pvp_bot_set_attacker_power() FROM anon, authenticated;