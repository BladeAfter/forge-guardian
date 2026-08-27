-- ═══════════ helpers ═══════════
CREATE OR REPLACE FUNCTION public.clan_collective_cfg()
RETURNS public.clan_collective_settings LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.clan_collective_settings WHERE id LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.clan_upgrade_level(p_clan uuid, p_code text)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT level FROM public.clan_upgrades WHERE clan_id = p_clan AND code = p_code), 0);
$$;

CREATE OR REPLACE FUNCTION public.clan_buff_pct(p_clan uuid, p_code text)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT bonus_pct FROM public.clan_buffs
                    WHERE clan_id = p_clan AND code = p_code AND expires_at > now()), 0);
$$;

CREATE OR REPLACE FUNCTION public.clan_has_permission(p_user uuid, p_perm text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.clan_members m
     WHERE m.user_id = p_user
       AND (m.role = 'leader' OR (m.role = 'officer' AND p_perm = ANY(m.permissions)))
  );
$$;

-- active members = joined + seen inside the activity window
CREATE OR REPLACE FUNCTION public.clan_active_members(p_clan uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT GREATEST(1, count(*)::int)
    FROM public.clan_members m
    JOIN public.game_players g ON g.id = m.user_id
   WHERE m.clan_id = p_clan
     AND COALESCE(g.last_seen_at, m.joined_at) > now() - make_interval(days => (SELECT active_member_days FROM public.clan_collective_settings WHERE id));
$$;

-- ═══════════ WEEKLY CYCLE ═══════════
CREATE OR REPLACE FUNCTION public.clan_weekly_cycle_ensure(p_clan uuid)
RETURNS public.clan_weekly_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; c public.clan_weekly_cycles;
        v_week date; v_active integer; v_target bigint;
BEGIN
  cfg := public.clan_collective_cfg();
  v_week := public.clan_week_key();
  SELECT * INTO c FROM public.clan_weekly_cycles WHERE clan_id = p_clan AND week_key = v_week;
  IF c.id IS NOT NULL THEN RETURN c; END IF;

  UPDATE public.clan_weekly_cycles SET status = 'CLOSED'
   WHERE clan_id = p_clan AND week_key < v_week AND status = 'OPEN';

  v_active := public.clan_active_members(p_clan);
  v_target := LEAST(cfg.weekly_target_max,
                    GREATEST(cfg.weekly_target_min, (v_active::bigint * cfg.weekly_target_per_active)));

  INSERT INTO public.clan_weekly_cycles(clan_id, week_key, target, active_members, ends_at)
  VALUES (p_clan, v_week, v_target, v_active, (v_week + 7)::timestamptz)
  ON CONFLICT (clan_id, week_key) DO UPDATE SET updated_at = now()
  RETURNING * INTO c;
  RETURN c;
END $$;

-- ═══════════ CONTRIBUTION (idempotent) ═══════════
CREATE OR REPLACE FUNCTION public.clan_award_contribution(
  p_user uuid, p_amount bigint, p_source_type text, p_source_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_clan uuid; c public.clan_weekly_cycles;
        v_coins bigint; v_xp integer; v_joined timestamptz;
BEGIN
  cfg := public.clan_collective_cfg();
  IF NOT cfg.enabled OR COALESCE(p_amount,0) <= 0 THEN RETURN jsonb_build_object('status','skipped'); END IF;

  SELECT clan_id, joined_at INTO v_clan, v_joined FROM public.clan_members WHERE user_id = p_user;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('status','no_clan'); END IF;

  c := public.clan_weekly_cycle_ensure(v_clan);

  INSERT INTO public.clan_contribution_ledger(clan_id, user_id, cycle_id, amount, source_type, source_id)
  VALUES (v_clan, p_user, c.id, p_amount, p_source_type, p_source_id)
  ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','duplicate'); END IF;

  INSERT INTO public.clan_weekly_member_progress(cycle_id, user_id, clan_id, contribution, joined_at)
  VALUES (c.id, p_user, v_clan, p_amount, COALESCE(v_joined, now()))
  ON CONFLICT (cycle_id, user_id) DO UPDATE
    SET contribution = public.clan_weekly_member_progress.contribution + EXCLUDED.contribution,
        updated_at = now();

  UPDATE public.clan_weekly_cycles
     SET total_contribution = total_contribution + p_amount, updated_at = now()
   WHERE id = c.id;

  UPDATE public.clans SET clan_points = clan_points + p_amount, updated_at = now() WHERE id = v_clan;

  v_coins := floor(p_amount * cfg.coins_per_contribution)::bigint;
  IF v_coins > 0 THEN
    UPDATE public.clan_members
       SET clan_points = clan_points + v_coins, contribution = contribution + p_amount, updated_at = now()
     WHERE user_id = p_user;
  END IF;

  v_xp := floor(p_amount * cfg.clan_xp_per_contribution)::int;
  IF v_xp > 0 THEN PERFORM public.grant_clan_xp(p_user, 'clan_contribution', v_xp); END IF;

  RETURN jsonb_build_object('status','ok','clanId', v_clan, 'amount', p_amount, 'coins', v_coins);
END $$;

-- Personal Boss victory hook: nth defeat of the day defines the points
CREATE OR REPLACE FUNCTION public.clan_contribution_from_personal_boss(p_user uuid, p_instance uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_nth integer; v_amount bigint;
BEGIN
  cfg := public.clan_collective_cfg();
  SELECT COALESCE(defeated_count, 1) INTO v_nth
    FROM public.clan_boss_daily_counters
   WHERE user_id = p_user AND reset_day = public.clan_boss_reset_day(now());
  v_nth := GREATEST(1, COALESCE(v_nth, 1));
  v_amount := COALESCE(cfg.boss_points[LEAST(v_nth, array_length(cfg.boss_points,1))],
                       cfg.boss_points[array_length(cfg.boss_points,1)]);
  RETURN public.clan_award_contribution(p_user, v_amount, 'PERSONAL_BOSS', p_instance::text);
END $$;

-- ═══════════ MILESTONES ═══════════
CREATE OR REPLACE FUNCTION public.clan_milestone_claim(p_telegram_id bigint, p_pct integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; c public.clan_weekly_cycles;
        mp public.clan_weekly_member_progress; v_reward jsonb; v_reached timestamptz; v_coins integer;
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  c := public.clan_weekly_cycle_ensure(v_clan);
  SELECT * INTO c FROM public.clan_weekly_cycles WHERE id = c.id FOR UPDATE;

  SELECT * INTO v_reward FROM (SELECT m FROM jsonb_array_elements(cfg.milestones) m
                                WHERE (m->>'pct')::int = p_pct LIMIT 1) s;
  IF v_reward IS NULL THEN RAISE EXCEPTION 'INVALID_MILESTONE'; END IF;

  IF c.target <= 0 OR c.total_contribution * 100 < c.target * p_pct THEN
    RAISE EXCEPTION 'MILESTONE_LOCKED';
  END IF;

  SELECT * INTO mp FROM public.clan_weekly_member_progress WHERE cycle_id = c.id AND user_id = v_uid;
  IF mp.user_id IS NULL OR mp.contribution < cfg.min_weekly_contribution THEN
    RAISE EXCEPTION 'MIN_CONTRIBUTION_REQUIRED';
  END IF;

  -- the member must have been contributing BEFORE the milestone was hit
  SELECT min(created_at) INTO v_reached
    FROM (SELECT created_at, sum(amount) OVER (ORDER BY created_at) AS running
            FROM public.clan_contribution_ledger WHERE cycle_id = c.id) t
   WHERE running * 100 >= c.target * p_pct;
  IF v_reached IS NOT NULL AND mp.joined_at > v_reached THEN
    RAISE EXCEPTION 'JOINED_AFTER_MILESTONE';
  END IF;

  INSERT INTO public.clan_milestone_claims(cycle_id, clan_id, user_id, milestone_pct, payload)
  VALUES (c.id, v_clan, v_uid, p_pct, v_reward)
  ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RAISE EXCEPTION 'ALREADY_CLAIMED'; END IF;

  PERFORM public.clan_boss_deliver(v_uid, v_reward);
  v_coins := COALESCE((v_reward->>'coins')::int, 0);
  IF v_coins > 0 THEN
    UPDATE public.clan_members SET clan_points = clan_points + v_coins, updated_at = now() WHERE user_id = v_uid;
  END IF;
  IF COALESCE((v_reward->>'clanXp')::int, 0) > 0 THEN
    PERFORM public.grant_clan_xp(v_uid, 'clan_milestone', (v_reward->>'clanXp')::int);
  END IF;

  RETURN jsonb_build_object('status','claimed','milestone', p_pct, 'reward', v_reward);
END $$;

-- ═══════════ CLAN RAID ═══════════
CREATE OR REPLACE FUNCTION public.clan_raid_ensure(p_clan uuid)
RETURNS public.clan_raid_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; r public.clan_raid_cycles;
        v_key date; v_power numeric; v_hp numeric; v_level integer;
BEGIN
  cfg := public.clan_collective_cfg();
  v_key := public.clan_week_key();

  UPDATE public.clan_raid_cycles SET status = 'EXPIRED'
   WHERE clan_id = p_clan AND status = 'ACTIVE' AND ends_at < now();

  SELECT * INTO r FROM public.clan_raid_cycles WHERE clan_id = p_clan AND raid_key = v_key;
  IF r.id IS NOT NULL OR NOT cfg.raid_enabled THEN RETURN r; END IF;

  SELECT COALESCE(sum(public.clan_player_power(m.user_id)), 0), COALESCE(max(c.level),1)
    INTO v_power, v_level
    FROM public.clan_members m JOIN public.clans c ON c.id = m.clan_id
   WHERE m.clan_id = p_clan;

  v_hp := LEAST(cfg.raid_hp_max, GREATEST(cfg.raid_hp_min, round(v_power * cfg.raid_hp_per_power)));

  INSERT INTO public.clan_raid_cycles(clan_id, raid_key, max_hp, current_hp, boss_atk, boss_def,
                                      rewards_snapshot, ends_at)
  VALUES (p_clan, v_key, v_hp, v_hp, round(v_power * 0.02), round(v_power * 0.01),
          cfg.raid_rewards, now() + make_interval(days => cfg.raid_duration_days))
  ON CONFLICT (clan_id, raid_key) DO UPDATE SET updated_at = now()
  RETURNING * INTO r;
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.clan_raid_settle(p_raid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.clan_raid_cycles; snap jsonb; v_min numeric; rec record;
        v_share numeric; v_reward jsonb; v_paid integer := 0; v_coins integer;
BEGIN
  SELECT * INTO r FROM public.clan_raid_cycles WHERE id = p_raid FOR UPDATE;
  IF r.id IS NULL OR r.settled_at IS NOT NULL THEN RETURN jsonb_build_object('status','already'); END IF;
  IF r.status NOT IN ('DEFEATED','EXPIRED') THEN RETURN jsonb_build_object('status','active'); END IF;

  snap := COALESCE(r.rewards_snapshot, '{}'::jsonb);
  v_min := r.max_hp * COALESCE((snap->>'minDamagePct')::numeric, 0.5) / 100.0;

  IF r.status = 'DEFEATED' THEN
    FOR rec IN
      SELECT user_id, sum(damage) AS dmg FROM public.clan_raid_attacks
       WHERE raid_id = r.id GROUP BY user_id HAVING sum(damage) >= v_min
    LOOP
      v_share := CASE WHEN r.total_damage > 0 THEN LEAST(1, rec.dmg / r.total_damage) ELSE 0 END;
      v_coins := floor(COALESCE((snap->>'coinsPool')::numeric, 0) * v_share)::int;
      v_reward := jsonb_build_object(
        'fc', floor(COALESCE((snap->>'fcPool')::numeric, 0) * v_share),
        'coins', v_coins);
      INSERT INTO public.clan_raid_rewards(raid_id, clan_id, user_id, damage, payload)
      VALUES (r.id, r.clan_id, rec.user_id, rec.dmg, v_reward)
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        PERFORM public.clan_boss_deliver(rec.user_id, v_reward);
        IF v_coins > 0 THEN
          UPDATE public.clan_members SET clan_points = clan_points + v_coins, updated_at = now()
           WHERE user_id = rec.user_id;
        END IF;
        IF COALESCE((snap->>'clanXp')::int, 0) > 0 THEN
          PERFORM public.grant_clan_xp(rec.user_id, 'clan_raid', (snap->>'clanXp')::int);
        END IF;
        v_paid := v_paid + 1;
      END IF;
    END LOOP;
  END IF;

  UPDATE public.clan_raid_cycles SET status = 'SETTLED', settled_at = now() WHERE id = r.id;
  RETURN jsonb_build_object('status','settled','rewarded', v_paid);
END $$;

CREATE OR REPLACE FUNCTION public.clan_raid_attack(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; r public.clan_raid_cycles;
        v_used integer; v_power numeric; v_dmg numeric; v_buff numeric; c public.clan_weekly_cycles;
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  IF NOT cfg.raid_enabled THEN RAISE EXCEPTION 'RAID_DISABLED'; END IF;

  PERFORM public.clan_raid_ensure(v_clan);
  SELECT * INTO r FROM public.clan_raid_cycles
   WHERE clan_id = v_clan AND raid_key = public.clan_week_key() FOR UPDATE;
  IF r.id IS NULL OR r.status <> 'ACTIVE' THEN RAISE EXCEPTION 'RAID_NOT_ACTIVE'; END IF;
  IF r.ends_at < now() THEN
    UPDATE public.clan_raid_cycles SET status = 'EXPIRED' WHERE id = r.id;
    PERFORM public.clan_raid_settle(r.id);
    RAISE EXCEPTION 'RAID_EXPIRED';
  END IF;

  SELECT count(*) INTO v_used FROM public.clan_raid_attacks
   WHERE raid_id = r.id AND user_id = v_uid AND attack_day = public.game_day_key();
  IF v_used >= cfg.raid_attacks_per_day THEN RAISE EXCEPTION 'RAID_DAILY_LIMIT'; END IF;

  v_power := GREATEST(1, public.clan_player_power(v_uid));
  v_buff := public.clan_buff_pct(v_clan, 'CLAN_RAID_DMG')
          + public.clan_upgrade_level(v_clan, 'WAR_HALL') * 0.5;
  v_dmg := round(v_power * (28 + random() * 14) * (1 + v_buff / 100.0));
  v_dmg := LEAST(v_dmg, r.current_hp);

  INSERT INTO public.clan_raid_attacks(raid_id, clan_id, user_id, damage,
    payload) VALUES (r.id, v_clan, v_uid, v_dmg, jsonb_build_object('power', v_power, 'buffPct', v_buff));

  UPDATE public.clan_raid_cycles
     SET current_hp = GREATEST(0, current_hp - v_dmg),
         total_damage = total_damage + v_dmg,
         participants = (SELECT count(DISTINCT user_id) FROM public.clan_raid_attacks WHERE raid_id = r.id),
         status = CASE WHEN current_hp - v_dmg <= 0 THEN 'DEFEATED' ELSE status END,
         updated_at = now()
   WHERE id = r.id
  RETURNING * INTO r;

  c := public.clan_weekly_cycle_ensure(v_clan);
  UPDATE public.clan_weekly_member_progress SET raid_damage = raid_damage + v_dmg, updated_at = now()
   WHERE cycle_id = c.id AND user_id = v_uid;
  IF NOT FOUND THEN
    INSERT INTO public.clan_weekly_member_progress(cycle_id, user_id, clan_id, raid_damage)
    VALUES (c.id, v_uid, v_clan, v_dmg) ON CONFLICT DO NOTHING;
  END IF;

  PERFORM public.record_clan_mission_progress(v_uid, 'clan_raid_damage', v_dmg::bigint);

  IF r.status = 'DEFEATED' THEN PERFORM public.clan_raid_settle(r.id); END IF;

  RETURN jsonb_build_object('status','ok','damage', v_dmg, 'bossHp', r.current_hp,
                            'maxHp', r.max_hp, 'defeated', r.status <> 'ACTIVE',
                            'attacksLeft', GREATEST(0, cfg.raid_attacks_per_day - v_used - 1));
END $$;

-- ═══════════ TREASURY ═══════════
CREATE OR REPLACE FUNCTION public.clan_treasury_move(
  p_clan uuid, p_user uuid, p_asset text, p_amount numeric, p_reason text)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t public.clan_treasury; v_before numeric; v_after numeric;
BEGIN
  INSERT INTO public.clan_treasury(clan_id) VALUES (p_clan) ON CONFLICT DO NOTHING;
  SELECT * INTO t FROM public.clan_treasury WHERE clan_id = p_clan FOR UPDATE;
  v_before := CASE p_asset WHEN 'FC' THEN t.fc WHEN 'MYTH' THEN t.myth ELSE t.materials END;
  v_after := v_before + p_amount;
  IF v_after < 0 THEN RAISE EXCEPTION 'TREASURY_INSUFFICIENT'; END IF;

  UPDATE public.clan_treasury
     SET fc = CASE WHEN p_asset = 'FC' THEN v_after ELSE fc END,
         myth = CASE WHEN p_asset = 'MYTH' THEN v_after ELSE myth END,
         materials = CASE WHEN p_asset = 'MATERIALS' THEN v_after ELSE materials END,
         updated_at = now()
   WHERE clan_id = p_clan;

  INSERT INTO public.clan_treasury_ledger(clan_id, user_id, asset, amount, reason, balance_before, balance_after)
  VALUES (p_clan, p_user, p_asset, p_amount, p_reason, v_before, v_after);
  RETURN v_after;
END $$;

CREATE OR REPLACE FUNCTION public.clan_treasury_donate(p_telegram_id bigint, p_asset text, p_amount numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; v_bal numeric; v_after numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  IF p_asset NOT IN ('FC','MYTH') OR NOT (p_asset = ANY(cfg.treasury_assets)) THEN RAISE EXCEPTION 'INVALID_ASSET'; END IF;
  IF COALESCE(p_amount,0) <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;

  IF p_asset = 'FC' THEN
    SELECT forge_coins INTO v_bal FROM public.game_players WHERE id = v_uid FOR UPDATE;
    IF COALESCE(v_bal,0) < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_FC'; END IF;
    UPDATE public.game_players SET forge_coins = forge_coins - p_amount, updated_at = now() WHERE id = v_uid;
  ELSE
    SELECT amount INTO v_bal FROM public.myth_balances WHERE user_id = v_uid FOR UPDATE;
    IF COALESCE(v_bal,0) < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_MYTH'; END IF;
    UPDATE public.myth_balances SET amount = amount - p_amount, updated_at = now() WHERE user_id = v_uid;
    INSERT INTO public.myth_ledger(user_id, direction, amount, reason)
    VALUES (v_uid, 'debit', p_amount, 'clan_treasury_donation');
  END IF;

  v_after := public.clan_treasury_move(v_clan, v_uid, p_asset, p_amount, 'CLAN_DONATION');
  PERFORM public.grant_clan_xp(v_uid, 'clan_donation', GREATEST(1, floor(p_amount / 10000))::int);
  RETURN jsonb_build_object('status','donated','asset', p_asset, 'amount', p_amount, 'treasury', v_after);
END $$;

-- ═══════════ UPGRADES / BUFFS ═══════════
CREATE OR REPLACE FUNCTION public.clan_upgrade_buy(p_telegram_id bigint, p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; cfgu public.clan_upgrade_config; v_level integer; v_cost numeric; v_clan_level integer;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  IF NOT public.clan_has_permission(v_uid, 'MANAGE_CLAN_UPGRADES') THEN RAISE EXCEPTION 'NO_PERMISSION'; END IF;

  SELECT * INTO cfgu FROM public.clan_upgrade_config WHERE code = p_code AND enabled;
  IF cfgu.code IS NULL THEN RAISE EXCEPTION 'INVALID_UPGRADE'; END IF;

  SELECT level INTO v_clan_level FROM public.clans WHERE id = v_clan;
  IF v_clan_level < cfgu.required_clan_level THEN RAISE EXCEPTION 'CLAN_LEVEL_REQUIRED'; END IF;

  INSERT INTO public.clan_upgrades(clan_id, code, level) VALUES (v_clan, p_code, 0) ON CONFLICT DO NOTHING;
  SELECT level INTO v_level FROM public.clan_upgrades WHERE clan_id = v_clan AND code = p_code FOR UPDATE;
  IF v_level >= cfgu.max_level THEN RAISE EXCEPTION 'MAX_LEVEL'; END IF;

  v_cost := round(cfgu.base_cost_fc * power(cfgu.cost_growth, v_level));
  PERFORM public.clan_treasury_move(v_clan, v_uid, 'FC', -v_cost, 'CLAN_UPGRADE_PURCHASE');
  UPDATE public.clan_upgrades SET level = v_level + 1, updated_at = now()
   WHERE clan_id = v_clan AND code = p_code;

  RETURN jsonb_build_object('status','upgraded','code', p_code, 'level', v_level + 1, 'cost', v_cost);
END $$;

CREATE OR REPLACE FUNCTION public.clan_buff_activate(p_telegram_id bigint, p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; b public.clan_buff_config; v_research integer; v_pct numeric;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  IF NOT public.clan_has_permission(v_uid, 'MANAGE_CLAN_BUFFS') THEN RAISE EXCEPTION 'NO_PERMISSION'; END IF;

  SELECT * INTO b FROM public.clan_buff_config WHERE code = p_code AND enabled;
  IF b.code IS NULL THEN RAISE EXCEPTION 'INVALID_BUFF'; END IF;

  v_research := public.clan_upgrade_level(v_clan, 'RESEARCH_HALL');
  IF v_research < b.required_research_level THEN RAISE EXCEPTION 'RESEARCH_HALL_REQUIRED'; END IF;
  IF EXISTS (SELECT 1 FROM public.clan_buffs WHERE clan_id = v_clan AND code = p_code AND expires_at > now()) THEN
    RAISE EXCEPTION 'BUFF_ALREADY_ACTIVE';
  END IF;

  PERFORM public.clan_treasury_move(v_clan, v_uid, 'FC', -b.cost_fc, 'CLAN_BUFF_PURCHASE');
  v_pct := LEAST(b.max_pct, b.bonus_pct);

  INSERT INTO public.clan_buffs(clan_id, code, bonus_pct, expires_at, activated_by)
  VALUES (v_clan, p_code, v_pct, now() + make_interval(hours => b.duration_hours), v_uid)
  ON CONFLICT (clan_id, code) DO UPDATE
    SET bonus_pct = EXCLUDED.bonus_pct, expires_at = EXCLUDED.expires_at,
        activated_by = EXCLUDED.activated_by, updated_at = now();

  RETURN jsonb_build_object('status','activated','code', p_code, 'pct', v_pct, 'hours', b.duration_hours);
END $$;

-- ═══════════ CLAN SHOP (Clan Coins) ═══════════
CREATE OR REPLACE FUNCTION public.clan_shop_purchase(
  p_telegram_id bigint, p_code text, p_quantity integer DEFAULT 1, p_idempotency_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; v_coins bigint; s public.clan_shop_config;
        v_qty integer; v_cost bigint; v_day integer; v_week integer; v_clan_level integer; v_total integer;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, clan_points INTO v_clan, v_coins FROM public.clan_members WHERE user_id = v_uid FOR UPDATE;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  SELECT * INTO s FROM public.clan_shop_config WHERE code = p_code AND enabled;
  IF s.code IS NULL THEN RAISE EXCEPTION 'INVALID_ITEM'; END IF;

  SELECT level INTO v_clan_level FROM public.clans WHERE id = v_clan;
  IF v_clan_level < s.required_clan_level THEN RAISE EXCEPTION 'CLAN_LEVEL_REQUIRED'; END IF;

  v_qty := GREATEST(1, LEAST(20, COALESCE(p_quantity, 1)));
  v_cost := s.cost_coins::bigint * v_qty;
  IF v_coins < v_cost THEN RAISE EXCEPTION 'INSUFFICIENT_CLAN_COINS'; END IF;

  SELECT COALESCE(sum(quantity),0) INTO v_day FROM public.clan_shop_purchases
   WHERE user_id = v_uid AND code = p_code AND purchase_day = public.game_day_key();
  IF s.daily_limit > 0 AND v_day + v_qty > s.daily_limit THEN RAISE EXCEPTION 'DAILY_LIMIT_REACHED'; END IF;

  SELECT COALESCE(sum(quantity),0) INTO v_week FROM public.clan_shop_purchases
   WHERE user_id = v_uid AND code = p_code AND week_key = public.clan_week_key();
  IF s.weekly_limit > 0 AND v_week + v_qty > s.weekly_limit THEN RAISE EXCEPTION 'WEEKLY_LIMIT_REACHED'; END IF;

  IF s.season_limit > 0 THEN
    SELECT COALESCE(sum(quantity),0) INTO v_total FROM public.clan_shop_purchases
     WHERE user_id = v_uid AND code = p_code;
    IF v_total + v_qty > s.season_limit THEN RAISE EXCEPTION 'SEASON_LIMIT_REACHED'; END IF;
  END IF;

  INSERT INTO public.clan_shop_purchases(clan_id, user_id, code, quantity, cost_coins, idempotency_key)
  VALUES (v_clan, v_uid, p_code, v_qty, v_cost, p_idempotency_key)
  ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','duplicate'); END IF;

  UPDATE public.clan_members SET clan_points = clan_points - v_cost, updated_at = now() WHERE user_id = v_uid;
  INSERT INTO public.clan_points_ledger(clan_id, user_id, amount, reason)
  VALUES (v_clan, v_uid, -v_cost, 'clan_shop:' || p_code);

  IF s.item_type = 'pvp_ticket' THEN
    UPDATE public.game_players SET pvp_tickets = pvp_tickets + (s.quantity * v_qty), updated_at = now()
     WHERE id = v_uid;
  ELSIF s.item_type = 'universal_fragments' THEN
    PERFORM public.add_universal_fragments(v_uid, s.quantity * v_qty);
  ELSIF s.item_type = 'pet_food' THEN
    INSERT INTO public.player_pet_food(user_id, food_code, quantity)
    VALUES (v_uid, s.item_code, s.quantity * v_qty)
    ON CONFLICT (user_id, food_code) DO UPDATE
      SET quantity = public.player_pet_food.quantity + EXCLUDED.quantity;
  ELSE
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (v_uid, s.item_type, s.item_code, s.quantity * v_qty)
    ON CONFLICT (user_id, item_type, item_code) DO UPDATE
      SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
  END IF;

  RETURN jsonb_build_object('status','purchased','code', p_code, 'quantity', v_qty,
                            'cost', v_cost, 'coins', v_coins - v_cost);
END $$;

-- ═══════════ CLAN HUB STATE ═══════════
CREATE OR REPLACE FUNCTION public.clan_hub_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; cl public.clans;
        c public.clan_weekly_cycles; r public.clan_raid_cycles; t public.clan_treasury;
        mp public.clan_weekly_member_progress; v_role text; v_coins bigint; v_perms text[];
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role, clan_points, permissions INTO v_clan, v_role, v_coins, v_perms
    FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('inClan', false); END IF;

  SELECT * INTO cl FROM public.clans WHERE id = v_clan;
  SELECT * INTO c FROM public.clan_weekly_cycles WHERE clan_id = v_clan AND week_key = public.clan_week_key();
  SELECT * INTO r FROM public.clan_raid_cycles WHERE clan_id = v_clan AND raid_key = public.clan_week_key();
  SELECT * INTO t FROM public.clan_treasury WHERE clan_id = v_clan;
  SELECT * INTO mp FROM public.clan_weekly_member_progress WHERE cycle_id = c.id AND user_id = v_uid;

  RETURN jsonb_build_object(
    'inClan', true,
    'clan', jsonb_build_object('id', cl.id, 'name', cl.name, 'tag', cl.tag, 'level', cl.level,
                               'xp', cl.xp, 'nextLevelXp', public.clan_level_xp(cl.level + 1),
                               'members', (SELECT count(*) FROM public.clan_members WHERE clan_id = v_clan),
                               'memberLimit', cl.member_limit,
                               'activeMembers', public.clan_active_members(v_clan)),
    'me', jsonb_build_object('role', v_role, 'coins', COALESCE(v_coins,0),
                             'permissions', COALESCE(to_jsonb(v_perms), '[]'::jsonb),
                             'contributionWeek', COALESCE(mp.contribution, 0),
                             'raidDamage', COALESCE(mp.raid_damage, 0),
                             'contributionToday', COALESCE((SELECT sum(amount) FROM public.clan_contribution_ledger
                                WHERE user_id = v_uid AND clan_id = v_clan AND game_day = public.game_day_key()), 0),
                             'contributionAllTime', COALESCE((SELECT sum(amount) FROM public.clan_contribution_ledger
                                WHERE user_id = v_uid), 0)),
    'weekly', CASE WHEN c.id IS NULL THEN NULL ELSE jsonb_build_object(
        'cycleId', c.id, 'weekKey', c.week_key, 'target', c.target,
        'total', c.total_contribution, 'activeMembers', c.active_members,
        'endsAt', c.ends_at, 'minContribution', cfg.min_weekly_contribution,
        'milestones', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
              'pct', (m->>'pct')::int,
              'required', ceil(c.target * (m->>'pct')::int / 100.0),
              'reward', m,
              'unlocked', c.total_contribution * 100 >= c.target * (m->>'pct')::int,
              'claimed', EXISTS (SELECT 1 FROM public.clan_milestone_claims mc
                                  WHERE mc.cycle_id = c.id AND mc.user_id = v_uid
                                    AND mc.milestone_pct = (m->>'pct')::int)
            ) ORDER BY (m->>'pct')::int), '[]'::jsonb) FROM jsonb_array_elements(cfg.milestones) m)) END,
    'raid', CASE WHEN r.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', r.id, 'name', r.boss_name, 'maxHp', r.max_hp, 'currentHp', r.current_hp,
        'status', r.status, 'endsAt', r.ends_at, 'totalDamage', r.total_damage,
        'participants', r.participants, 'attacksPerDay', cfg.raid_attacks_per_day,
        'attacksUsed', (SELECT count(*) FROM public.clan_raid_attacks
                         WHERE raid_id = r.id AND user_id = v_uid AND attack_day = public.game_day_key()),
        'top', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
                  SELECT g.username, sum(a.damage) AS damage
                    FROM public.clan_raid_attacks a JOIN public.game_players g ON g.id = a.user_id
                   WHERE a.raid_id = r.id GROUP BY g.username ORDER BY sum(a.damage) DESC LIMIT 5) x)) END,
    'treasury', jsonb_build_object('fc', COALESCE(t.fc,0), 'myth', COALESCE(t.myth,0),
                                   'materials', COALESCE(t.materials,0), 'tonEnabled', cfg.treasury_ton_enabled),
    'upgrades', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'code', u.code, 'label', u.label, 'description', u.description,
        'level', public.clan_upgrade_level(v_clan, u.code), 'maxLevel', u.max_level,
        'requiredClanLevel', u.required_clan_level,
        'nextCost', round(u.base_cost_fc * power(u.cost_growth, public.clan_upgrade_level(v_clan, u.code)))
      ) ORDER BY u.code), '[]'::jsonb) FROM public.clan_upgrade_config u WHERE u.enabled),
    'buffs', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'code', b.code, 'label', b.label, 'pct', LEAST(b.max_pct, b.bonus_pct),
        'costFc', b.cost_fc, 'hours', b.duration_hours,
        'requiredResearch', b.required_research_level,
        'activePct', public.clan_buff_pct(v_clan, b.code),
        'expiresAt', (SELECT expires_at FROM public.clan_buffs
                       WHERE clan_id = v_clan AND code = b.code AND expires_at > now())
      ) ORDER BY b.code), '[]'::jsonb) FROM public.clan_buff_config b WHERE b.enabled),
    'shop', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'code', s.code, 'label', s.label, 'cost', s.cost_coins, 'quantity', s.quantity,
        'dailyLimit', s.daily_limit, 'requiredClanLevel', s.required_clan_level,
        'boughtToday', COALESCE((SELECT sum(quantity) FROM public.clan_shop_purchases p
                                  WHERE p.user_id = v_uid AND p.code = s.code
                                    AND p.purchase_day = public.game_day_key()), 0)
      ) ORDER BY s.sort_order), '[]'::jsonb) FROM public.clan_shop_config s WHERE s.enabled),
    'contributors', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
        SELECT g.username, p.contribution, p.raid_damage
          FROM public.clan_weekly_member_progress p JOIN public.game_players g ON g.id = p.user_id
         WHERE p.cycle_id = c.id ORDER BY p.contribution DESC LIMIT 10) x),
    'bossPoints', to_jsonb(cfg.boss_points)
  );
END $$;

-- ═══════════ lock down execution (service role / edge functions only) ═══════════
DO $$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'clan_collective_cfg','clan_upgrade_level','clan_buff_pct','clan_has_permission','clan_active_members',
    'clan_weekly_cycle_ensure','clan_award_contribution','clan_contribution_from_personal_boss',
    'clan_milestone_claim','clan_raid_ensure','clan_raid_settle','clan_raid_attack',
    'clan_treasury_move','clan_treasury_donate','clan_upgrade_buy','clan_buff_activate',
    'clan_shop_purchase','clan_hub_state']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I TO service_role', fn);
  END LOOP;
END $$;