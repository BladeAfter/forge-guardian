-- ============================================================ CLAN BOSS (exclusive, isolated from Global Boss)
-- Nothing here reads or writes global_boss_* tables. Cooldowns, HP, damage,
-- ranking and rewards live in dedicated tables owned by each clan.

CREATE TABLE IF NOT EXISTS public.clan_boss_config (
  id smallint PRIMARY KEY DEFAULT 1,
  boss_key text NOT NULL DEFAULT 'abyssal_warlord',
  boss_name text NOT NULL DEFAULT 'Abyssal Warlord',
  base_hp numeric NOT NULL DEFAULT 1000000,
  hp_per_clan_level_pct numeric NOT NULL DEFAULT 25,
  hp_per_member_pct numeric NOT NULL DEFAULT 2,
  hp_per_cycle_pct numeric NOT NULL DEFAULT 5,
  duration_hours integer NOT NULL DEFAULT 24,
  cooldown_seconds integer NOT NULL DEFAULT 1800,
  clan_xp_reward integer NOT NULL DEFAULT 500,
  min_damage_pct numeric NOT NULL DEFAULT 1,
  rewards jsonb NOT NULL DEFAULT jsonb_build_object(
    'fcPool', 500000,
    'participant', jsonb_build_object('fc', 10000, 'fragments', 5, 'petFood', 3, 'chests', 1, 'pvpTickets', 1),
    'topDamage', jsonb_build_object('fc', 50000, 'fragments', 10, 'chests', 2, 'pvpTickets', 2)
  ),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT clan_boss_config_single CHECK (id = 1)
);
INSERT INTO public.clan_boss_config(id) VALUES (1) ON CONFLICT (id) DO NOTHING;
GRANT SELECT ON public.clan_boss_config TO anon, authenticated;
GRANT ALL ON public.clan_boss_config TO service_role;
ALTER TABLE public.clan_boss_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "clan boss config is public read" ON public.clan_boss_config FOR SELECT USING (true);

CREATE TABLE IF NOT EXISTS public.clan_boss_instances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  boss_key text NOT NULL DEFAULT 'abyssal_warlord',
  boss_name text NOT NULL DEFAULT 'Abyssal Warlord',
  cycle integer NOT NULL DEFAULT 1,
  level integer NOT NULL DEFAULT 1,
  max_hp numeric NOT NULL,
  current_hp numeric NOT NULL,
  status text NOT NULL DEFAULT 'active',
  total_damage numeric NOT NULL DEFAULT 0,
  attacks integer NOT NULL DEFAULT 0,
  participants integer NOT NULL DEFAULT 0,
  top_user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  clan_xp_awarded integer NOT NULL DEFAULT 0,
  min_damage_required numeric NOT NULL DEFAULT 0,
  rewards_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz NOT NULL,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT clan_boss_instances_status_check CHECK (status IN ('active','defeated','expired'))
);
CREATE UNIQUE INDEX IF NOT EXISTS clan_boss_instances_active_uidx ON public.clan_boss_instances(clan_id) WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS clan_boss_instances_cycle_uidx ON public.clan_boss_instances(clan_id, cycle);
CREATE INDEX IF NOT EXISTS clan_boss_instances_clan_idx ON public.clan_boss_instances(clan_id, created_at DESC);
GRANT SELECT ON public.clan_boss_instances TO anon, authenticated;
GRANT ALL ON public.clan_boss_instances TO service_role;
ALTER TABLE public.clan_boss_instances ENABLE ROW LEVEL SECURITY;
-- Read-only exposure (no telegram ids, no wallet data): required for the realtime HP bar.
CREATE POLICY "clan boss instances are readable" ON public.clan_boss_instances FOR SELECT USING (true);

CREATE TABLE IF NOT EXISTS public.clan_boss_damage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  instance_id uuid NOT NULL REFERENCES public.clan_boss_instances(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  damage numeric NOT NULL DEFAULT 0,
  attacks integer NOT NULL DEFAULT 0,
  last_attack_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT clan_boss_damage_unique UNIQUE (instance_id, user_id)
);
CREATE INDEX IF NOT EXISTS clan_boss_damage_rank_idx ON public.clan_boss_damage(instance_id, damage DESC);
CREATE INDEX IF NOT EXISTS clan_boss_damage_clan_idx ON public.clan_boss_damage(clan_id);
GRANT SELECT ON public.clan_boss_damage TO anon, authenticated;
GRANT ALL ON public.clan_boss_damage TO service_role;
ALTER TABLE public.clan_boss_damage ENABLE ROW LEVEL SECURITY;
CREATE POLICY "clan boss damage is readable" ON public.clan_boss_damage FOR SELECT USING (true);

CREATE TABLE IF NOT EXISTS public.clan_boss_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  instance_id uuid NOT NULL REFERENCES public.clan_boss_instances(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  damage numeric NOT NULL DEFAULT 0,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT clan_boss_claims_unique UNIQUE (instance_id, user_id)
);
GRANT SELECT ON public.clan_boss_claims TO authenticated;
GRANT ALL ON public.clan_boss_claims TO service_role;
ALTER TABLE public.clan_boss_claims ENABLE ROW LEVEL SECURITY;
CREATE POLICY "clan boss claims service only" ON public.clan_boss_claims FOR SELECT USING (false);

-- Realtime: HP + internal ranking update live for the clan members watching the screen.
DO $$ BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.clan_boss_instances; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.clan_boss_damage; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
ALTER TABLE public.clan_boss_instances REPLICA IDENTITY FULL;
ALTER TABLE public.clan_boss_damage REPLICA IDENTITY FULL;

-- ------------------------------------------------------------ helpers
CREATE OR REPLACE FUNCTION public.clan_boss_cfg()
RETURNS public.clan_boss_config LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT * FROM public.clan_boss_config WHERE id = 1
$$;

-- Moderate scaling: clan level, roster size and cycle count.
CREATE OR REPLACE FUNCTION public.clan_boss_scaled_hp(p_clan_id uuid, p_cycle integer)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg public.clan_boss_config; v_level integer; v_members integer;
BEGIN
  cfg := public.clan_boss_cfg();
  SELECT level INTO v_level FROM public.clans WHERE id = p_clan_id;
  SELECT count(*) INTO v_members FROM public.clan_members WHERE clan_id = p_clan_id;
  RETURN round(cfg.base_hp
    * (1 + (GREATEST(1, COALESCE(v_level,1)) - 1) * cfg.hp_per_clan_level_pct / 100.0)
    * (1 + GREATEST(0, COALESCE(v_members,1) - 1) * cfg.hp_per_member_pct / 100.0)
    * (1 + GREATEST(0, COALESCE(p_cycle,1) - 1) * cfg.hp_per_cycle_pct / 100.0));
END $$;

-- Delivers the configured in-game rewards (no TON involved, so the economy is untouched).
CREATE OR REPLACE FUNCTION public.clan_boss_deliver(p_user_id uuid, p_reward jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_fc numeric := COALESCE((p_reward->>'fc')::numeric, 0);
        v_frag integer := COALESCE((p_reward->>'fragments')::int, 0);
        v_food integer := COALESCE((p_reward->>'petFood')::int, 0);
        v_chest integer := COALESCE((p_reward->>'chests')::int, 0);
        v_tickets integer := COALESCE((p_reward->>'pvpTickets')::int, 0);
BEGIN
  IF v_fc > 0 OR v_tickets > 0 THEN
    UPDATE public.game_players
       SET forge_coins = forge_coins + GREATEST(0, v_fc),
           pvp_tickets = pvp_tickets + GREATEST(0, v_tickets),
           updated_at = now()
     WHERE id = p_user_id;
  END IF;
  IF v_frag > 0 THEN PERFORM public.add_universal_fragments(p_user_id, v_frag); END IF;
  IF v_food > 0 THEN
    UPDATE public.player_pet_food SET quantity = quantity + v_food, updated_at = now()
     WHERE user_id = p_user_id AND food_code = 'pet_ration';
    IF NOT found THEN
      INSERT INTO public.player_pet_food(user_id, food_code, quantity) VALUES (p_user_id, 'pet_ration', v_food)
      ON CONFLICT (user_id, food_code) DO UPDATE SET quantity = public.player_pet_food.quantity + v_food;
    END IF;
  END IF;
  IF v_chest > 0 THEN
    UPDATE public.player_inventory SET quantity = quantity + v_chest, updated_at = now()
     WHERE user_id = p_user_id AND item_type = 'hero_chest' AND item_code = 'rare_chest';
    IF NOT found THEN
      INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
      VALUES (p_user_id, 'hero_chest', 'rare_chest', v_chest);
    END IF;
  END IF;
END $$;

-- Closes an instance (defeated or expired), snapshots the ranking, grants clan XP once
-- and pays every member above the minimum damage requirement.
CREATE OR REPLACE FUNCTION public.clan_boss_settle(p_instance_id uuid, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg public.clan_boss_config; b public.clan_boss_instances; r record;
        v_min numeric; v_pool numeric; v_share numeric; v_reward jsonb; v_top uuid; v_xp integer;
BEGIN
  cfg := public.clan_boss_cfg();
  SELECT * INTO b FROM public.clan_boss_instances WHERE id = p_instance_id FOR UPDATE;
  IF b.id IS NULL OR b.status <> 'active' THEN RETURN; END IF;

  SELECT user_id INTO v_top FROM public.clan_boss_damage WHERE instance_id = b.id ORDER BY damage DESC LIMIT 1;
  v_min := GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0));
  v_pool := CASE WHEN p_status = 'defeated' THEN COALESCE((cfg.rewards->>'fcPool')::numeric, 0) ELSE 0 END;
  v_xp := CASE WHEN p_status = 'defeated' THEN GREATEST(0, cfg.clan_xp_reward) ELSE 0 END;

  UPDATE public.clan_boss_instances
     SET status = p_status, finished_at = now(), top_user_id = v_top,
         min_damage_required = v_min, clan_xp_awarded = v_xp,
         rewards_snapshot = cfg.rewards,
         total_damage = COALESCE((SELECT SUM(damage) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
         participants = COALESCE((SELECT count(*) FROM public.clan_boss_damage WHERE instance_id = b.id), 0)
   WHERE id = b.id;

  IF p_status = 'defeated' THEN
    FOR r IN SELECT user_id, damage FROM public.clan_boss_damage WHERE instance_id = b.id AND damage >= v_min LOOP
      v_share := CASE WHEN b.max_hp > 0 THEN r.damage / b.max_hp ELSE 0 END;
      v_reward := jsonb_build_object(
        'fc', floor(COALESCE((cfg.rewards->'participant'->>'fc')::numeric, 0) + v_pool * v_share),
        'fragments', COALESCE((cfg.rewards->'participant'->>'fragments')::int, 0),
        'petFood', COALESCE((cfg.rewards->'participant'->>'petFood')::int, 0),
        'chests', COALESCE((cfg.rewards->'participant'->>'chests')::int, 0),
        'pvpTickets', COALESCE((cfg.rewards->'participant'->>'pvpTickets')::int, 0)
      );
      IF r.user_id = v_top THEN
        v_reward := jsonb_build_object(
          'fc', COALESCE((v_reward->>'fc')::numeric,0) + COALESCE((cfg.rewards->'topDamage'->>'fc')::numeric, 0),
          'fragments', COALESCE((v_reward->>'fragments')::int,0) + COALESCE((cfg.rewards->'topDamage'->>'fragments')::int, 0),
          'petFood', COALESCE((v_reward->>'petFood')::int,0) + COALESCE((cfg.rewards->'topDamage'->>'petFood')::int, 0),
          'chests', COALESCE((v_reward->>'chests')::int,0) + COALESCE((cfg.rewards->'topDamage'->>'chests')::int, 0),
          'pvpTickets', COALESCE((v_reward->>'pvpTickets')::int,0) + COALESCE((cfg.rewards->'topDamage'->>'pvpTickets')::int, 0)
        );
      END IF;
      -- Idempotent: the unique (instance_id, user_id) guard makes double payouts impossible.
      INSERT INTO public.clan_boss_claims(instance_id, clan_id, user_id, damage, payload)
      VALUES (b.id, b.clan_id, r.user_id, r.damage, v_reward)
      ON CONFLICT (instance_id, user_id) DO NOTHING;
      IF found THEN
        PERFORM public.clan_boss_deliver(r.user_id, v_reward);
        -- Clan XP is granted once per finished cycle, never per individual hit.
        IF v_xp > 0 THEN PERFORM public.grant_clan_xp(r.user_id, 'clan_boss_cycle', v_xp); END IF;
      END IF;
    END LOOP;
  END IF;
END $$;

-- Guarantees an active instance for the clan; expires stale ones and opens the next cycle.
CREATE OR REPLACE FUNCTION public.clan_boss_ensure(p_clan_id uuid)
RETURNS public.clan_boss_instances LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg public.clan_boss_config; b public.clan_boss_instances; v_cycle integer; v_hp numeric; v_level integer;
BEGIN
  cfg := public.clan_boss_cfg();
  SELECT * INTO b FROM public.clan_boss_instances WHERE clan_id = p_clan_id AND status = 'active' LIMIT 1;
  IF b.id IS NOT NULL AND b.ends_at <= now() THEN
    PERFORM public.clan_boss_settle(b.id, 'expired');
    b := NULL;
  END IF;
  IF b.id IS NULL THEN
    SELECT COALESCE(MAX(cycle), 0) + 1 INTO v_cycle FROM public.clan_boss_instances WHERE clan_id = p_clan_id;
    SELECT GREATEST(1, level) INTO v_level FROM public.clans WHERE id = p_clan_id;
    v_hp := public.clan_boss_scaled_hp(p_clan_id, v_cycle);
    INSERT INTO public.clan_boss_instances(clan_id, boss_key, boss_name, cycle, level, max_hp, current_hp,
      min_damage_required, rewards_snapshot, starts_at, ends_at)
    VALUES (p_clan_id, cfg.boss_key, cfg.boss_name, v_cycle, COALESCE(v_level,1), v_hp, v_hp,
      round(v_hp * cfg.min_damage_pct / 100.0), cfg.rewards, now(), now() + make_interval(hours => GREATEST(1, cfg.duration_hours)))
    RETURNING * INTO b;
  END IF;
  RETURN b;
END $$;

-- ------------------------------------------------------------ player-facing state
CREATE OR REPLACE FUNCTION public.get_clan_boss(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg public.clan_boss_config; v_uid uuid; v_clan uuid; c public.clans%rowtype;
        b public.clan_boss_instances; d public.clan_boss_damage; v_rank integer; v_next timestamptz;
BEGIN
  cfg := public.clan_boss_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN
    RETURN jsonb_build_object('inClan', false, 'bossName', cfg.boss_name, 'bossKey', cfg.boss_key, 'serverTime', now());
  END IF;
  SELECT * INTO c FROM public.clans WHERE id = v_clan;
  b := public.clan_boss_ensure(v_clan);
  SELECT * INTO d FROM public.clan_boss_damage WHERE instance_id = b.id AND user_id = v_uid;
  SELECT count(*) + 1 INTO v_rank FROM public.clan_boss_damage
   WHERE instance_id = b.id AND damage > COALESCE(d.damage, 0);
  v_next := COALESCE(d.last_attack_at, to_timestamp(0)) + make_interval(secs => GREATEST(1, cfg.cooldown_seconds));

  RETURN jsonb_build_object(
    'inClan', true,
    'clan', jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'level', c.level, 'emblem', c.emblem_config),
    'boss', jsonb_build_object(
      'id', b.id, 'key', b.boss_key, 'name', b.boss_name, 'cycle', b.cycle, 'level', b.level,
      'maxHp', b.max_hp, 'currentHp', b.current_hp, 'status', b.status,
      'startsAt', b.starts_at, 'endsAt', b.ends_at,
      'clanDamage', COALESCE((SELECT SUM(damage) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'attacks', COALESCE((SELECT SUM(attacks) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'participants', COALESCE((SELECT count(*) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'minDamageForRewards', GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0)),
      'clanXpReward', cfg.clan_xp_reward,
      'cooldownSeconds', cfg.cooldown_seconds
    ),
    'me', jsonb_build_object(
      'damage', COALESCE(d.damage, 0), 'attacks', COALESCE(d.attacks, 0),
      'rank', CASE WHEN COALESCE(d.damage,0) > 0 THEN v_rank ELSE NULL END,
      'nextAttackAt', CASE WHEN d.last_attack_at IS NULL THEN NULL ELSE v_next END,
      'canAttack', b.status = 'active' AND b.current_hp > 0 AND (d.last_attack_at IS NULL OR v_next <= now()),
      'eligibleForRewards', COALESCE(d.damage,0) >= GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0)),
      'power', public.clan_player_power(v_uid)
    ),
    -- Internal ranking only: members of this clan and this instance, nobody else.
    'ranking', COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'damage')::numeric DESC) FROM (
        SELECT jsonb_build_object('userId', dd.user_id,
          'name', COALESCE(g.display_name, g.first_name, g.username, 'Player'),
          'username', g.username, 'avatar', g.avatar_url,
          'damage', dd.damage, 'attacks', dd.attacks, 'isMe', dd.user_id = v_uid) x
        FROM public.clan_boss_damage dd JOIN public.game_players g ON g.id = dd.user_id
        WHERE dd.instance_id = b.id ORDER BY dd.damage DESC LIMIT 50) s), '[]'::jsonb),
    'rewards', cfg.rewards,
    'history', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'cycle', h.cycle, 'status', h.status, 'maxHp', h.max_hp, 'totalDamage', h.total_damage,
        'clanXp', h.clan_xp_awarded, 'finishedAt', h.finished_at,
        'topName', COALESCE(tg.display_name, tg.username, NULL)) ORDER BY h.cycle DESC)
      FROM public.clan_boss_instances h LEFT JOIN public.game_players tg ON tg.id = h.top_user_id
      WHERE h.clan_id = v_clan AND h.status <> 'active'), '[]'::jsonb),
    'serverTime', now()
  );
END $$;

-- ------------------------------------------------------------ attack (transactional, clan-scoped)
CREATE OR REPLACE FUNCTION public.clan_boss_strike(p_telegram_id bigint, p_instance_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg public.clan_boss_config; v_uid uuid; v_clan uuid; b public.clan_boss_instances;
        v_last timestamptz; v_damage numeric; v_power numeric; v_bonus numeric; v_crit boolean := false; v_defeated boolean := false;
BEGIN
  cfg := public.clan_boss_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('clanbossv2:'||v_clan::text, 0));
  b := public.clan_boss_ensure(v_clan);

  -- Cross-clan protection: an id coming from the client can never target another clan's boss.
  IF p_instance_id IS NOT NULL AND p_instance_id <> b.id THEN
    IF EXISTS (SELECT 1 FROM public.clan_boss_instances WHERE id = p_instance_id AND clan_id <> v_clan)
      THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
    RAISE EXCEPTION 'CLAN_BOSS_STALE';
  END IF;

  SELECT * INTO b FROM public.clan_boss_instances WHERE id = b.id FOR UPDATE;
  IF b.clan_id <> v_clan THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
  IF b.status <> 'active' OR b.current_hp <= 0 THEN RAISE EXCEPTION 'CLAN_BOSS_DEFEATED'; END IF;
  IF b.ends_at <= now() THEN RAISE EXCEPTION 'CLAN_BOSS_EXPIRED'; END IF;

  SELECT last_attack_at INTO v_last FROM public.clan_boss_damage WHERE instance_id = b.id AND user_id = v_uid;
  IF v_last IS NOT NULL AND v_last > now() - make_interval(secs => GREATEST(1, cfg.cooldown_seconds)) THEN
    RAISE EXCEPTION 'CLAN_BOSS_COOLDOWN';
  END IF;

  v_power := GREATEST(1, public.clan_player_power(v_uid));
  v_bonus := COALESCE((public.get_pet_bonuses(v_uid)->>'boss_damage_percent')::numeric, 0)
           + COALESCE((public.get_pet_bonuses(v_uid)->>'team_attack_percent')::numeric, 0);
  v_damage := GREATEST(100, round(v_power * (0.85 + random() * 0.3) * (1 + v_bonus / 100.0)));
  IF random() < LEAST(0.35, COALESCE((public.get_pet_bonuses(v_uid)->>'critical_chance_percent')::numeric, 0) / 100.0) THEN
    v_crit := true;
    v_damage := round(v_damage * (1.5 + COALESCE((public.get_pet_bonuses(v_uid)->>'critical_damage_percent')::numeric, 0) / 100.0));
  END IF;
  v_damage := LEAST(v_damage, b.current_hp);

  UPDATE public.clan_boss_instances
     SET current_hp = GREATEST(0, current_hp - v_damage),
         total_damage = total_damage + v_damage,
         attacks = attacks + 1
   WHERE id = b.id RETURNING * INTO b;

  INSERT INTO public.clan_boss_damage(instance_id, clan_id, user_id, damage, attacks, last_attack_at)
  VALUES (b.id, v_clan, v_uid, v_damage, 1, now())
  ON CONFLICT (instance_id, user_id) DO UPDATE
    SET damage = public.clan_boss_damage.damage + EXCLUDED.damage,
        attacks = public.clan_boss_damage.attacks + 1,
        last_attack_at = now();

  UPDATE public.clan_boss_instances
     SET participants = COALESCE((SELECT count(*) FROM public.clan_boss_damage WHERE instance_id = b.id), 0)
   WHERE id = b.id;

  IF b.current_hp <= 0 THEN
    v_defeated := true;
    PERFORM public.clan_boss_settle(b.id, 'defeated');
    PERFORM public.clan_boss_ensure(v_clan);
  END IF;

  PERFORM public.record_clan_mission_progress(v_uid, 'clan_boss_damage', v_damage::bigint);

  RETURN jsonb_build_object('status','ok', 'damage', v_damage, 'critical', v_crit,
    'currentHp', GREATEST(0, b.current_hp), 'maxHp', b.max_hp, 'defeated', v_defeated,
    'nextAttackAt', now() + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)));
END $$;

-- ------------------------------------------------------------ admin
CREATE OR REPLACE FUNCTION public.admin_clan_boss(p_admin_id bigint, p_action text DEFAULT 'overview',
  p_ref text DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg public.clan_boss_config; v_clan uuid; b public.clan_boss_instances; v_num numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_action = 'set' THEN
    v_num := COALESCE((p_payload->>'value')::numeric, 0);
    UPDATE public.clan_boss_config SET
      base_hp = CASE WHEN p_ref='base_hp' THEN GREATEST(1000, v_num) ELSE base_hp END,
      hp_per_clan_level_pct = CASE WHEN p_ref='hp_per_clan_level_pct' THEN LEAST(200, GREATEST(0, v_num)) ELSE hp_per_clan_level_pct END,
      hp_per_member_pct = CASE WHEN p_ref='hp_per_member_pct' THEN LEAST(50, GREATEST(0, v_num)) ELSE hp_per_member_pct END,
      hp_per_cycle_pct = CASE WHEN p_ref='hp_per_cycle_pct' THEN LEAST(100, GREATEST(0, v_num)) ELSE hp_per_cycle_pct END,
      duration_hours = CASE WHEN p_ref='duration_hours' THEN LEAST(720, GREATEST(1, v_num))::int ELSE duration_hours END,
      cooldown_seconds = CASE WHEN p_ref='cooldown_seconds' THEN LEAST(86400, GREATEST(10, v_num))::int ELSE cooldown_seconds END,
      clan_xp_reward = CASE WHEN p_ref='clan_xp_reward' THEN LEAST(100000, GREATEST(0, v_num))::int ELSE clan_xp_reward END,
      min_damage_pct = CASE WHEN p_ref='min_damage_pct' THEN LEAST(50, GREATEST(0, v_num)) ELSE min_damage_pct END,
      boss_name = CASE WHEN p_ref='boss_name' THEN COALESCE(NULLIF(p_payload->>'text',''), boss_name) ELSE boss_name END,
      rewards = CASE WHEN p_ref='rewards' THEN COALESCE(p_payload->'rewards', rewards) ELSE rewards END,
      updated_at = now()
    WHERE id = 1;
    PERFORM public.admin_log(p_admin_id, 'clan_boss_config', p_ref, p_payload);
  ELSIF p_action = 'force_start' THEN
    v_clan := NULLIF(p_ref,'')::uuid;
    SELECT * INTO b FROM public.clan_boss_instances WHERE clan_id = v_clan AND status='active' LIMIT 1;
    IF b.id IS NOT NULL THEN PERFORM public.clan_boss_settle(b.id, 'expired'); END IF;
    b := public.clan_boss_ensure(v_clan);
    PERFORM public.admin_log(p_admin_id, 'clan_boss_force_start', p_ref, jsonb_build_object('cycle', b.cycle, 'maxHp', b.max_hp));
  ELSIF p_action = 'end_cycle' THEN
    v_clan := NULLIF(p_ref,'')::uuid;
    SELECT * INTO b FROM public.clan_boss_instances WHERE clan_id = v_clan AND status='active' LIMIT 1;
    IF b.id IS NOT NULL THEN
      PERFORM public.clan_boss_settle(b.id, CASE WHEN COALESCE((p_payload->>'reward')::boolean, false) THEN 'defeated' ELSE 'expired' END);
      PERFORM public.clan_boss_ensure(v_clan);
    END IF;
    PERFORM public.admin_log(p_admin_id, 'clan_boss_end_cycle', p_ref, p_payload);
  END IF;

  cfg := public.clan_boss_cfg();
  RETURN jsonb_build_object(
    'config', jsonb_build_object('bossName', cfg.boss_name, 'bossKey', cfg.boss_key, 'baseHp', cfg.base_hp,
      'hpPerClanLevelPct', cfg.hp_per_clan_level_pct, 'hpPerMemberPct', cfg.hp_per_member_pct,
      'hpPerCyclePct', cfg.hp_per_cycle_pct, 'durationHours', cfg.duration_hours,
      'cooldownSeconds', cfg.cooldown_seconds, 'clanXpReward', cfg.clan_xp_reward,
      'minDamagePct', cfg.min_damage_pct, 'rewards', cfg.rewards),
    'active', COALESCE((SELECT jsonb_agg(jsonb_build_object('clanId', c.id, 'clan', c.name, 'tag', c.tag,
        'cycle', i.cycle, 'level', i.level, 'maxHp', i.max_hp, 'currentHp', i.current_hp,
        'participants', i.participants, 'endsAt', i.ends_at) ORDER BY i.current_hp ASC)
      FROM public.clan_boss_instances i JOIN public.clans c ON c.id = i.clan_id WHERE i.status='active'), '[]'::jsonb),
    'audit', COALESCE((SELECT jsonb_agg(jsonb_build_object('clan', c.name, 'cycle', i.cycle, 'status', i.status,
        'totalDamage', i.total_damage, 'clanXp', i.clan_xp_awarded, 'finishedAt', i.finished_at,
        'top', COALESCE(g.display_name, g.username)) ORDER BY i.finished_at DESC)
      FROM (SELECT * FROM public.clan_boss_instances WHERE status <> 'active' ORDER BY finished_at DESC LIMIT 15) i
      JOIN public.clans c ON c.id = i.clan_id LEFT JOIN public.game_players g ON g.id = i.top_user_id), '[]'::jsonb)
  );
END $$;

REVOKE ALL ON FUNCTION public.clan_boss_cfg() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_boss_scaled_hp(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_boss_deliver(uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_boss_settle(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_boss_ensure(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_clan_boss(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_boss_strike(bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_clan_boss(bigint, text, text, jsonb) FROM PUBLIC, anon, authenticated;