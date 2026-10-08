-- 1. Ledger extension
ALTER TABLE public.season_pass_xp_ledger
  ADD COLUMN IF NOT EXISTS base_xp integer,
  ADD COLUMN IF NOT EXISTS multiplier numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS game_day date;

UPDATE public.season_pass_xp_ledger SET base_xp = xp_amount WHERE base_xp IS NULL;

CREATE INDEX IF NOT EXISTS season_pass_xp_ledger_cap_idx
  ON public.season_pass_xp_ledger(user_id, source, game_day);

-- 2. Settings
INSERT INTO public.game_settings(key, value) VALUES ('season_pass_xp', jsonb_build_object(
  'daily_login', 30,
  'daily_quest', 75,
  'daily_quest_all', 200,
  'daily_chest', 100,
  'pvp_battle', 40,
  'pvp_victory', 20,
  'boss_attack', 50,
  'boss_damage_milestone', 50,
  'boss_reward', 100,
  'boss_defeated', 150,
  'reward_open', 25,
  'pet_feed', 10,
  'pet_level_up', 50,
  'pet_evolution', 150,
  'hero_fuse', 75,
  'rarity_fusion', 100,
  'rarity_fusion_success', 100,
  'calendar_claim', 20
)) ON CONFLICT (key) DO UPDATE SET value = public.game_settings.value || EXCLUDED.value;

INSERT INTO public.game_settings(key, value) VALUES ('season_pass_xp_multipliers', jsonb_build_object(
  'none', 1.0, 'free', 1.0, 'adventurer', 1.2, 'legendary', 1.4
)) ON CONFLICT (key) DO NOTHING;

INSERT INTO public.game_settings(key, value) VALUES ('season_pass_xp_caps', jsonb_build_object(
  'pet_feed', 100,
  'reward_open', 150,
  'pvp_battle', 400,
  'pvp_victory', 200,
  'boss_attack', 50,
  'boss_damage_milestone', 150,
  'boss_reward', 100,
  'pet_level_up', 250,
  'pet_evolution', 450,
  'hero_fuse', 300,
  'rarity_fusion', 300,
  'rarity_fusion_success', 300,
  'calendar_claim', 20,
  'daily_login', 30
)) ON CONFLICT (key) DO NOTHING;

INSERT INTO public.game_settings(key, value) VALUES ('boss_damage_milestones', '[25,50,75,100]'::jsonb)
  ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.season_pass_xp_multipliers()
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT value FROM public.game_settings WHERE key = 'season_pass_xp_multipliers'),
    '{"none":1,"adventurer":1.2,"legendary":1.4}'::jsonb)
$$;

CREATE OR REPLACE FUNCTION public.season_pass_xp_caps()
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT value FROM public.game_settings WHERE key = 'season_pass_xp_caps'), '{}'::jsonb)
$$;

CREATE OR REPLACE FUNCTION public.season_pass_tier_multiplier(p_tier text)
RETURNS numeric LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT GREATEST(0.1, COALESCE((public.season_pass_xp_multipliers()->>COALESCE(p_tier,'none'))::numeric, 1))
$$;

-- 3. Central XP function
CREATE OR REPLACE FUNCTION public.grant_season_pass_xp(
  p_user_id uuid, p_source text, p_reference_id text DEFAULT NULL::text, p_amount integer DEFAULT NULL::integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  s public.season_pass_seasons%rowtype; sp public.player_season_pass%rowtype;
  v_base integer; v_cap integer; v_used integer; v_final integer;
  v_mult numeric; v_day date;
  v_before integer; v_after integer; v_max integer;
  v_lvl_before integer; v_lvl_after integer; v_ins uuid;
BEGIN
  IF p_user_id IS NULL OR COALESCE(p_source,'') = '' THEN RETURN NULL; END IF;

  SELECT * INTO s FROM public.season_pass_seasons
   WHERE active AND now() BETWEEN start_at AND end_at
   ORDER BY start_at DESC LIMIT 1;
  IF s.id IS NULL THEN RETURN NULL; END IF;

  v_base := COALESCE(p_amount, (public.season_pass_xp_config()->>p_source)::int, 0);
  IF v_base <= 0 THEN RETURN NULL; END IF;

  v_day := public.game_day_key();

  -- daily cap on BASE xp per source
  v_cap := NULLIF(public.season_pass_xp_caps()->>p_source, '')::int;
  IF v_cap IS NOT NULL THEN
    SELECT COALESCE(SUM(COALESCE(base_xp, xp_amount)), 0) INTO v_used
      FROM public.season_pass_xp_ledger
     WHERE user_id = p_user_id AND source = p_source AND game_day = v_day;
    v_base := LEAST(v_base, GREATEST(0, v_cap - v_used));
    IF v_base <= 0 THEN
      RETURN jsonb_build_object('granted', false, 'capped', true, 'source', p_source);
    END IF;
  END IF;

  INSERT INTO public.player_season_pass(user_id, season_id, tier)
  VALUES (p_user_id, s.id, 'none') ON CONFLICT (user_id, season_id) DO NOTHING;

  SELECT * INTO sp FROM public.player_season_pass
   WHERE user_id = p_user_id AND season_id = s.id FOR UPDATE;

  v_mult := public.season_pass_tier_multiplier(sp.tier);
  v_final := GREATEST(1, floor(v_base * v_mult)::int);

  v_max := s.levels * s.xp_per_level;
  v_before := COALESCE(sp.xp, 0);
  v_after := GREATEST(0, LEAST(v_max, v_before + v_final));
  v_lvl_before := LEAST(s.levels, v_before / GREATEST(1, s.xp_per_level) + 1);
  v_lvl_after := LEAST(s.levels, v_after / GREATEST(1, s.xp_per_level) + 1);

  IF p_reference_id IS NULL THEN
    INSERT INTO public.season_pass_xp_ledger(user_id, season_id, source, reference_id, xp_amount,
        base_xp, multiplier, game_day, xp_before, xp_after, level_before, level_after)
    VALUES (p_user_id, s.id, p_source, NULL, v_after - v_before,
        v_base, v_mult, v_day, v_before, v_after, v_lvl_before, v_lvl_after)
    RETURNING id INTO v_ins;
  ELSE
    INSERT INTO public.season_pass_xp_ledger(user_id, season_id, source, reference_id, xp_amount,
        base_xp, multiplier, game_day, xp_before, xp_after, level_before, level_after)
    VALUES (p_user_id, s.id, p_source, p_reference_id, v_after - v_before,
        v_base, v_mult, v_day, v_before, v_after, v_lvl_before, v_lvl_after)
    ON CONFLICT (user_id, season_id, source, reference_id) WHERE reference_id IS NOT NULL DO NOTHING
    RETURNING id INTO v_ins;
  END IF;

  IF v_ins IS NULL THEN
    RETURN jsonb_build_object('granted', false, 'duplicate', true,
      'xp', v_before, 'level', v_lvl_before, 'xpPerLevel', s.xp_per_level, 'levels', s.levels);
  END IF;

  UPDATE public.player_season_pass SET xp = v_after, updated_at = now()
   WHERE user_id = p_user_id AND season_id = s.id;

  RETURN jsonb_build_object('granted', true, 'amount', v_after - v_before,
    'source', p_source, 'baseXp', v_base, 'multiplier', v_mult, 'tier', COALESCE(sp.tier,'none'),
    'bonusPercent', round((v_mult - 1) * 100),
    'xp', v_after, 'level', v_lvl_after, 'levelUp', v_lvl_after > v_lvl_before,
    'xpPerLevel', s.xp_per_level, 'levels', s.levels, 'maxed', v_after >= v_max);
END;
$function$;

-- 4. Daily login xp inside quest event recorder
CREATE OR REPLACE FUNCTION public.record_quest_event(p_user_id uuid, p_event text, p_amount integer DEFAULT 1)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE q record; v_date date; v_amount integer := GREATEST(1, COALESCE(p_amount, 1));
        v_progress integer; v_done boolean; v_total int; v_completed int;
BEGIN
  IF p_user_id IS NULL OR COALESCE(p_event,'') = '' THEN RETURN; END IF;
  v_date := public.quest_today();

  IF p_event = 'daily_login' THEN
    PERFORM public.grant_season_pass_xp(p_user_id, 'daily_login', 'login:' || v_date::text);
  END IF;

  FOR q IN SELECT * FROM public.quest_definitions WHERE enabled AND event_key = p_event LOOP
    INSERT INTO public.player_quest_progress (user_id, quest_code, quest_date, progress)
    VALUES (p_user_id, q.code, v_date, 0)
    ON CONFLICT (user_id, quest_code, quest_date) DO NOTHING;

    UPDATE public.player_quest_progress
       SET progress = LEAST(progress + v_amount, q.target_amount), updated_at = now()
     WHERE user_id = p_user_id AND quest_code = q.code AND quest_date = v_date
     RETURNING progress INTO v_progress;

    v_done := false;
    UPDATE public.player_quest_progress
       SET completed_at = now()
     WHERE user_id = p_user_id AND quest_code = q.code AND quest_date = v_date
       AND completed_at IS NULL AND v_progress >= q.target_amount
    RETURNING true INTO v_done;

    IF COALESCE(v_done, false) THEN
      PERFORM public.grant_season_pass_xp(p_user_id, 'daily_quest', 'quest:' || q.code || ':' || v_date::text);
    END IF;
  END LOOP;

  SELECT count(*) INTO v_total FROM public.quest_definitions WHERE enabled;
  SELECT count(*) INTO v_completed
    FROM public.quest_definitions d
    JOIN public.player_quest_progress p ON p.quest_code = d.code AND p.user_id = p_user_id AND p.quest_date = v_date
   WHERE d.enabled AND p.completed_at IS NOT NULL;
  IF v_total > 0 AND v_completed >= v_total THEN
    PERFORM public.grant_season_pass_xp(p_user_id, 'daily_quest_all', 'quests_all:' || v_date::text);
  END IF;
END; $function$;

-- 5. Boss: participation + damage milestones (no xp per tick)
CREATE OR REPLACE FUNCTION public.quest_hook_boss_attack()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_ms jsonb; v_pct numeric; v_old_pct numeric; m numeric;
BEGIN
  IF NEW.total_damage_dealt > COALESCE(OLD.total_damage_dealt, 0) THEN
    PERFORM public.record_quest_event(NEW.user_id, 'boss_attack', 1);
    PERFORM public.grant_season_pass_xp(NEW.user_id, 'boss_attack', 'boss:' || NEW.id::text);

    v_ms := COALESCE((SELECT value FROM public.game_settings WHERE key = 'boss_damage_milestones'), '[25,50,75,100]'::jsonb);
    v_pct := 100.0 * NEW.total_damage_dealt / GREATEST(1, NEW.boss_max_hp);
    v_old_pct := 100.0 * COALESCE(OLD.total_damage_dealt, 0) / GREATEST(1, NEW.boss_max_hp);
    FOR m IN SELECT (jsonb_array_elements_text(v_ms))::numeric LOOP
      IF v_pct >= m AND v_old_pct < m THEN
        PERFORM public.grant_season_pass_xp(NEW.user_id, 'boss_damage_milestone',
          'boss_ms:' || NEW.id::text || ':' || m::text);
      END IF;
    END LOOP;
  END IF;
  IF NEW.status = 'defeated' AND COALESCE(OLD.status,'') <> 'defeated' THEN
    PERFORM public.grant_season_pass_xp(NEW.user_id, 'boss_defeated', 'boss_kill:' || NEW.id::text);
  END IF;
  RETURN NEW;
END; $function$;

CREATE OR REPLACE FUNCTION public.pass_hook_boss_reward()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  PERFORM public.grant_season_pass_xp(NEW.user_id, 'boss_reward', 'boss_reward:' || NEW.id::text);
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS pass_boss_reward ON public.boss_reward_transactions;
CREATE TRIGGER pass_boss_reward AFTER INSERT ON public.boss_reward_transactions
  FOR EACH ROW EXECUTE FUNCTION public.pass_hook_boss_reward();

-- 6. Pets: level up + evolution
CREATE OR REPLACE FUNCTION public.pass_hook_pet_upgrade()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF COALESCE(NEW.new_level, 0) > COALESCE(NEW.old_level, 0) THEN
    PERFORM public.grant_season_pass_xp(NEW.user_id, 'pet_level_up', 'pet_lvl:' || NEW.id::text);
  END IF;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS pass_pet_upgrade ON public.pet_upgrade_history;
CREATE TRIGGER pass_pet_upgrade AFTER INSERT ON public.pet_upgrade_history
  FOR EACH ROW EXECUTE FUNCTION public.pass_hook_pet_upgrade();

CREATE OR REPLACE FUNCTION public.pass_hook_pet_evolution()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  PERFORM public.grant_season_pass_xp(NEW.user_id, 'pet_evolution', 'pet_evo:' || NEW.id::text);
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS pass_pet_evolution ON public.pet_evolution_history;
CREATE TRIGGER pass_pet_evolution AFTER INSERT ON public.pet_evolution_history
  FOR EACH ROW EXECUTE FUNCTION public.pass_hook_pet_evolution();

-- 7. Hero fusion (duplicates) + rarity fusion
CREATE OR REPLACE FUNCTION public.pass_hook_hero_fuse()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  PERFORM public.grant_season_pass_xp(NEW.user_id, 'hero_fuse', 'fuse:' || NEW.id::text);
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS pass_hero_fuse ON public.hero_fusion_history;
CREATE TRIGGER pass_hero_fuse AFTER INSERT ON public.hero_fusion_history
  FOR EACH ROW EXECUTE FUNCTION public.pass_hook_hero_fuse();

CREATE OR REPLACE FUNCTION public.pass_hook_rarity_fusion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  PERFORM public.grant_season_pass_xp(NEW.user_id, 'rarity_fusion', 'rfuse:' || NEW.id::text);
  IF NEW.success THEN
    PERFORM public.grant_season_pass_xp(NEW.user_id, 'rarity_fusion_success', 'rfuse_ok:' || NEW.id::text);
  END IF;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS pass_rarity_fusion ON public.hero_rarity_fusion_history;
CREATE TRIGGER pass_rarity_fusion AFTER INSERT ON public.hero_rarity_fusion_history
  FOR EACH ROW EXECUTE FUNCTION public.pass_hook_rarity_fusion();

-- 8. Admin: multipliers + caps
CREATE OR REPLACE FUNCTION public.admin_set_pass_xp_multipliers(p_admin_id bigint, p_patch jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_old := public.season_pass_xp_multipliers();
  v_new := v_old || COALESCE(p_patch, '{}'::jsonb);
  INSERT INTO public.game_settings(key, value) VALUES ('season_pass_xp_multipliers', v_new)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  PERFORM public.admin_bump_settings_version();
  PERFORM public.admin_log(p_admin_id, 'pass_xp_multipliers_updated', 'settings', 'season_pass_xp_multipliers',
    v_old, v_new, p_reason, '{}'::jsonb);
  RETURN v_new;
END; $function$;

CREATE OR REPLACE FUNCTION public.admin_set_pass_xp_caps(p_admin_id bigint, p_patch jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_old := public.season_pass_xp_caps();
  v_new := v_old || COALESCE(p_patch, '{}'::jsonb);
  INSERT INTO public.game_settings(key, value) VALUES ('season_pass_xp_caps', v_new)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  PERFORM public.admin_bump_settings_version();
  PERFORM public.admin_log(p_admin_id, 'pass_xp_caps_updated', 'settings', 'season_pass_xp_caps',
    v_old, v_new, p_reason, '{}'::jsonb);
  RETURN v_new;
END; $function$;

-- 9. Recent XP gains for frontend toasts
CREATE OR REPLACE FUNCTION public.get_recent_pass_xp(p_telegram_id bigint, p_since timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RETURN '[]'::jsonb; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('id', l.id, 'source', l.source, 'baseXp', COALESCE(l.base_xp, l.xp_amount),
      'multiplier', l.multiplier, 'xp', l.xp_amount, 'levelUp', l.level_after > l.level_before,
      'level', l.level_after, 'createdAt', l.created_at) ORDER BY l.created_at)
    FROM public.season_pass_xp_ledger l
    WHERE l.user_id = u AND l.xp_amount > 0
      AND l.created_at > COALESCE(p_since, now() - interval '30 seconds')
    LIMIT 20), '[]'::jsonb);
END; $function$;

-- 10. Dashboard exposes multiplier info
CREATE OR REPLACE FUNCTION public.get_season_pass_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE u uuid; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        v_level int; v_xpl int; v_max int; v_mult numeric;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  SELECT * INTO s FROM public.season_pass_seasons WHERE active AND now() BETWEEN start_at AND end_at;
  IF u IS NULL OR s.id IS NULL THEN RAISE EXCEPTION 'SEASON_NOT_AVAILABLE'; END IF;
  INSERT INTO public.player_season_pass(user_id, season_id, tier) VALUES (u, s.id, 'none')
    ON CONFLICT (user_id, season_id) DO NOTHING;
  SELECT * INTO p FROM public.player_season_pass WHERE user_id = u AND season_id = s.id;
  v_xpl := GREATEST(1, s.xp_per_level);
  v_max := s.levels * v_xpl;
  v_level := LEAST(s.levels, p.xp / v_xpl + 1);
  v_mult := public.season_pass_tier_multiplier(p.tier);
  RETURN jsonb_build_object(
    'season', jsonb_build_object('id', s.id, 'name', s.name, 'endsAt', s.end_at, 'levels', s.levels,
      'xpPerLevel', v_xpl, 'adventurerPriceTon', s.adventurer_price_ton,
      'legendaryPriceTon', s.legendary_price_ton,
      'upgradePriceTon', GREATEST(0, s.legendary_price_ton - s.adventurer_price_ton)),
    'player', jsonb_build_object('xp', p.xp, 'level', v_level, 'tier', p.tier,
      'totalXp', p.xp, 'maxXp', v_max, 'maxed', p.xp >= v_max,
      'xpIntoLevel', CASE WHEN p.xp >= v_max THEN v_xpl ELSE p.xp % v_xpl END,
      'xpForNextLevel', v_xpl,
      'xpMultiplier', v_mult, 'xpBonusPercent', round((v_mult - 1) * 100),
      'adventurerOwned', p.tier IN ('adventurer','legendary'), 'legendaryOwned', p.tier = 'legendary'),
    'xpRates', public.season_pass_xp_config(),
    'xpMultipliers', public.season_pass_xp_multipliers(),
    'xpCaps', public.season_pass_xp_caps(),
    'xpToday', COALESCE((SELECT SUM(xp_amount) FROM public.season_pass_xp_ledger
      WHERE user_id = u AND game_day = public.game_day_key()), 0),
    'rewards', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('id', r.id, 'level', r.level, 'tier', r.tier,
        'type', r.reward_type, 'code', r.reward_code, 'amount', r.amount, 'title', r.title,
        'claimed', c.id IS NOT NULL,
        'unlocked', r.level <= v_level AND (
          (r.tier = 'adventurer' AND p.tier IN ('adventurer','legendary'))
          OR (r.tier = 'legendary' AND p.tier = 'legendary')))
        ORDER BY r.level, CASE r.tier WHEN 'adventurer' THEN 1 ELSE 2 END), '[]')
      FROM public.season_pass_rewards r
      LEFT JOIN public.season_pass_claims c ON c.reward_id = r.id AND c.user_id = u
      WHERE r.season_id = s.id AND r.enabled AND r.tier IN ('adventurer','legendary')));
END; $function$;