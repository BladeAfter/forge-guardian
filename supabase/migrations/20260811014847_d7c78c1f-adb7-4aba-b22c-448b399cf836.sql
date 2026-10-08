CREATE OR REPLACE FUNCTION public.admin_repair_daily_quests(p_admin_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE v_total int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  INSERT INTO public.quest_definitions (code, title, description, icon, event_key, target_amount, reward_fc, sort_order, enabled)
  VALUES
    ('daily_login','DAILY LOGIN','Enter Mythreon today and keep your streak alive.','login','daily_login',1,2000,1,true),
    ('feed_companion','FEED YOUR COMPANION','Feed any pet once.','pet','pet_fed',1,3000,2,true),
    ('challenge_boss','CHALLENGE THE BOSS','Participate in one Boss battle.','boss','boss_attack',1,4000,3,true),
    ('enter_arena','ENTER THE ARENA','Complete one PvP battle.','pvp','pvp_battle',1,4000,4,true),
    ('open_reward','OPEN A REWARD','Open any Egg or Chest.','chest','reward_opened',1,5000,5,true)
  ON CONFLICT (code) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    event_key = EXCLUDED.event_key,
    reward_fc = EXCLUDED.reward_fc,
    sort_order = EXCLUDED.sort_order,
    enabled = EXCLUDED.enabled,
    updated_at = now();

  SELECT count(*) INTO v_total FROM public.quest_definitions WHERE enabled;
  PERFORM public.admin_log(p_admin_id, NULL, 'quests_repair', jsonb_build_object('activeDailyCount', v_total));
  RETURN jsonb_build_object('ok', true, 'activeDailyCount', v_total);
END;
$fn$;