-- ---------------------------------------------------------------------------
-- Daily activity scoring: Community Pool points + Season Pass XP
-- Single source of truth: public.record_game_activity(user, activity, reference)
-- ---------------------------------------------------------------------------

ALTER TABLE public.pool_points
  ADD COLUMN IF NOT EXISTS game_day date;

UPDATE public.pool_points SET game_day = public.game_day_key(created_at) WHERE game_day IS NULL;

ALTER TABLE public.pool_points
  ALTER COLUMN game_day SET DEFAULT public.game_day_key();

CREATE INDEX IF NOT EXISTS idx_pool_points_user_activity_day
  ON public.pool_points (user_id, activity_type, game_day);

-- Central config (admin editable) --------------------------------------------
INSERT INTO public.game_settings(key, value)
VALUES ('activity_rewards', jsonb_build_object(
  'PVP_COMPLETE',        jsonb_build_object('poolPoints',10,'poolDailyCap',5, 'passXp',25,'passSource','activity_pvp'),
  'GLOBAL_BOSS_ATTACK',  jsonb_build_object('poolPoints',5, 'poolDailyCap',5, 'passXp',20,'passSource','activity_global_boss'),
  'CLAN_BOSS_ATTACK',    jsonb_build_object('poolPoints',5, 'poolDailyCap',5, 'passXp',20,'passSource','activity_clan_boss'),
  'PET_FEED',            jsonb_build_object('poolPoints',2, 'poolDailyCap',10,'passXp',5, 'passSource','activity_pet_feed'),
  'EXPEDITION_COMPLETE', jsonb_build_object('poolPoints',15,'poolDailyCap',5, 'passXp',40,'passSource','activity_expedition')
))
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.activity_rewards_config()
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT value FROM public.game_settings WHERE key = 'activity_rewards'), '{}'::jsonb)
$$;

-- Season pass XP amount/cap per activity source live in the existing pass config
UPDATE public.game_settings SET value = value
  || jsonb_build_object('activity_pvp',25,'activity_global_boss',20,'activity_clan_boss',20,
                        'activity_pet_feed',5,'activity_expedition',40)
 WHERE key = 'season_pass_xp';

UPDATE public.game_settings SET value = value
  || jsonb_build_object('activity_pvp',125,'activity_global_boss',100,'activity_clan_boss',100,
                        'activity_pet_feed',50,'activity_expedition',200)
 WHERE key = 'season_pass_xp_caps';

-- ---------------------------------------------------------------------------
-- record_game_activity: decides pool points, pass xp, daily caps, idempotency
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_game_activity(
  p_user_id uuid,
  p_activity text,
  p_reference_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  cfg jsonb; v_act text; v_pool_pts int; v_pool_cap int; v_day date;
  v_used int := 0; v_pool_id uuid; v_key text; v_ref text;
  v_granted_pool int := 0; v_pass jsonb; v_ins uuid; v_source text;
BEGIN
  IF p_user_id IS NULL THEN RETURN NULL; END IF;
  v_act := upper(COALESCE(p_activity, ''));
  cfg := public.activity_rewards_config() -> v_act;
  IF cfg IS NULL THEN RETURN NULL; END IF;

  v_ref := COALESCE(NULLIF(p_reference_id, ''), gen_random_uuid()::text);
  v_day := public.game_day_key();
  v_pool_pts := COALESCE((cfg->>'poolPoints')::int, 0);
  v_pool_cap := COALESCE((cfg->>'poolDailyCap')::int, 0);
  v_source := COALESCE(NULLIF(cfg->>'passSource',''), 'activity_' || lower(v_act));

  -- 1) Community Pool points (never multiplied by pass bonuses)
  SELECT count(*)::int INTO v_used
    FROM public.pool_points
   WHERE user_id = p_user_id AND activity_type = v_act AND game_day = v_day;

  IF v_pool_pts > 0 AND v_used < v_pool_cap THEN
    SELECT id INTO v_pool_id FROM public.pool_balance WHERE status = 'active' LIMIT 1;
    IF v_pool_id IS NOT NULL THEN
      v_key := 'activity:' || v_pool_id || ':' || v_act || ':' || v_ref || ':' || p_user_id;
      INSERT INTO public.pool_points(pool_id, user_id, activity_type, points, source_id, idempotency_key, game_day)
      VALUES (v_pool_id, p_user_id, v_act, v_pool_pts, v_ref, v_key, v_day)
      ON CONFLICT (idempotency_key) DO NOTHING
      RETURNING id INTO v_ins;
      IF v_ins IS NOT NULL THEN
        v_granted_pool := v_pool_pts;
        v_used := v_used + 1;
      END IF;
    END IF;
  END IF;

  -- 2) Season Pass XP (daily cap + tier bonus handled by grant_season_pass_xp)
  v_pass := public.grant_season_pass_xp(p_user_id, v_source, v_act || ':' || v_ref,
                                        NULLIF((cfg->>'passXp')::int, 0));

  RETURN jsonb_build_object(
    'activity', v_act,
    'poolPoints', v_granted_pool,
    'poolUsed', v_used,
    'poolDailyCap', v_pool_cap,
    'poolCapped', v_granted_pool = 0,
    'passXp', COALESCE((v_pass->>'amount')::int, 0),
    'passBaseXp', COALESCE((v_pass->>'baseXp')::int, 0),
    'passBonusPercent', COALESCE((v_pass->>'bonusPercent')::int, 0),
    'passLevelUp', COALESCE((v_pass->>'levelUp')::boolean, false)
  );
END; $$;

REVOKE ALL ON FUNCTION public.record_game_activity(uuid, text, text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Daily progress read model for the UI ("TODAY" panel)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.activity_daily_progress(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg jsonb; k text; v jsonb; v_day date; v_used int; v_xp int; out jsonb := '[]'::jsonb;
BEGIN
  cfg := public.activity_rewards_config();
  v_day := public.game_day_key();
  FOR k, v IN SELECT * FROM jsonb_each(cfg) LOOP
    SELECT count(*)::int INTO v_used FROM public.pool_points
     WHERE user_id = p_user_id AND activity_type = k AND game_day = v_day;
    SELECT COALESCE(SUM(COALESCE(base_xp, xp_amount)), 0)::int INTO v_xp
      FROM public.season_pass_xp_ledger
     WHERE user_id = p_user_id AND game_day = v_day
       AND source = COALESCE(NULLIF(v->>'passSource',''), 'activity_' || lower(k));
    out := out || jsonb_build_object(
      'activity', k,
      'poolPoints', COALESCE((v->>'poolPoints')::int, 0),
      'passXp', COALESCE((v->>'passXp')::int, 0),
      'dailyCap', COALESCE((v->>'poolDailyCap')::int, 0),
      'used', v_used,
      'xpToday', v_xp
    );
  END LOOP;
  RETURN jsonb_build_object('gameDay', v_day, 'activities', out);
END; $$;

REVOKE ALL ON FUNCTION public.activity_daily_progress(uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Hooks: route every activity through record_game_activity (no double reward)
-- ---------------------------------------------------------------------------

-- PvP: completed battle (win not required). Old direct pass XP grants removed.
CREATE OR REPLACE FUNCTION public.quest_hook_pvp_battle()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.record_quest_event(NEW.attacker_id, 'pvp_battle', 1);
  PERFORM public.record_game_activity(NEW.attacker_id, 'PVP_COMPLETE', NEW.id::text);
  RETURN NEW;
END; $$;

-- Pet feed: only after the backend confirmed the feed action
CREATE OR REPLACE FUNCTION public.quest_hook_pet_feed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.action LIKE 'feed%' THEN
    PERFORM public.record_quest_event(NEW.user_id, 'pet_fed', 1);
    PERFORM public.record_game_activity(NEW.user_id, 'PET_FEED', NEW.idempotency_key);
  END IF;
  RETURN NEW;
END; $$;

-- Global Boss: one scored entry per registered attack
CREATE OR REPLACE FUNCTION public.activity_hook_global_boss_attack()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF COALESCE(NEW.damage, 0) > 0 THEN
    PERFORM public.record_game_activity(NEW.user_id, 'GLOBAL_BOSS_ATTACK', NEW.id::text);
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS activity_global_boss_attack ON public.global_boss_attack_log;
CREATE TRIGGER activity_global_boss_attack AFTER INSERT ON public.global_boss_attack_log
FOR EACH ROW EXECUTE FUNCTION public.activity_hook_global_boss_attack();

-- Clan Boss: one scored entry per registered attack
CREATE OR REPLACE FUNCTION public.activity_hook_clan_boss_attack()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF COALESCE(NEW.damage, 0) > 0 THEN
    PERFORM public.record_game_activity(NEW.user_id, 'CLAN_BOSS_ATTACK', NEW.id::text);
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS activity_clan_boss_attack ON public.clan_boss_attack_log;
CREATE TRIGGER activity_clan_boss_attack AFTER INSERT ON public.clan_boss_attack_log
FOR EACH ROW EXECUTE FUNCTION public.activity_hook_clan_boss_attack();

-- Pet Expeditions: scored on completion (claim), never on start
CREATE OR REPLACE FUNCTION public.activity_hook_expedition_complete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.status = 'CLAIMED' AND COALESCE(OLD.status, '') <> 'CLAIMED' THEN
    PERFORM public.record_game_activity(NEW.user_id, 'EXPEDITION_COMPLETE', NEW.id::text);
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS activity_expedition_complete ON public.pet_expeditions;
CREATE TRIGGER activity_expedition_complete AFTER UPDATE ON public.pet_expeditions
FOR EACH ROW EXECUTE FUNCTION public.activity_hook_expedition_complete();

-- Legacy pool sources for gameplay actions are superseded by the new activities
CREATE OR REPLACE FUNCTION public.pool_points_from_game_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  RETURN NEW;
END; $$;

-- Admin setter for the activity config -------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_activity_reward(
  p_admin_id bigint, p_activity text, p_field text, p_value integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg jsonb; v_act text; v_field text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_act := upper(COALESCE(p_activity, ''));
  v_field := COALESCE(p_field, '');
  IF v_field NOT IN ('poolPoints', 'poolDailyCap', 'passXp') THEN RAISE EXCEPTION 'INVALID_FIELD'; END IF;
  cfg := public.activity_rewards_config();
  IF cfg -> v_act IS NULL THEN RAISE EXCEPTION 'INVALID_ACTIVITY'; END IF;
  cfg := jsonb_set(cfg, ARRAY[v_act, v_field], to_jsonb(GREATEST(0, COALESCE(p_value, 0))));
  INSERT INTO public.game_settings(key, value) VALUES ('activity_rewards', cfg)
  ON CONFLICT (key) DO UPDATE SET value = excluded.value;

  IF v_field = 'passXp' THEN
    UPDATE public.game_settings
       SET value = value || jsonb_build_object(COALESCE(NULLIF(cfg->v_act->>'passSource',''), 'activity_' || lower(v_act)), GREATEST(0, COALESCE(p_value,0)))
     WHERE key = 'season_pass_xp';
  END IF;
  IF v_field IN ('passXp', 'poolDailyCap') THEN
    UPDATE public.game_settings
       SET value = value || jsonb_build_object(
             COALESCE(NULLIF(cfg->v_act->>'passSource',''), 'activity_' || lower(v_act)),
             GREATEST(0, COALESCE((cfg->v_act->>'passXp')::int,0)) * GREATEST(0, COALESCE((cfg->v_act->>'poolDailyCap')::int,0)))
     WHERE key = 'season_pass_xp_caps';
  END IF;

  PERFORM public.admin_log(p_admin_id, 'activity_reward_set', NULL,
    jsonb_build_object('activity', v_act, 'field', v_field, 'value', p_value));
  RETURN cfg;
END; $$;

REVOKE ALL ON FUNCTION public.admin_set_activity_reward(bigint, text, text, integer) FROM PUBLIC, anon, authenticated;