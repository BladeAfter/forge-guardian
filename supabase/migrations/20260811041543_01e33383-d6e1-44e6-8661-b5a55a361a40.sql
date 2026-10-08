
-- ============ CLAN SYSTEM ============
CREATE TABLE IF NOT EXISTS public.clans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  tag text NOT NULL,
  description text NOT NULL DEFAULT '',
  leader_user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  level integer NOT NULL DEFAULT 1,
  xp integer NOT NULL DEFAULT 0,
  join_type text NOT NULL DEFAULT 'open',
  minimum_trophies integer NOT NULL DEFAULT 0,
  member_limit integer NOT NULL DEFAULT 20,
  emblem_config jsonb NOT NULL DEFAULT '{"shield":"classic","background":"navy","symbol":"dragon","border":"gold"}'::jsonb,
  clan_points bigint NOT NULL DEFAULT 0,
  total_power numeric NOT NULL DEFAULT 0,
  suspended boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS clans_name_unique ON public.clans (lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS clans_tag_unique ON public.clans (upper(tag));
GRANT ALL ON public.clans TO service_role;
ALTER TABLE public.clans ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid NOT NULL UNIQUE REFERENCES public.game_players(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member',
  contribution bigint NOT NULL DEFAULT 0,
  clan_points bigint NOT NULL DEFAULT 0,
  joined_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS clan_members_clan_idx ON public.clan_members(clan_id);
GRANT ALL ON public.clan_members TO service_role;
ALTER TABLE public.clan_members ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_join_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (clan_id, user_id)
);
GRANT ALL ON public.clan_join_requests TO service_role;
ALTER TABLE public.clan_join_requests ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_xp_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  source text NOT NULL,
  xp_amount integer NOT NULL,
  game_day date NOT NULL DEFAULT public.game_day_key(),
  reference_id text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS clan_xp_ledger_day_idx ON public.clan_xp_ledger(clan_id, user_id, source, game_day);
GRANT ALL ON public.clan_xp_ledger TO service_role;
ALTER TABLE public.clan_xp_ledger ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_points_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  amount bigint NOT NULL,
  reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_points_ledger TO service_role;
ALTER TABLE public.clan_points_ledger ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  author_name text NOT NULL DEFAULT '',
  author_avatar text,
  body text NOT NULL,
  deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS clan_messages_clan_idx ON public.clan_messages(clan_id, created_at DESC);
GRANT ALL ON public.clan_messages TO service_role;
ALTER TABLE public.clan_messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_missions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  title text NOT NULL,
  metric text NOT NULL,
  target bigint NOT NULL,
  reward_points integer NOT NULL DEFAULT 500,
  reward_xp integer NOT NULL DEFAULT 500,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_missions TO service_role;
ALTER TABLE public.clan_missions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_mission_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  mission_code text NOT NULL,
  week_key date NOT NULL,
  progress bigint NOT NULL DEFAULT 0,
  completed boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (clan_id, mission_code, week_key)
);
GRANT ALL ON public.clan_mission_progress TO service_role;
ALTER TABLE public.clan_mission_progress ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_boss_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  name text NOT NULL DEFAULT 'Clan Warlord',
  max_health numeric NOT NULL DEFAULT 1000000,
  current_health numeric NOT NULL DEFAULT 1000000,
  status text NOT NULL DEFAULT 'active',
  reward_points integer NOT NULL DEFAULT 2000,
  started_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  finished_at timestamptz
);
CREATE INDEX IF NOT EXISTS clan_boss_active_idx ON public.clan_boss_cycles(clan_id, status);
GRANT ALL ON public.clan_boss_cycles TO service_role;
ALTER TABLE public.clan_boss_cycles ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_boss_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES public.clan_boss_cycles(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  damage numeric NOT NULL DEFAULT 0,
  attacks integer NOT NULL DEFAULT 0,
  last_attack_at timestamptz,
  UNIQUE (cycle_id, user_id)
);
GRANT ALL ON public.clan_boss_participants TO service_role;
ALTER TABLE public.clan_boss_participants ENABLE ROW LEVEL SECURITY;

-- Placeholder for the future CLAN WAR feature (not exposed anywhere yet).
CREATE TABLE IF NOT EXISTS public.clan_wars (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_a uuid REFERENCES public.clans(id) ON DELETE CASCADE,
  clan_b uuid REFERENCES public.clans(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'scheduled',
  score_a bigint NOT NULL DEFAULT 0,
  score_b bigint NOT NULL DEFAULT 0,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_wars TO service_role;
ALTER TABLE public.clan_wars ENABLE ROW LEVEL SECURITY;

-- ============ SETTINGS ============
INSERT INTO public.game_settings(key, value, category, label) VALUES
  ('clan_create_cost_fc', '100000'::jsonb, 'clans', 'Custo de criação de clã (FC)'),
  ('clan_xp_config', '{"daily_quest":2,"daily_quest_all":10,"pvp_battle":2,"pvp_victory":3,"boss_attack":5,"pet_level_up":3,"hero_fuse":5,"rarity_fusion":5,"reward_open":1}'::jsonb, 'clans', 'XP de clã por ação'),
  ('clan_xp_daily_cap', '120'::jsonb, 'clans', 'Limite diário de XP de clã por jogador'),
  ('clan_level_xp', '5000'::jsonb, 'clans', 'XP base por nível de clã')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.clan_missions(code, title, metric, target, reward_points, reward_xp) VALUES
  ('win_pvp', 'WIN 500 PVP BATTLES', 'pvp_victory', 500, 1500, 1500),
  ('boss_damage', 'ATTACK THE GLOBAL BOSS', 'boss_attack', 500, 1500, 1500),
  ('open_eggs', 'OPEN 1,000 EGGS', 'reward_open', 1000, 1200, 1200),
  ('feed_pets', 'FEED PETS', 'pet_feed', 2000, 1000, 1000)
ON CONFLICT (code) DO NOTHING;

-- ============ HELPERS ============
CREATE OR REPLACE FUNCTION public.clan_member_limit(p_level integer)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$ SELECT LEAST(60, 18 + GREATEST(1, COALESCE(p_level,1)) * 2) $$;

CREATE OR REPLACE FUNCTION public.clan_level_xp(p_level integer)
RETURNS integer LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT GREATEST(1000, COALESCE((SELECT value::text::int FROM public.game_settings WHERE key='clan_level_xp'), 5000) * GREATEST(1, COALESCE(p_level,1)))
$$;

CREATE OR REPLACE FUNCTION public.clan_week_key()
RETURNS date LANGUAGE sql STABLE SET search_path = public AS $$ SELECT date_trunc('week', public.game_day_key()::timestamp)::date $$;

CREATE OR REPLACE FUNCTION public.clan_role_rank(p_role text)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE lower(COALESCE(p_role,'member')) WHEN 'leader' THEN 4 WHEN 'co-leader' THEN 3 WHEN 'officer' THEN 2 ELSE 1 END
$$;

CREATE OR REPLACE FUNCTION public.clan_player_power(p_user_id uuid)
RETURNS numeric LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT COALESCE(SUM(final_atk * 2 + final_hp / 4), 0) FROM public.player_heroes WHERE user_id = p_user_id
$$;

CREATE OR REPLACE FUNCTION public.clan_public(p_clan public.clans)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', p_clan.id, 'name', p_clan.name, 'tag', p_clan.tag, 'description', p_clan.description,
    'level', p_clan.level, 'xp', p_clan.xp, 'xpNeeded', public.clan_level_xp(p_clan.level),
    'joinType', p_clan.join_type, 'minimumTrophies', p_clan.minimum_trophies,
    'memberLimit', p_clan.member_limit, 'emblem', p_clan.emblem_config,
    'clanPoints', p_clan.clan_points, 'suspended', p_clan.suspended,
    'power', (SELECT COALESCE(SUM(public.clan_player_power(m.user_id)),0)::bigint FROM public.clan_members m WHERE m.clan_id = p_clan.id),
    'members', (SELECT count(*) FROM public.clan_members m WHERE m.clan_id = p_clan.id)
  )
$$;

-- ============ XP / MISSION EVENT HOOK ============
CREATE OR REPLACE FUNCTION public.grant_clan_xp(p_user_id uuid, p_source text, p_amount integer DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_clan uuid; v_amount integer; v_cap integer; v_used integer; v_day date; v_need integer; c public.clans%rowtype;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = p_user_id;
  IF v_clan IS NULL THEN RETURN; END IF;
  v_amount := COALESCE(p_amount, (SELECT (value->>p_source)::int FROM public.game_settings WHERE key='clan_xp_config'), 0);
  IF COALESCE(v_amount,0) <= 0 THEN RETURN; END IF;
  v_day := public.game_day_key();
  v_cap := COALESCE((SELECT value::text::int FROM public.game_settings WHERE key='clan_xp_daily_cap'), 120);
  SELECT COALESCE(SUM(xp_amount),0) INTO v_used FROM public.clan_xp_ledger
   WHERE clan_id = v_clan AND user_id = p_user_id AND game_day = v_day;
  v_amount := LEAST(v_amount, GREATEST(0, v_cap - v_used));
  IF v_amount <= 0 THEN RETURN; END IF;

  INSERT INTO public.clan_xp_ledger(clan_id, user_id, source, xp_amount, game_day)
  VALUES (v_clan, p_user_id, p_source, v_amount, v_day);

  UPDATE public.clan_members SET contribution = contribution + v_amount, updated_at = now() WHERE user_id = p_user_id;

  SELECT * INTO c FROM public.clans WHERE id = v_clan FOR UPDATE;
  c.xp := c.xp + v_amount;
  LOOP
    v_need := public.clan_level_xp(c.level);
    EXIT WHEN c.xp < v_need OR c.level >= 30;
    c.xp := c.xp - v_need; c.level := c.level + 1;
  END LOOP;
  UPDATE public.clans SET xp = c.xp, level = c.level,
    member_limit = GREATEST(member_limit, public.clan_member_limit(c.level)), updated_at = now()
   WHERE id = v_clan;
END; $$;

CREATE OR REPLACE FUNCTION public.record_clan_mission_progress(p_user_id uuid, p_metric text, p_amount bigint DEFAULT 1)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_clan uuid; m public.clan_missions%rowtype; v_week date; v_row public.clan_mission_progress%rowtype;
BEGIN
  IF p_user_id IS NULL OR COALESCE(p_amount,0) <= 0 THEN RETURN; END IF;
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = p_user_id;
  IF v_clan IS NULL THEN RETURN; END IF;
  v_week := public.clan_week_key();
  FOR m IN SELECT * FROM public.clan_missions WHERE active AND metric = p_metric LOOP
    INSERT INTO public.clan_mission_progress(clan_id, mission_code, week_key, progress)
    VALUES (v_clan, m.code, v_week, 0) ON CONFLICT (clan_id, mission_code, week_key) DO NOTHING;
    UPDATE public.clan_mission_progress
       SET progress = LEAST(m.target, progress + p_amount), updated_at = now()
     WHERE clan_id = v_clan AND mission_code = m.code AND week_key = v_week
     RETURNING * INTO v_row;
    IF v_row.id IS NOT NULL AND NOT v_row.completed AND v_row.progress >= m.target THEN
      UPDATE public.clan_mission_progress SET completed = true, completed_at = now() WHERE id = v_row.id;
      UPDATE public.clans SET clan_points = clan_points + m.reward_points, updated_at = now() WHERE id = v_clan;
      INSERT INTO public.clan_points_ledger(clan_id, amount, reason) VALUES (v_clan, m.reward_points, 'mission:'||m.code);
    END IF;
  END LOOP;
END; $$;

-- Every confirmed player action already writes to the battle pass XP ledger,
-- so clan XP and clan missions are fed from that single trusted event stream.
CREATE OR REPLACE FUNCTION public.clan_hook_from_pass_xp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.grant_clan_xp(NEW.user_id, NEW.source);
  PERFORM public.record_clan_mission_progress(NEW.user_id, NEW.source, 1);
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS clan_xp_from_pass_xp ON public.season_pass_xp_ledger;
CREATE TRIGGER clan_xp_from_pass_xp AFTER INSERT ON public.season_pass_xp_ledger
FOR EACH ROW EXECUTE FUNCTION public.clan_hook_from_pass_xp();

-- ============ PLAYER RPCs ============
CREATE OR REPLACE FUNCTION public.clan_resolve_user(p_telegram_id bigint)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.get_clan_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; c public.clans%rowtype; v_role text; v_week date;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN
    RETURN jsonb_build_object(
      'inClan', false,
      'createCostFc', COALESCE((SELECT value::text::numeric FROM public.game_settings WHERE key='clan_create_cost_fc'), 100000),
      'balance', COALESCE((SELECT forge_coins FROM public.game_players WHERE id = v_uid), 0),
      'recommended', COALESCE((SELECT jsonb_agg(public.clan_public(x) ORDER BY x.level DESC)
        FROM (SELECT * FROM public.clans WHERE NOT suspended ORDER BY level DESC, xp DESC LIMIT 20) x), '[]'::jsonb)
    );
  END IF;
  SELECT * INTO c FROM public.clans WHERE id = v_clan;
  v_week := public.clan_week_key();
  RETURN jsonb_build_object(
    'inClan', true,
    'role', v_role,
    'clan', public.clan_public(c),
    'me', (SELECT jsonb_build_object('contribution', contribution, 'clanPoints', clan_points, 'role', role) FROM public.clan_members WHERE user_id = v_uid),
    'members', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'userId', m.user_id, 'role', m.role, 'contribution', m.contribution,
        'name', COALESCE(g.display_name, g.first_name, g.username, 'Player'),
        'username', g.username, 'avatar', g.avatar_url,
        'trophies', g.pvp_trophies, 'power', public.clan_player_power(m.user_id)::bigint,
        'lastActive', g.last_seen_at, 'isMe', m.user_id = v_uid)
        ORDER BY public.clan_role_rank(m.role) DESC, m.contribution DESC)
      FROM public.clan_members m JOIN public.game_players g ON g.id = m.user_id WHERE m.clan_id = v_clan), '[]'::jsonb),
    'requests', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', r.id, 'userId', r.user_id,
        'name', COALESCE(g.display_name, g.first_name, g.username,'Player'), 'avatar', g.avatar_url, 'trophies', g.pvp_trophies))
      FROM public.clan_join_requests r JOIN public.game_players g ON g.id = r.user_id
      WHERE r.clan_id = v_clan AND r.status='pending'), '[]'::jsonb),
    'missions', COALESCE((SELECT jsonb_agg(jsonb_build_object('code', m.code, 'title', m.title, 'target', m.target,
        'rewardPoints', m.reward_points,
        'progress', COALESCE((SELECT p.progress FROM public.clan_mission_progress p WHERE p.clan_id=v_clan AND p.mission_code=m.code AND p.week_key=v_week),0),
        'completed', COALESCE((SELECT p.completed FROM public.clan_mission_progress p WHERE p.clan_id=v_clan AND p.mission_code=m.code AND p.week_key=v_week),false)))
      FROM public.clan_missions m WHERE m.active), '[]'::jsonb),
    'boss', (SELECT jsonb_build_object('id', b.id, 'name', b.name, 'maxHealth', b.max_health, 'currentHealth', b.current_health,
        'status', b.status, 'endsAt', b.ends_at, 'rewardPoints', b.reward_points,
        'myDamage', COALESCE((SELECT damage FROM public.clan_boss_participants WHERE cycle_id=b.id AND user_id=v_uid),0),
        'top', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', COALESCE(g.display_name,g.first_name,'Player'),'avatar',g.avatar_url,'damage',p.damage) ORDER BY p.damage DESC)
          FROM public.clan_boss_participants p JOIN public.game_players g ON g.id=p.user_id WHERE p.cycle_id=b.id),'[]'::jsonb))
      FROM public.clan_boss_cycles b WHERE b.clan_id=v_clan AND b.status='active' ORDER BY b.started_at DESC LIMIT 1),
    'ranking', COALESCE((SELECT jsonb_agg(public.clan_public(x)) FROM (SELECT * FROM public.clans WHERE NOT suspended ORDER BY level DESC, xp DESC LIMIT 20) x), '[]'::jsonb)
  );
END; $$;

CREATE OR REPLACE FUNCTION public.search_clans(p_telegram_id bigint, p_query text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE q text;
BEGIN
  PERFORM public.clan_resolve_user(p_telegram_id);
  q := '%' || lower(COALESCE(p_query,'')) || '%';
  RETURN COALESCE((SELECT jsonb_agg(public.clan_public(x)) FROM (
    SELECT * FROM public.clans WHERE NOT suspended AND (lower(name) LIKE q OR lower(tag) LIKE q)
    ORDER BY level DESC, xp DESC LIMIT 30) x), '[]'::jsonb);
END; $$;

CREATE OR REPLACE FUNCTION public.create_clan(p_telegram_id bigint, p_name text, p_tag text, p_description text,
  p_join_type text, p_min_trophies integer, p_emblem jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_cost numeric; v_bal numeric; c public.clans%rowtype; v_name text; v_tag text;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('clan:'||v_uid::text, 0));
  IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = v_uid) THEN RAISE EXCEPTION 'ALREADY_IN_CLAN'; END IF;
  v_name := btrim(COALESCE(p_name,''));
  v_tag := upper(btrim(COALESCE(p_tag,'')));
  IF length(v_name) < 3 OR length(v_name) > 24 THEN RAISE EXCEPTION 'INVALID_CLAN_NAME'; END IF;
  IF v_tag !~ '^[A-Z0-9]{2,5}$' THEN RAISE EXCEPTION 'INVALID_CLAN_TAG'; END IF;
  IF EXISTS (SELECT 1 FROM public.clans WHERE lower(name) = lower(v_name)) THEN RAISE EXCEPTION 'CLAN_NAME_TAKEN'; END IF;
  IF EXISTS (SELECT 1 FROM public.clans WHERE upper(tag) = v_tag) THEN RAISE EXCEPTION 'CLAN_TAG_TAKEN'; END IF;
  IF COALESCE(p_join_type,'open') NOT IN ('open','approval','closed') THEN RAISE EXCEPTION 'INVALID_JOIN_TYPE'; END IF;

  v_cost := COALESCE((SELECT value::text::numeric FROM public.game_settings WHERE key='clan_create_cost_fc'), 100000);
  SELECT forge_coins INTO v_bal FROM public.game_players WHERE id = v_uid FOR UPDATE;
  IF COALESCE(v_bal,0) < v_cost THEN RAISE EXCEPTION 'INSUFFICIENT_FC'; END IF;

  INSERT INTO public.clans(name, tag, description, leader_user_id, join_type, minimum_trophies, member_limit, emblem_config)
  VALUES (v_name, v_tag, COALESCE(btrim(p_description),''), v_uid, COALESCE(p_join_type,'open'), GREATEST(0, COALESCE(p_min_trophies,0)),
          public.clan_member_limit(1), COALESCE(p_emblem, '{}'::jsonb))
  RETURNING * INTO c;

  INSERT INTO public.clan_members(clan_id, user_id, role) VALUES (c.id, v_uid, 'leader');

  UPDATE public.game_players SET forge_coins = forge_coins - v_cost, updated_at = now() WHERE id = v_uid;
  INSERT INTO public.wallet_ledger(user_id, entry_type, amount, balance_before, balance_after, reference_id, metadata)
  VALUES (v_uid, 'clan_create', -v_cost, v_bal, v_bal - v_cost, 'clan:'||c.id::text, jsonb_build_object('clanId', c.id, 'name', c.name));

  INSERT INTO public.clan_boss_cycles(clan_id) VALUES (c.id);
  RETURN jsonb_build_object('status','created','clan', public.clan_public(c));
END; $$;

CREATE OR REPLACE FUNCTION public.join_clan(p_telegram_id bigint, p_clan_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; c public.clans%rowtype; v_count integer; v_trophies integer;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('clan:'||p_clan_id::text, 0));
  IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = v_uid) THEN RAISE EXCEPTION 'ALREADY_IN_CLAN'; END IF;
  SELECT * INTO c FROM public.clans WHERE id = p_clan_id AND NOT suspended;
  IF c.id IS NULL THEN RAISE EXCEPTION 'CLAN_NOT_FOUND'; END IF;
  SELECT pvp_trophies INTO v_trophies FROM public.game_players WHERE id = v_uid;
  IF COALESCE(v_trophies,0) < c.minimum_trophies THEN RAISE EXCEPTION 'TROPHIES_TOO_LOW'; END IF;
  SELECT count(*) INTO v_count FROM public.clan_members WHERE clan_id = c.id;
  IF v_count >= c.member_limit THEN RAISE EXCEPTION 'CLAN_FULL'; END IF;
  IF c.join_type = 'closed' THEN RAISE EXCEPTION 'CLAN_CLOSED'; END IF;
  IF c.join_type = 'approval' THEN
    INSERT INTO public.clan_join_requests(clan_id, user_id) VALUES (c.id, v_uid)
    ON CONFLICT (clan_id, user_id) DO UPDATE SET status='pending', created_at=now();
    RETURN jsonb_build_object('status','requested');
  END IF;
  INSERT INTO public.clan_members(clan_id, user_id, role) VALUES (c.id, v_uid, 'member');
  RETURN jsonb_build_object('status','joined','clan', public.clan_public(c));
END; $$;

CREATE OR REPLACE FUNCTION public.leave_clan(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; v_role text; v_next uuid;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  DELETE FROM public.clan_members WHERE user_id = v_uid;
  IF v_role = 'leader' THEN
    SELECT user_id INTO v_next FROM public.clan_members WHERE clan_id = v_clan
     ORDER BY public.clan_role_rank(role) DESC, contribution DESC LIMIT 1;
    IF v_next IS NULL THEN
      DELETE FROM public.clans WHERE id = v_clan;
      RETURN jsonb_build_object('status','disbanded');
    END IF;
    UPDATE public.clan_members SET role='leader' WHERE user_id = v_next;
    UPDATE public.clans SET leader_user_id = v_next, updated_at = now() WHERE id = v_clan;
  END IF;
  RETURN jsonb_build_object('status','left');
END; $$;

CREATE OR REPLACE FUNCTION public.clan_manage(p_telegram_id bigint, p_action text, p_target uuid DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; v_role text; v_trole text; v_count integer; c public.clans%rowtype;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  SELECT * INTO c FROM public.clans WHERE id = v_clan;

  IF p_action = 'edit' THEN
    IF public.clan_role_rank(v_role) < 3 THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clans SET
      description = COALESCE(NULLIF(btrim(p_payload->>'description'),''), description),
      join_type = COALESCE(NULLIF(p_payload->>'joinType',''), join_type),
      minimum_trophies = COALESCE((p_payload->>'minimumTrophies')::int, minimum_trophies),
      emblem_config = COALESCE(p_payload->'emblem', emblem_config),
      updated_at = now()
     WHERE id = v_clan;
    RETURN jsonb_build_object('status','updated');
  END IF;

  IF p_target IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;
  SELECT role INTO v_trole FROM public.clan_members WHERE user_id = p_target AND clan_id = v_clan;

  IF p_action IN ('accept','reject') THEN
    IF public.clan_role_rank(v_role) < 2 THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    IF p_action = 'reject' THEN
      UPDATE public.clan_join_requests SET status='rejected' WHERE clan_id=v_clan AND user_id=p_target;
      RETURN jsonb_build_object('status','rejected');
    END IF;
    SELECT count(*) INTO v_count FROM public.clan_members WHERE clan_id = v_clan;
    IF v_count >= c.member_limit THEN RAISE EXCEPTION 'CLAN_FULL'; END IF;
    IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = p_target) THEN RAISE EXCEPTION 'ALREADY_IN_CLAN'; END IF;
    INSERT INTO public.clan_members(clan_id, user_id, role) VALUES (v_clan, p_target, 'member');
    UPDATE public.clan_join_requests SET status='accepted' WHERE clan_id=v_clan AND user_id=p_target;
    RETURN jsonb_build_object('status','accepted');
  END IF;

  IF v_trole IS NULL THEN RAISE EXCEPTION 'MEMBER_NOT_FOUND'; END IF;

  IF p_action = 'kick' THEN
    IF public.clan_role_rank(v_role) < 3 OR public.clan_role_rank(v_trole) >= public.clan_role_rank(v_role) THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    DELETE FROM public.clan_members WHERE user_id = p_target AND clan_id = v_clan;
    RETURN jsonb_build_object('status','kicked');
  ELSIF p_action IN ('promote','demote') THEN
    IF v_role <> 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    IF v_trole = 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clan_members SET role = CASE
        WHEN p_action='promote' THEN CASE v_trole WHEN 'member' THEN 'officer' WHEN 'officer' THEN 'co-leader' ELSE 'co-leader' END
        ELSE CASE v_trole WHEN 'co-leader' THEN 'officer' WHEN 'officer' THEN 'member' ELSE 'member' END END,
      updated_at = now()
     WHERE user_id = p_target AND clan_id = v_clan;
    RETURN jsonb_build_object('status','role_changed');
  ELSIF p_action = 'transfer' THEN
    IF v_role <> 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clan_members SET role='leader' WHERE user_id = p_target AND clan_id = v_clan;
    UPDATE public.clan_members SET role='co-leader' WHERE user_id = v_uid AND clan_id = v_clan;
    UPDATE public.clans SET leader_user_id = p_target, updated_at = now() WHERE id = v_clan;
    RETURN jsonb_build_object('status','transferred');
  END IF;
  RAISE EXCEPTION 'INVALID_ACTION';
END; $$;

CREATE OR REPLACE FUNCTION public.clan_chat(p_telegram_id bigint, p_action text DEFAULT 'list', p_body text DEFAULT NULL, p_message_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; v_role text; g public.game_players%rowtype; v_recent integer; v_text text;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  SELECT * INTO g FROM public.game_players WHERE id = v_uid;

  IF p_action = 'send' THEN
    v_text := btrim(COALESCE(p_body,''));
    IF length(v_text) = 0 OR length(v_text) > 300 THEN RAISE EXCEPTION 'INVALID_MESSAGE'; END IF;
    SELECT count(*) INTO v_recent FROM public.clan_messages
     WHERE user_id = v_uid AND created_at > now() - interval '60 seconds';
    IF v_recent >= 10 THEN RAISE EXCEPTION 'CHAT_RATE_LIMIT'; END IF;
    INSERT INTO public.clan_messages(clan_id, user_id, author_name, author_avatar, body)
    VALUES (v_clan, v_uid, COALESCE(g.display_name, g.first_name, g.username, 'Player'), g.avatar_url, v_text);
  ELSIF p_action = 'delete' THEN
    IF public.clan_role_rank(v_role) < 2 THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clan_messages SET deleted = true WHERE id = p_message_id AND clan_id = v_clan;
  END IF;

  RETURN jsonb_build_object('messages', COALESCE((SELECT jsonb_agg(x ORDER BY x->>'createdAt') FROM (
    SELECT jsonb_build_object('id', m.id, 'name', m.author_name, 'avatar', m.author_avatar,
      'body', CASE WHEN m.deleted THEN '—' ELSE m.body END, 'createdAt', m.created_at,
      'isMe', m.user_id = v_uid) AS x
    FROM public.clan_messages m WHERE m.clan_id = v_clan ORDER BY m.created_at DESC LIMIT 60) s), '[]'::jsonb));
END; $$;

CREATE OR REPLACE FUNCTION public.clan_boss_attack(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; b public.clan_boss_cycles%rowtype; v_damage numeric; v_share numeric; r record;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('clanboss:'||v_clan::text, 0));
  SELECT * INTO b FROM public.clan_boss_cycles WHERE clan_id = v_clan AND status='active' ORDER BY started_at DESC LIMIT 1 FOR UPDATE;
  IF b.id IS NULL THEN
    INSERT INTO public.clan_boss_cycles(clan_id) VALUES (v_clan) RETURNING * INTO b;
  END IF;
  IF b.current_health <= 0 THEN RAISE EXCEPTION 'CLAN_BOSS_DEFEATED'; END IF;
  IF EXISTS (SELECT 1 FROM public.clan_boss_participants WHERE cycle_id=b.id AND user_id=v_uid AND last_attack_at > now() - interval '30 minutes')
    THEN RAISE EXCEPTION 'CLAN_BOSS_COOLDOWN'; END IF;

  v_damage := GREATEST(100, public.clan_player_power(v_uid) * (0.8 + random() * 0.4));
  UPDATE public.clan_boss_cycles SET current_health = GREATEST(0, current_health - v_damage) WHERE id = b.id RETURNING * INTO b;
  INSERT INTO public.clan_boss_participants(cycle_id, user_id, damage, attacks, last_attack_at)
  VALUES (b.id, v_uid, v_damage, 1, now())
  ON CONFLICT (cycle_id, user_id) DO UPDATE SET damage = clan_boss_participants.damage + EXCLUDED.damage,
    attacks = clan_boss_participants.attacks + 1, last_attack_at = now();

  IF b.current_health <= 0 THEN
    UPDATE public.clan_boss_cycles SET status='defeated', finished_at = now() WHERE id = b.id;
    FOR r IN SELECT user_id, damage FROM public.clan_boss_participants WHERE cycle_id = b.id LOOP
      v_share := GREATEST(1, floor(b.reward_points * (r.damage / GREATEST(1, b.max_health))));
      UPDATE public.clan_members SET clan_points = clan_points + v_share WHERE user_id = r.user_id;
      INSERT INTO public.clan_points_ledger(clan_id, user_id, amount, reason) VALUES (v_clan, r.user_id, v_share, 'clan_boss');
    END LOOP;
    INSERT INTO public.clan_boss_cycles(clan_id) VALUES (v_clan);
  END IF;

  RETURN jsonb_build_object('status','ok','damage', floor(v_damage), 'currentHealth', b.current_health, 'maxHealth', b.max_health);
END; $$;

-- Clan shop: spends CLAN POINTS only. Never FC, never TON.
CREATE OR REPLACE FUNCTION public.clan_shop_buy(p_telegram_id bigint, p_item text, p_quantity integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; v_points bigint; v_cost bigint; v_qty integer; v_unit integer;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, clan_points INTO v_clan, v_points FROM public.clan_members WHERE user_id = v_uid FOR UPDATE;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  v_qty := GREATEST(1, LEAST(20, COALESCE(p_quantity,1)));
  v_unit := CASE p_item WHEN 'pet_food' THEN 40 WHEN 'pvp_ticket' THEN 120 WHEN 'fragments' THEN 60 WHEN 'hero_chest' THEN 800 ELSE 0 END;
  IF v_unit = 0 THEN RAISE EXCEPTION 'INVALID_ITEM'; END IF;
  v_cost := v_unit::bigint * v_qty;
  IF v_points < v_cost THEN RAISE EXCEPTION 'INSUFFICIENT_CLAN_POINTS'; END IF;

  UPDATE public.clan_members SET clan_points = clan_points - v_cost, updated_at = now() WHERE user_id = v_uid;
  INSERT INTO public.clan_points_ledger(clan_id, user_id, amount, reason) VALUES (v_clan, v_uid, -v_cost, 'shop:'||p_item);

  IF p_item = 'pvp_ticket' THEN
    UPDATE public.game_players SET pvp_tickets = pvp_tickets + v_qty WHERE id = v_uid;
  ELSIF p_item = 'pet_food' THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (v_uid, 'pet_food', 'pet_food', v_qty)
    ON CONFLICT (user_id, item_type, item_code) DO UPDATE SET quantity = player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
  ELSIF p_item = 'fragments' THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (v_uid, 'fragments', 'fragments', v_qty)
    ON CONFLICT (user_id, item_type, item_code) DO UPDATE SET quantity = player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
  ELSE
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (v_uid, 'hero_chest', 'common', v_qty)
    ON CONFLICT (user_id, item_type, item_code) DO UPDATE SET quantity = player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
  END IF;

  RETURN jsonb_build_object('status','purchased','item', p_item, 'quantity', v_qty, 'clanPoints', v_points - v_cost);
END; $$;

-- ============ ADMIN ============
CREATE OR REPLACE FUNCTION public.admin_clans(p_admin_id bigint, p_action text DEFAULT 'list', p_ref text DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c public.clans%rowtype;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  IF p_action IN ('list','ranking') THEN
    RETURN jsonb_build_object('clans', COALESCE((SELECT jsonb_agg(public.clan_public(x))
      FROM (SELECT * FROM public.clans ORDER BY level DESC, xp DESC LIMIT 30) x), '[]'::jsonb));
  END IF;

  IF p_action = 'search' THEN
    RETURN jsonb_build_object('clans', COALESCE((SELECT jsonb_agg(public.clan_public(x))
      FROM (SELECT * FROM public.clans WHERE lower(name) LIKE '%'||lower(COALESCE(p_ref,''))||'%'
        OR upper(tag) = upper(COALESCE(p_ref,'')) ORDER BY level DESC LIMIT 20) x), '[]'::jsonb));
  END IF;

  SELECT * INTO c FROM public.clans WHERE id::text = p_ref OR upper(tag) = upper(COALESCE(p_ref,''));
  IF c.id IS NULL THEN RAISE EXCEPTION 'CLAN_NOT_FOUND'; END IF;

  IF p_action = 'detail' THEN
    RETURN jsonb_build_object('clan', public.clan_public(c),
      'members', COALESCE((SELECT jsonb_agg(jsonb_build_object('userId', m.user_id, 'telegramId', g.telegram_id,
          'name', COALESCE(g.display_name,g.first_name,'Player'), 'role', m.role, 'contribution', m.contribution)
          ORDER BY public.clan_role_rank(m.role) DESC)
        FROM public.clan_members m JOIN public.game_players g ON g.id=m.user_id WHERE m.clan_id=c.id), '[]'::jsonb),
      'missions', COALESCE((SELECT jsonb_agg(jsonb_build_object('code', mission_code, 'progress', progress, 'completed', completed))
        FROM public.clan_mission_progress WHERE clan_id=c.id AND week_key = public.clan_week_key()), '[]'::jsonb),
      'boss', (SELECT jsonb_build_object('name', name, 'currentHealth', current_health, 'maxHealth', max_health, 'status', status)
        FROM public.clan_boss_cycles WHERE clan_id=c.id AND status='active' ORDER BY started_at DESC LIMIT 1),
      'audit', COALESCE((SELECT jsonb_agg(jsonb_build_object('source', source, 'xp', xp_amount, 'at', created_at))
        FROM (SELECT * FROM public.clan_xp_ledger WHERE clan_id=c.id ORDER BY created_at DESC LIMIT 15) a), '[]'::jsonb));
  ELSIF p_action = 'xp' THEN
    UPDATE public.clans SET xp = GREATEST(0, xp + COALESCE((p_payload->>'xp')::int,0)),
      level = GREATEST(1, COALESCE((p_payload->>'level')::int, level)), updated_at = now() WHERE id = c.id;
  ELSIF p_action = 'edit' THEN
    UPDATE public.clans SET
      name = COALESCE(NULLIF(btrim(p_payload->>'name'),''), name),
      tag = COALESCE(NULLIF(upper(btrim(p_payload->>'tag')),''), tag),
      member_limit = COALESCE((p_payload->>'memberLimit')::int, member_limit),
      join_type = COALESCE(NULLIF(p_payload->>'joinType',''), join_type),
      updated_at = now() WHERE id = c.id;
  ELSIF p_action = 'suspend' THEN
    UPDATE public.clans SET suspended = NOT suspended, updated_at = now() WHERE id = c.id;
  ELSIF p_action = 'delete' THEN
    DELETE FROM public.clans WHERE id = c.id;
  ELSIF p_action = 'boss' THEN
    UPDATE public.clan_boss_cycles SET status='ended', finished_at=now() WHERE clan_id=c.id AND status='active';
    INSERT INTO public.clan_boss_cycles(clan_id, max_health, current_health)
    VALUES (c.id, COALESCE((p_payload->>'hp')::numeric, 1000000), COALESCE((p_payload->>'hp')::numeric, 1000000));
  ELSE
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  PERFORM public.admin_log(p_admin_id, 'clans', p_action, c.id::text, p_payload);
  RETURN jsonb_build_object('status','ok','clan', public.clan_public((SELECT x FROM public.clans x WHERE x.id = c.id)));
END; $$;
