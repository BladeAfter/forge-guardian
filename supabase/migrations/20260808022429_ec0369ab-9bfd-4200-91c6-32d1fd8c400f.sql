-- ================= HEROES =================
CREATE OR REPLACE FUNCTION public.admin_list_heroes(p_admin_id bigint, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb; v_total int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT count(*) INTO v_total FROM public.hero_catalog;
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.sort_order, t.hero_key), '[]'::jsonb) INTO v FROM (
    SELECT hero_key, name, rarity, enabled, in_shop, price_fc, price_ton, drop_weight, sort_order, featured, stock
    FROM public.hero_catalog ORDER BY sort_order, hero_key
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit,20),50)) OFFSET GREATEST(0, COALESCE(p_offset,0))
  ) t;
  RETURN jsonb_build_object('total', v_total, 'heroes', v);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_hero_detail(p_admin_id bigint, p_hero_key text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(c) INTO v FROM public.hero_catalog c WHERE c.hero_key = p_hero_key;
  IF v IS NULL THEN RAISE EXCEPTION 'hero_not_found'; END IF;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_hero(p_admin_id bigint, p_hero_key text, p_patch jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF COALESCE(btrim(p_hero_key),'') = '' THEN RAISE EXCEPTION 'invalid_key'; END IF;
  SELECT to_jsonb(c) INTO v_old FROM public.hero_catalog c WHERE c.hero_key = p_hero_key;

  IF v_old IS NULL THEN
    INSERT INTO public.hero_catalog (hero_key, name, rarity, image, enabled)
    VALUES (p_hero_key, COALESCE(p_patch->>'name', p_hero_key),
            public.normalize_hero_rarity(COALESCE(p_patch->>'rarity','comum')),
            COALESCE(p_patch->>'image',''), COALESCE((p_patch->>'enabled')::boolean, true));
  END IF;

  UPDATE public.hero_catalog c SET
    name = COALESCE(p_patch->>'name', c.name),
    description = COALESCE(p_patch->>'description', c.description),
    image = COALESCE(p_patch->>'image', c.image),
    battle_image = COALESCE(p_patch->>'battle_image', c.battle_image),
    rarity = COALESCE(public.normalize_hero_rarity(p_patch->>'rarity'), c.rarity),
    hero_class = COALESCE(p_patch->>'hero_class', c.hero_class),
    base_atk = COALESCE((p_patch->>'base_atk')::numeric, c.base_atk),
    base_hp = COALESCE((p_patch->>'base_hp')::numeric, c.base_hp),
    power = COALESCE((p_patch->>'power')::numeric, c.power),
    start_level = COALESCE((p_patch->>'start_level')::int, c.start_level),
    max_level = COALESCE((p_patch->>'max_level')::int, c.max_level),
    price_fc = COALESCE((p_patch->>'price_fc')::numeric, c.price_fc),
    price_ton = COALESCE((p_patch->>'price_ton')::numeric, c.price_ton),
    discount_percent = COALESCE((p_patch->>'discount_percent')::numeric, c.discount_percent),
    drop_weight = COALESCE((p_patch->>'drop_weight')::numeric, c.drop_weight),
    stock = COALESCE((p_patch->>'stock')::int, c.stock),
    per_player_limit = COALESCE((p_patch->>'per_player_limit')::int, c.per_player_limit),
    featured = COALESCE((p_patch->>'featured')::boolean, c.featured),
    in_shop = COALESCE((p_patch->>'in_shop')::boolean, c.in_shop),
    enabled = COALESCE((p_patch->>'enabled')::boolean, c.enabled),
    sort_order = COALESCE((p_patch->>'sort_order')::int, c.sort_order),
    available_from = COALESCE((p_patch->>'available_from')::timestamptz, c.available_from),
    available_until = COALESCE((p_patch->>'available_until')::timestamptz, c.available_until),
    buffs = COALESCE(p_patch->'buffs', c.buffs),
    skills = COALESCE(p_patch->'skills', c.skills),
    updated_at = now()
  WHERE c.hero_key = p_hero_key;

  SELECT to_jsonb(c) INTO v_new FROM public.hero_catalog c WHERE c.hero_key = p_hero_key;
  PERFORM public.admin_log(p_admin_id, CASE WHEN v_old IS NULL THEN 'hero.create' ELSE 'hero.update' END,'hero',p_hero_key,v_old,v_new,p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_hero_rarity_rates(p_admin_id bigint, p_rates jsonb, p_normalize boolean DEFAULT false, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_total numeric := 0; k text; v numeric; v_final jsonb := '{}'::jsonb; v_old jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  FOR k, v IN SELECT key, (value #>> '{}')::numeric FROM jsonb_each(p_rates) LOOP
    IF v < 0 THEN RAISE EXCEPTION 'invalid_rate'; END IF;
    v_total := v_total + v;
  END LOOP;
  IF v_total <= 0 THEN RAISE EXCEPTION 'invalid_total'; END IF;
  IF abs(v_total - 100) > 0.001 THEN
    IF NOT COALESCE(p_normalize,false) THEN RAISE EXCEPTION 'rates_must_total_100:%', v_total; END IF;
    FOR k, v IN SELECT key, (value #>> '{}')::numeric FROM jsonb_each(p_rates) LOOP
      v_final := v_final || jsonb_build_object(k, round((v / v_total) * 100, 4));
    END LOOP;
  ELSE
    v_final := p_rates;
  END IF;
  SELECT value INTO v_old FROM public.game_settings WHERE key = 'hero_rarity_rates';
  INSERT INTO public.game_settings (key, value, category, label, updated_at, updated_by)
  VALUES ('hero_rarity_rates', v_final, 'heroes','Chances de raridade dos heróis', now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;
  PERFORM public.admin_log(p_admin_id,'hero.rarity_rates','setting','hero_rarity_rates',v_old,v_final,p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN jsonb_build_object('rates', v_final, 'normalized', abs(v_total - 100) > 0.001);
END;
$$;

-- ================= PETS =================
CREATE OR REPLACE FUNCTION public.admin_list_pets(p_admin_id bigint, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v FROM (
    SELECT id, slug, name, category, species, is_enabled FROM public.pets ORDER BY name
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit,20),50)) OFFSET GREATEST(0, COALESCE(p_offset,0))
  ) t;
  RETURN jsonb_build_object('total',(SELECT count(*) FROM public.pets),'pets', v);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_pet(p_admin_id bigint, p_slug text, p_patch jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(p) INTO v_old FROM public.pets p WHERE p.slug = p_slug;
  IF v_old IS NULL THEN
    INSERT INTO public.pets (name, slug, species, category, is_enabled)
    VALUES (COALESCE(p_patch->>'name', p_slug), p_slug, COALESCE(p_patch->>'species','beast'), COALESCE(p_patch->>'category','fire'), COALESCE((p_patch->>'is_enabled')::boolean,true));
  END IF;
  UPDATE public.pets p SET
    name = COALESCE(p_patch->>'name', p.name),
    species = COALESCE(p_patch->>'species', p.species),
    category = COALESCE(p_patch->>'category', p.category),
    description = COALESCE(p_patch->>'description', p.description),
    base_passives = COALESCE(p_patch->'base_passives', p.base_passives),
    active_skill = COALESCE(p_patch->'active_skill', p.active_skill),
    image_baby_url = COALESCE(p_patch->>'image_baby_url', p.image_baby_url),
    image_young_url = COALESCE(p_patch->>'image_young_url', p.image_young_url),
    image_adult_url = COALESCE(p_patch->>'image_adult_url', p.image_adult_url),
    image_ancestral_url = COALESCE(p_patch->>'image_ancestral_url', p.image_ancestral_url),
    is_enabled = COALESCE((p_patch->>'is_enabled')::boolean, p.is_enabled),
    updated_at = now()
  WHERE p.slug = p_slug;
  SELECT to_jsonb(p) INTO v_new FROM public.pets p WHERE p.slug = p_slug;
  PERFORM public.admin_log(p_admin_id, CASE WHEN v_old IS NULL THEN 'pet.create' ELSE 'pet.update' END,'pet',p_slug,v_old,v_new,p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_pet_config(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object(
    'eggs', (SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.name),'[]'::jsonb) FROM public.pet_eggs e),
    'food', (SELECT COALESCE(jsonb_agg(to_jsonb(f) ORDER BY f.sort_order),'[]'::jsonb) FROM public.pet_food_items f),
    'tiers', (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.tier),'[]'::jsonb) FROM public.pet_evolution_tiers t),
    'buffs', (SELECT COALESCE(jsonb_agg(to_jsonb(b)),'[]'::jsonb) FROM public.pet_buff_pool b),
    'settings', (SELECT COALESCE(jsonb_object_agg(key, value),'{}'::jsonb) FROM public.pet_settings)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_pet_food(p_admin_id bigint, p_code text, p_patch jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(f) INTO v_old FROM public.pet_food_items f WHERE f.code = p_code;
  INSERT INTO public.pet_food_items (code, name, rarity, xp_value, icon, sort_order, enabled)
  VALUES (p_code, COALESCE(p_patch->>'name',p_code), COALESCE(p_patch->>'rarity','comum'),
          COALESCE((p_patch->>'xp_value')::int, 50), COALESCE(p_patch->>'icon','🍖'),
          COALESCE((p_patch->>'sort_order')::int, 100), COALESCE((p_patch->>'enabled')::boolean,true))
  ON CONFLICT (code) DO UPDATE SET
    name = COALESCE(EXCLUDED.name, public.pet_food_items.name),
    rarity = COALESCE(p_patch->>'rarity', public.pet_food_items.rarity),
    xp_value = COALESCE((p_patch->>'xp_value')::int, public.pet_food_items.xp_value),
    icon = COALESCE(p_patch->>'icon', public.pet_food_items.icon),
    sort_order = COALESCE((p_patch->>'sort_order')::int, public.pet_food_items.sort_order),
    enabled = COALESCE((p_patch->>'enabled')::boolean, public.pet_food_items.enabled),
    updated_at = now();
  SELECT to_jsonb(f) INTO v_new FROM public.pet_food_items f WHERE f.code = p_code;
  PERFORM public.admin_log(p_admin_id,'pet.food.upsert','pet_food',p_code,v_old,v_new,p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END;
$$;

-- ================= PVP =================
CREATE OR REPLACE FUNCTION public.admin_upsert_league(p_admin_id bigint, p_code text, p_patch jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(l) INTO v_old FROM public.pvp_leagues l WHERE l.code = p_code;
  INSERT INTO public.pvp_leagues (code, name, icon, min_trophies, max_trophies, reward, sort_order, enabled)
  VALUES (p_code, COALESCE(p_patch->>'name',p_code), COALESCE(p_patch->>'icon','🏅'),
          COALESCE((p_patch->>'min_trophies')::int,0), (p_patch->>'max_trophies')::int,
          COALESCE(p_patch->'reward','{}'::jsonb), COALESCE((p_patch->>'sort_order')::int,0),
          COALESCE((p_patch->>'enabled')::boolean,true))
  ON CONFLICT (code) DO UPDATE SET
    name = COALESCE(p_patch->>'name', public.pvp_leagues.name),
    icon = COALESCE(p_patch->>'icon', public.pvp_leagues.icon),
    min_trophies = COALESCE((p_patch->>'min_trophies')::int, public.pvp_leagues.min_trophies),
    max_trophies = COALESCE((p_patch->>'max_trophies')::int, public.pvp_leagues.max_trophies),
    reward = COALESCE(p_patch->'reward', public.pvp_leagues.reward),
    sort_order = COALESCE((p_patch->>'sort_order')::int, public.pvp_leagues.sort_order),
    enabled = COALESCE((p_patch->>'enabled')::boolean, public.pvp_leagues.enabled),
    updated_at = now();
  SELECT to_jsonb(l) INTO v_new FROM public.pvp_leagues l WHERE l.code = p_code;
  PERFORM public.admin_log(p_admin_id,'pvp.league.upsert','league',p_code,v_old,v_new,p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_pvp_overview(p_admin_id bigint, p_top integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.trophies DESC),'[]'::jsonb) INTO v FROM (
    SELECT id, telegram_id, COALESCE(display_name, username,'Jogador') AS name, username,
           pvp_trophies AS trophies, pvp_wins AS wins, pvp_losses AS losses, public.pvp_league(pvp_trophies) AS league, banned
    FROM public.game_players WHERE NOT pvp_banned ORDER BY pvp_trophies DESC, pvp_wins DESC
    LIMIT GREATEST(1, LEAST(COALESCE(p_top,10),100))
  ) t;
  RETURN jsonb_build_object(
    'leagues',(SELECT COALESCE(jsonb_agg(to_jsonb(l) ORDER BY l.sort_order),'[]'::jsonb) FROM public.pvp_leagues l),
    'settings', jsonb_build_object('win', public.setting_num('pvp_trophy_win',30), 'loss', public.setting_num('pvp_trophy_loss',-20),
      'ticket_start', public.setting_num('pvp_ticket_start',5),'ticket_max', public.setting_num('pvp_ticket_max',10),
      'ticket_cost', public.setting_num('pvp_ticket_cost',1),'ticket_regen_minutes', public.setting_num('pvp_ticket_regen_minutes',30),
      'ticket_price_fc', public.setting_num('pvp_ticket_price_fc',5000)),
    'battles_today',(SELECT count(*) FROM public.pvp_battles WHERE created_at > now() - interval '1 day'),
    'ranking', v);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reset_pvp_season(p_admin_id bigint, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_players int; v_snapshot jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF COALESCE(btrim(p_reason),'') = '' THEN RAISE EXCEPTION 'reason_required'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'trophies',pvp_trophies)),'[]'::jsonb), count(*)
    INTO v_snapshot, v_players FROM public.game_players WHERE pvp_trophies <> 0;
  INSERT INTO public.admin_snapshots (admin_id, label, payload) VALUES (p_admin_id,'pvp_season_reset', v_snapshot);
  UPDATE public.game_players SET pvp_trophies = 0, pvp_wins = 0, pvp_losses = 0, updated_at = now();
  PERFORM public.admin_log(p_admin_id,'pvp.season.reset','pvp',NULL,jsonb_build_object('players',v_players),'{}'::jsonb,p_reason,jsonb_build_object('dangerous',true));
  RETURN jsonb_build_object('players_reset', v_players);
END;
$$;

-- ================= SEASON PASS =================
CREATE OR REPLACE FUNCTION public.admin_pass_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.season_pass_seasons;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO s FROM public.season_pass_seasons WHERE active ORDER BY start_at DESC LIMIT 1;
  RETURN jsonb_build_object(
    'season', to_jsonb(s),
    'rewards', (SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.level, r.tier),'[]'::jsonb) FROM public.season_pass_rewards r WHERE r.season_id = s.id),
    'owners', jsonb_build_object(
      'adventurer',(SELECT count(*) FROM public.player_season_pass WHERE season_id = s.id AND adventurer_owned),
      'legendary',(SELECT count(*) FROM public.player_season_pass WHERE season_id = s.id AND legendary_owned)));
END;
$$;

-- ================= POOL =================
CREATE OR REPLACE FUNCTION public.admin_pool_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE p public.pool_balance;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO p FROM public.pool_balance WHERE status = 'open' ORDER BY starts_at DESC LIMIT 1;
  RETURN jsonb_build_object(
    'pool', to_jsonb(p),
    'settings',(SELECT to_jsonb(s) FROM public.pool_settings s LIMIT 1),
    'participants',(SELECT count(DISTINCT user_id) FROM public.pool_points WHERE pool_id = p.id),
    'eligible',(SELECT count(*) FROM (SELECT user_id, sum(points) pts FROM public.pool_points WHERE pool_id = p.id GROUP BY user_id) x
                 WHERE x.pts >= COALESCE((SELECT minimum_points FROM public.pool_settings LIMIT 1),0)));
END;
$$;

-- ================= REFERRAL =================
CREATE OR REPLACE FUNCTION public.admin_set_referral_percent(p_admin_id bigint, p_level integer, p_percent numeric, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_level NOT IN (1,2,3) THEN RAISE EXCEPTION 'invalid_level'; END IF;
  IF p_percent IS NULL OR p_percent < 0 OR p_percent > 100 THEN RAISE EXCEPTION 'invalid_percent'; END IF;
  SELECT percent INTO v_old FROM public.referral_commission_settings WHERE level = p_level;
  INSERT INTO public.referral_commission_settings (level, percent, updated_at)
  VALUES (p_level, p_percent, now())
  ON CONFLICT (level) DO UPDATE SET percent = EXCLUDED.percent, updated_at = now();
  PERFORM public.admin_set_setting(p_admin_id, 'referral_percent_level_'||p_level, to_jsonb(p_percent), p_reason);
  PERFORM public.admin_log(p_admin_id,'referral.percent','referral',p_level::text,to_jsonb(v_old),to_jsonb(p_percent),p_reason);
  RETURN jsonb_build_object('level',p_level,'old_value',v_old,'new_value',p_percent);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_referral_tree(p_admin_id bigint, p_ref text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  RETURN jsonb_build_object(
    'user_id', v_uid,
    'levels', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'level', r.level,
        'user', jsonb_build_object('id',g.id,'telegram_id',g.telegram_id,'name',COALESCE(g.display_name,g.username,'Jogador'),
          'username',g.username,'avatar_url',g.avatar_url,
          'deposited_ton',(SELECT COALESCE(sum(amount_ton),0) FROM public.wallet_deposits d WHERE d.user_id = g.id AND d.status = 'credited'))
      ) ORDER BY r.level, g.created_at), '[]'::jsonb)
      FROM public.referrals r JOIN public.game_players g ON g.id = r.user_id WHERE r.inviter_id = v_uid),
    'commissions', (SELECT COALESCE(jsonb_agg(jsonb_build_object('level',c.level,'amount_fc',c.amount_fc,'from',COALESCE(f.username,f.display_name),'at',c.created_at) ORDER BY c.created_at DESC),'[]'::jsonb)
      FROM (SELECT * FROM public.referral_commissions WHERE user_id = v_uid ORDER BY created_at DESC LIMIT 20) c
      JOIN public.game_players f ON f.id = c.from_user),
    'total_commission_fc', (SELECT COALESCE(sum(amount_fc),0) FROM public.referral_commissions WHERE user_id = v_uid));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_unlink_referral(p_admin_id bigint, p_ref text, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_old jsonb; v_count int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF COALESCE(btrim(p_reason),'') = '' THEN RAISE EXCEPTION 'reason_required'; END IF;
  v_uid := public.admin_resolve_player(p_ref);
  SELECT COALESCE(jsonb_agg(to_jsonb(r)),'[]'::jsonb) INTO v_old FROM public.referrals r WHERE r.user_id = v_uid;
  DELETE FROM public.referrals WHERE user_id = v_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  PERFORM public.admin_log(p_admin_id,'referral.unlink','player',v_uid::text,v_old,'[]'::jsonb,p_reason,jsonb_build_object('dangerous',true));
  RETURN jsonb_build_object('user_id',v_uid,'removed',v_count);
END;
$$;

-- ================= BOSS =================
CREATE OR REPLACE FUNCTION public.admin_upsert_boss(p_admin_id bigint, p_code text, p_patch jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(b) INTO v_old FROM public.boss_templates b WHERE b.code = p_code;
  INSERT INTO public.boss_templates (code, name) VALUES (p_code, COALESCE(p_patch->>'name',p_code))
  ON CONFLICT (code) DO NOTHING;
  UPDATE public.boss_templates b SET
    name = COALESCE(p_patch->>'name', b.name),
    image_url = COALESCE(p_patch->>'image_url', b.image_url),
    level = COALESCE((p_patch->>'level')::int, b.level),
    max_hp = COALESCE((p_patch->>'max_hp')::numeric, b.max_hp),
    attack = COALESCE((p_patch->>'attack')::numeric, b.attack),
    defense = COALESCE((p_patch->>'defense')::numeric, b.defense),
    attack_interval_seconds = COALESCE((p_patch->>'attack_interval_seconds')::int, b.attack_interval_seconds),
    difficulty = COALESCE(p_patch->>'difficulty', b.difficulty),
    reward_amount = COALESCE((p_patch->>'reward_amount')::numeric, b.reward_amount),
    cooldown_seconds = COALESCE((p_patch->>'cooldown_seconds')::int, b.cooldown_seconds),
    ticket_cost = COALESCE((p_patch->>'ticket_cost')::int, b.ticket_cost),
    attack_limit = COALESCE((p_patch->>'attack_limit')::int, b.attack_limit),
    starts_at = COALESCE((p_patch->>'starts_at')::timestamptz, b.starts_at),
    ends_at = COALESCE((p_patch->>'ends_at')::timestamptz, b.ends_at),
    updated_at = now()
  WHERE b.code = p_code;
  SELECT to_jsonb(b) INTO v_new FROM public.boss_templates b WHERE b.code = p_code;
  PERFORM public.admin_log(p_admin_id, CASE WHEN v_old IS NULL THEN 'boss.create' ELSE 'boss.update' END,'boss',p_code,v_old,v_new,p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_boss_control(p_admin_id bigint, p_action text, p_code text DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_action text := lower(COALESCE(p_action,'')); v_count int := 0; b public.boss_templates;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_action = 'spawn' THEN
    SELECT * INTO b FROM public.boss_templates WHERE code = p_code;
    IF b.code IS NULL THEN RAISE EXCEPTION 'boss_not_found'; END IF;
    UPDATE public.boss_templates SET active = (code = p_code), updated_at = now();
    DELETE FROM public.hero_combat_state WHERE combat_id IN (SELECT id FROM public.boss_combats WHERE status = 'active');
    DELETE FROM public.boss_combats WHERE status = 'active';
    GET DIAGNOSTICS v_count = ROW_COUNT;
  ELSIF v_action = 'end' THEN
    UPDATE public.boss_templates SET active = false, updated_at = now() WHERE active;
    UPDATE public.boss_combats SET status = 'expired', updated_at = now() WHERE status = 'active';
    GET DIAGNOSTICS v_count = ROW_COUNT;
  ELSIF v_action = 'reset_hp' THEN
    UPDATE public.boss_combats SET boss_current_hp = boss_max_hp, total_damage_dealt = 0, updated_at = now() WHERE status = 'active';
    GET DIAGNOSTICS v_count = ROW_COUNT;
  ELSE
    RAISE EXCEPTION 'invalid_action';
  END IF;
  PERFORM public.admin_log(p_admin_id,'boss.'||v_action,'boss',p_code,NULL,jsonb_build_object('affected',v_count),p_reason,jsonb_build_object('dangerous',true));
  RETURN jsonb_build_object('action',v_action,'affected',v_count);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_boss_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object(
    'templates',(SELECT COALESCE(jsonb_agg(to_jsonb(b) ORDER BY b.level),'[]'::jsonb) FROM public.boss_templates b),
    'active_combats',(SELECT count(*) FROM public.boss_combats WHERE status = 'active'),
    'top_damage',(SELECT COALESCE(jsonb_agg(jsonb_build_object('name',COALESCE(g.display_name,g.username,'Jogador'),'damage',c.total_damage_dealt) ORDER BY c.total_damage_dealt DESC),'[]'::jsonb)
      FROM (SELECT * FROM public.boss_combats WHERE status = 'active' ORDER BY total_damage_dealt DESC LIMIT 10) c
      JOIN public.game_players g ON g.id = c.user_id));
END;
$$;

-- ================= MISSIONS =================
CREATE OR REPLACE FUNCTION public.admin_upsert_mission(p_admin_id bigint, p_code text, p_patch jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(m) INTO v_old FROM public.game_missions m WHERE m.code = p_code;
  INSERT INTO public.game_missions (code, title) VALUES (p_code, COALESCE(p_patch->>'title',p_code))
  ON CONFLICT (code) DO NOTHING;
  UPDATE public.game_missions m SET
    scope = COALESCE(p_patch->>'scope', m.scope),
    title = COALESCE(p_patch->>'title', m.title),
    description = COALESCE(p_patch->>'description', m.description),
    target_metric = COALESCE(p_patch->>'target_metric', m.target_metric),
    target_amount = COALESCE((p_patch->>'target_amount')::numeric, m.target_amount),
    reward_type = COALESCE(p_patch->>'reward_type', m.reward_type),
    reward_code = COALESCE(p_patch->>'reward_code', m.reward_code),
    reward_amount = COALESCE((p_patch->>'reward_amount')::numeric, m.reward_amount),
    reward_xp = COALESCE((p_patch->>'reward_xp')::int, m.reward_xp),
    daily_limit = COALESCE((p_patch->>'daily_limit')::int, m.daily_limit),
    sort_order = COALESCE((p_patch->>'sort_order')::int, m.sort_order),
    enabled = COALESCE((p_patch->>'enabled')::boolean, m.enabled),
    updated_at = now()
  WHERE m.code = p_code;
  SELECT to_jsonb(m) INTO v_new FROM public.game_missions m WHERE m.code = p_code;
  PERFORM public.admin_log(p_admin_id, CASE WHEN v_old IS NULL THEN 'mission.create' ELSE 'mission.update' END,'mission',p_code,v_old,v_new,p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_missions_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object('missions',(SELECT COALESCE(jsonb_agg(to_jsonb(m) ORDER BY m.scope, m.sort_order),'[]'::jsonb) FROM public.game_missions m));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reset_missions(p_admin_id bigint, p_scope text, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  DELETE FROM public.player_mission_progress pmp
   WHERE p_scope IS NULL OR pmp.mission_code IN (SELECT code FROM public.game_missions WHERE scope = p_scope);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  PERFORM public.admin_log(p_admin_id,'mission.reset','mission',p_scope,NULL,jsonb_build_object('cleared',v_count),p_reason,jsonb_build_object('dangerous',true));
  RETURN jsonb_build_object('cleared',v_count);
END;
$$;

-- ================= WALLET =================
CREATE OR REPLACE FUNCTION public.admin_list_transactions(p_admin_id bigint, p_kind text, p_status text DEFAULT NULL, p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb; v_kind text := lower(COALESCE(p_kind,'deposit'));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_kind = 'deposit' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC),'[]'::jsonb) INTO v FROM (
      SELECT d.id, d.amount_ton, d.amount_fc, d.status, d.tx_hash, d.from_wallet, d.created_at,
             COALESCE(g.username, g.display_name, g.telegram_id::text) AS player
      FROM public.wallet_deposits d JOIN public.game_players g ON g.id = d.user_id
      WHERE p_status IS NULL OR d.status = p_status
      ORDER BY d.created_at DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit,10),50))) t;
  ELSE
    SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC),'[]'::jsonb) INTO v FROM (
      SELECT w.id, w.amount_fc, w.amount_ton, w.status, w.tx_hash, w.wallet_address, w.created_at,
             COALESCE(g.username, g.display_name, g.telegram_id::text) AS player
      FROM public.wallet_withdrawals w JOIN public.game_players g ON g.id = w.user_id
      WHERE p_status IS NULL OR w.status = p_status
      ORDER BY w.created_at DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit,10),50))) t;
  END IF;
  RETURN jsonb_build_object('kind',v_kind,'items',v);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_review_deposit(p_admin_id bigint, p_deposit_id uuid, p_approve boolean, p_tx_hash text DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d public.wallet_deposits; v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO d FROM public.wallet_deposits WHERE id = p_deposit_id FOR UPDATE;
  IF d.id IS NULL THEN RAISE EXCEPTION 'deposit_not_found'; END IF;
  IF d.status IN ('credited','confirmed') AND p_approve THEN RAISE EXCEPTION 'already_confirmed'; END IF;
  IF p_approve THEN
    v := public.confirm_wallet_deposit(d.id, COALESCE(p_tx_hash, d.tx_hash, 'admin:'||d.id::text), NULL);
  ELSE
    UPDATE public.wallet_deposits SET status = 'rejected' WHERE id = d.id;
    v := jsonb_build_object('status','rejected');
  END IF;
  PERFORM public.admin_log(p_admin_id, CASE WHEN p_approve THEN 'deposit.confirm' ELSE 'deposit.reject' END,'deposit',d.id::text,
    jsonb_build_object('status',d.status), v, p_reason, jsonb_build_object('financial',true));
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_review_withdrawal(p_admin_id bigint, p_withdrawal_id uuid, p_status text, p_tx_hash text DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE w public.wallet_withdrawals; v jsonb; v_status text := lower(COALESCE(p_status,''));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_status NOT IN ('paid','rejected','approved') THEN RAISE EXCEPTION 'invalid_status'; END IF;
  SELECT * INTO w FROM public.wallet_withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
  IF w.id IS NULL THEN RAISE EXCEPTION 'withdrawal_not_found'; END IF;
  IF w.status IN ('paid','rejected') THEN RAISE EXCEPTION 'already_processed'; END IF;
  IF v_status = 'approved' THEN
    UPDATE public.wallet_withdrawals SET status = 'approved' WHERE id = w.id;
    v := jsonb_build_object('status','approved');
  ELSE
    v := public.finish_wallet_withdrawal(w.id, v_status, p_tx_hash);
  END IF;
  PERFORM public.admin_log(p_admin_id,'withdrawal.'||v_status,'withdrawal',w.id::text,
    jsonb_build_object('status',w.status), v, p_reason, jsonb_build_object('financial',true));
  RETURN v;
END;
$$;

-- ================= ADS =================
CREATE OR REPLACE FUNCTION public.admin_upsert_ad_provider(p_admin_id bigint, p_code text, p_patch jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(a) INTO v_old FROM public.ad_providers a WHERE a.code = p_code;
  INSERT INTO public.ad_providers (code, name) VALUES (p_code, COALESCE(p_patch->>'name',p_code))
  ON CONFLICT (code) DO NOTHING;
  UPDATE public.ad_providers a SET
    name = COALESCE(p_patch->>'name', a.name),
    enabled = COALESCE((p_patch->>'enabled')::boolean, a.enabled),
    daily_limit = COALESCE((p_patch->>'daily_limit')::int, a.daily_limit),
    reward_fc = COALESCE((p_patch->>'reward_fc')::numeric, a.reward_fc),
    cooldown_seconds = COALESCE((p_patch->>'cooldown_seconds')::int, a.cooldown_seconds),
    config = COALESCE(p_patch->'config', a.config),
    updated_at = now()
  WHERE a.code = p_code;
  SELECT to_jsonb(a) INTO v_new FROM public.ad_providers a WHERE a.code = p_code;
  PERFORM public.admin_log(p_admin_id,'ads.update','ad_provider',p_code,v_old,v_new,p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_ads_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object('providers',(SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.code),'[]'::jsonb) FROM public.ad_providers a));
END;
$$;

-- ================= STATUS / AUDIT / SNAPSHOT / BROADCAST =================
CREATE OR REPLACE FUNCTION public.admin_status_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object(
    'players_total',(SELECT count(*) FROM public.game_players),
    'players_active_24h',(SELECT count(*) FROM public.game_players WHERE last_seen_at > now() - interval '1 day'),
    'players_new_24h',(SELECT count(*) FROM public.game_players WHERE created_at > now() - interval '1 day'),
    'players_banned',(SELECT count(*) FROM public.game_players WHERE banned),
    'fc_circulating',(SELECT COALESCE(sum(forge_coins),0) FROM public.game_players),
    'ton_deposited',(SELECT COALESCE(sum(amount_ton),0) FROM public.wallet_deposits WHERE status = 'credited'),
    'ton_withdrawn',(SELECT COALESCE(sum(amount_ton),0) FROM public.wallet_withdrawals WHERE status = 'paid'),
    'pool_balance',(SELECT COALESCE(balance_ton,0) FROM public.pool_balance WHERE status = 'open' ORDER BY starts_at DESC LIMIT 1),
    'pvp_battles_24h',(SELECT count(*) FROM public.pvp_battles WHERE created_at > now() - interval '1 day'),
    'boss_active',(SELECT count(*) FROM public.boss_combats WHERE status = 'active'),
    'heroes_total',(SELECT count(*) FROM public.player_heroes),
    'pets_total',(SELECT count(*) FROM public.player_pets),
    'referrals_total',(SELECT count(*) FROM public.referrals WHERE level = 1),
    'maintenance', public.setting_bool('maintenance_mode', false),
    'settings_version', public.setting_num('settings_version',1)::int);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_audit(p_admin_id bigint, p_limit integer DEFAULT 15, p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC),'[]'::jsonb) INTO v FROM (
    SELECT id, admin_id, action, target_type, target_id, old_value, new_value, reason, created_at
    FROM public.admin_audit_logs ORDER BY created_at DESC
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit,15),50)) OFFSET GREATEST(0, COALESCE(p_offset,0))) t;
  RETURN jsonb_build_object('total',(SELECT count(*) FROM public.admin_audit_logs),'events',v);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_create_snapshot(p_admin_id bigint, p_label text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_payload jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_payload := jsonb_build_object(
    'settings',(SELECT COALESCE(jsonb_object_agg(key,value),'{}'::jsonb) FROM public.game_settings),
    'heroes',(SELECT COALESCE(jsonb_agg(to_jsonb(c)),'[]'::jsonb) FROM public.hero_catalog c),
    'leagues',(SELECT COALESCE(jsonb_agg(to_jsonb(l)),'[]'::jsonb) FROM public.pvp_leagues l),
    'missions',(SELECT COALESCE(jsonb_agg(to_jsonb(m)),'[]'::jsonb) FROM public.game_missions m),
    'boss',(SELECT COALESCE(jsonb_agg(to_jsonb(b)),'[]'::jsonb) FROM public.boss_templates b),
    'pool_settings',(SELECT to_jsonb(s) FROM public.pool_settings s LIMIT 1),
    'referral',(SELECT COALESCE(jsonb_agg(to_jsonb(r)),'[]'::jsonb) FROM public.referral_commission_settings r),
    'stats', public.admin_status_overview(p_admin_id));
  INSERT INTO public.admin_snapshots (admin_id, label, payload)
  VALUES (p_admin_id, COALESCE(NULLIF(btrim(p_label),''), 'snapshot'), v_payload) RETURNING id INTO v_id;
  PERFORM public.admin_log(p_admin_id,'snapshot.create','system',v_id::text,NULL,jsonb_build_object('label',p_label),NULL);
  RETURN jsonb_build_object('snapshot_id',v_id,'label',p_label,'created_at',now());
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_broadcast_targets(p_admin_id bigint, p_segment text, p_limit integer DEFAULT 2000)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb; v_seg text := lower(COALESCE(p_segment,'all'));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(telegram_id),'[]'::jsonb) INTO v FROM (
    SELECT telegram_id FROM public.game_players g
     WHERE NOT g.banned AND (
       v_seg = 'all'
       OR (v_seg = 'vip' AND g.vip_until > now())
       OR (v_seg = 'premium' AND g.premium_until > now())
       OR (v_seg = 'active' AND g.last_seen_at > now() - interval '7 days')
       OR (v_seg = 'top_pvp' AND g.pvp_trophies > 0))
     ORDER BY CASE WHEN v_seg = 'top_pvp' THEN g.pvp_trophies ELSE 0 END DESC, g.last_seen_at DESC
     LIMIT GREATEST(1, LEAST(COALESCE(p_limit,2000), 5000))) t;
  RETURN jsonb_build_object('segment',v_seg,'targets',v);
END;
$$;

-- lock everything down
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname LIKE 'admin\_%'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon, authenticated', r.sig);
  END LOOP;
END $$;
