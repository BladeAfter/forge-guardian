-- 1) attack ledger: separate combat damage from HP damage
ALTER TABLE public.clan_raid_attacks
  ADD COLUMN IF NOT EXISTS combat_damage numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hp_damage_applied numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS boss_hp_before numeric,
  ADD COLUMN IF NOT EXISTS boss_hp_after numeric,
  ADD COLUMN IF NOT EXISTS daily_hp_remaining_before numeric,
  ADD COLUMN IF NOT EXISTS daily_hp_remaining_after numeric,
  ADD COLUMN IF NOT EXISTS attack_number integer;

UPDATE public.clan_raid_attacks
   SET combat_damage = GREATEST(COALESCE((payload->>'rawDamage')::numeric, 0), COALESCE(damage, 0)),
       hp_damage_applied = COALESCE(damage, 0)
 WHERE combat_damage = 0;

CREATE INDEX IF NOT EXISTS clan_raid_attacks_raid_user_idx
  ON public.clan_raid_attacks (raid_id, user_id);

ALTER TABLE public.clan_raid_participation
  ADD COLUMN IF NOT EXISTS combat_damage numeric NOT NULL DEFAULT 0;

UPDATE public.clan_raid_participation p
   SET combat_damage = s.total
  FROM (SELECT raid_id, user_id, sum(combat_damage) AS total
          FROM public.clan_raid_attacks GROUP BY raid_id, user_id) s
 WHERE s.raid_id = p.raid_id AND s.user_id = p.user_id AND p.combat_damage = 0;

ALTER TABLE public.clan_raid_cycles
  ADD COLUMN IF NOT EXISTS combat_damage numeric NOT NULL DEFAULT 0;

UPDATE public.clan_raid_cycles c
   SET combat_damage = COALESCE(s.total, 0)
  FROM (SELECT raid_id, sum(combat_damage) AS total FROM public.clan_raid_attacks GROUP BY raid_id) s
 WHERE s.raid_id = c.id AND c.combat_damage = 0;

-- 2) attack: full combat damage always ranked, HP capped by the daily gate
CREATE OR REPLACE FUNCTION public.clan_raid_attack(p_telegram_id bigint, p_key text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; r public.clan_raid_cycles;
        v_used integer; v_power numeric; v_combat numeric; v_hp_dmg numeric; v_buff numeric;
        c public.clan_weekly_cycles;
        v_floor numeric; v_day integer; v_catch numeric; v_existing numeric;
        v_unlock timestamptz; v_protected boolean; v_hp_floor numeric; v_first boolean := false;
        v_hp_before numeric; v_rem_before numeric; v_rem_after numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  IF NOT cfg.raid_enabled THEN RAISE EXCEPTION 'RAID_DISABLED'; END IF;

  -- idempotency: a retry never duplicates ranking, HP damage nor the attack charge
  IF p_key IS NOT NULL THEN
    SELECT combat_damage INTO v_existing FROM public.clan_raid_attacks
     WHERE user_id = v_uid AND idempotency_key = p_key LIMIT 1;
    IF v_existing IS NOT NULL THEN
      RETURN jsonb_build_object('status','duplicate','damage', v_existing, 'combatDamage', v_existing);
    END IF;
  END IF;

  PERFORM public.clan_raid_ensure(v_clan);
  SELECT * INTO r FROM public.clan_raid_cycles
   WHERE clan_id = v_clan AND raid_key = public.clan_week_key() FOR UPDATE;
  IF r.id IS NULL OR r.status <> 'ACTIVE' THEN RAISE EXCEPTION 'RAID_NOT_ACTIVE'; END IF;

  IF r.ends_at < now() THEN
    UPDATE public.clan_raid_cycles SET status = 'EXPIRED' WHERE id = r.id;
    PERFORM public.clan_raid_settle(r.id);
    RAISE EXCEPTION 'RAID_EXPIRED';
  END IF;

  v_day := public.clan_raid_day(r.started_at);
  v_floor := public.clan_raid_phase_floor(r);           -- HP the daily gate still protects
  v_unlock := public.clan_raid_kill_unlock_at(r);
  v_protected := now() < v_unlock;
  -- HP never goes below 1 while the minimum duration is not reached.
  -- Stats (max_hp / atk / def) are NEVER touched here.
  v_hp_floor := GREATEST(v_floor, CASE WHEN v_protected THEN 1 ELSE 0 END);

  -- personal attack budget only: the daily HP gate never blocks an attack
  SELECT count(*) INTO v_used FROM public.clan_raid_attacks
   WHERE raid_id = r.id AND user_id = v_uid AND attack_day = public.game_day_key();
  IF v_used >= cfg.raid_attacks_per_day THEN RAISE EXCEPTION 'RAID_DAILY_LIMIT'; END IF;

  v_power := GREATEST(1, public.clan_player_power(v_uid));
  v_buff := public.clan_buff_pct(v_clan, 'CLAN_RAID_DMG')
          + public.clan_upgrade_level(v_clan, 'WAR_HALL') * 0.5;
  v_catch := public.clan_raid_catchup_pct(r);
  -- real combat damage (unchanged formula, never nerfed by the protection)
  v_combat := round(v_power * (28 + random() * 14) * (1 + (v_buff + v_catch) / 100.0));

  v_hp_before := r.current_hp;
  v_rem_before := GREATEST(0, r.current_hp - v_hp_floor);
  v_hp_dmg := LEAST(v_combat, v_rem_before);
  v_rem_after := v_rem_before - v_hp_dmg;

  INSERT INTO public.clan_raid_attacks(raid_id, clan_id, user_id, damage, combat_damage,
      hp_damage_applied, boss_hp_before, boss_hp_after,
      daily_hp_remaining_before, daily_hp_remaining_after, attack_number,
      idempotency_key, phase, payload)
  VALUES (r.id, v_clan, v_uid, v_hp_dmg, v_combat, v_hp_dmg,
          v_hp_before, v_hp_before - v_hp_dmg, v_rem_before, v_rem_after, v_used + 1,
          p_key, LEAST(r.target_days, v_day),
          jsonb_build_object('power', v_power, 'buffPct', v_buff, 'catchupPct', v_catch,
                             'combatDamage', v_combat, 'hpDamageApplied', v_hp_dmg,
                             'killProtected', v_protected, 'hpFloor', v_hp_floor));

  INSERT INTO public.clan_raid_participation(raid_id, clan_id, user_id, attacks, effective_damage, combat_damage)
  VALUES (r.id, v_clan, v_uid, 1, v_hp_dmg, v_combat)
  ON CONFLICT (raid_id, user_id) DO UPDATE
    SET attacks = public.clan_raid_participation.attacks + 1,
        effective_damage = public.clan_raid_participation.effective_damage + EXCLUDED.effective_damage,
        combat_damage = public.clan_raid_participation.combat_damage + EXCLUDED.combat_damage,
        last_attack_at = now(), updated_at = now()
  RETURNING (attacks = 1) INTO v_first;

  UPDATE public.clan_raid_cycles
     SET current_hp = GREATEST(v_hp_floor, current_hp - v_hp_dmg),
         total_damage = total_damage + v_hp_dmg,
         combat_damage = combat_damage + v_combat,
         catchup_pct = v_catch,
         participants = (SELECT count(*) FROM public.clan_raid_participation WHERE raid_id = r.id),
         status = CASE WHEN NOT v_protected AND current_hp - v_hp_dmg <= 0 THEN 'DEFEATED' ELSE status END,
         cleared_in_hours = CASE WHEN NOT v_protected AND current_hp - v_hp_dmg <= 0
                                 THEN EXTRACT(epoch FROM (now() - started_at)) / 3600 ELSE cleared_in_hours END,
         updated_at = now()
   WHERE id = r.id
  RETURNING * INTO r;

  -- contribution / missions always use the real combat damage
  c := public.clan_weekly_cycle_ensure(v_clan);
  UPDATE public.clan_weekly_member_progress SET raid_damage = raid_damage + v_combat, updated_at = now()
   WHERE cycle_id = c.id AND user_id = v_uid;
  IF NOT FOUND THEN
    INSERT INTO public.clan_weekly_member_progress(cycle_id, user_id, clan_id, raid_damage)
    VALUES (c.id, v_uid, v_clan, v_combat) ON CONFLICT DO NOTHING;
  END IF;
  PERFORM public.record_clan_mission_progress(v_uid, 'clan_raid_damage', v_combat::bigint);

  IF r.status = 'DEFEATED' THEN PERFORM public.clan_raid_settle(r.id); END IF;

  RETURN jsonb_build_object('status','ok',
    'damage', v_combat, 'combatDamage', v_combat, 'hpDamageApplied', v_hp_dmg,
    'hpProtected', v_hp_dmg < v_combat,
    'bossHp', r.current_hp, 'maxHp', r.max_hp, 'defeated', r.status <> 'ACTIVE',
    'killProtected', v_protected, 'killUnlockAt', v_unlock, 'minKillDays', r.min_kill_days,
    'firstAttack', v_first,
    'phaseFloor', public.clan_raid_phase_floor(r), 'catchupPct', v_catch,
    'attacksLeft', GREATEST(0, cfg.raid_attacks_per_day - v_used - 1));
END $function$;

-- 3) state: ranking / my damage / clan damage from combat_damage; HP bar from hp_damage_applied
CREATE OR REPLACE FUNCTION public.clan_raid_state(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; r public.clan_raid_cycles;
        v_day integer; v_floor numeric; v_used integer;
        v_unlocked numeric; v_allowed numeric; v_dealt numeric; v_phase integer;
        v_unlock timestamptz; v_protected boolean;
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('inClan', false); END IF;

  PERFORM public.clan_raid_ensure(v_clan);
  SELECT * INTO r FROM public.clan_raid_cycles WHERE clan_id = v_clan AND raid_key = public.clan_week_key();
  IF r.id IS NULL THEN RETURN jsonb_build_object('inClan', true, 'raid', NULL); END IF;

  v_day := public.clan_raid_day(r.started_at);
  v_phase := LEAST(r.target_days, v_day);
  v_floor := public.clan_raid_phase_floor(r);
  v_dealt := GREATEST(0, r.max_hp - r.current_hp);
  v_unlocked := CASE WHEN r.gates_enabled THEN LEAST(1, v_phase::numeric / GREATEST(1, r.target_days)) ELSE 1 END;
  v_allowed := r.max_hp * v_unlocked;
  v_unlock := public.clan_raid_kill_unlock_at(r);
  v_protected := now() < v_unlock AND r.status = 'ACTIVE';

  SELECT count(*) INTO v_used FROM public.clan_raid_attacks
   WHERE raid_id = r.id AND user_id = v_uid AND attack_day = public.game_day_key();

  RETURN jsonb_build_object(
    'inClan', true,
    'raid', jsonb_build_object(
      'id', r.id, 'name', r.boss_name, 'tier', r.boss_tier, 'theme', r.boss_theme,
      'maxHp', r.max_hp, 'currentHp', r.current_hp, 'status', r.status,
      'atk', r.boss_atk, 'def', r.boss_def,
      'startedAt', r.started_at, 'endsAt', r.ends_at,
      'day', LEAST(v_day, r.deadline_days), 'deadlineDays', r.deadline_days, 'targetDays', r.target_days,
      'minKillDays', GREATEST(1, COALESCE(r.min_kill_days, 5)),
      'killUnlockAt', v_unlock,
      'killProtected', v_protected,
      'phase', v_phase, 'phases', r.target_days,
      'phaseFloor', v_floor, 'phaseLocked', false,
      'unlockedPct', round(v_unlocked * 100, 2),
      'allowedDamage', v_allowed,
      'damageDealt', v_dealt,
      'remainingAllowed', GREATEST(0, LEAST(v_allowed - v_dealt, r.current_hp - v_floor)),
      'hpGateReached', GREATEST(0, r.current_hp - v_floor) <= 0,
      'nextPhaseAt', r.started_at + make_interval(days => v_day),
      'catchupPct', public.clan_raid_catchup_pct(r),
      'totalDamage', COALESCE((SELECT sum(combat_damage) FROM public.clan_raid_attacks WHERE raid_id = r.id), 0),
      'hpDamageTotal', r.total_damage,
      'participants', (SELECT count(*) FROM public.clan_raid_participation WHERE raid_id = r.id),
      'myFirstAttackAt', (SELECT first_attack_at FROM public.clan_raid_participation
                           WHERE raid_id = r.id AND user_id = v_uid),
      'memberCount', (SELECT count(*) FROM public.clan_members WHERE clan_id = v_clan),
      'attacksPerDay', cfg.raid_attacks_per_day, 'attacksUsed', v_used,
      'myDamage', COALESCE((SELECT sum(combat_damage) FROM public.clan_raid_attacks
                             WHERE raid_id = r.id AND user_id = v_uid), 0),
      'clearedInHours', r.cleared_in_hours,
      'ranking', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
          SELECT g.username, g.avatar_url AS avatar, sum(a.combat_damage) AS damage,
                 count(*) AS attacks
            FROM public.clan_raid_attacks a JOIN public.game_players g ON g.id = a.user_id
           WHERE a.raid_id = r.id GROUP BY g.username, g.avatar_url
           ORDER BY sum(a.combat_damage) DESC LIMIT 50) x)
    ));
END $function$;

-- 4) settlement ranks by real combat damage
CREATE OR REPLACE FUNCTION public.clan_raid_settle(p_raid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r public.clan_raid_cycles; cfg public.clan_collective_settings; cc public.clan_coin_settings;
        snap jsonb; v_min numeric; rec record; v_share numeric; v_reward jsonb;
        v_paid integer := 0; v_coins integer; v_rank integer; v_total numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  cc := public.clan_coin_cfg();
  SELECT * INTO r FROM public.clan_raid_cycles WHERE id = p_raid FOR UPDATE;
  IF r.id IS NULL OR r.settled_at IS NOT NULL THEN RETURN jsonb_build_object('status','already'); END IF;
  IF r.status NOT IN ('DEFEATED','EXPIRED') THEN RETURN jsonb_build_object('status','active'); END IF;

  snap := COALESCE(r.rewards_snapshot, '{}'::jsonb);
  v_min := r.max_hp * COALESCE((snap->>'minDamagePct')::numeric, 0.5) / 100.0;
  SELECT COALESCE(sum(combat_damage), 0) INTO v_total FROM public.clan_raid_attacks WHERE raid_id = r.id;

  IF r.status = 'DEFEATED' OR NOT cfg.raid_full_kill_required THEN
    FOR rec IN
      SELECT user_id, sum(combat_damage) AS dmg,
             row_number() OVER (ORDER BY sum(combat_damage) DESC) AS rnk
        FROM public.clan_raid_attacks
       WHERE raid_id = r.id GROUP BY user_id HAVING sum(combat_damage) >= v_min
    LOOP
      v_share := CASE WHEN v_total > 0 THEN LEAST(1, rec.dmg / v_total) ELSE 0 END;
      v_rank := rec.rnk::int;
      v_coins := cc.raid_participation
               + CASE WHEN r.status = 'DEFEATED' THEN cc.raid_defeat ELSE 0 END
               + COALESCE(cc.raid_top_bonus[v_rank], 0);
      v_reward := jsonb_build_object(
        'fc', floor(COALESCE((snap->>'fcPool')::numeric, 0) * v_share),
        'coins', v_coins);
      INSERT INTO public.clan_raid_rewards(raid_id, clan_id, user_id, damage, payload)
      VALUES (r.id, r.clan_id, rec.user_id, rec.dmg, v_reward)
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        PERFORM public.clan_boss_deliver(rec.user_id, v_reward - 'coins');
        PERFORM public.clan_coin_award(rec.user_id, 'CLAN_RAID', r.id::text, v_coins);
        IF COALESCE((snap->>'clanXp')::int, 0) > 0 THEN
          PERFORM public.grant_clan_xp(rec.user_id, 'clan_raid', (snap->>'clanXp')::int);
        END IF;
        v_paid := v_paid + 1;
      END IF;
    END LOOP;
  END IF;

  UPDATE public.clan_raid_cycles SET status = 'SETTLED', settled_at = now() WHERE id = r.id;
  RETURN jsonb_build_object('status','settled','rewarded', v_paid);
END $function$;