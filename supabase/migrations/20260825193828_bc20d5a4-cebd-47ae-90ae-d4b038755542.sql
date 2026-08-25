CREATE OR REPLACE FUNCTION public.admin_clan_boss_clan(
  p_admin_id bigint,
  p_clan_id uuid,
  p_action text DEFAULT 'overview',
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  b public.clan_boss_instances;
  v_num numeric;
  cc jsonb;
  v_clan record;
  v_member_count integer := 0;
  v_reset integer := 0;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  SELECT c.id, c.name, c.tag, c.level
    INTO v_clan
    FROM public.clans c
   WHERE c.id = p_clan_id;

  IF v_clan.id IS NULL THEN
    RETURN jsonb_build_object('error', 'clan_not_found');
  END IF;

  SELECT COUNT(*)::integer
    INTO v_member_count
    FROM public.clan_members cm
   WHERE cm.clan_id = p_clan_id;

  IF p_action IN ('set_hp', 'set_reward', 'set_per_day', 'set_duration') THEN
    v_num := GREATEST(0, COALESCE((p_payload->>'value')::numeric, 0));

    INSERT INTO public.clan_boss_clan_settings(clan_id)
    VALUES (p_clan_id)
    ON CONFLICT (clan_id) DO NOTHING;

    UPDATE public.clan_boss_clan_settings
       SET fixed_hp = CASE WHEN p_action = 'set_hp' THEN v_num ELSE fixed_hp END,
           reward_fc_pool = CASE WHEN p_action = 'set_reward' THEN v_num ELSE reward_fc_pool END,
           bosses_per_day = CASE WHEN p_action = 'set_per_day' THEN GREATEST(1, LEAST(48, v_num))::int ELSE bosses_per_day END,
           duration_hours = CASE WHEN p_action = 'set_duration' THEN GREATEST(1, LEAST(168, v_num))::int ELSE duration_hours END,
           updated_at = now()
     WHERE clan_id = p_clan_id;

    IF p_action = 'set_hp' AND v_num > 0 THEN
      UPDATE public.clan_boss_instances
         SET max_hp = round(v_num),
             current_hp = LEAST(round(v_num), GREATEST(1, round(current_hp * v_num / GREATEST(1, max_hp)))),
             min_damage_required = round(v_num * (SELECT min_damage_pct FROM public.clan_boss_config WHERE id = 1) / 100.0)
       WHERE clan_id = p_clan_id
         AND status = 'active';
    END IF;

    IF p_action = 'set_reward' THEN
      UPDATE public.clan_boss_instances
         SET rewards_snapshot = COALESCE(rewards_snapshot, '{}'::jsonb) || jsonb_build_object('fcPool', v_num)
       WHERE clan_id = p_clan_id
         AND status = 'active';
    END IF;

    IF p_action = 'set_duration' AND v_num > 0 THEN
      UPDATE public.clan_boss_instances
         SET ends_at = starts_at + make_interval(hours => v_num::int),
             cycle_ends_at = starts_at + make_interval(hours => v_num::int)
       WHERE clan_id = p_clan_id
         AND status = 'active';
    END IF;

  ELSIF p_action = 'set_rewards_json' THEN
    INSERT INTO public.clan_boss_clan_settings(clan_id)
    VALUES (p_clan_id)
    ON CONFLICT (clan_id) DO NOTHING;

    UPDATE public.clan_boss_clan_settings
       SET rewards = p_payload->'rewards',
           updated_at = now()
     WHERE clan_id = p_clan_id;

    UPDATE public.clan_boss_instances
       SET rewards_snapshot = COALESCE(rewards_snapshot, '{}'::jsonb) || COALESCE(p_payload->'rewards', '{}'::jsonb)
     WHERE clan_id = p_clan_id
       AND status = 'active';

  ELSIF p_action = 'clear' THEN
    DELETE FROM public.clan_boss_clan_settings
     WHERE clan_id = p_clan_id;

  ELSIF p_action = 'reset_cycle' THEN
    SELECT *
      INTO b
      FROM public.clan_boss_instances
     WHERE clan_id = p_clan_id
       AND status = 'active'
     LIMIT 1;

    IF b.id IS NOT NULL THEN
      PERFORM public.clan_boss_settle(b.id, 'expired');
    END IF;

    UPDATE public.clan_boss_instances
       SET starts_at = now() - interval '48 hours',
           cycle_started_at = now() - interval '48 hours',
           cycle_ends_at = now() - interval '24 hours',
           finished_at = COALESCE(finished_at, now() - interval '24 hours')
     WHERE clan_id = p_clan_id
       AND status <> 'active'
       AND starts_at > now() - interval '24 hours';

    v_reset := 1;

    DELETE FROM public.clan_boss_player_locks
     WHERE clan_id = p_clan_id;

    b := public.clan_boss_ensure(p_clan_id);
  END IF;

  PERFORM public.admin_log(
    p_admin_id,
    'clan_boss_clan_' || p_action,
    'clan_boss',
    p_clan_id::text,
    NULL::jsonb,
    p_payload,
    'painel admin',
    '{}'::jsonb
  );

  cc := public.clan_boss_clan_cfg(p_clan_id);

  SELECT *
    INTO b
    FROM public.clan_boss_instances
   WHERE clan_id = p_clan_id
     AND status = 'active'
   LIMIT 1;

  RETURN jsonb_build_object(
    'clan', jsonb_build_object(
      'id', v_clan.id,
      'name', v_clan.name,
      'tag', v_clan.tag,
      'level', v_clan.level,
      'members', v_member_count
    ),
    'settings', cc,
    'reset', v_reset,
    'lock', public.clan_boss_cycle_lock(p_clan_id),
    'killedLast24h', COALESCE((
      SELECT count(*)
        FROM public.clan_boss_instances
       WHERE clan_id = p_clan_id
         AND status = 'defeated'
         AND finished_at > now() - interval '24 hours'
    ), 0),
    'active', CASE WHEN b.id IS NULL THEN NULL ELSE jsonb_build_object(
      'cycle', b.cycle,
      'maxHp', b.max_hp,
      'currentHp', b.current_hp,
      'participants', b.participants,
      'totalDamage', b.total_damage,
      'endsAt', b.ends_at,
      'fcPool', (b.rewards_snapshot->>'fcPool')::numeric
    ) END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_clan_boss_clan(bigint, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_clan_boss_clan(bigint, uuid, text, jsonb) TO service_role;