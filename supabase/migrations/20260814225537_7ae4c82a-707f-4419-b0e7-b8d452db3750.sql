-- ============ 0022: Pet Expeditions per-mission daily extra attempts ============

CREATE TABLE IF NOT EXISTS public.expedition_attempts (
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  mission_id uuid NOT NULL REFERENCES public.expedition_missions(id) ON DELETE CASCADE,
  period date NOT NULL,
  free_used int NOT NULL DEFAULT 0,
  rewarded_ads_used int NOT NULL DEFAULT 0,
  fc_extra_purchases_used int NOT NULL DEFAULT 0,
  extra_available int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, mission_id, period)
);
GRANT ALL ON public.expedition_attempts TO service_role;
ALTER TABLE public.expedition_attempts ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.expedition_extra_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  mission_id uuid NOT NULL REFERENCES public.expedition_missions(id) ON DELETE CASCADE,
  period date NOT NULL,
  source text NOT NULL CHECK (source IN ('ADS','FC')),
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','GRANTED','CANCELLED')),
  cost_fc numeric NOT NULL DEFAULT 0,
  idempotency_key text,
  created_at timestamptz NOT NULL DEFAULT now(),
  granted_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS expedition_extra_grants_key_idx
  ON public.expedition_extra_grants(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS expedition_extra_grants_pending_idx
  ON public.expedition_extra_grants(user_id, mission_id) WHERE status = 'PENDING';
GRANT ALL ON public.expedition_extra_grants TO service_role;
ALTER TABLE public.expedition_extra_grants ENABLE ROW LEVEL SECURITY;

-- ---------- configuration helpers (editable in game_settings, no deploy) ----------
CREATE OR REPLACE FUNCTION public.expedition_extra_price_fc(p_rarity text)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r text := lower(coalesce(p_rarity, 'common')); d numeric;
BEGIN
  d := CASE r WHEN 'common' THEN 10000 WHEN 'uncommon' THEN 10000 WHEN 'rare' THEN 50000
              WHEN 'epic' THEN 100000 WHEN 'legendary' THEN 200000 ELSE 100000 END;
  RETURN greatest(0, public.setting_num('expedition_extra_price_fc_'||r, d));
END $$;

CREATE OR REPLACE FUNCTION public.expedition_limits()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT jsonb_build_object(
    'freeAttemptsPerDay', greatest(0, public.setting_num('expedition_free_attempts_per_day', 1)::int),
    'maxAdsPerMissionPerDay', greatest(0, public.setting_num('expedition_max_ads_per_day', 5)::int),
    'maxFcPurchasesPerMissionPerDay', greatest(0, public.setting_num('expedition_max_fc_purchases_per_day', 5)::int)
  )
$$;

-- ---------- per (user, mission, day) state ----------
CREATE OR REPLACE FUNCTION public.expedition_attempt_row(p_user_id uuid, p_mission_id uuid, p_lock boolean DEFAULT false)
RETURNS public.expedition_attempts LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v public.expedition_attempts; v_period date := public.game_day_key(now());
BEGIN
  INSERT INTO public.expedition_attempts(user_id, mission_id, period)
  VALUES (p_user_id, p_mission_id, v_period)
  ON CONFLICT (user_id, mission_id, period) DO NOTHING;
  IF p_lock THEN
    SELECT * INTO v FROM public.expedition_attempts
      WHERE user_id = p_user_id AND mission_id = p_mission_id AND period = v_period FOR UPDATE;
  ELSE
    SELECT * INTO v FROM public.expedition_attempts
      WHERE user_id = p_user_id AND mission_id = p_mission_id AND period = v_period;
  END IF;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.expedition_mission_attempts(p_user_id uuid, p_mission_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg jsonb := public.expedition_limits(); v public.expedition_attempts;
        v_period date := public.game_day_key(now()); m public.expedition_missions;
        free_limit int; ads_limit int; fc_limit int;
BEGIN
  SELECT * INTO m FROM public.expedition_missions WHERE id = p_mission_id;
  SELECT * INTO v FROM public.expedition_attempts
    WHERE user_id = p_user_id AND mission_id = p_mission_id AND period = v_period;
  free_limit := (cfg->>'freeAttemptsPerDay')::int;
  ads_limit := (cfg->>'maxAdsPerMissionPerDay')::int;
  fc_limit := (cfg->>'maxFcPurchasesPerMissionPerDay')::int;
  RETURN jsonb_build_object(
    'missionId', p_mission_id,
    'period', v_period,
    'resetsAt', public.ad_reward_period_reset_at(),
    'freeLimit', free_limit,
    'freeUsed', least(free_limit, coalesce(v.free_used, 0)),
    'freeRemaining', greatest(0, free_limit - coalesce(v.free_used, 0)),
    'adsUsed', coalesce(v.rewarded_ads_used, 0),
    'adsLimit', ads_limit,
    'adsRemaining', greatest(0, ads_limit - coalesce(v.rewarded_ads_used, 0)),
    'fcUsed', coalesce(v.fc_extra_purchases_used, 0),
    'fcLimit', fc_limit,
    'fcRemaining', greatest(0, fc_limit - coalesce(v.fc_extra_purchases_used, 0)),
    'extraAvailable', coalesce(v.extra_available, 0),
    'priceFc', public.expedition_extra_price_fc(m.rarity),
    'canStart', (greatest(0, free_limit - coalesce(v.free_used, 0)) + coalesce(v.extra_available, 0)) > 0
  );
END $$;

-- ---------- rewarded ad: begin + claim (atomic, idempotent, mission scoped) ----------
CREATE OR REPLACE FUNCTION public.expedition_extra_ad_begin(p_telegram_id bigint, p_mission_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; m public.expedition_missions; st jsonb; v_id uuid; v_block text;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF coalesce(u.banned, false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;
  SELECT * INTO m FROM public.expedition_missions WHERE id = p_mission_id AND enabled;
  IF m.id IS NULL THEN RAISE EXCEPTION 'MISSION_NOT_FOUND'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('exp_extra:'||u.id::text||':'||m.id::text, 0));
  PERFORM public.expedition_attempt_row(u.id, m.id, true);
  st := public.expedition_mission_attempts(u.id, m.id);
  IF (st->>'adsRemaining')::int <= 0 THEN RAISE EXCEPTION 'EXPEDITION_AD_LIMIT_REACHED'; END IF;

  v_block := nullif(trim(coalesce(public.setting_text('adsgram_pvp_reward_block_id', '42560'), '')), '');
  IF v_block IS NULL THEN RAISE EXCEPTION 'AD_REWARDS_DISABLED'; END IF;

  UPDATE public.expedition_extra_grants SET status = 'CANCELLED'
    WHERE user_id = u.id AND status = 'PENDING' AND created_at < now() - interval '10 minutes';

  SELECT id INTO v_id FROM public.expedition_extra_grants
    WHERE user_id = u.id AND mission_id = m.id AND source = 'ADS' AND status = 'PENDING'
    ORDER BY created_at DESC LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.expedition_extra_grants(user_id, mission_id, period, source, status)
    VALUES (u.id, m.id, public.game_day_key(now()), 'ADS', 'PENDING')
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object('viewId', v_id, 'blockId', v_block, 'attempts', st);
END $$;

CREATE OR REPLACE FUNCTION public.expedition_extra_ad_claim(p_telegram_id bigint, p_view_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; g public.expedition_extra_grants; st jsonb;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  SELECT * INTO g FROM public.expedition_extra_grants WHERE id = p_view_id AND user_id = u.id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'EXPEDITION_AD_VIEW_NOT_FOUND'; END IF;
  IF g.status = 'GRANTED' THEN
    RETURN jsonb_build_object('granted', false, 'reason', 'ALREADY_GRANTED',
      'attempts', public.expedition_mission_attempts(u.id, g.mission_id));
  END IF;
  IF g.status <> 'PENDING' THEN RAISE EXCEPTION 'EXPEDITION_AD_VIEW_EXPIRED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('exp_extra:'||u.id::text||':'||g.mission_id::text, 0));
  PERFORM public.expedition_attempt_row(u.id, g.mission_id, true);
  st := public.expedition_mission_attempts(u.id, g.mission_id);
  IF (st->>'adsRemaining')::int <= 0 THEN
    UPDATE public.expedition_extra_grants SET status = 'CANCELLED' WHERE id = g.id;
    RAISE EXCEPTION 'EXPEDITION_AD_LIMIT_REACHED';
  END IF;

  UPDATE public.expedition_attempts
    SET rewarded_ads_used = rewarded_ads_used + 1,
        extra_available = extra_available + 1,
        updated_at = now()
    WHERE user_id = u.id AND mission_id = g.mission_id AND period = public.game_day_key(now());

  UPDATE public.expedition_extra_grants
    SET status = 'GRANTED', granted_at = now(), period = public.game_day_key(now())
    WHERE id = g.id;

  RETURN jsonb_build_object('granted', true, 'missionId', g.mission_id,
    'attempts', public.expedition_mission_attempts(u.id, g.mission_id));
END $$;

-- ---------- FC purchase (atomic, idempotent, mission scoped) ----------
CREATE OR REPLACE FUNCTION public.expedition_extra_buy_fc(p_telegram_id bigint, p_mission_id uuid, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid; bal numeric; m public.expedition_missions; st jsonb; price numeric; existing uuid;
BEGIN
  IF length(coalesce(p_idempotency_key, '')) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST_KEY'; END IF;
  SELECT id, forge_coins INTO u, bal FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO m FROM public.expedition_missions WHERE id = p_mission_id AND enabled;
  IF m.id IS NULL THEN RAISE EXCEPTION 'MISSION_NOT_FOUND'; END IF;

  SELECT id INTO existing FROM public.expedition_extra_grants
    WHERE user_id = u AND idempotency_key = p_idempotency_key;
  IF existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true,
      'attempts', public.expedition_mission_attempts(u, m.id));
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('exp_extra:'||u::text||':'||m.id::text, 0));
  PERFORM public.expedition_attempt_row(u, m.id, true);
  st := public.expedition_mission_attempts(u, m.id);
  IF (st->>'fcRemaining')::int <= 0 THEN RAISE EXCEPTION 'EXPEDITION_FC_LIMIT_REACHED'; END IF;

  price := public.expedition_extra_price_fc(m.rarity);
  IF coalesce(bal, 0) < price THEN RAISE EXCEPTION 'NOT_ENOUGH_FORGE_COINS'; END IF;

  UPDATE public.game_players SET forge_coins = forge_coins - price, updated_at = now() WHERE id = u;

  UPDATE public.expedition_attempts
    SET fc_extra_purchases_used = fc_extra_purchases_used + 1,
        extra_available = extra_available + 1,
        updated_at = now()
    WHERE user_id = u AND mission_id = m.id AND period = public.game_day_key(now());

  INSERT INTO public.expedition_extra_grants(user_id, mission_id, period, source, status, cost_fc, idempotency_key, granted_at)
  VALUES (u, m.id, public.game_day_key(now()), 'FC', 'GRANTED', price, p_idempotency_key, now());

  BEGIN PERFORM public.spending_track_fc_spend(u, price); EXCEPTION WHEN others THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'spentFc', price,
    'attempts', public.expedition_mission_attempts(u, m.id));
END $$;

-- ---------- start: consume a free attempt, otherwise a mission-scoped extra ----------
CREATE OR REPLACE FUNCTION public.expedition_start(p_telegram_id bigint, p_mission_id uuid, p_pet_ids uuid[])
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare u uuid; m public.expedition_missions; total int := 0; bonus numeric := 0; chance int;
        pid uuid; sn public.sub_nfts; dur numeric; e public.pet_expeditions;
        cfg jsonb; att public.expedition_attempts; free_limit int; v_period date := public.game_day_key(now());
        used_extra boolean := false;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into m from public.expedition_missions where id = p_mission_id and enabled;
  if m.id is null then raise exception 'MISSION_NOT_FOUND'; end if;
  if array_length(p_pet_ids, 1) is distinct from 3 then raise exception 'TEAM_MUST_HAVE_3_PETS'; end if;
  if (select count(distinct x) from unnest(p_pet_ids) x) <> 3 then raise exception 'DUPLICATED_PET'; end if;

  dur := m.duration_hours;
  foreach pid in array p_pet_ids loop
    if not exists (select 1 from public.player_pets where id = pid and user_id = u) then raise exception 'PET_NOT_YOURS'; end if;
    if exists (select 1 from public.pet_expeditions where user_id = u and status = 'ACTIVE' and pid = any(pet_ids)) then
      raise exception 'PET_ON_EXPEDITION'; end if;
    select * into sn from public.sub_nfts where player_pet_id = pid or id = (select sub_nft_id from public.player_pets where id = pid);
    if sn.id is not null and sn.maturity_stage <> 'ADULT' then raise exception 'SUB_NFT_NOT_ADULT'; end if;
    total := total + public.pet_instance_power(pid);
    if sn.trait_code is not null then
      select case tr.effect_key
               when 'mission_success' then tr.effect_value
               when 'long_mission_success' then case when m.duration_hours >= 8 then tr.effect_value else 0 end
               else 0 end
        into bonus from public.sub_nft_traits tr where tr.code = sn.trait_code and tr.enabled;
      bonus := coalesce(bonus, 0);
      if sn.trait_code = 'swift' then dur := dur * 0.95; end if;
    end if;
  end loop;

  -- attempt accounting happens only after every other validation passed
  perform pg_advisory_xact_lock(hashtextextended('exp_extra:'||u::text||':'||m.id::text, 0));
  perform public.expedition_attempt_row(u, m.id, true);
  cfg := public.expedition_limits();
  free_limit := (cfg->>'freeAttemptsPerDay')::int;
  select * into att from public.expedition_attempts
    where user_id = u and mission_id = m.id and period = v_period;

  if att.free_used < free_limit then
    update public.expedition_attempts set free_used = free_used + 1, updated_at = now()
      where user_id = u and mission_id = m.id and period = v_period;
  elsif att.extra_available > 0 then
    update public.expedition_attempts set extra_available = extra_available - 1, updated_at = now()
      where user_id = u and mission_id = m.id and period = v_period;
    used_extra := true;
  else
    raise exception 'EXPEDITION_NO_ATTEMPTS_LEFT';
  end if;

  chance := public.expedition_success_chance(total, m.required_power, bonus);

  insert into public.pet_expeditions(user_id, mission_id, pet_ids, team_power, success_chance, finishes_at)
  values (u, m.id, p_pet_ids, total, chance, now() + make_interval(mins => (dur * 60)::int))
  returning * into e;

  return jsonb_build_object('ok', true, 'expeditionId', e.id, 'teamPower', total, 'successChance', chance,
    'finishesAt', e.finishes_at, 'usedExtra', used_extra,
    'attempts', public.expedition_mission_attempts(u, m.id));
end $function$;

-- ---------- state: expose per-mission counters ----------
CREATE OR REPLACE FUNCTION public.expedition_state(p_telegram_id bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare u uuid; busy uuid[];
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.sub_nft_sync(u);
  select coalesce(array_agg(pid), '{}') into busy
    from (select unnest(pet_ids) pid from public.pet_expeditions where user_id = u and status = 'ACTIVE') b;

  return jsonb_build_object(
    'limits', public.expedition_limits(),
    'pets', coalesce((select jsonb_agg(jsonb_build_object(
        'playerPetId', pp.id, 'name', p.name,
        'image', coalesce(sn_t.image_url, p.image_adult_url, p.image_baby_url),
        'rarity', pp.rarity, 'level', pp.level, 'power', public.pet_instance_power(pp.id),
        'isSubNft', sn.id is not null, 'stage', sn.maturity_stage,
        'trait', sn.trait_code,
        'eligible', (sn.id is null or sn.maturity_stage = 'ADULT') and not (pp.id = any(busy)),
        'busy', pp.id = any(busy)) order by public.pet_instance_power(pp.id) desc)
      from public.player_pets pp
      join public.pets p on p.id = pp.pet_id
      left join public.sub_nfts sn on sn.player_pet_id = pp.id or sn.id = pp.sub_nft_id
      left join public.sub_nft_templates sn_t on sn_t.id = sn.template_id
      where pp.user_id = u), '[]'::jsonb),
    'missions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'code', m.code, 'name', m.name, 'rarity', m.rarity,
        'durationHours', m.duration_hours, 'requiredPower', m.required_power,
        'element', m.recommended_element, 'rewards', m.reward_pool,
        'attempts', public.expedition_mission_attempts(u, m.id)) order by m.sort_order)
      from public.expedition_missions m where m.enabled), '[]'::jsonb),
    'active', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'missionName', m.name, 'missionRarity', m.rarity,
        'startedAt', e.started_at, 'finishesAt', e.finishes_at,
        'teamPower', e.team_power, 'successChance', e.success_chance,
        'ready', e.finishes_at <= now(),
        'pets', (select jsonb_agg(jsonb_build_object('name', p2.name, 'image', coalesce(p2.image_adult_url, p2.image_baby_url)))
                   from public.player_pets pp2 join public.pets p2 on p2.id = pp2.pet_id where pp2.id = any(e.pet_ids)))
        order by e.finishes_at)
      from public.pet_expeditions e join public.expedition_missions m on m.id = e.mission_id
      where e.user_id = u and e.status = 'ACTIVE'), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'missionName', m.name, 'success', e.success, 'rewards', e.rewards, 'claimedAt', e.claimed_at)
        order by e.claimed_at desc)
      from (select * from public.pet_expeditions where user_id = u and status = 'CLAIMED' order by claimed_at desc limit 10) e
      join public.expedition_missions m on m.id = e.mission_id), '[]'::jsonb));
end $function$;

REVOKE ALL ON FUNCTION public.expedition_limits() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expedition_extra_price_fc(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expedition_attempt_row(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expedition_mission_attempts(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expedition_extra_ad_begin(bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expedition_extra_ad_claim(bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expedition_extra_buy_fc(bigint, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expedition_start(bigint, uuid, uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expedition_state(bigint) FROM PUBLIC, anon, authenticated;