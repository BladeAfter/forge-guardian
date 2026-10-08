-- ============================================================
-- CLAN BOSS: PER-CLAN SETTINGS + CYCLE RESET + REALTIME REWARDS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.clan_boss_clan_settings (
  clan_id uuid PRIMARY KEY REFERENCES public.clans(id) ON DELETE CASCADE,
  fixed_hp numeric NOT NULL DEFAULT 0,
  reward_fc_pool numeric,
  rewards jsonb,
  bosses_per_day integer,
  duration_hours integer,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.clan_boss_clan_settings TO service_role;
ALTER TABLE public.clan_boss_clan_settings ENABLE ROW LEVEL SECURITY;
-- No anon/authenticated policies: admin-only data, reached through SECURITY DEFINER functions.

CREATE OR REPLACE FUNCTION public.clan_boss_clan_settings_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_clan_boss_clan_settings_touch ON public.clan_boss_clan_settings;
CREATE TRIGGER trg_clan_boss_clan_settings_touch
BEFORE UPDATE ON public.clan_boss_clan_settings
FOR EACH ROW EXECUTE FUNCTION public.clan_boss_clan_settings_touch();

-- Global defaults: 100M HP, 4 bosses/day (6h cycles), 1M FC pool.
ALTER TABLE public.clan_boss_scaling_config
  ADD COLUMN IF NOT EXISTS bosses_per_day integer NOT NULL DEFAULT 4;

UPDATE public.clan_boss_scaling_config
   SET fixed_hp = 100000000, bosses_per_day = 4, cycle_hours = 6, cycle_lock_hours = 0
 WHERE id = 1;

UPDATE public.clan_boss_config
   SET rewards = COALESCE(rewards, '{}'::jsonb) || jsonb_build_object('fcPool', 1000000),
       duration_hours = 6,
       updated_at = now()
 WHERE id = 1;

-- Seed MythBR with its own explicit values.
INSERT INTO public.clan_boss_clan_settings (clan_id, fixed_hp, reward_fc_pool, bosses_per_day, duration_hours)
SELECT id, 100000000, 1000000, 4, 6 FROM public.clans WHERE lower(name) = lower('MythBR') OR lower(tag) = lower('MythBR')
ON CONFLICT (clan_id) DO UPDATE
  SET fixed_hp = 100000000, reward_fc_pool = 1000000, bosses_per_day = 4, duration_hours = 6, updated_at = now();

-- ---------- per-clan effective settings
CREATE OR REPLACE FUNCTION public.clan_boss_clan_cfg(p_clan_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE sc public.clan_boss_scaling_config; cs public.clan_boss_clan_settings; cfg public.clan_boss_config;
        v_per_day integer; v_hours integer; v_hp numeric; v_pool numeric;
BEGIN
  sc := public.clan_boss_scaling_cfg();
  cfg := public.clan_boss_cfg();
  SELECT * INTO cs FROM public.clan_boss_clan_settings WHERE clan_id = p_clan_id;
  v_per_day := GREATEST(1, LEAST(48, COALESCE(cs.bosses_per_day, sc.bosses_per_day, 4)));
  v_hours := GREATEST(1, LEAST(168, COALESCE(cs.duration_hours, GREATEST(1, floor(24.0 / v_per_day)::int))));
  v_hp := COALESCE(NULLIF(cs.fixed_hp, 0), NULLIF(sc.fixed_hp, 0), 0);
  v_pool := COALESCE(cs.reward_fc_pool, (cfg.rewards->>'fcPool')::numeric, 0);
  RETURN jsonb_build_object(
    'clanId', p_clan_id,
    'bossesPerDay', v_per_day,
    'durationHours', v_hours,
    'fixedHp', v_hp,
    'rewardFcPool', v_pool,
    'rewards', COALESCE(cs.rewards, '{}'::jsonb),
    'hasOverride', cs.clan_id IS NOT NULL
  );
END $$;

-- ---------- fixed HP now respects the per-clan override
CREATE OR REPLACE FUNCTION public.clan_boss_apply_fixed_hp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_fixed numeric;
BEGIN
  v_fixed := (public.clan_boss_clan_cfg(NEW.clan_id)->>'fixedHp')::numeric;
  IF COALESCE(v_fixed, 0) > 0 THEN
    NEW.max_hp := round(v_fixed);
    NEW.current_hp := LEAST(COALESCE(NEW.current_hp, round(v_fixed)), round(v_fixed));
    NEW.min_damage_required := LEAST(COALESCE(NEW.min_damage_required, 0), round(v_fixed));
  END IF;
  RETURN NEW;
END $$;

-- ---------- cycle lock allows N bosses per rolling 24h, per clan
CREATE OR REPLACE FUNCTION public.clan_boss_cycle_lock(p_clan_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE sc public.clan_boss_scaling_config; c jsonb; v_per_day integer;
        v_started integer; v_oldest timestamptz; v_last timestamptz; v_lock numeric; v_next timestamptz;
BEGIN
  sc := public.clan_boss_scaling_cfg();
  IF NOT sc.cycle_lock_enabled THEN RETURN jsonb_build_object('locked', false); END IF;
  c := public.clan_boss_clan_cfg(p_clan_id);
  v_per_day := (c->>'bossesPerDay')::int;

  SELECT count(*), MIN(starts_at) INTO v_started, v_oldest
    FROM public.clan_boss_instances
   WHERE clan_id = p_clan_id AND starts_at > now() - interval '24 hours';

  IF v_started >= v_per_day THEN
    v_next := COALESCE(v_oldest, now()) + interval '24 hours';
    RETURN jsonb_build_object('locked', true, 'reason', 'daily_limit', 'bossesPerDay', v_per_day,
      'startedLast24h', v_started, 'nextBossAt', v_next,
      'secondsRemaining', GREATEST(0, ceil(EXTRACT(epoch FROM (v_next - now())))::int));
  END IF;

  v_lock := GREATEST(0, COALESCE(sc.cycle_lock_hours, 0));
  IF v_lock > 0 THEN
    SELECT MAX(COALESCE(finished_at, ends_at)) INTO v_last
      FROM public.clan_boss_instances WHERE clan_id = p_clan_id AND status <> 'active';
    IF v_last IS NOT NULL THEN
      v_next := v_last + make_interval(mins => round(v_lock * 60)::int);
      IF v_next > now() THEN
        RETURN jsonb_build_object('locked', true, 'reason', 'cooldown', 'bossesPerDay', v_per_day,
          'startedLast24h', v_started, 'nextBossAt', v_next,
          'secondsRemaining', GREATEST(0, ceil(EXTRACT(epoch FROM (v_next - now())))::int));
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('locked', false, 'bossesPerDay', v_per_day, 'startedLast24h', v_started);
END $$;

-- ---------- ensure: per-clan duration + rewards applied at spawn time
CREATE OR REPLACE FUNCTION public.clan_boss_ensure(p_clan_id uuid)
RETURNS clan_boss_instances LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_boss_config; sc public.clan_boss_scaling_config;
        b public.clan_boss_instances; tpl public.clan_boss_templates;
        v_cycle integer; v_level integer; v_rewards jsonb; s jsonb; v_hp numeric;
        v_key text; v_name text; v_dur integer; cc jsonb;
BEGIN
  cfg := public.clan_boss_cfg();
  sc := public.clan_boss_scaling_cfg();
  cc := public.clan_boss_clan_cfg(p_clan_id);

  SELECT * INTO b FROM public.clan_boss_instances
   WHERE clan_id = p_clan_id AND status = 'active' LIMIT 1;
  IF b.id IS NOT NULL AND b.ends_at <= now() THEN
    PERFORM public.clan_boss_settle(b.id, 'expired');
    b := NULL;
  END IF;
  IF b.id IS NOT NULL THEN RETURN b; END IF;

  IF (public.clan_boss_cycle_lock(p_clan_id)->>'locked')::boolean THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(MAX(cycle), 0) + 1 INTO v_cycle FROM public.clan_boss_instances WHERE clan_id = p_clan_id;
  SELECT GREATEST(1, level) INTO v_level FROM public.clans WHERE id = p_clan_id;
  tpl := public.clan_boss_template_for_cycle(v_cycle);
  s := public.clan_boss_scaling_persist(p_clan_id);
  v_hp := GREATEST(1, (s->>'effectiveHp')::numeric);
  IF COALESCE((cc->>'fixedHp')::numeric, 0) > 0 THEN
    v_hp := round((cc->>'fixedHp')::numeric);
  END IF;
  v_dur := GREATEST(1, COALESCE((cc->>'durationHours')::int, sc.cycle_hours, 24));
  v_key := COALESCE(tpl.boss_key, cfg.boss_key);
  v_name := COALESCE(tpl.name, cfg.boss_name);
  v_rewards := COALESCE(cfg.rewards, '{}'::jsonb);
  IF tpl.id IS NOT NULL THEN
    v_rewards := v_rewards || jsonb_build_object('fcPool', tpl.reward_fc, 'clanXp', tpl.reward_clan_xp,
      'bossKey', tpl.boss_key, 'theme', tpl.theme, 'baseDamage', tpl.base_damage);
  END IF;
  -- per-clan overrides win over template/global values
  v_rewards := v_rewards || COALESCE(cc->'rewards', '{}'::jsonb);
  IF COALESCE((cc->>'rewardFcPool')::numeric, 0) > 0 THEN
    v_rewards := v_rewards || jsonb_build_object('fcPool', (cc->>'rewardFcPool')::numeric);
  END IF;

  INSERT INTO public.clan_boss_instances(
    clan_id, boss_key, boss_name, cycle, level, max_hp, current_hp,
    min_damage_required, rewards_snapshot, starts_at, ends_at,
    base_hp, hp_multiplier, def_multiplier, atk_multiplier,
    boss_def, boss_atk, boss_power,
    clan_power_snapshot, active_members_snapshot, historical_dps_snapshot,
    scaling_snapshot, scaling_version, target_duration_seconds,
    cycle_started_at, cycle_ends_at)
  VALUES (p_clan_id, v_key, v_name, v_cycle, COALESCE(v_level, 1), v_hp, v_hp,
    round(v_hp * cfg.min_damage_pct / 100.0), v_rewards, now(),
    now() + make_interval(hours => v_dur),
    (s->>'baseHp')::numeric, (s->>'hpMultiplier')::numeric,
    (s->>'defMultiplier')::numeric, (s->>'atkMultiplier')::numeric,
    (s->>'effectiveDef')::numeric, (s->>'effectiveAtk')::numeric, (s->>'bossPower')::numeric,
    (s->'dps'->'metrics'->>'clanPower')::numeric,
    (s->'dps'->'metrics'->>'active24h')::int,
    (s->'dps'->>'dps')::numeric,
    s, (s->>'scalingVersion')::int, (s->>'targetDurationSeconds')::int,
    now(), now() + make_interval(hours => v_dur))
  RETURNING * INTO b;

  RETURN b;
END $$;

-- ---------- admin: per-clan config + cycle reset + live reward edit
CREATE OR REPLACE FUNCTION public.admin_clan_boss_clan(p_admin_id bigint, p_clan_id uuid,
  p_action text DEFAULT 'overview', p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b public.clan_boss_instances; v_num numeric; cc jsonb; v_clan record; v_reset integer := 0;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT id, name, tag, level, member_count INTO v_clan FROM public.clans WHERE id = p_clan_id;
  IF v_clan.id IS NULL THEN RETURN jsonb_build_object('error', 'clan_not_found'); END IF;

  IF p_action IN ('set_hp', 'set_reward', 'set_per_day', 'set_duration') THEN
    v_num := GREATEST(0, COALESCE((p_payload->>'value')::numeric, 0));
    INSERT INTO public.clan_boss_clan_settings(clan_id) VALUES (p_clan_id) ON CONFLICT (clan_id) DO NOTHING;
    UPDATE public.clan_boss_clan_settings SET
      fixed_hp = CASE WHEN p_action = 'set_hp' THEN v_num ELSE fixed_hp END,
      reward_fc_pool = CASE WHEN p_action = 'set_reward' THEN v_num ELSE reward_fc_pool END,
      bosses_per_day = CASE WHEN p_action = 'set_per_day' THEN GREATEST(1, LEAST(48, v_num))::int ELSE bosses_per_day END,
      duration_hours = CASE WHEN p_action = 'set_duration' THEN GREATEST(1, LEAST(168, v_num))::int ELSE duration_hours END,
      updated_at = now()
    WHERE clan_id = p_clan_id;

    -- Apply immediately to the running boss: no deploy, no waiting for next cycle.
    IF p_action = 'set_hp' AND v_num > 0 THEN
      UPDATE public.clan_boss_instances
         SET max_hp = round(v_num),
             current_hp = LEAST(round(v_num), GREATEST(1, round(current_hp * v_num / GREATEST(1, max_hp)))),
             min_damage_required = round(v_num * (SELECT min_damage_pct FROM public.clan_boss_config WHERE id = 1) / 100.0)
       WHERE clan_id = p_clan_id AND status = 'active';
    END IF;
    IF p_action = 'set_reward' THEN
      UPDATE public.clan_boss_instances
         SET rewards_snapshot = COALESCE(rewards_snapshot, '{}'::jsonb) || jsonb_build_object('fcPool', v_num)
       WHERE clan_id = p_clan_id AND status = 'active';
    END IF;
    IF p_action = 'set_duration' AND v_num > 0 THEN
      UPDATE public.clan_boss_instances
         SET ends_at = starts_at + make_interval(hours => v_num::int),
             cycle_ends_at = starts_at + make_interval(hours => v_num::int)
       WHERE clan_id = p_clan_id AND status = 'active';
    END IF;

  ELSIF p_action = 'set_rewards_json' THEN
    INSERT INTO public.clan_boss_clan_settings(clan_id) VALUES (p_clan_id) ON CONFLICT (clan_id) DO NOTHING;
    UPDATE public.clan_boss_clan_settings SET rewards = p_payload->'rewards', updated_at = now()
     WHERE clan_id = p_clan_id;
    UPDATE public.clan_boss_instances
       SET rewards_snapshot = COALESCE(rewards_snapshot, '{}'::jsonb) || COALESCE(p_payload->'rewards', '{}'::jsonb)
     WHERE clan_id = p_clan_id AND status = 'active';

  ELSIF p_action = 'clear' THEN
    DELETE FROM public.clan_boss_clan_settings WHERE clan_id = p_clan_id;

  ELSIF p_action = 'reset_cycle' THEN
    -- Closes the running boss without rewards, clears daily limit + locks and spawns a fresh one.
    SELECT * INTO b FROM public.clan_boss_instances WHERE clan_id = p_clan_id AND status = 'active' LIMIT 1;
    IF b.id IS NOT NULL THEN PERFORM public.clan_boss_settle(b.id, 'expired'); END IF;
    UPDATE public.clan_boss_instances
       SET starts_at = now() - interval '48 hours',
           cycle_started_at = now() - interval '48 hours',
           cycle_ends_at = now() - interval '24 hours',
           finished_at = COALESCE(finished_at, now() - interval '24 hours')
     WHERE clan_id = p_clan_id AND status <> 'active' AND starts_at > now() - interval '24 hours';
    v_reset := 1;
    DELETE FROM public.clan_boss_player_locks WHERE clan_id = p_clan_id;
    b := public.clan_boss_ensure(p_clan_id);
  END IF;

  PERFORM public.admin_log(p_admin_id, 'clan_boss_clan_' || p_action, 'clan_boss', p_clan_id::text,
    NULL::jsonb, p_payload, 'painel admin', '{}'::jsonb);

  cc := public.clan_boss_clan_cfg(p_clan_id);
  SELECT * INTO b FROM public.clan_boss_instances WHERE clan_id = p_clan_id AND status = 'active' LIMIT 1;
  RETURN jsonb_build_object(
    'clan', jsonb_build_object('id', v_clan.id, 'name', v_clan.name, 'tag', v_clan.tag,
      'level', v_clan.level, 'members', v_clan.member_count),
    'settings', cc,
    'reset', v_reset,
    'lock', public.clan_boss_cycle_lock(p_clan_id),
    'killedLast24h', COALESCE((SELECT count(*) FROM public.clan_boss_instances
       WHERE clan_id = p_clan_id AND status = 'defeated' AND finished_at > now() - interval '24 hours'), 0),
    'active', CASE WHEN b.id IS NULL THEN NULL ELSE jsonb_build_object(
      'cycle', b.cycle, 'maxHp', b.max_hp, 'currentHp', b.current_hp,
      'participants', b.participants, 'totalDamage', b.total_damage,
      'endsAt', b.ends_at, 'fcPool', (b.rewards_snapshot->>'fcPool')::numeric) END
  );
END $$;

REVOKE ALL ON FUNCTION public.clan_boss_clan_cfg(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_clan_boss_clan(bigint, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_boss_clan_cfg(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_clan_boss_clan(bigint, uuid, text, jsonb) TO service_role;

-- Apply the new 100M cap to bosses already running.
UPDATE public.clan_boss_instances i
   SET max_hp = 100000000,
       current_hp = LEAST(100000000, GREATEST(1, round(i.current_hp * 100000000 / GREATEST(1, i.max_hp)))),
       min_damage_required = round(100000000 * 0.01 / 100.0)
 WHERE i.status = 'active' AND i.max_hp > 100000000;
