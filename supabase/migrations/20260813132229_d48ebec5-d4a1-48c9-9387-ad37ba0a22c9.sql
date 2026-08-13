-- 1) Clan Boss Auto ATK preference — INDEPENDENT from the global boss toggle.
CREATE TABLE IF NOT EXISTS public.clan_boss_auto_attack (
  user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT true,
  last_auto_attack_at timestamptz,
  next_auto_attack_at timestamptz NOT NULL DEFAULT now(),
  attacks_total bigint NOT NULL DEFAULT 0,
  paused_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_boss_auto_attack TO service_role;
ALTER TABLE public.clan_boss_auto_attack ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_clan_auto_due ON public.clan_boss_auto_attack(next_auto_attack_at) WHERE enabled;

-- 2) Attack audit log (manual + auto), mirroring global_boss_attack_log.
CREATE TABLE IF NOT EXISTS public.clan_boss_attack_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  telegram_id bigint,
  clan_id uuid,
  clan_boss_id uuid,
  attack_type text NOT NULL CHECK (attack_type IN ('manual','season_pass_auto')),
  damage numeric NOT NULL DEFAULT 0,
  team_power numeric NOT NULL DEFAULT 0,
  pass_type text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_boss_attack_log TO service_role;
ALTER TABLE public.clan_boss_attack_log ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_cb_attack_log_user ON public.clan_boss_attack_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cb_attack_log_boss ON public.clan_boss_attack_log(clan_boss_id, created_at DESC);

-- 3) State json. Reuses global_boss_auto_pass_tier: the pass benefit is ONE
--    benefit (adventurer OR legendary), it just now covers two bosses.
CREATE OR REPLACE FUNCTION public.clan_boss_auto_attack_state_json(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a public.clan_boss_auto_attack%rowtype; cfg public.clan_boss_config;
        v_tier text; v_team boolean; v_clan uuid; v_boss boolean; v_reason text;
BEGIN
  IF p_user IS NULL THEN RETURN jsonb_build_object('eligible',false,'enabled',false,'active',false,'reason','no_pass'); END IF;
  cfg := public.clan_boss_cfg();
  INSERT INTO public.clan_boss_auto_attack(user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO a FROM public.clan_boss_auto_attack WHERE user_id = p_user;
  v_tier := public.global_boss_auto_pass_tier(p_user);
  v_team := public.clan_player_power(p_user) > 0;
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = p_user;
  v_boss := v_clan IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.clan_boss_instances
     WHERE clan_id = v_clan AND status = 'active' AND current_hp > 0 AND ends_at > now());
  v_reason := CASE WHEN v_tier IS NULL THEN 'no_pass' WHEN NOT a.enabled THEN 'disabled'
                   WHEN v_clan IS NULL THEN 'no_clan' WHEN NOT v_team THEN 'no_team'
                   WHEN NOT v_boss THEN 'no_boss' ELSE NULL END;
  RETURN jsonb_build_object(
    'eligible', v_tier IS NOT NULL, 'passTier', v_tier, 'enabled', a.enabled,
    'hasTeam', v_team, 'inClan', v_clan IS NOT NULL, 'bossActive', v_boss,
    'active', v_tier IS NOT NULL AND a.enabled AND v_team AND v_clan IS NOT NULL AND v_boss,
    'intervalSeconds', GREATEST(1, cfg.cooldown_seconds),
    'lastAttackAt', a.last_auto_attack_at, 'nextAttackAt', a.next_auto_attack_at,
    'attacksTotal', a.attacks_total, 'reason', v_reason);
END $$;
REVOKE ALL ON FUNCTION public.clan_boss_auto_attack_state_json(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_boss_auto_attack_state_json(uuid) TO postgres, service_role;

-- 4) Toggle RPC (persisted preference, independent from the global boss one).
CREATE OR REPLACE FUNCTION public.set_clan_boss_auto_attack(p_telegram_id bigint, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF public.global_boss_auto_pass_tier(u) IS NULL THEN RAISE EXCEPTION 'SEASON_PASS_REQUIRED'; END IF;
  INSERT INTO public.clan_boss_auto_attack(user_id, enabled, next_auto_attack_at)
    VALUES (u, coalesce(p_enabled,true), now())
  ON CONFLICT (user_id) DO UPDATE SET enabled = coalesce(p_enabled,true),
    next_auto_attack_at = CASE WHEN coalesce(p_enabled,true)
      THEN LEAST(public.clan_boss_auto_attack.next_auto_attack_at, now())
      ELSE public.clan_boss_auto_attack.next_auto_attack_at END,
    paused_reason = NULL, updated_at = now();
  RETURN public.clan_boss_auto_attack_state_json(u);
END $$;
REVOKE ALL ON FUNCTION public.set_clan_boss_auto_attack(bigint, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_clan_boss_auto_attack(bigint, boolean) TO postgres, service_role;

-- 5) The SAME attack function serves manual and automatic strikes. The damage
--    math, cooldown, locks, missions and ranking are untouched; only the audit
--    log + the auto-tick bookkeeping are added. The attack type is passed via a
--    transaction-local setting so the (bigint, uuid) signature stays unique.
CREATE OR REPLACE FUNCTION public.clan_boss_strike(p_telegram_id bigint, p_instance_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_boss_config; v_uid uuid; v_clan uuid; b public.clan_boss_instances;
        v_last timestamptz; v_damage numeric; v_base numeric; v_power numeric; v_bonus numeric; v_buffs jsonb;
        v_crit boolean := false; v_defeated boolean := false; v_type text;
BEGIN
  cfg := public.clan_boss_cfg();
  v_type := CASE WHEN coalesce(current_setting('mythreon.clan_attack_type', true), 'manual') = 'season_pass_auto'
                 THEN 'season_pass_auto' ELSE 'manual' END;
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('clanbossv2:'||v_clan::text, 0));
  b := public.clan_boss_ensure(v_clan);

  IF p_instance_id IS NOT NULL AND p_instance_id <> b.id THEN
    IF EXISTS (SELECT 1 FROM public.clan_boss_instances WHERE id = p_instance_id AND clan_id <> v_clan)
      THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
    RAISE EXCEPTION 'CLAN_BOSS_STALE';
  END IF;

  SELECT * INTO b FROM public.clan_boss_instances WHERE id = b.id FOR UPDATE;
  IF b.clan_id <> v_clan THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
  IF b.status <> 'active' OR b.current_hp <= 0 THEN RAISE EXCEPTION 'CLAN_BOSS_DEFEATED'; END IF;
  IF b.ends_at <= now() THEN RAISE EXCEPTION 'CLAN_BOSS_EXPIRED'; END IF;

  -- Single cooldown shared by manual and automatic attacks of THIS boss.
  SELECT last_attack_at INTO v_last FROM public.clan_boss_damage WHERE instance_id = b.id AND user_id = v_uid FOR UPDATE;
  IF v_last IS NOT NULL AND v_last > now() - make_interval(secs => GREATEST(1, cfg.cooldown_seconds)) THEN
    RAISE EXCEPTION 'CLAN_BOSS_COOLDOWN';
  END IF;

  v_buffs := COALESCE(public.get_pet_bonuses(v_uid), '{}'::jsonb);
  v_power := GREATEST(1, public.clan_player_power(v_uid));
  v_bonus := COALESCE((v_buffs->>'boss_damage_percent')::numeric, 0)
           + COALESCE((v_buffs->>'team_attack_percent')::numeric, 0);
  v_base := GREATEST(100, round(v_power * (0.85 + random() * 0.3)));
  v_damage := GREATEST(100, round(v_base * (1 + v_bonus / 100.0)));
  IF random() < LEAST(0.35, COALESCE((v_buffs->>'critical_chance_percent')::numeric, 0) / 100.0) THEN
    v_crit := true;
    v_damage := round(v_damage * (1.5 + COALESCE((v_buffs->>'critical_damage_percent')::numeric, 0) / 100.0));
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

  INSERT INTO public.clan_boss_attack_log(user_id, telegram_id, clan_id, clan_boss_id, attack_type, damage, team_power, pass_type)
  VALUES (v_uid, p_telegram_id, v_clan, b.id, v_type, v_damage, v_power, public.global_boss_auto_pass_tier(v_uid));

  -- Manual attacks push the automatic tick forward (shared clan boss cooldown).
  UPDATE public.clan_boss_auto_attack
     SET last_auto_attack_at = CASE WHEN v_type = 'season_pass_auto' THEN now() ELSE last_auto_attack_at END,
         next_auto_attack_at = now() + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)),
         attacks_total = attacks_total + CASE WHEN v_type = 'season_pass_auto' THEN 1 ELSE 0 END,
         paused_reason = NULL, updated_at = now()
   WHERE user_id = v_uid;

  IF b.current_hp <= 0 THEN
    v_defeated := true;
    PERFORM public.clan_boss_settle(b.id, 'defeated');
    PERFORM public.clan_boss_ensure(v_clan);
  END IF;

  PERFORM public.record_clan_mission_progress(v_uid, 'clan_boss_damage', v_damage::bigint);

  RETURN jsonb_build_object('status','ok', 'damage', v_damage, 'critical', v_crit,
    'currentHp', GREATEST(0, b.current_hp), 'maxHp', b.max_hp, 'defeated', v_defeated,
    'damageBeforePet', v_base, 'petBossDamagePercent', v_bonus, 'attackType', v_type,
    'nextAttackAt', now() + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)));
END $function$;

-- 6) Backend scheduler routine: offline Auto ATK for pass holders (clan boss).
--    Batched, advisory-locked and SKIP LOCKED, exactly like the global boss one.
CREATE OR REPLACE FUNCTION public.process_clan_boss_auto_attacks(p_limit int DEFAULT 500)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_boss_config; r record; v_tier text; v_count int := 0; v_paused int := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('clan_boss_auto_attacks')) THEN
    RETURN jsonb_build_object('processed', 0, 'skipped', 'locked');
  END IF;
  cfg := public.clan_boss_cfg();
  FOR r IN
    SELECT a.user_id, g.telegram_id, cm.clan_id
    FROM public.clan_boss_auto_attack a
    JOIN public.game_players g ON g.id = a.user_id
    LEFT JOIN public.clan_members cm ON cm.user_id = a.user_id
    WHERE a.enabled AND a.next_auto_attack_at <= now()
    ORDER BY a.next_auto_attack_at
    LIMIT GREATEST(1, LEAST(coalesce(p_limit, 500), 2000))
    FOR UPDATE OF a SKIP LOCKED
  LOOP
    -- Never trust the stored preference: the pass must still be valid NOW.
    v_tier := public.global_boss_auto_pass_tier(r.user_id);
    IF v_tier IS NULL OR r.clan_id IS NULL OR public.clan_player_power(r.user_id) <= 0
       OR NOT EXISTS (SELECT 1 FROM public.clan_boss_instances
                       WHERE clan_id = r.clan_id AND status = 'active' AND current_hp > 0 AND ends_at > now()) THEN
      UPDATE public.clan_boss_auto_attack
         SET next_auto_attack_at = now() + make_interval(secs => GREATEST(60, cfg.cooldown_seconds / 5)),
             paused_reason = CASE WHEN v_tier IS NULL THEN 'no_pass' WHEN r.clan_id IS NULL THEN 'no_clan'
                                  WHEN public.clan_player_power(r.user_id) <= 0 THEN 'no_team' ELSE 'no_boss' END,
             updated_at = now()
       WHERE user_id = r.user_id;
      v_paused := v_paused + 1;
      CONTINUE;
    END IF;
    BEGIN
      PERFORM set_config('mythreon.clan_attack_type', 'season_pass_auto', true);
      PERFORM public.clan_boss_strike(r.telegram_id, NULL);
      PERFORM set_config('mythreon.clan_attack_type', 'manual', true);
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('mythreon.clan_attack_type', 'manual', true);
      UPDATE public.clan_boss_auto_attack
         SET next_auto_attack_at = now() + make_interval(secs => GREATEST(60, cfg.cooldown_seconds / 5)),
             paused_reason = left(SQLERRM, 200), updated_at = now()
       WHERE user_id = r.user_id;
    END;
  END LOOP;
  RETURN jsonb_build_object('processed', v_count, 'paused', v_paused);
END $$;
REVOKE ALL ON FUNCTION public.process_clan_boss_auto_attacks(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_clan_boss_auto_attacks(int) TO postgres, service_role;

-- 7) Expose the clan boss auto attack state in the clan boss payload.
CREATE OR REPLACE FUNCTION public.get_clan_boss(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_boss_config; v_uid uuid; v_clan uuid; c public.clans%rowtype;
        b public.clan_boss_instances; d public.clan_boss_damage; v_rank integer; v_next timestamptz;
        tpl public.clan_boss_templates; v_total integer; v_last integer;
BEGIN
  cfg := public.clan_boss_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  SELECT count(*)::int, COALESCE(MAX(cycle_number),0) INTO v_total, v_last
    FROM public.clan_boss_templates WHERE enabled;
  IF v_clan IS NULL THEN
    RETURN jsonb_build_object('inClan', false, 'bossName', cfg.boss_name, 'bossKey', cfg.boss_key,
      'totalBosses', v_total, 'autoAttack', public.clan_boss_auto_attack_state_json(v_uid), 'serverTime', now());
  END IF;
  SELECT * INTO c FROM public.clans WHERE id = v_clan;
  b := public.clan_boss_ensure(v_clan);
  tpl := public.clan_boss_template_for_cycle(b.cycle);
  SELECT * INTO d FROM public.clan_boss_damage WHERE instance_id = b.id AND user_id = v_uid;
  SELECT count(*) + 1 INTO v_rank FROM public.clan_boss_damage
   WHERE instance_id = b.id AND damage > COALESCE(d.damage, 0);
  v_next := COALESCE(d.last_attack_at, to_timestamp(0)) + make_interval(secs => GREATEST(1, cfg.cooldown_seconds));

  RETURN jsonb_build_object(
    'inClan', true,
    'totalBosses', v_total,
    'autoAttack', public.clan_boss_auto_attack_state_json(v_uid),
    'clan', jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'level', c.level, 'emblem', c.emblem_config),
    'boss', jsonb_build_object(
      'id', b.id, 'key', b.boss_key, 'name', b.boss_name, 'cycle', b.cycle, 'level', b.level,
      'maxHp', b.max_hp, 'currentHp', b.current_hp, 'status', b.status,
      'startsAt', b.starts_at, 'endsAt', b.ends_at,
      'subtitle', COALESCE(tpl.subtitle, ''),
      'theme', COALESCE(tpl.theme, 'abyss'),
      'imageUrl', tpl.image_url,
      'backgroundUrl', tpl.background_url,
      'baseDamage', COALESCE(tpl.base_damage, 0),
      'rewardFc', COALESCE(tpl.reward_fc, 0),
      'bossNumber', COALESCE(tpl.cycle_number, b.cycle),
      'isFinal', COALESCE(tpl.cycle_number, 0) >= v_last,
      'clanDamage', COALESCE((SELECT SUM(damage) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'attacks', COALESCE((SELECT SUM(attacks) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'participants', COALESCE((SELECT count(*) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'minDamageForRewards', GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0)),
      'clanXpReward', COALESCE((b.rewards_snapshot->>'clanXp')::integer, cfg.clan_xp_reward),
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
    'ranking', COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'damage')::numeric DESC) FROM (
        SELECT jsonb_build_object('userId', dd.user_id,
          'name', COALESCE(g.display_name, g.first_name, g.username, 'Player'),
          'username', g.username, 'avatar', g.avatar_url,
          'damage', dd.damage, 'attacks', dd.attacks, 'isMe', dd.user_id = v_uid) x
        FROM public.clan_boss_damage dd JOIN public.game_players g ON g.id = dd.user_id
        WHERE dd.instance_id = b.id ORDER BY dd.damage DESC LIMIT 50) s), '[]'::jsonb),
    'rewards', COALESCE(b.rewards_snapshot, cfg.rewards),
    'history', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'cycle', h.cycle, 'status', h.status, 'maxHp', h.max_hp, 'totalDamage', h.total_damage,
        'bossName', h.boss_name, 'bossKey', h.boss_key,
        'clanXp', h.clan_xp_awarded, 'finishedAt', h.finished_at,
        'topName', COALESCE(tg.display_name, tg.username, NULL),
        'topDamage', (SELECT MAX(damage) FROM public.clan_boss_damage cd WHERE cd.instance_id = h.id)) ORDER BY h.cycle DESC)
      FROM public.clan_boss_instances h LEFT JOIN public.game_players tg ON tg.id = h.top_user_id
      WHERE h.clan_id = v_clan AND h.status <> 'active'), '[]'::jsonb),
    'serverTime', now()
  );
END $function$;