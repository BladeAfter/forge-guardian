CREATE TABLE IF NOT EXISTS public.quest_definitions (
  code text PRIMARY KEY,
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  event_key text NOT NULL,
  target_amount integer NOT NULL DEFAULT 1,
  reward_fc numeric NOT NULL DEFAULT 0,
  reward_item_type text,
  reward_item_code text,
  reward_item_quantity integer NOT NULL DEFAULT 0,
  icon text,
  sort_order integer NOT NULL DEFAULT 100,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.quest_definitions TO service_role;
ALTER TABLE public.quest_definitions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.player_quest_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  quest_code text NOT NULL REFERENCES public.quest_definitions(code) ON DELETE CASCADE,
  quest_date date NOT NULL,
  progress integer NOT NULL DEFAULT 0,
  completed_at timestamptz,
  claimed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, quest_code, quest_date)
);
GRANT ALL ON public.player_quest_progress TO service_role;
ALTER TABLE public.player_quest_progress ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS player_quest_progress_user_date_idx ON public.player_quest_progress (user_id, quest_date);

CREATE TABLE IF NOT EXISTS public.player_quest_bonus (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  quest_date date NOT NULL,
  item_type text NOT NULL,
  item_code text NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  claimed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, quest_date)
);
GRANT ALL ON public.player_quest_bonus TO service_role;
ALTER TABLE public.player_quest_bonus ENABLE ROW LEVEL SECURITY;

INSERT INTO public.game_settings (key, value, category, label) VALUES
  ('quest_timezone', '"UTC"'::jsonb, 'quests', 'Fuso horario do reset das missoes diarias'),
  ('quest_bonus_chest', '{"item_type":"hero_chest","item_code":"rare_chest","name":"Rare Chest","quantity":1}'::jsonb, 'quests', 'Bau extra ao concluir todas as missoes diarias')
ON CONFLICT (key) DO NOTHING;

DELETE FROM public.player_mission_progress;
DELETE FROM public.game_missions;

INSERT INTO public.quest_definitions (code, title, description, event_key, target_amount, reward_fc, icon, sort_order) VALUES
  ('daily_login','DAILY LOGIN','Enter Mythreon today.','daily_login',1,5000,'login',1),
  ('feed_companion','FEED YOUR COMPANION','Feed any pet once.','pet_fed',1,7500,'pet',2),
  ('challenge_boss','CHALLENGE THE BOSS','Participate in one Boss battle.','boss_attack',1,10000,'boss',3),
  ('enter_arena','ENTER THE ARENA','Complete one PvP battle.','pvp_battle',1,10000,'pvp',4),
  ('open_reward','OPEN A REWARD','Open any Egg or Chest.','reward_opened',1,12000,'chest',5),
  ('collect_hero','COLLECT A HERO','Obtain one Hero.','hero_obtained',1,12000,'hero',6)
ON CONFLICT (code) DO NOTHING;

UPDATE public.quest_definitions SET enabled = false WHERE code = 'collect_hero';

CREATE OR REPLACE FUNCTION public.quest_timezone()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(NULLIF(trim(both '"' from (SELECT value::text FROM public.game_settings WHERE key = 'quest_timezone')), ''), 'UTC');
$$;

CREATE OR REPLACE FUNCTION public.quest_today()
RETURNS date LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE tz text := public.quest_timezone();
BEGIN
  RETURN (now() AT TIME ZONE tz)::date;
EXCEPTION WHEN others THEN
  RETURN (now() AT TIME ZONE 'UTC')::date;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_quest_event(p_user_id uuid, p_event text, p_amount integer DEFAULT 1)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE q record; v_date date; v_amount integer := GREATEST(1, COALESCE(p_amount, 1)); v_progress integer;
BEGIN
  IF p_user_id IS NULL OR COALESCE(p_event,'') = '' THEN RETURN; END IF;
  v_date := public.quest_today();
  FOR q IN SELECT * FROM public.quest_definitions WHERE enabled AND event_key = p_event LOOP
    INSERT INTO public.player_quest_progress (user_id, quest_code, quest_date, progress)
    VALUES (p_user_id, q.code, v_date, 0)
    ON CONFLICT (user_id, quest_code, quest_date) DO NOTHING;

    UPDATE public.player_quest_progress
       SET progress = LEAST(progress + v_amount, q.target_amount), updated_at = now()
     WHERE user_id = p_user_id AND quest_code = q.code AND quest_date = v_date
     RETURNING progress INTO v_progress;

    UPDATE public.player_quest_progress
       SET completed_at = now()
     WHERE user_id = p_user_id AND quest_code = q.code AND quest_date = v_date
       AND completed_at IS NULL AND v_progress >= q.target_amount;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_quest_event_for_telegram(p_telegram_id bigint, p_event text, p_amount integer DEFAULT 1)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NOT NULL THEN PERFORM public.record_quest_event(u, p_event, p_amount); END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.quest_hook_pet_feed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.action LIKE 'feed%' THEN PERFORM public.record_quest_event(NEW.user_id, 'pet_fed', 1); END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS quest_pet_feed ON public.pet_action_idempotency;
CREATE TRIGGER quest_pet_feed AFTER INSERT ON public.pet_action_idempotency
FOR EACH ROW EXECUTE FUNCTION public.quest_hook_pet_feed();

CREATE OR REPLACE FUNCTION public.quest_hook_pvp_battle()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.record_quest_event(NEW.attacker_id, 'pvp_battle', 1);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS quest_pvp_battle ON public.pvp_battles;
CREATE TRIGGER quest_pvp_battle AFTER INSERT ON public.pvp_battles
FOR EACH ROW EXECUTE FUNCTION public.quest_hook_pvp_battle();

CREATE OR REPLACE FUNCTION public.quest_hook_reward_opened()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.record_quest_event(NEW.user_id, 'reward_opened', 1);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS quest_egg_hatch ON public.pet_hatch_history;
CREATE TRIGGER quest_egg_hatch AFTER INSERT ON public.pet_hatch_history
FOR EACH ROW EXECUTE FUNCTION public.quest_hook_reward_opened();
DROP TRIGGER IF EXISTS quest_chest_open ON public.reward_open_logs;
CREATE TRIGGER quest_chest_open AFTER INSERT ON public.reward_open_logs
FOR EACH ROW EXECUTE FUNCTION public.quest_hook_reward_opened();

CREATE OR REPLACE FUNCTION public.quest_hook_hero_obtained()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.record_quest_event(NEW.user_id, 'hero_obtained', 1);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS quest_hero_obtained ON public.player_heroes;
CREATE TRIGGER quest_hero_obtained AFTER INSERT ON public.player_heroes
FOR EACH ROW EXECUTE FUNCTION public.quest_hook_hero_obtained();

CREATE OR REPLACE FUNCTION public.attack_boss(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b public.boss_templates; v_result jsonb;
BEGIN
  b := public.active_boss_template();
  IF b.code IS NULL THEN RAISE EXCEPTION 'BOSS_NOT_ACTIVE'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.boss_team_slots ts JOIN public.game_players g ON g.id = ts.user_id WHERE g.telegram_id = p_telegram_id) THEN
    RAISE EXCEPTION 'BOSS_TEAM_EMPTY';
  END IF;
  v_result := public.process_boss_combat(p_telegram_id);
  PERFORM public.record_quest_event_for_telegram(p_telegram_id, 'boss_attack', 1);
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_daily_quests(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; v_date date; v_total int; v_completed int; v_bonus jsonb; v_claimed boolean; v_quests jsonb;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_date := public.quest_today();
  PERFORM public.record_quest_event(u, 'daily_login', 1);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'code', q.code,
           'title', q.title,
           'description', q.description,
           'icon', q.icon,
           'target', q.target_amount,
           'progress', LEAST(COALESCE(p.progress,0), q.target_amount),
           'rewardFc', q.reward_fc,
           'rewardItem', CASE WHEN q.reward_item_code IS NULL THEN NULL ELSE jsonb_build_object('type', q.reward_item_type, 'code', q.reward_item_code, 'quantity', q.reward_item_quantity) END,
           'completed', p.completed_at IS NOT NULL,
           'claimed', p.claimed_at IS NOT NULL
         ) ORDER BY q.sort_order), '[]'::jsonb)
    INTO v_quests
    FROM public.quest_definitions q
    LEFT JOIN public.player_quest_progress p
      ON p.quest_code = q.code AND p.user_id = u AND p.quest_date = v_date
   WHERE q.enabled;

  SELECT count(*) INTO v_total FROM public.quest_definitions WHERE enabled;
  SELECT count(*) INTO v_completed
    FROM public.quest_definitions q
    JOIN public.player_quest_progress p ON p.quest_code = q.code AND p.user_id = u AND p.quest_date = v_date
   WHERE q.enabled AND p.completed_at IS NOT NULL;

  SELECT value INTO v_bonus FROM public.game_settings WHERE key = 'quest_bonus_chest';
  SELECT EXISTS (SELECT 1 FROM public.player_quest_bonus WHERE user_id = u AND quest_date = v_date) INTO v_claimed;

  RETURN jsonb_build_object(
    'questDate', v_date,
    'timezone', public.quest_timezone(),
    'total', v_total,
    'completed', v_completed,
    'quests', v_quests,
    'balance', (SELECT forge_coins FROM public.game_players WHERE id = u),
    'bonus', jsonb_build_object(
      'name', COALESCE(v_bonus->>'name','Rare Chest'),
      'itemType', COALESCE(v_bonus->>'item_type','hero_chest'),
      'itemCode', COALESCE(v_bonus->>'item_code','rare_chest'),
      'quantity', COALESCE((v_bonus->>'quantity')::int, 1),
      'unlocked', v_total > 0 AND v_completed >= v_total,
      'claimed', v_claimed));
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_daily_quest(p_telegram_id bigint, p_quest_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; v_date date; q public.quest_definitions; p public.player_quest_progress; v_balance numeric;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_date := public.quest_today();

  SELECT * INTO q FROM public.quest_definitions WHERE code = p_quest_code AND enabled;
  IF q.code IS NULL THEN RAISE EXCEPTION 'QUEST_NOT_FOUND'; END IF;

  SELECT * INTO p FROM public.player_quest_progress
   WHERE user_id = u AND quest_code = q.code AND quest_date = v_date FOR UPDATE;
  IF p.id IS NULL OR p.completed_at IS NULL THEN RAISE EXCEPTION 'QUEST_NOT_COMPLETED'; END IF;
  IF p.claimed_at IS NOT NULL THEN RAISE EXCEPTION 'QUEST_ALREADY_CLAIMED'; END IF;

  UPDATE public.player_quest_progress SET claimed_at = now(), updated_at = now() WHERE id = p.id;

  IF q.reward_fc > 0 THEN
    UPDATE public.game_players SET forge_coins = forge_coins + q.reward_fc, updated_at = now()
     WHERE id = u RETURNING forge_coins INTO v_balance;
  ELSE
    SELECT forge_coins INTO v_balance FROM public.game_players WHERE id = u;
  END IF;

  IF q.reward_item_code IS NOT NULL AND q.reward_item_quantity > 0 THEN
    INSERT INTO public.player_inventory (user_id, item_type, item_code, quantity)
    VALUES (u, COALESCE(q.reward_item_type,'hero_chest'), q.reward_item_code, q.reward_item_quantity);
  END IF;

  RETURN jsonb_build_object('claimed', true, 'code', q.code, 'rewardFc', q.reward_fc, 'balance', v_balance,
                            'quests', public.get_daily_quests(p_telegram_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_daily_quest_chest(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; v_date date; v_total int; v_completed int; v_bonus jsonb; v_type text; v_code text; v_qty int; v_item uuid;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_date := public.quest_today();

  SELECT count(*) INTO v_total FROM public.quest_definitions WHERE enabled;
  SELECT count(*) INTO v_completed
    FROM public.quest_definitions q
    JOIN public.player_quest_progress p ON p.quest_code = q.code AND p.user_id = u AND p.quest_date = v_date
   WHERE q.enabled AND p.completed_at IS NOT NULL;
  IF v_total = 0 OR v_completed < v_total THEN RAISE EXCEPTION 'QUESTS_NOT_COMPLETED'; END IF;

  SELECT value INTO v_bonus FROM public.game_settings WHERE key = 'quest_bonus_chest';
  v_type := COALESCE(v_bonus->>'item_type','hero_chest');
  v_code := COALESCE(v_bonus->>'item_code','rare_chest');
  v_qty := GREATEST(1, COALESCE((v_bonus->>'quantity')::int, 1));

  BEGIN
    INSERT INTO public.player_quest_bonus (user_id, quest_date, item_type, item_code, quantity)
    VALUES (u, v_date, v_type, v_code, v_qty);
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'BONUS_ALREADY_CLAIMED';
  END;

  INSERT INTO public.player_inventory (user_id, item_type, item_code, quantity)
  VALUES (u, v_type, v_code, v_qty)
  RETURNING id INTO v_item;

  RETURN jsonb_build_object('claimed', true, 'itemType', v_type, 'itemCode', v_code, 'inventoryItemId', v_item,
                            'quests', public.get_daily_quests(p_telegram_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_quests_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object(
    'timezone', public.quest_timezone(),
    'questDate', public.quest_today(),
    'bonus', (SELECT value FROM public.game_settings WHERE key = 'quest_bonus_chest'),
    'quests', (SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.sort_order),'[]'::jsonb) FROM public.quest_definitions q),
    'chests', (SELECT COALESCE(jsonb_agg(jsonb_build_object('code',c.chest_code,'name',c.name) ORDER BY c.chest_code),'[]'::jsonb) FROM public.chest_reward_tables c WHERE c.enabled),
    'claimedToday', (SELECT count(*) FROM public.player_quest_progress WHERE quest_date = public.quest_today() AND claimed_at IS NOT NULL));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_quest(p_admin_id bigint, p_code text, p_patch jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(q) INTO v_old FROM public.quest_definitions q WHERE q.code = p_code;
  INSERT INTO public.quest_definitions (code, title, event_key)
  VALUES (p_code, COALESCE(p_patch->>'title', p_code), COALESCE(p_patch->>'event_key','daily_login'))
  ON CONFLICT (code) DO NOTHING;
  UPDATE public.quest_definitions q SET
    title = COALESCE(p_patch->>'title', q.title),
    description = COALESCE(p_patch->>'description', q.description),
    event_key = COALESCE(p_patch->>'event_key', q.event_key),
    target_amount = GREATEST(1, COALESCE((p_patch->>'target_amount')::int, q.target_amount)),
    reward_fc = GREATEST(0, COALESCE((p_patch->>'reward_fc')::numeric, q.reward_fc)),
    reward_item_type = COALESCE(p_patch->>'reward_item_type', q.reward_item_type),
    reward_item_code = COALESCE(p_patch->>'reward_item_code', q.reward_item_code),
    reward_item_quantity = GREATEST(0, COALESCE((p_patch->>'reward_item_quantity')::int, q.reward_item_quantity)),
    icon = COALESCE(p_patch->>'icon', q.icon),
    sort_order = COALESCE((p_patch->>'sort_order')::int, q.sort_order),
    enabled = COALESCE((p_patch->>'enabled')::boolean, q.enabled),
    updated_at = now()
  WHERE q.code = p_code;
  SELECT to_jsonb(q) INTO v_new FROM public.quest_definitions q WHERE q.code = p_code;
  PERFORM public.admin_log(p_admin_id, CASE WHEN v_old IS NULL THEN 'quest.create' ELSE 'quest.update' END, 'quest', p_code, v_old, v_new, p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_quest_bonus(p_admin_id bigint, p_item_type text, p_item_code text, p_name text, p_quantity integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v := jsonb_build_object('item_type', p_item_type, 'item_code', p_item_code, 'name', p_name, 'quantity', GREATEST(1, COALESCE(p_quantity,1)));
  INSERT INTO public.game_settings (key, value, category, label) VALUES ('quest_bonus_chest', v, 'quests', 'Bau extra das missoes diarias')
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;
  PERFORM public.admin_log(p_admin_id, 'quest.bonus', 'quest', 'bonus', NULL, v, NULL);
  PERFORM public.admin_bump_settings_version();
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reset_quests(p_admin_id bigint, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  DELETE FROM public.player_quest_progress WHERE quest_date = public.quest_today();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  DELETE FROM public.player_quest_bonus WHERE quest_date = public.quest_today();
  PERFORM public.admin_log(p_admin_id, 'quest.reset', 'quest', 'daily', NULL, jsonb_build_object('cleared', v_count), p_reason, jsonb_build_object('dangerous', true));
  RETURN jsonb_build_object('cleared', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_quest_timezone(p_admin_id bigint, p_timezone text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM now() AT TIME ZONE p_timezone;
  INSERT INTO public.game_settings (key, value, category, label) VALUES ('quest_timezone', to_jsonb(p_timezone), 'quests', 'Fuso horario do reset das missoes diarias')
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;
  PERFORM public.admin_log(p_admin_id, 'quest.timezone', 'quest', 'timezone', NULL, to_jsonb(p_timezone), NULL);
  RETURN jsonb_build_object('timezone', p_timezone);
END;
$$;