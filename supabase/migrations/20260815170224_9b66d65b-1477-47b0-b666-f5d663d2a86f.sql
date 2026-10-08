-- ============================================================
-- HERO PROGRESSION: LV.1 -> LV.20 with gameplay XP + daily caps
-- ============================================================

ALTER TABLE public.player_heroes
  ADD COLUMN IF NOT EXISTS xp integer NOT NULL DEFAULT 0;

ALTER TABLE public.pet_expeditions
  ADD COLUMN IF NOT EXISTS hero_ids uuid[] NOT NULL DEFAULT '{}'::uuid[];

ALTER TABLE public.quest_definitions
  ADD COLUMN IF NOT EXISTS reward_hero_xp boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.hero_xp_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  player_hero_id uuid NOT NULL REFERENCES public.player_heroes(id) ON DELETE CASCADE,
  activity_type text NOT NULL,
  reference_id text NOT NULL,
  xp_awarded integer NOT NULL DEFAULT 0,
  level_before integer NOT NULL DEFAULT 1,
  level_after integer NOT NULL DEFAULT 1,
  daily_period date NOT NULL DEFAULT public.game_day_key(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hero_xp_events_unique UNIQUE (player_hero_id, activity_type, reference_id)
);

GRANT ALL ON public.hero_xp_events TO service_role;
ALTER TABLE public.hero_xp_events ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS hero_xp_events_hero_day_idx
  ON public.hero_xp_events (player_hero_id, daily_period);
CREATE INDEX IF NOT EXISTS hero_xp_events_user_day_idx
  ON public.hero_xp_events (user_id, daily_period);

-- ---------- config (server-side editable) ----------
INSERT INTO public.game_settings (key, value)
VALUES ('hero_progression', jsonb_build_object(
  'maxLevel', 20,
  'dailyXpCapPerHero', 800,
  'curve', jsonb_build_array(300,400,500,650,800,1000,1200,1450,1700,2000,2350,2700,3100,3500,4000,4500,5000,5600,6300),
  'activities', jsonb_build_object(
    'DUNGEON',     jsonb_build_object('xp', 40, 'dailyEvents', 5, 'dailyXpCap', 200),
    'GLOBAL_BOSS', jsonb_build_object('xp', 20, 'dailyEvents', 5, 'dailyXpCap', 100),
    'CLAN_BOSS',   jsonb_build_object('xp', 20, 'dailyEvents', 5, 'dailyXpCap', 100),
    'MISSION',     jsonb_build_object('xp', 30, 'dailyEvents', 5, 'dailyXpCap', 150),
    'EXPEDITION',  jsonb_build_object('xp', 50, 'dailyEvents', 5, 'dailyXpCap', 250)
  )
))
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.hero_progression_config()
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT value FROM public.game_settings WHERE key = 'hero_progression'), '{}'::jsonb)
$$;
REVOKE ALL ON FUNCTION public.hero_progression_config() FROM PUBLIC, anon, authenticated;

-- XP required to reach the NEXT level from p_level (0 = max level)
CREATE OR REPLACE FUNCTION public.hero_xp_to_next(p_level integer)
RETURNS integer LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
declare cfg jsonb := public.hero_progression_config(); v_max int; v int;
begin
  v_max := COALESCE((cfg->>'maxLevel')::int, 20);
  if COALESCE(p_level, 1) >= v_max then return 0; end if;
  v := (cfg->'curve'->>(GREATEST(1, COALESCE(p_level, 1)) - 1))::int;
  return COALESCE(v, 0);
end $$;
REVOKE ALL ON FUNCTION public.hero_xp_to_next(integer) FROM PUBLIC, anon, authenticated;

-- Heroes that actually took part in an activity, per team type
CREATE OR REPLACE FUNCTION public.hero_activity_team_ids(p_user_id uuid, p_activity text)
RETURNS uuid[] LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
declare a text := upper(COALESCE(p_activity, '')); ids uuid[] := '{}'::uuid[];
begin
  if p_user_id is null then return ids; end if;

  if a = 'DUNGEON' then
    select COALESCE(array_agg(s.hero_id order by s.slot), '{}'::uuid[]) into ids
      from public.tower_team_slots s where s.user_id = p_user_id and s.hero_id is not null;
  elsif a in ('GLOBAL_BOSS', 'CLAN_BOSS') then
    select COALESCE(array_agg(s.player_hero_id order by s.slot), '{}'::uuid[]) into ids
      from public.boss_team_slots s where s.user_id = p_user_id and s.player_hero_id is not null;
  else
    -- generic combat team fallback (missions / expedition snapshot)
    select COALESCE(array_agg(s.player_hero_id order by s.slot), '{}'::uuid[]) into ids
      from public.boss_team_slots s where s.user_id = p_user_id and s.player_hero_id is not null;
    if COALESCE(array_length(ids, 1), 0) = 0 then
      select COALESCE(array_agg(s.hero_id order by s.slot), '{}'::uuid[]) into ids
        from public.tower_team_slots s where s.user_id = p_user_id and s.hero_id is not null;
    end if;
    if COALESCE(array_length(ids, 1), 0) = 0 then
      select COALESCE(array_agg(s.hero_id order by s.slot), '{}'::uuid[]) into ids
        from public.pvp_team_slots s where s.user_id = p_user_id and s.hero_id is not null;
    end if;
  end if;

  return COALESCE(ids, '{}'::uuid[]);
end $$;
REVOKE ALL ON FUNCTION public.hero_activity_team_ids(uuid, text) FROM PUBLIC, anon, authenticated;

-- ---------- core grant (idempotent, per-hero daily caps) ----------
CREATE OR REPLACE FUNCTION public.grant_hero_xp(
  p_user_id uuid, p_activity text, p_reference_id text, p_hero_ids uuid[] DEFAULT NULL::uuid[]
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare
  cfg jsonb := public.hero_progression_config();
  act jsonb; a text := upper(COALESCE(p_activity, ''));
  v_max_level int := COALESCE((cfg->>'maxLevel')::int, 20);
  v_hero_cap int := COALESCE((cfg->>'dailyXpCapPerHero')::int, 800);
  v_xp int; v_events_cap int; v_src_cap int;
  v_day date := public.game_day_key();
  v_ref text := NULLIF(p_reference_id, '');
  ids uuid[]; hid uuid; h public.player_heroes;
  v_used_src int; v_events int; v_used_total int; v_award int; v_need int;
  v_level int; v_xp_cur int; v_before_level int; v_before_atk numeric; v_before_hp numeric;
  out_heroes jsonb := '[]'::jsonb; v_any boolean := false;
begin
  if p_user_id is null or v_ref is null then return NULL; end if;
  act := cfg->'activities'->a;
  if act is null then return NULL; end if;

  v_xp := COALESCE((act->>'xp')::int, 0);
  v_events_cap := COALESCE((act->>'dailyEvents')::int, 0);
  v_src_cap := COALESCE((act->>'dailyXpCap')::int, 0);
  if v_xp <= 0 then return NULL; end if;

  ids := COALESCE(p_hero_ids, public.hero_activity_team_ids(p_user_id, a));
  if COALESCE(array_length(ids, 1), 0) = 0 then
    return jsonb_build_object('activity', a, 'xpEach', v_xp, 'heroes', '[]'::jsonb, 'granted', false);
  end if;

  foreach hid in array (select array_agg(distinct x) from unnest(ids) x) loop
    select * into h from public.player_heroes
      where id = hid and user_id = p_user_id and NOT COALESCE(market_locked, false)
      for update;
    if h.id is null then continue; end if;

    -- already paid for this exact event?
    if exists (select 1 from public.hero_xp_events
                where player_hero_id = h.id and activity_type = a and reference_id = v_ref) then
      continue;
    end if;

    v_level := GREATEST(1, COALESCE(h.level, 1));
    v_xp_cur := GREATEST(0, COALESCE(h.xp, 0));

    if v_level >= v_max_level then
      out_heroes := out_heroes || jsonb_build_array(jsonb_build_object(
        'heroId', h.id, 'name', h.name, 'image', h.image, 'xpAwarded', 0,
        'level', v_level, 'levelBefore', v_level, 'xp', 0, 'xpToNext', 0,
        'maxLevel', v_max_level, 'maxed', true, 'leveledUp', false,
        'dailyXp', 0, 'dailyXpCap', v_hero_cap, 'capped', false));
      continue;
    end if;

    select COALESCE(sum(xp_awarded), 0)::int, count(*)::int into v_used_src, v_events
      from public.hero_xp_events
     where player_hero_id = h.id and activity_type = a and daily_period = v_day;
    select COALESCE(sum(xp_awarded), 0)::int into v_used_total
      from public.hero_xp_events
     where player_hero_id = h.id and daily_period = v_day;

    v_award := v_xp;
    if v_events_cap > 0 and v_events >= v_events_cap then v_award := 0; end if;
    if v_src_cap > 0 then v_award := LEAST(v_award, GREATEST(0, v_src_cap - v_used_src)); end if;
    if v_hero_cap > 0 then v_award := LEAST(v_award, GREATEST(0, v_hero_cap - v_used_total)); end if;

    if v_award <= 0 then
      out_heroes := out_heroes || jsonb_build_array(jsonb_build_object(
        'heroId', h.id, 'name', h.name, 'image', h.image, 'xpAwarded', 0,
        'level', v_level, 'levelBefore', v_level, 'xp', v_xp_cur,
        'xpToNext', public.hero_xp_to_next(v_level), 'maxLevel', v_max_level,
        'maxed', false, 'leveledUp', false,
        'dailyXp', v_used_total, 'dailyXpCap', v_hero_cap, 'capped', true));
      continue;
    end if;

    v_before_level := v_level;
    v_before_atk := COALESCE(h.final_atk, 0);
    v_before_hp := COALESCE(h.final_hp, 0);
    v_xp_cur := v_xp_cur + v_award;

    -- multiple level ups, leftover XP carries over
    loop
      v_need := public.hero_xp_to_next(v_level);
      exit when v_level >= v_max_level or v_need <= 0 or v_xp_cur < v_need;
      v_xp_cur := v_xp_cur - v_need;
      v_level := v_level + 1;
    end loop;
    if v_level >= v_max_level then v_xp_cur := 0; end if;

    update public.player_heroes set level = v_level, xp = v_xp_cur, updated_at = now()
      where id = h.id;
    select * into h from public.player_heroes where id = h.id;

    insert into public.hero_xp_events(user_id, player_hero_id, activity_type, reference_id,
                                      xp_awarded, level_before, level_after, daily_period)
    values (p_user_id, h.id, a, v_ref, v_award, v_before_level, v_level, v_day)
    on conflict (player_hero_id, activity_type, reference_id) do nothing;

    v_any := true;
    out_heroes := out_heroes || jsonb_build_array(jsonb_build_object(
      'heroId', h.id, 'name', h.name, 'image', h.image, 'xpAwarded', v_award,
      'level', v_level, 'levelBefore', v_before_level, 'xp', v_xp_cur,
      'xpToNext', public.hero_xp_to_next(v_level), 'maxLevel', v_max_level,
      'maxed', v_level >= v_max_level, 'leveledUp', v_level > v_before_level,
      'atkGain', GREATEST(0, round(COALESCE(h.final_atk,0) - v_before_atk)),
      'hpGain', GREATEST(0, round(COALESCE(h.final_hp,0) - v_before_hp)),
      'powerGain', GREATEST(0, round((COALESCE(h.final_atk,0)*2.2 + COALESCE(h.final_hp,0)*0.18 + v_level*25)
                                   - (v_before_atk*2.2 + v_before_hp*0.18 + v_before_level*25))),
      'dailyXp', v_used_total + v_award, 'dailyXpCap', v_hero_cap, 'capped', false));
  end loop;

  return jsonb_build_object('activity', a, 'xpEach', v_xp, 'granted', v_any, 'heroes', out_heroes);
end $$;
REVOKE ALL ON FUNCTION public.grant_hero_xp(uuid, text, text, uuid[]) FROM PUBLIC, anon, authenticated;

-- ---------- player facing state ----------
CREATE OR REPLACE FUNCTION public.hero_progression_json(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
declare cfg jsonb := public.hero_progression_config(); v_day date := public.game_day_key();
begin
  return jsonb_build_object(
    'maxLevel', COALESCE((cfg->>'maxLevel')::int, 20),
    'dailyXpCapPerHero', COALESCE((cfg->>'dailyXpCapPerHero')::int, 800),
    'gameDay', v_day,
    'activities', cfg->'activities',
    'heroes', COALESCE((
      select jsonb_agg(jsonb_build_object(
        'heroId', h.id,
        'level', GREATEST(1, COALESCE(h.level,1)),
        'xp', GREATEST(0, COALESCE(h.xp,0)),
        'xpToNext', public.hero_xp_to_next(GREATEST(1, COALESCE(h.level,1))),
        'dailyXp', COALESCE((select sum(e.xp_awarded)::int from public.hero_xp_events e
                              where e.player_hero_id = h.id and e.daily_period = v_day), 0)
      ))
      from public.player_heroes h where h.user_id = p_user_id), '[]'::jsonb)
  );
end $$;
REVOKE ALL ON FUNCTION public.hero_progression_json(uuid) FROM PUBLIC, anon, authenticated;

-- ---------- hooks: only real, validated activity ----------
CREATE OR REPLACE FUNCTION public.hero_xp_hook_global_boss()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
begin
  if COALESCE(NEW.damage, 0) > 0 then
    perform public.grant_hero_xp(NEW.user_id, 'GLOBAL_BOSS', NEW.id::text, NULL);
  end if;
  return NEW;
end $$;

CREATE OR REPLACE FUNCTION public.hero_xp_hook_clan_boss()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
begin
  if COALESCE(NEW.damage, 0) > 0 then
    perform public.grant_hero_xp(NEW.user_id, 'CLAN_BOSS', NEW.id::text, NULL);
  end if;
  return NEW;
end $$;

-- Tower/Dungeon: the row only exists after a paid, fully simulated run
CREATE OR REPLACE FUNCTION public.hero_xp_hook_dungeon()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
begin
  perform public.grant_hero_xp(NEW.user_id, 'DUNGEON', NEW.id::text, NULL);
  return NEW;
end $$;

-- Expedition: snapshot the hero team when it starts
CREATE OR REPLACE FUNCTION public.hero_xp_snapshot_expedition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
begin
  if COALESCE(array_length(NEW.hero_ids, 1), 0) = 0 then
    NEW.hero_ids := public.hero_activity_team_ids(NEW.user_id, 'EXPEDITION');
  end if;
  return NEW;
end $$;

CREATE OR REPLACE FUNCTION public.hero_xp_hook_expedition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
begin
  if NEW.status = 'CLAIMED' and COALESCE(OLD.status, '') <> 'CLAIMED' then
    -- snapshot only: swapping the team after starting must not move the XP
    perform public.grant_hero_xp(NEW.user_id, 'EXPEDITION', NEW.id::text, NEW.hero_ids);
  end if;
  return NEW;
end $$;

DROP TRIGGER IF EXISTS hero_xp_global_boss ON public.global_boss_attack_log;
CREATE TRIGGER hero_xp_global_boss AFTER INSERT ON public.global_boss_attack_log
  FOR EACH ROW EXECUTE FUNCTION public.hero_xp_hook_global_boss();

DROP TRIGGER IF EXISTS hero_xp_clan_boss ON public.clan_boss_attack_log;
CREATE TRIGGER hero_xp_clan_boss AFTER INSERT ON public.clan_boss_attack_log
  FOR EACH ROW EXECUTE FUNCTION public.hero_xp_hook_clan_boss();

DROP TRIGGER IF EXISTS hero_xp_dungeon ON public.tower_runs;
CREATE TRIGGER hero_xp_dungeon AFTER INSERT ON public.tower_runs
  FOR EACH ROW EXECUTE FUNCTION public.hero_xp_hook_dungeon();

DROP TRIGGER IF EXISTS hero_xp_expedition_snapshot ON public.pet_expeditions;
CREATE TRIGGER hero_xp_expedition_snapshot BEFORE INSERT ON public.pet_expeditions
  FOR EACH ROW EXECUTE FUNCTION public.hero_xp_snapshot_expedition();

DROP TRIGGER IF EXISTS hero_xp_expedition_claim ON public.pet_expeditions;
CREATE TRIGGER hero_xp_expedition_claim AFTER UPDATE ON public.pet_expeditions
  FOR EACH ROW EXECUTE FUNCTION public.hero_xp_hook_expedition();

-- ---------- missions: only quests flagged with reward_hero_xp ----------
CREATE OR REPLACE FUNCTION public.claim_daily_quest(p_telegram_id bigint, p_quest_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE u uuid; v_date date; q public.quest_definitions; p public.player_quest_progress; v_balance numeric; v_hero_xp jsonb;
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

  IF COALESCE(q.reward_hero_xp, false) THEN
    v_hero_xp := public.grant_hero_xp(u, 'MISSION', 'quest:' || q.code || ':' || v_date::text, NULL);
  END IF;

  RETURN jsonb_build_object('claimed', true, 'code', q.code, 'rewardFc', q.reward_fc, 'balance', v_balance,
                            'heroXp', v_hero_xp,
                            'quests', public.get_daily_quests(p_telegram_id));
END;
$function$;
REVOKE ALL ON FUNCTION public.claim_daily_quest(bigint, text) FROM PUBLIC, anon, authenticated;

-- combat-related daily quests grant hero XP by default
UPDATE public.quest_definitions SET reward_hero_xp = true, updated_at = now()
 WHERE event_key IN ('boss_attack', 'pvp_battle', 'tower_run', 'tower_clear', 'expedition_complete');

-- ---------- admin bot configuration ----------
CREATE OR REPLACE FUNCTION public.admin_hero_progression_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare cfg jsonb; v_day date := public.game_day_key();
begin
  perform public.admin_assert(p_admin_id);
  cfg := public.hero_progression_config();
  return jsonb_build_object(
    'maxLevel', COALESCE((cfg->>'maxLevel')::int, 20),
    'dailyXpCapPerHero', COALESCE((cfg->>'dailyXpCapPerHero')::int, 800),
    'curve', cfg->'curve',
    'activities', cfg->'activities',
    'gameDay', v_day,
    'xpToday', COALESCE((select sum(xp_awarded)::int from public.hero_xp_events where daily_period = v_day), 0),
    'heroesToday', COALESCE((select count(distinct player_hero_id)::int from public.hero_xp_events where daily_period = v_day), 0),
    'levelUpsToday', COALESCE((select count(*)::int from public.hero_xp_events where daily_period = v_day and level_after > level_before), 0),
    'maxedHeroes', COALESCE((select count(*)::int from public.player_heroes where level >= COALESCE((cfg->>'maxLevel')::int, 20)), 0),
    'questsWithHeroXp', COALESCE((select jsonb_agg(jsonb_build_object('code', code, 'title', title, 'enabled', reward_hero_xp)
                                    order by sort_order) from public.quest_definitions where enabled), '[]'::jsonb)
  );
end $$;
REVOKE ALL ON FUNCTION public.admin_hero_progression_overview(bigint) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_hero_progression_set(
  p_admin_id bigint, p_field text, p_target text, p_value numeric
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare cfg jsonb; f text := lower(COALESCE(p_field, '')); t text := upper(COALESCE(p_target, '')); v int;
begin
  perform public.admin_assert(p_admin_id);
  cfg := public.hero_progression_config();
  v := GREATEST(0, COALESCE(p_value, 0))::int;

  if f = 'maxlevel' then
    if v < 1 or v > 20 then raise exception 'HERO_MAX_LEVEL_INVALID'; end if;
    cfg := jsonb_set(cfg, '{maxLevel}', to_jsonb(v));
  elsif f = 'dailycap' then
    cfg := jsonb_set(cfg, '{dailyXpCapPerHero}', to_jsonb(v));
  elsif f in ('activity_xp', 'activity_events', 'activity_cap') then
    if cfg->'activities'->t is null then raise exception 'HERO_ACTIVITY_INVALID'; end if;
    cfg := jsonb_set(cfg, array['activities', t,
      case f when 'activity_xp' then 'xp' when 'activity_events' then 'dailyEvents' else 'dailyXpCap' end],
      to_jsonb(v));
  elsif f = 'curve' then
    if COALESCE(t, '') !~ '^\d+$' then raise exception 'HERO_CURVE_LEVEL_INVALID'; end if;
    if t::int < 1 or t::int > 19 then raise exception 'HERO_CURVE_LEVEL_INVALID'; end if;
    cfg := jsonb_set(cfg, array['curve', (t::int - 1)::text], to_jsonb(GREATEST(1, v)));
  elsif f = 'quest_hero_xp' then
    update public.quest_definitions set reward_hero_xp = (v > 0), updated_at = now() where code = lower(p_target);
    perform public.admin_log(p_admin_id, 'hero_progression.quest', 'quest', null, null,
      jsonb_build_object('code', lower(p_target), 'enabled', v > 0), 'Hero XP em missão');
    return public.admin_hero_progression_overview(p_admin_id);
  else
    raise exception 'HERO_PROGRESSION_FIELD_INVALID';
  end if;

  insert into public.game_settings(key, value) values ('hero_progression', cfg)
  on conflict (key) do update set value = excluded.value;
  perform public.admin_bump_settings_version();
  perform public.admin_log(p_admin_id, 'hero_progression.set', 'settings', null, null,
    jsonb_build_object('field', f, 'target', t, 'value', v), 'Configuração de progressão de heróis');

  return public.admin_hero_progression_overview(p_admin_id);
end $$;
REVOKE ALL ON FUNCTION public.admin_hero_progression_set(bigint, text, text, numeric) FROM PUBLIC, anon, authenticated;