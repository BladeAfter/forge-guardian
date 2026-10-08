-- 1. XP ledger
CREATE TABLE IF NOT EXISTS public.season_pass_xp_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  season_id uuid NOT NULL REFERENCES public.season_pass_seasons(id) ON DELETE CASCADE,
  source text NOT NULL,
  reference_id text,
  xp_amount integer NOT NULL,
  xp_before integer NOT NULL,
  xp_after integer NOT NULL,
  level_before integer NOT NULL,
  level_after integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.season_pass_xp_ledger TO service_role;
ALTER TABLE public.season_pass_xp_ledger ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS season_pass_xp_ledger_ref_uniq
  ON public.season_pass_xp_ledger(user_id, season_id, source, reference_id)
  WHERE reference_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS season_pass_xp_ledger_user_idx
  ON public.season_pass_xp_ledger(user_id, created_at DESC);

-- 2. configurable XP values
INSERT INTO public.game_settings(key, value)
VALUES ('season_pass_xp', jsonb_build_object(
  'daily_quest', 100, 'daily_quest_all', 250, 'daily_chest', 100,
  'pvp_battle', 50, 'pvp_victory', 25,
  'boss_attack', 75, 'boss_defeated', 150,
  'reward_open', 25, 'pet_feed', 10, 'calendar_claim', 20))
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.season_pass_xp_config()
RETURNS jsonb LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT COALESCE((SELECT value FROM public.game_settings WHERE key = 'season_pass_xp'), '{}'::jsonb)
$$;

-- 3. central grant function
CREATE OR REPLACE FUNCTION public.grant_season_pass_xp(
  p_user_id uuid, p_source text, p_reference_id text DEFAULT NULL, p_amount integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s public.season_pass_seasons%rowtype; sp public.player_season_pass%rowtype;
  v_amount integer; v_before integer; v_after integer; v_max integer;
  v_lvl_before integer; v_lvl_after integer; v_ins uuid;
BEGIN
  IF p_user_id IS NULL OR COALESCE(p_source,'') = '' THEN RETURN NULL; END IF;

  SELECT * INTO s FROM public.season_pass_seasons
   WHERE active AND now() BETWEEN start_at AND end_at
   ORDER BY start_at DESC LIMIT 1;
  IF s.id IS NULL THEN RETURN NULL; END IF;

  v_amount := COALESCE(p_amount, (public.season_pass_xp_config()->>p_source)::int, 0);
  IF v_amount = 0 THEN RETURN NULL; END IF;

  INSERT INTO public.player_season_pass(user_id, season_id, tier)
  VALUES (p_user_id, s.id, 'none') ON CONFLICT (user_id, season_id) DO NOTHING;

  SELECT * INTO sp FROM public.player_season_pass
   WHERE user_id = p_user_id AND season_id = s.id FOR UPDATE;

  v_max := s.levels * s.xp_per_level;
  v_before := COALESCE(sp.xp, 0);
  v_after := GREATEST(0, LEAST(v_max, v_before + v_amount));
  v_lvl_before := LEAST(s.levels, v_before / GREATEST(1, s.xp_per_level) + 1);
  v_lvl_after := LEAST(s.levels, v_after / GREATEST(1, s.xp_per_level) + 1);

  INSERT INTO public.season_pass_xp_ledger(user_id, season_id, source, reference_id, xp_amount,
      xp_before, xp_after, level_before, level_after)
  VALUES (p_user_id, s.id, p_source, p_reference_id, v_after - v_before,
      v_before, v_after, v_lvl_before, v_lvl_after)
  ON CONFLICT (user_id, season_id, source, reference_id) DO NOTHING
  RETURNING id INTO v_ins;

  IF v_ins IS NULL THEN
    RETURN jsonb_build_object('granted', false, 'duplicate', true,
      'xp', v_before, 'level', v_lvl_before, 'xpPerLevel', s.xp_per_level, 'levels', s.levels);
  END IF;

  UPDATE public.player_season_pass SET xp = v_after, updated_at = now()
   WHERE user_id = p_user_id AND season_id = s.id;

  RETURN jsonb_build_object('granted', true, 'amount', v_after - v_before,
    'xp', v_after, 'level', v_lvl_after, 'levelUp', v_lvl_after > v_lvl_before,
    'xpPerLevel', s.xp_per_level, 'levels', s.levels, 'maxed', v_after >= v_max);
END; $$;

-- 4. quest completion XP inside the central quest event recorder
CREATE OR REPLACE FUNCTION public.record_quest_event(p_user_id uuid, p_event text, p_amount integer DEFAULT 1)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE q record; v_date date; v_amount integer := GREATEST(1, COALESCE(p_amount, 1));
        v_progress integer; v_done boolean; v_total int; v_completed int;
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
END; $$;

-- 5. action hooks
CREATE OR REPLACE FUNCTION public.quest_hook_pet_feed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.action LIKE 'feed%' THEN
    PERFORM public.record_quest_event(NEW.user_id, 'pet_fed', 1);
    PERFORM public.grant_season_pass_xp(NEW.user_id, 'pet_feed', 'feed:' || NEW.id::text);
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.quest_hook_pvp_battle()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.record_quest_event(NEW.attacker_id, 'pvp_battle', 1);
  PERFORM public.grant_season_pass_xp(NEW.attacker_id, 'pvp_battle', 'pvp:' || NEW.id::text);
  IF NEW.winner_id IS NOT NULL AND NEW.winner_id = NEW.attacker_id THEN
    PERFORM public.grant_season_pass_xp(NEW.attacker_id, 'pvp_victory', 'pvp_win:' || NEW.id::text);
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.quest_hook_boss_attack()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.total_damage_dealt > COALESCE(OLD.total_damage_dealt, 0) THEN
    PERFORM public.record_quest_event(NEW.user_id, 'boss_attack', 1);
    PERFORM public.grant_season_pass_xp(NEW.user_id, 'boss_attack', 'boss:' || NEW.id::text);
  END IF;
  IF NEW.status = 'defeated' AND COALESCE(OLD.status,'') <> 'defeated' THEN
    PERFORM public.grant_season_pass_xp(NEW.user_id, 'boss_defeated', 'boss_kill:' || NEW.id::text);
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.quest_hook_reward_opened()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.record_quest_event(NEW.user_id, 'reward_opened', 1);
  PERFORM public.grant_season_pass_xp(NEW.user_id, 'reward_open', 'reward_log:' || NEW.id::text);
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.quest_hook_pet_egg_hatched()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'completed' AND (TG_OP = 'INSERT' OR COALESCE(OLD.status,'') <> 'completed') THEN
    PERFORM public.record_quest_event(NEW.user_id, 'reward_opened', 1);
    PERFORM public.grant_season_pass_xp(NEW.user_id, 'reward_open', 'hatch:' || NEW.id::text);
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.pass_hook_calendar_claim()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.grant_season_pass_xp(NEW.user_id, 'calendar_claim', 'calendar:' || NEW.id::text);
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS pass_calendar_claim ON public.daily_calendar_claims;
CREATE TRIGGER pass_calendar_claim AFTER INSERT ON public.daily_calendar_claims
  FOR EACH ROW EXECUTE FUNCTION public.pass_hook_calendar_claim();

CREATE OR REPLACE FUNCTION public.pass_hook_quest_bonus()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.grant_season_pass_xp(NEW.user_id, 'daily_chest', 'quest_chest:' || NEW.quest_date::text);
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS pass_quest_bonus ON public.player_quest_bonus;
CREATE TRIGGER pass_quest_bonus AFTER INSERT ON public.player_quest_bonus
  FOR EACH ROW EXECUTE FUNCTION public.pass_hook_quest_bonus();

-- 6. dashboard exposes level progress details
CREATE OR REPLACE FUNCTION public.get_season_pass_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        v_level int; v_xpl int; v_max int;
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
  RETURN jsonb_build_object(
    'season', jsonb_build_object('id', s.id, 'name', s.name, 'endsAt', s.end_at, 'levels', s.levels,
      'xpPerLevel', v_xpl, 'adventurerPriceTon', s.adventurer_price_ton,
      'legendaryPriceTon', s.legendary_price_ton,
      'upgradePriceTon', GREATEST(0, s.legendary_price_ton - s.adventurer_price_ton)),
    'player', jsonb_build_object('xp', p.xp, 'level', v_level, 'tier', p.tier,
      'totalXp', p.xp, 'maxXp', v_max, 'maxed', p.xp >= v_max,
      'xpIntoLevel', CASE WHEN p.xp >= v_max THEN v_xpl ELSE p.xp % v_xpl END,
      'xpForNextLevel', v_xpl,
      'adventurerOwned', p.tier IN ('adventurer','legendary'), 'legendaryOwned', p.tier = 'legendary'),
    'xpRates', public.season_pass_xp_config(),
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
END; $$;

-- 7. admin controls
CREATE OR REPLACE FUNCTION public.admin_set_pass_xp_settings(p_admin_id bigint, p_patch jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_old := public.season_pass_xp_config();
  v_new := v_old || COALESCE(p_patch, '{}'::jsonb);
  INSERT INTO public.game_settings(key, value) VALUES ('season_pass_xp', v_new)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  PERFORM public.admin_bump_settings_version();
  PERFORM public.admin_log(p_admin_id, 'pass_xp_settings_updated', 'settings', 'season_pass_xp',
    v_old, v_new, p_reason, '{}'::jsonb);
  RETURN v_new;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_adjust_pass_xp(p_admin_id bigint, p_ref text, p_delta integer, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; s public.season_pass_seasons%rowtype; v_before int; v_after int; v_max int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO s FROM public.season_pass_seasons WHERE active ORDER BY start_at DESC LIMIT 1;
  IF s.id IS NULL THEN RAISE EXCEPTION 'season_not_found'; END IF;
  INSERT INTO public.player_season_pass(user_id, season_id, tier) VALUES (v_uid, s.id, 'none')
    ON CONFLICT (user_id, season_id) DO NOTHING;
  SELECT xp INTO v_before FROM public.player_season_pass WHERE user_id = v_uid AND season_id = s.id FOR UPDATE;
  v_max := s.levels * GREATEST(1, s.xp_per_level);
  v_after := GREATEST(0, LEAST(v_max, COALESCE(v_before,0) + p_delta));
  UPDATE public.player_season_pass SET xp = v_after, updated_at = now()
   WHERE user_id = v_uid AND season_id = s.id;
  INSERT INTO public.season_pass_xp_ledger(user_id, season_id, source, reference_id, xp_amount,
      xp_before, xp_after, level_before, level_after)
  VALUES (v_uid, s.id, 'admin_adjust', 'admin:' || p_admin_id || ':' || clock_timestamp()::text,
      v_after - COALESCE(v_before,0), COALESCE(v_before,0), v_after,
      LEAST(s.levels, COALESCE(v_before,0) / GREATEST(1, s.xp_per_level) + 1),
      LEAST(s.levels, v_after / GREATEST(1, s.xp_per_level) + 1));
  PERFORM public.admin_log(p_admin_id, 'pass_xp_adjusted', 'player', v_uid::text,
    jsonb_build_object('xp', COALESCE(v_before,0)), jsonb_build_object('xp', v_after, 'delta', p_delta),
    p_reason, jsonb_build_object('season', s.name));
  RETURN jsonb_build_object('user_id', v_uid, 'xp', v_after,
    'level', LEAST(s.levels, v_after / GREATEST(1, s.xp_per_level) + 1),
    'levels', s.levels, 'xp_per_level', s.xp_per_level);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_pass_level(p_admin_id bigint, p_ref text, p_level integer, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.season_pass_seasons%rowtype; v_uid uuid; v_target int; v_cur int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO s FROM public.season_pass_seasons WHERE active ORDER BY start_at DESC LIMIT 1;
  IF s.id IS NULL THEN RAISE EXCEPTION 'season_not_found'; END IF;
  v_target := GREATEST(1, LEAST(s.levels, COALESCE(p_level, 1)));
  INSERT INTO public.player_season_pass(user_id, season_id, tier) VALUES (v_uid, s.id, 'none')
    ON CONFLICT (user_id, season_id) DO NOTHING;
  SELECT xp INTO v_cur FROM public.player_season_pass WHERE user_id = v_uid AND season_id = s.id FOR UPDATE;
  RETURN public.admin_adjust_pass_xp(p_admin_id, p_ref,
    ((v_target - 1) * GREATEST(1, s.xp_per_level)) - COALESCE(v_cur, 0),
    COALESCE(p_reason, 'set level ' || v_target));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_player_pass(p_admin_id bigint, p_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; p public.game_players; s public.season_pass_seasons; sp public.player_season_pass; v_xpl int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO p FROM public.game_players WHERE id = v_uid;
  SELECT * INTO s FROM public.season_pass_seasons WHERE active ORDER BY start_at DESC LIMIT 1;
  IF s.id IS NULL THEN RAISE EXCEPTION 'season_not_found'; END IF;
  SELECT * INTO sp FROM public.player_season_pass WHERE user_id = v_uid AND season_id = s.id;
  v_xpl := GREATEST(1, s.xp_per_level);
  RETURN jsonb_build_object(
    'user_id', p.id, 'telegram_id', p.telegram_id, 'username', p.username,
    'name', COALESCE(NULLIF(btrim(p.display_name),''), NULLIF(btrim(concat_ws(' ', p.first_name, p.last_name)),''), 'Jogador'),
    'season_id', s.id, 'season_name', s.name, 'levels', s.levels, 'xp_per_level', v_xpl,
    'tier', COALESCE(sp.tier,'none'), 'xp', COALESCE(sp.xp,0),
    'level', LEAST(s.levels, COALESCE(sp.xp,0) / v_xpl + 1),
    'xp_into_level', COALESCE(sp.xp,0) % v_xpl,
    'purchased_at', sp.purchased_at, 'upgraded_at', sp.upgraded_at,
    'claimed', (SELECT count(*) FROM public.season_pass_claims c WHERE c.user_id = v_uid),
    'paid_orders', (SELECT count(*) FROM public.season_pass_orders o WHERE o.user_id = v_uid AND o.status = 'activated'),
    'xp_events', (SELECT count(*) FROM public.season_pass_xp_ledger l WHERE l.user_id = v_uid AND l.season_id = s.id));
END; $$;