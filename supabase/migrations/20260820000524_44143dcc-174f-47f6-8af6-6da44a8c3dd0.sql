-- ===== HERO FUSION FEE =====
drop function if exists public.fuse_heroes(bigint, uuid, uuid[], boolean, text);
create or replace function public.fuse_heroes(p_telegram_id bigint, p_main_hero_id uuid, p_material_ids uuid[] default '{}'::uuid[],
  p_use_fragments boolean default false, p_idempotency_key text default null, p_fee_currency text default 'FC')
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid; balance numeric; cfg jsonb := hero_fusion_config(); main player_heroes%rowtype;
  required int; cost numeric; max_stars int; ids uuid[] := '{}'::uuid[]; used int := 0;
  after_row player_heroes%rowtype; after_balance numeric;
  frag_cost int := 0; frag_left int := null; v_key text; v_cur text; v_myth numeric; v_burn jsonb;
begin
  v_cur := case when upper(coalesce(p_fee_currency,'FC')) = 'MYTH' then 'MYTH' else 'FC' end;
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('hero_fusion:' || u::text, 0));

  v_key := nullif(p_idempotency_key, '');
  if v_key is not null and exists (
    select 1 from hero_fusion_history where user_id = u and idempotency_key = v_key
  ) then
    raise exception 'DUPLICATE_REQUEST';
  end if;

  select * into main from player_heroes where id = p_main_hero_id and user_id = u for update;
  if main.id is null then raise exception 'HERO_NOT_OWNED'; end if;
  if main.is_nft_exclusive then raise exception 'NFT_HERO_UNIQUE'; end if;

  max_stars := coalesce((cfg->>'max_stars')::int, 5);
  if main.fusion_level >= max_stars then raise exception 'HERO_MAX_STARS'; end if;
  required := public.hero_fusion_required_copies(main.fusion_level);
  cost := coalesce((cfg->'cost_fc'->>(main.fusion_level+1)::text)::numeric, 0);

  if v_cur = 'MYTH' then
    if cost > 0 then
      v_myth := public.myth_utility_price('HERO_FUSE', cost, 0);
      if v_myth is null then raise exception 'MYTH_PAYMENT_NOT_ENABLED'; end if;
    else v_myth := 0; end if;
  else
    if balance < cost then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;
  end if;

  -- Materials are ALWAYS required, regardless of the currency used for the fee.
  if p_use_fragments then
    frag_cost := public.universal_fusion_fragment_cost();
    if public.universal_fragment_balance(u) < frag_cost then raise exception 'NOT_ENOUGH_UNIVERSAL_FRAGMENTS'; end if;
    update player_pet_inventory set quantity = quantity - frag_cost, updated_at = now()
      where user_id = u and item_type = 'universal_fragment' and item_id is null
      returning quantity into frag_left;
    if frag_left is null or frag_left < 0 then raise exception 'NOT_ENOUGH_UNIVERSAL_FRAGMENTS'; end if;
  else
    if exists(select 1 from player_heroes where id = any(coalesce(p_material_ids,'{}'::uuid[])) and is_nft_exclusive) then
      raise exception 'NFT_HERO_UNIQUE';
    end if;
    select coalesce(array_agg(id), '{}') into ids from (
      select ph.id from player_heroes ph
      where ph.user_id = u and ph.id <> main.id and ph.hero_key = main.hero_key
        and ph.id = any(coalesce(p_material_ids, '{}'::uuid[]))
        and public.hero_fusion_material_available(ph.id)
      order by ph.fusion_level, ph.level
      limit required
      for update
    ) s;
    used := coalesce(array_length(ids,1), 0);
    if used < required then raise exception 'NOT_ENOUGH_DUPLICATES'; end if;
  end if;

  if v_cur = 'MYTH' then
    after_balance := balance;
    if coalesce(v_myth,0) > 0 then
      v_burn := public.myth_utility_charge(u, 'HERO_FUSE', v_myth, main.id::text,
        coalesce(v_key, 'fuse:'||u::text||':'||gen_random_uuid()::text),
        jsonb_build_object('heroId', main.id, 'fromStars', main.fusion_level, 'fcEquivalent', cost));
    end if;
  else
    update game_players set forge_coins = forge_coins - cost, updated_at = now() where id = u returning forge_coins into after_balance;
  end if;

  if not p_use_fragments then
    delete from hero_combat_state where hero_id = any(ids);
    delete from player_heroes where id = any(ids) and user_id = u;
  end if;

  update player_heroes set fusion_level = fusion_level + 1, updated_at = now() where id = main.id returning * into after_row;

  insert into hero_fusion_history(user_id, hero_id, hero_key, from_stars, to_stars, materials_consumed, material_ids, cost_fc,
      atk_before, atk_after, hp_before, hp_after, universal_fragments_spent, idempotency_key)
  values (u, main.id, main.hero_key, main.fusion_level, after_row.fusion_level, used, ids,
      case when v_cur = 'MYTH' then 0 else cost end,
      main.final_atk, after_row.final_atk, main.final_hp, after_row.final_hp, frag_cost, v_key);

  return jsonb_build_object(
    'heroId', main.id, 'name', after_row.name, 'fromStars', main.fusion_level, 'toStars', after_row.fusion_level,
    'atkBefore', round(main.final_atk), 'atkAfter', round(after_row.final_atk),
    'hpBefore', round(main.final_hp), 'hpAfter', round(after_row.final_hp),
    'bonusPercent', coalesce((cfg->'bonus_percent'->>after_row.fusion_level::text)::numeric, 0),
    'maxLevel', hero_max_level(after_row.fusion_level),
    'costFc', case when v_cur = 'MYTH' then 0 else cost end, 'consumed', used, 'balance', after_balance,
    'paidWith', v_cur, 'mythSpent', coalesce(v_myth, 0), 'mythBurn', v_burn,
    'usedFragments', p_use_fragments, 'fragmentsSpent', frag_cost,
    'universalFragments', public.universal_fragment_balance(u),
    'dashboard', get_hero_fusion_dashboard(p_telegram_id)
  );
end $$;

-- ===== PET EVOLUTION =====
drop function if exists public.evolve_pet(bigint, uuid, text);
create or replace function public.evolve_pet(p_telegram_id bigint, p_player_pet_id uuid, p_idempotency_key text,
  p_currency text default 'FC')
returns jsonb language plpgsql security definer set search_path to 'public' as $$
DECLARE u uuid; balance numeric; pet player_pets%rowtype; cat text; base jsonb; nxt pet_evolution_tiers%rowtype;
        before_primary numeric; pkey text; buffs jsonb; payload jsonb;
        used int; roll numeric; newkey text; newval numeric; newrarity text; cand text[]; pick jsonb; acc numeric; total numeric;
        spec_spend int; uni_spend int; uni_have int; v_cur text; v_myth numeric; v_burn jsonb;
BEGIN
  IF length(coalesce(p_idempotency_key,'')) < 8 THEN RAISE EXCEPTION 'INVALID_EVOLVE_REQUEST'; END IF;
  v_cur := case when upper(coalesce(p_currency,'FC')) = 'MYTH' then 'MYTH' else 'FC' end;
  SELECT id, forge_coins INTO u, balance FROM game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT result INTO payload FROM pet_action_idempotency WHERE idempotency_key = p_idempotency_key AND user_id = u;
  IF payload IS NOT NULL THEN RETURN payload; END IF;

  SELECT * INTO pet FROM player_pets WHERE id = p_player_pet_id AND user_id = u FOR UPDATE;
  IF pet.id IS NULL THEN RAISE EXCEPTION 'PET_NOT_OWNED'; END IF;
  SELECT p.category, p.base_passives INTO cat, base FROM pets p WHERE p.id = pet.pet_id;

  SELECT * INTO nxt FROM pet_evolution_tiers WHERE tier = pet.evolution_tier + 1 AND enabled;
  IF nxt.tier IS NULL THEN RAISE EXCEPTION 'PET_FULLY_EVOLVED'; END IF;
  IF pet.level < nxt.required_level THEN RAISE EXCEPTION 'PET_LEVEL_TOO_LOW'; END IF;

  IF v_cur = 'MYTH' THEN
    IF nxt.fc_cost > 0 THEN
      v_myth := public.myth_utility_price('PET_UPGRADE', nxt.fc_cost, 0);
      IF v_myth IS NULL THEN RAISE EXCEPTION 'MYTH_PAYMENT_NOT_ENABLED'; END IF;
    ELSE v_myth := 0; END IF;
  ELSE
    IF balance < nxt.fc_cost THEN RAISE EXCEPTION 'NOT_ENOUGH_FORGE_COINS'; END IF;
  END IF;

  SELECT quantity INTO uni_have FROM player_pet_inventory
    WHERE user_id = u AND item_type = 'universal_fragment' AND item_id IS NULL FOR UPDATE;
  uni_have := coalesce(uni_have, 0);
  spec_spend := least(pet.fragments, nxt.fragment_cost);
  uni_spend := nxt.fragment_cost - spec_spend;
  IF uni_spend > uni_have THEN RAISE EXCEPTION 'NOT_ENOUGH_PET_FRAGMENTS'; END IF;

  buffs := player_pet_buffs(pet.id);
  SELECT key INTO pkey FROM jsonb_each(coalesce(base,'{}'::jsonb)) ORDER BY (value#>>'{}')::numeric DESC LIMIT 1;
  before_primary := coalesce((buffs->>pkey)::numeric, 0);

  IF v_cur = 'MYTH' THEN
    IF coalesce(v_myth,0) > 0 THEN
      v_burn := public.myth_utility_charge(u, 'PET_UPGRADE', v_myth, pet.id::text, p_idempotency_key,
        jsonb_build_object('petId', pet.id, 'tier', nxt.tier, 'fcEquivalent', nxt.fc_cost, 'kind', 'evolution'));
    END IF;
  ELSE
    UPDATE game_players SET forge_coins = forge_coins - nxt.fc_cost, updated_at = now() WHERE id = u;
  END IF;

  UPDATE player_pets SET fragments = fragments - spec_spend, evolution_tier = nxt.tier,
         evolution_stage = nxt.evolution_stage, updated_at = now() WHERE id = pet.id;
  IF uni_spend > 0 THEN
    UPDATE player_pet_inventory SET quantity = quantity - uni_spend, updated_at = now()
      WHERE user_id = u AND item_type = 'universal_fragment' AND item_id IS NULL;
  END IF;

  used := jsonb_array_length(coalesce(pet.secondary_buffs,'[]'::jsonb));
  IF used < nxt.max_secondary_buffs THEN
    roll := random();
    IF roll < nxt.new_buff_chance THEN
      SELECT array_agg(b.buff_key) INTO cand FROM pet_buff_pool b
        WHERE b.enabled AND b.categories ? cat
          AND NOT (coalesce(base,'{}'::jsonb) ? b.buff_key)
          AND NOT exists(SELECT 1 FROM jsonb_array_elements(coalesce(pet.secondary_buffs,'[]'::jsonb)) s WHERE s->>'key' = b.buff_key);
      IF cand IS NOT NULL AND array_length(cand,1) > 0 THEN
        newkey := cand[1 + floor(random() * array_length(cand,1))::int];
        SELECT sum((value->>'weight')::numeric) INTO total FROM jsonb_array_elements((SELECT value FROM pet_settings WHERE key = 'secondary_buff_rarities'));
        roll := random() * coalesce(total,1); acc := 0;
        FOR pick IN SELECT value FROM jsonb_array_elements((SELECT value FROM pet_settings WHERE key = 'secondary_buff_rarities')) LOOP
          acc := acc + (pick->>'weight')::numeric;
          IF roll <= acc THEN newrarity := pick->>'rarity'; newval := (pick->>'value')::numeric; EXIT; END IF;
        END LOOP;
        IF newrarity IS NULL THEN newrarity := 'common'; newval := 2; END IF;
        UPDATE player_pets SET secondary_buffs = coalesce(secondary_buffs,'[]'::jsonb) ||
          jsonb_build_array(jsonb_build_object('key', newkey, 'value', newval, 'rarity', newrarity, 'tier', nxt.tier))
          WHERE id = pet.id;
      ELSE newkey := NULL; END IF;
    END IF;
  END IF;

  INSERT INTO pet_evolutions (user_id, player_pet_id, evolution_from, evolution_to, level_at_evolution,
    fc_spent, fragments_spent, unlocked_buff, unlocked_buff_value, unlocked_buff_rarity, idempotency_key)
  VALUES (u, pet.id, pet.evolution_tier, nxt.tier, pet.level,
    case when v_cur = 'MYTH' then 0 else nxt.fc_cost end, nxt.fragment_cost, newkey, newval, newrarity, p_idempotency_key);

  buffs := player_pet_buffs(pet.id);
  payload := jsonb_build_object('dashboard', get_pet_dashboard(p_telegram_id),
    'paidWith', v_cur, 'mythSpent', coalesce(v_myth, 0), 'mythBurn', v_burn,
    'evolveResult', jsonb_build_object('petName', (SELECT name FROM pets WHERE id = pet.pet_id),
      'tier', nxt.tier, 'label', nxt.label, 'primaryBuffKey', pkey,
      'primaryBefore', before_primary, 'primaryAfter', coalesce((buffs->>pkey)::numeric, 0),
      'newBuff', CASE WHEN newkey IS NULL THEN NULL ELSE jsonb_build_object('key', newkey, 'value', newval, 'rarity', newrarity) END,
      'fcSpent', case when v_cur = 'MYTH' then 0 else nxt.fc_cost end, 'fragmentsSpent', nxt.fragment_cost,
      'petFragmentsSpent', spec_spend, 'universalFragmentsSpent', uni_spend,
      'universalFragmentsLeft', uni_have - uni_spend));
  INSERT INTO pet_action_idempotency VALUES (p_idempotency_key, u, pet.id, 'evolve', payload, now());
  RETURN payload;
END $$;

-- ===== SEASON PASS: buy with MYTH =====
create or replace function public.season_pass_buy_with_myth(p_telegram_id bigint, p_tier text, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        v_price_ton numeric; v_myth numeric; v_burn jsonb; v_upgrade boolean := false; v_row public.player_season_pass;
begin
  if p_tier not in ('adventurer','legendary') then raise exception 'INVALID_PASS_TIER'; end if;
  if length(coalesce(p_idempotency_key,'')) < 8 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  select id into u from game_players where telegram_id = p_telegram_id;
  select * into s from public.season_pass_seasons where active and now() between start_at and end_at;
  if u is null or s.id is null then raise exception 'SEASON_NOT_AVAILABLE'; end if;
  perform pg_advisory_xact_lock(hashtextextended('pass_myth:'||u::text, 0));

  insert into public.player_season_pass(user_id, season_id, tier) values (u, s.id, 'none')
    on conflict (user_id, season_id) do nothing;
  select * into p from public.player_season_pass where user_id = u and season_id = s.id for update;
  if p.tier = 'legendary' then raise exception 'PASS_ALREADY_OWNED'; end if;
  if p_tier = 'adventurer' and p.tier = 'adventurer' then raise exception 'PASS_ALREADY_OWNED'; end if;

  v_upgrade := (p_tier = 'legendary' and p.tier = 'adventurer');
  v_price_ton := case
    when p_tier = 'adventurer' then s.adventurer_price_ton
    when v_upgrade then greatest(s.legendary_price_ton - s.adventurer_price_ton, 0)
    else s.legendary_price_ton end;
  if coalesce(v_price_ton,0) <= 0 then raise exception 'INVALID_PASS_PRICE'; end if;

  v_myth := public.myth_utility_price('PASS_PURCHASE', 0, v_price_ton);
  if v_myth is null then raise exception 'MYTH_PAYMENT_NOT_ENABLED'; end if;

  v_burn := public.myth_utility_charge(u, 'PASS_PURCHASE', v_myth, s.id::text || ':' || p_tier, p_idempotency_key,
    jsonb_build_object('seasonId', s.id, 'tier', p_tier, 'tonReference', v_price_ton, 'upgrade', v_upgrade));

  v_row := public.season_pass_apply_entitlement(u, s.id, p_tier);

  return public.get_season_pass_dashboard(p_telegram_id) || jsonb_build_object(
    'purchase', jsonb_build_object('tier', v_row.tier, 'paidWith', 'MYTH', 'mythSpent', v_myth,
      'tonReference', v_price_ton, 'upgrade', v_upgrade, 'mythBurn', v_burn));
end $$;

-- ===== SEASON PASS LEVELS =====
drop function if exists public.buy_season_pass_levels(bigint, integer, text);
create or replace function public.buy_season_pass_levels(p_telegram_id bigint, p_levels integer, p_idempotency_key text,
  p_currency text default 'FC')
returns jsonb language plpgsql security definer set search_path to 'public' as $$
DECLARE u public.game_players; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        cfg jsonb; v_price numeric; v_limit int; v_bought int; v_xpl int; v_level int;
        v_new_level int; v_xp_into int; v_new_xp numeric; v_before numeric; v_day date;
        v_cur text; v_myth numeric; v_burn jsonb;
BEGIN
  v_cur := case when upper(coalesce(p_currency,'FC')) = 'MYTH' then 'MYTH' else 'FC' end;
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pass_level_buy'||u.id::text, 0));
  IF EXISTS (SELECT 1 FROM public.season_pass_level_purchases WHERE idempotency_key = p_idempotency_key) THEN
    RETURN public.get_season_pass_dashboard(p_telegram_id);
  END IF;

  cfg := public.season_pass_level_purchase_config();
  IF NOT COALESCE((cfg->>'enabled')::boolean, true) THEN RAISE EXCEPTION 'LEVEL_PURCHASE_DISABLED'; END IF;
  v_price := (cfg->'prices'->>p_levels::text)::numeric;
  IF v_price IS NULL OR p_levels <= 0 THEN RAISE EXCEPTION 'INVALID_PACK'; END IF;

  SELECT * INTO s FROM public.season_pass_seasons WHERE active AND now() BETWEEN start_at AND end_at;
  IF s.id IS NULL THEN RAISE EXCEPTION 'SEASON_NOT_AVAILABLE'; END IF;
  INSERT INTO public.player_season_pass(user_id, season_id, tier) VALUES (u.id, s.id, 'none')
    ON CONFLICT (user_id, season_id) DO NOTHING;
  SELECT * INTO p FROM public.player_season_pass WHERE user_id = u.id AND season_id = s.id FOR UPDATE;

  v_xpl := GREATEST(1, s.xp_per_level);
  v_level := LEAST(s.levels, (p.xp / v_xpl)::int + 1);
  IF v_level >= s.levels THEN RAISE EXCEPTION 'MAX_LEVEL_REACHED'; END IF;
  IF v_level + p_levels > s.levels THEN RAISE EXCEPTION 'LEVELS_AVAILABLE_%', s.levels - v_level; END IF;

  v_day := public.quest_today();
  v_limit := GREATEST(0, COALESCE((cfg->>'daily_limit')::int, 5));
  SELECT COALESCE(sum(levels_bought),0) INTO v_bought FROM public.season_pass_level_purchases
    WHERE user_id = u.id AND purchase_date = v_day;
  IF v_bought + p_levels > v_limit THEN RAISE EXCEPTION 'DAILY_LIMIT_%', GREATEST(0, v_limit - v_bought); END IF;

  v_xp_into := (p.xp % v_xpl)::int;
  v_new_level := v_level + p_levels;
  v_new_xp := (v_new_level - 1)::numeric * v_xpl + v_xp_into;
  v_before := COALESCE(u.forge_coins,0);

  IF v_cur = 'MYTH' THEN
    v_myth := public.myth_utility_price('PASS_LEVELS', v_price, 0);
    IF v_myth IS NULL THEN RAISE EXCEPTION 'MYTH_PAYMENT_NOT_ENABLED'; END IF;
    v_burn := public.myth_utility_charge(u.id, 'PASS_LEVELS', v_myth, s.id::text, p_idempotency_key,
      jsonb_build_object('levels', p_levels, 'fcEquivalent', v_price));
  ELSE
    IF COALESCE(u.forge_coins,0) < v_price THEN RAISE EXCEPTION 'INSUFFICIENT_FC'; END IF;
    UPDATE public.game_players SET forge_coins = forge_coins - v_price WHERE id = u.id;
    INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id)
    VALUES (u.id, 'battle_pass_level_purchase', -v_price, v_before, v_before - v_price, p_idempotency_key);
  END IF;

  UPDATE public.player_season_pass SET xp = v_new_xp, updated_at = now()
    WHERE user_id = u.id AND season_id = s.id;

  INSERT INTO public.season_pass_level_purchases
    (user_id, season_id, purchase_date, levels_bought, fc_spent, level_before, level_after, xp_before, xp_after, idempotency_key)
  VALUES (u.id, s.id, v_day, p_levels, CASE WHEN v_cur = 'MYTH' THEN 0 ELSE v_price END,
    v_level, v_new_level, p.xp, v_new_xp, p_idempotency_key);

  RETURN public.get_season_pass_dashboard(p_telegram_id)
    || jsonb_build_object('purchase', jsonb_build_object('levelsBought', p_levels,
         'fcSpent', CASE WHEN v_cur = 'MYTH' THEN 0 ELSE v_price END, 'paidWith', v_cur,
         'mythSpent', COALESCE(v_myth, 0), 'mythBurn', v_burn,
         'levelBefore', v_level, 'levelAfter', v_new_level));
END; $$;

-- ===== server-only execution for every function touched here =====
revoke execute on function public.buy_pet_food(bigint, text, integer, text, text) from public, anon, authenticated;
revoke execute on function public.buy_pet_egg(bigint, uuid, integer, text, text) from public, anon, authenticated;
revoke execute on function public.upgrade_pet_v2(bigint, uuid, text, text) from public, anon, authenticated;
revoke execute on function public.evolve_pet(bigint, uuid, text, text) from public, anon, authenticated;
revoke execute on function public.fuse_heroes(bigint, uuid, uuid[], boolean, text, text) from public, anon, authenticated;
revoke execute on function public.buy_season_pass_levels(bigint, integer, text, text) from public, anon, authenticated;
revoke execute on function public.season_pass_buy_with_myth(bigint, text, text) from public, anon, authenticated;
revoke execute on function public.tower_enter_floor(bigint, text) from public, anon, authenticated;
grant execute on function public.buy_pet_food(bigint, text, integer, text, text) to service_role;
grant execute on function public.buy_pet_egg(bigint, uuid, integer, text, text) to service_role;
grant execute on function public.upgrade_pet_v2(bigint, uuid, text, text) to service_role;
grant execute on function public.evolve_pet(bigint, uuid, text, text) to service_role;
grant execute on function public.fuse_heroes(bigint, uuid, uuid[], boolean, text, text) to service_role;
grant execute on function public.buy_season_pass_levels(bigint, integer, text, text) to service_role;
grant execute on function public.season_pass_buy_with_myth(bigint, text, text) to service_role;
grant execute on function public.tower_enter_floor(bigint, text) to service_role;