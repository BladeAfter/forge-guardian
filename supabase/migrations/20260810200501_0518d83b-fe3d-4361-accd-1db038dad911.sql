-- 1. Canonical daily quest definitions (stable codes, upsert = no duplicates)
INSERT INTO public.quest_definitions (code, title, description, icon, event_key, target_amount, reward_fc, sort_order, enabled)
VALUES
  ('daily_login','DAILY LOGIN','Enter Mythreon today and keep your streak alive.','login','daily_login',1,5000,1,true),
  ('feed_companion','FEED YOUR COMPANION','Feed any pet once.','pet','pet_fed',1,7500,2,true),
  ('challenge_boss','CHALLENGE THE BOSS','Participate in one Boss battle.','boss','boss_attack',1,10000,3,true),
  ('enter_arena','ENTER THE ARENA','Complete one PvP battle.','pvp','pvp_battle',1,10000,4,true),
  ('open_reward','OPEN A REWARD','Open any Egg or Chest.','chest','reward_opened',1,12000,5,true)
ON CONFLICT (code) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  icon = EXCLUDED.icon,
  event_key = EXCLUDED.event_key,
  target_amount = EXCLUDED.target_amount,
  reward_fc = EXCLUDED.reward_fc,
  sort_order = EXCLUDED.sort_order,
  enabled = true,
  updated_at = now();

-- 2. Anything outside the canonical five stays disabled (definitions are never deleted)
UPDATE public.quest_definitions
   SET enabled = false, updated_at = now()
 WHERE code NOT IN ('daily_login','feed_companion','challenge_boss','enter_arena','open_reward')
   AND enabled;

-- 3. Missing hook: boss damage now feeds the boss quest
CREATE OR REPLACE FUNCTION public.quest_hook_boss_attack()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.total_damage_dealt > COALESCE(OLD.total_damage_dealt, 0) THEN
    PERFORM public.record_quest_event(NEW.user_id, 'boss_attack', 1);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quest_boss_attack ON public.boss_combats;
CREATE TRIGGER quest_boss_attack
AFTER UPDATE OF total_damage_dealt ON public.boss_combats
FOR EACH ROW EXECUTE FUNCTION public.quest_hook_boss_attack();

-- 4. Admin repair routine: restore the five defaults without touching player progress
CREATE OR REPLACE FUNCTION public.admin_repair_daily_quests(p_admin_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_total int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  INSERT INTO public.quest_definitions (code, title, description, icon, event_key, target_amount, reward_fc, sort_order, enabled)
  VALUES
    ('daily_login','DAILY LOGIN','Enter Mythreon today and keep your streak alive.','login','daily_login',1,5000,1,true),
    ('feed_companion','FEED YOUR COMPANION','Feed any pet once.','pet','pet_fed',1,7500,2,true),
    ('challenge_boss','CHALLENGE THE BOSS','Participate in one Boss battle.','boss','boss_attack',1,10000,3,true),
    ('enter_arena','ENTER THE ARENA','Complete one PvP battle.','pvp','pvp_battle',1,10000,4,true),
    ('open_reward','OPEN A REWARD','Open any Egg or Chest.','chest','reward_opened',1,12000,5,true)
  ON CONFLICT (code) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    event_key = EXCLUDED.event_key,
    target_amount = EXCLUDED.target_amount,
    reward_fc = EXCLUDED.reward_fc,
    sort_order = EXCLUDED.sort_order,
    enabled = true,
    updated_at = now();

  SELECT count(*) INTO v_total FROM public.quest_definitions WHERE enabled;
  PERFORM public.admin_log(p_admin_id, NULL, 'quests_repair', jsonb_build_object('activeDailyCount', v_total));
  RETURN jsonb_build_object('ok', true, 'activeDailyCount', v_total);
END;
$$;