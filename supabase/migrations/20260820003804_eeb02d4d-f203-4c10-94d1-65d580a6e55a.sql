DO $$
DECLARE v_user uuid; v_hero uuid; v_res jsonb;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id=5154918326;
  SELECT id INTO v_hero FROM public.player_heroes
   WHERE user_id=v_user AND hero_key='mx_bramwel' AND rarity='common' AND level=1
     AND coalesce(market_locked,false)=false AND coalesce(locked,false)=false
   ORDER BY created_at DESC LIMIT 1;
  IF v_hero IS NULL THEN RAISE EXCEPTION 'hero comum nao encontrado'; END IF;
  DELETE FROM public.pvp_team_slots WHERE hero_id=v_hero;
  DELETE FROM public.boss_team_slots WHERE player_hero_id=v_hero;
  DELETE FROM public.hero_combat_state WHERE hero_id=v_hero;
  UPDATE public.player_equipment SET hero_id=NULL WHERE hero_id=v_hero;
  DELETE FROM public.player_heroes WHERE id=v_hero;
  v_res := public.admin_grant_hero(8118569391, '5154918326', 'mx_draveth', 1, 'compensacao bau epico');
  RAISE NOTICE 'grant: %', v_res;
END $$;