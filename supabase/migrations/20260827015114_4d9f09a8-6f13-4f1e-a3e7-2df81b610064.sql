CREATE OR REPLACE FUNCTION public.clan_hub_prepare(p_telegram_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RETURN; END IF;
  PERFORM public.clan_weekly_cycle_ensure(v_clan);
  PERFORM public.clan_raid_ensure(v_clan);
END $$;

REVOKE ALL ON FUNCTION public.clan_hub_prepare(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_hub_prepare(bigint) TO service_role;