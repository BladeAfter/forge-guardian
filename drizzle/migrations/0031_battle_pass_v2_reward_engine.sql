-- ============================================================
-- BATTLE PASS V2 — reward engine (slots, assets, highlights)
-- Additive only: V1 rewards/claims/XP untouched.
-- ============================================================
ALTER TABLE public.season_pass_rewards
  ADD COLUMN IF NOT EXISTS reward_slot integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS is_highlight boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reward_asset text,
  ADD COLUMN IF NOT EXISTS requires_asset boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS image_url text;

ALTER TABLE public.season_pass_rewards DROP CONSTRAINT IF EXISTS season_pass_rewards_season_id_level_tier_key;
CREATE UNIQUE INDEX IF NOT EXISTS season_pass_rewards_season_level_tier_slot_key
  ON public.season_pass_rewards(season_id, level, tier, reward_slot);

ALTER TABLE public.season_pass_rewards DROP CONSTRAINT IF EXISTS season_pass_rewards_reward_type_check;
ALTER TABLE public.season_pass_rewards ADD CONSTRAINT season_pass_rewards_reward_type_check
  CHECK (reward_type = ANY (ARRAY[
    'fc','hero_chest','pet_egg','pet_food','fragments','pvp_ticket','skin','equipment','hero_random','exclusive_chest',
    'myth','pet_random','nft_equipment','nft_pet','chest','equipment_chest','evolution_pack']));

-- ------------------------------------------------------------
-- Reward delivery (adds MYTH, pets, NFT instances, chests, admin-selected assets)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_season_pass_reward(p_telegram_id bigint, p_reward_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u game_players%rowtype; r season_pass_rewards%rowtype; p player_season_pass%rowtype; s season_pass_seasons%rowtype;
  egg uuid; v_key text; v_rarity text; v_qty integer; v_extra jsonb := '{}'::jsonb; v_food text; v_total integer;
  tpl equipment_templates%rowtype; hc hero_catalog%rowtype; v_id uuid; v_before integer; v_after integer; v_claim uuid;
  v_ver int; v_levels int; v_allowed boolean; v_asset text; pt public.pets%rowtype; v_unit uuid; v_serial text; v_num numeric;
begin
  select * into u from game_players where telegram_id = p_telegram_id for update;
  select * into r from season_pass_rewards where id = p_reward_id and enabled and tier in ('adventurer','legendary');
  if r.id is null then raise exception 'REWARD_LOCKED'; end if;
  select * into s from season_pass_seasons where id = r.season_id;
  select * into p from player_season_pass where user_id = u.id and season_id = s.id for update;
  if u.id is null or s.id is null or p.tier = 'none' then raise exception 'REWARD_LOCKED'; end if;

  v_allowed := (s.id = public.pass_user_season_id(u.id))
    or exists (select 1 from public.pass_versions v where v.season_id = s.id and v.status in ('ACTIVE','ARCHIVED'))
    or not exists (select 1 from public.pass_versions v where v.season_id = s.id);
  if not v_allowed then raise exception 'REWARD_LOCKED'; end if;

  v_ver := coalesce(p.pass_version, 1);
  v_levels := season_pass_levels_for(v_ver, s.levels);
  if coalesce(r.min_pass_version, 1) > v_ver then raise exception 'PASS_VERSION_REQUIRED'; end if;
  if r.level > least(v_levels, floor(p.xp / s.xp_per_level)::int + 1) then raise exception 'REWARD_LOCKED'; end if;
  if r.tier = 'adventurer' and p.tier not in ('adventurer','legendary') or r.tier = 'legendary' and p.tier <> 'legendary' then raise exception 'PASS_NOT_OWNED'; end if;

  perform pg_advisory_xact_lock(hashtextextended(u.id::text || ':' || r.id::text, 42));
  if exists (select 1 from season_pass_claims where user_id = u.id and reward_id = r.id) then
    return get_season_pass_dashboard(p_telegram_id);
  end if;
  v_key := 'season_reward:' || u.id || ':' || r.id;
  v_claim := gen_random_uuid();
  v_asset := nullif(btrim(coalesce(r.reward_asset,'')),'');
  if r.requires_asset and v_asset is null then
    insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, claim_status, error_message)
    values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, 'PASS_REWARD_FAILED', 'asset not selected');
    raise exception 'REWARD_ASSET_NOT_SELECTED';
  end if;

  if r.reward_type = 'pvp_ticket' then
    update game_players set pvp_tickets = pvp_tickets + greatest(1, r.amount::int), updated_at = now() where id = u.id
      returning pvp_tickets into v_after;
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','pvp_ticket','quantity',greatest(1, r.amount::int),'balance',v_after,'title',r.title));
  elsif r.reward_type = 'fc' then
    update game_players set forge_coins = forge_coins + r.amount, updated_at = now() where id = u.id;
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','fc','quantity',r.amount,'title',r.title));
  elsif r.reward_type = 'myth' then
    -- MYTH comes from the configured reward reserve: credit the official balance, never mint new supply.
    v_num := greatest(1, r.amount);
    insert into myth_balances(user_id, amount) values (u.id, v_num)
      on conflict (user_id) do update set amount = myth_balances.amount + excluded.amount;
    insert into myth_ledger(user_id, direction, amount, reason)
      values (u.id, 'credit', v_num, 'season_pass_reward');
    select amount into v_num from myth_balances where user_id = u.id;
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','myth','quantity',greatest(1, r.amount),'balance',v_num,'title',r.title));
  elsif r.reward_type = 'exclusive_chest' then
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (u.id, 'exclusive_chest', coalesce(nullif(r.reward_code,''),'exclusive-hero-chest'), greatest(1, r.amount::int))
    on conflict(user_id, item_type, item_code) do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now();
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','exclusive_chest','code',r.reward_code,
      'quantity',greatest(1, r.amount::int),'exclusive',true,'title',r.title));
  elsif r.reward_code = 'universal_fragment' and r.reward_type <> 'fragments' then
    v_rarity := roll_universal_fragment_rarity();
    select coalesce((gs.value)::text::numeric, 25)::int into v_qty from game_settings gs where gs.key = 'universal_fragment_quantity';
    v_qty := greatest(1, coalesce(v_qty, r.amount::int));
    v_total := add_universal_fragments(u.id, v_qty);
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','fragments','code','universal_fragment','rarity',v_rarity,
      'quantity',v_qty,'balance',v_total,
      'title', upper(v_rarity) || ' UNIVERSAL FRAGMENT x' || v_qty));
  elsif r.reward_type = 'equipment' then
    select count(*) into v_before from player_equipment where user_id = u.id;
    if v_asset is not null then
      select * into tpl from equipment_templates t where t.id::text = v_asset or t.code = v_asset;
    elsif lower(coalesce(r.reward_code,'')) in ('common','uncommon','rare','epic','legendary','mythic') then
      select * into tpl from equipment_templates t where t.is_active and t.rarity = lower(r.reward_code) order by random() limit 1;
    else
      select * into tpl from equipment_templates t
        where t.is_active and t.rarity = 'rare' and t.slot = coalesce(nullif(r.reward_code,''),'weapon')
        order by random() limit 1;
    end if;
    if tpl.id is null then
      select * into tpl from equipment_templates t where t.is_active and t.rarity = 'rare' order by random() limit 1;
    end if;
    if tpl.id is null then
      insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, claim_status, error_message)
      values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, 'PASS_REWARD_FAILED', 'no active equipment template');
      raise exception 'REWARD_MISCONFIGURED';
    end if;
    insert into player_equipment(user_id, template_id, source, source_ref)
    values (u.id, tpl.id, 'season_pass', v_claim) returning id into v_id;
    select count(*) into v_after from player_equipment where user_id = u.id;
    if v_id is null then raise exception 'REWARD_NOT_DELIVERED'; end if;
    insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, item_id, quantity, inventory_before, inventory_after, claim_status)
    values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, tpl.code, 1, v_before, v_after, 'PASS_REWARD_CLAIM');
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','equipment','instanceId',v_id,'code',tpl.code,
      'name',tpl.name,'slot',tpl.slot,'rarity',tpl.rarity,'imageUrl',tpl.image_url,'power',tpl.power,'title',r.title));
  elsif r.reward_type = 'nft_equipment' then
    -- A real unique instance is transferred, never plain template ownership.
    select ne.id into v_unit from nft_equipment ne
      where ne.owner_user_id is null and coalesce(ne.status,'available') in ('available','stock','pool')
        and (ne.template_id::text = v_asset or exists (select 1 from equipment_templates t where t.id = ne.template_id and t.code = v_asset))
      order by ne.created_at limit 1;
    if v_unit is null then
      insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, claim_status, error_message)
      values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, 'PASS_REWARD_FAILED', 'no free nft equipment unit');
      raise exception 'REWARD_ASSET_UNAVAILABLE';
    end if;
    perform public.nft_equipment_assign_unit(v_unit, u.id, 'BATTLE_PASS_REWARD');
    select nft_serial into v_serial from nft_equipment where id = v_unit;
    insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, item_id, quantity, claim_status)
    values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, v_unit::text, 1, 'PASS_REWARD_CLAIM');
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','nft_equipment','instanceId',v_unit,'serial',v_serial,'title',r.title));
  elsif r.reward_type = 'nft_pet' then
    select np.id into v_unit from nft_pets np
      where np.owner_user_id is null and coalesce(np.status,'available') in ('available','stock','pool')
        and (np.pet_template_id::text = v_asset or exists (select 1 from pets pp where pp.id = np.pet_template_id and pp.slug = v_asset))
      order by np.created_at limit 1;
    if v_unit is null then
      insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, claim_status, error_message)
      values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, 'PASS_REWARD_FAILED', 'no free nft pet unit');
      raise exception 'REWARD_ASSET_UNAVAILABLE';
    end if;
    select * into pt from pets where id = (select pet_template_id from nft_pets where id = v_unit);
    insert into player_pets(user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active, nft_pet_id, tradable)
      values (u.id, pt.id, public.normalize_pet_rarity(pt.rarity), 1, 0, 'baby', 0, false, v_unit, true)
      returning id into v_id;
    update nft_pets set owner_user_id = u.id, player_pet_id = v_id, status = 'assigned', assigned_at = now(), updated_at = now()
      where id = v_unit and owner_user_id is null;
    if not exists (select 1 from nft_pets where id = v_unit and owner_user_id = u.id) then raise exception 'REWARD_ASSET_UNAVAILABLE'; end if;
    select nft_serial into v_serial from nft_pets where id = v_unit;
    insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, item_id, quantity, claim_status)
    values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, v_unit::text, 1, 'PASS_REWARD_CLAIM');
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','nft_pet','instanceId',v_id,'serial',v_serial,'name',pt.name,'title',r.title));
  elsif r.reward_type = 'hero_random' then
    if v_asset is not null then
      select * into hc from hero_catalog c where c.hero_key = v_asset;
    else
      select * into hc from hero_catalog c
        where coalesce(c.enabled,true) and lower(c.rarity) = coalesce(nullif(lower(r.reward_code),''),'legendary')
          and not coalesce(c.is_nft_exclusive,false) and not coalesce(c.is_pass_exclusive,false)
          and not coalesce(c.roulette_exclusive,false)
        order by random() limit 1;
    end if;
    if hc.hero_key is null then raise exception 'REWARD_MISCONFIGURED'; end if;
    insert into player_heroes(user_id, hero_key, name, rarity, level, image)
      values (u.id, hc.hero_key, hc.name, normalize_hero_rarity(hc.rarity), 1, hc.image) returning id into v_id;
    insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, item_id, quantity, claim_status)
    values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, hc.hero_key, 1, 'PASS_REWARD_CLAIM');
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','hero','heroId',v_id,'heroKey',hc.hero_key,
      'name',hc.name,'rarity',normalize_hero_rarity(hc.rarity),'image',hc.image,'title',hc.name));
  elsif r.reward_type = 'pet_random' then
    if v_asset is not null then
      select * into pt from pets where slug = v_asset or id::text = v_asset;
    else
      select * into pt from pets
        where rarity = coalesce(nullif(lower(r.reward_code),''),'legendary')
          and not coalesce(is_nft_exclusive,false) and rarity <> 'nft_exclusive'
        order by random() limit 1;
    end if;
    if pt.id is null then raise exception 'REWARD_MISCONFIGURED'; end if;
    insert into player_pets(user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active)
      values (u.id, pt.id, public.normalize_pet_rarity(pt.rarity), 1, 0, 'baby', 0, false) returning id into v_id;
    insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, item_id, quantity, claim_status)
    values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, pt.slug, 1, 'PASS_REWARD_CLAIM');
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','pet','petId',v_id,'name',pt.name,'rarity',pt.rarity,'title',r.title));
  elsif r.reward_type = 'pet_egg' then
    select pe.id into egg from pet_eggs pe where pe.slug = coalesce(v_asset, r.reward_code);
    if egg is null then raise exception 'REWARD_MISCONFIGURED'; end if;
    insert into player_pet_inventory(user_id, item_type, item_id, quantity) values (u.id, 'egg', egg, r.amount::int)
    on conflict(user_id, item_type, (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid))) do update set quantity = player_pet_inventory.quantity + excluded.quantity, updated_at = now();
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','pet_egg','code',coalesce(v_asset, r.reward_code),'quantity',r.amount::int,'title',r.title));
  elsif r.reward_type = 'pet_food' then
    select pf.code into v_food from pet_food_items pf where pf.code = coalesce(nullif(r.reward_code, ''), 'pet_food') and pf.enabled;
    if v_food is null then
      select pf.code into v_food from pet_food_items pf where pf.code = 'pet_food' and pf.enabled;
    end if;
    if v_food is null then raise exception 'REWARD_MISCONFIGURED'; end if;
    insert into player_pet_food(user_id, food_code, quantity) values (u.id, v_food, r.amount::int)
    on conflict(user_id, food_code) do update set quantity = player_pet_food.quantity + excluded.quantity, updated_at = now();
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','pet_food','code',v_food,'quantity',r.amount::int,'title',r.title));
  elsif r.reward_type = 'fragments' and coalesce(nullif(r.reward_code,''),'') in ('', 'fragments', 'universal_fragment') then
    v_qty := greatest(1, r.amount::int);
    v_total := add_universal_fragments(u.id, v_qty);
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','fragments','code','universal_fragment',
      'quantity',v_qty,'balance',v_total,'title', 'UNIVERSAL FRAGMENT x' || v_qty));
  elsif r.reward_type in ('fragments','hero_chest','skin','chest','equipment_chest','evolution_pack') then
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (u.id, case when r.reward_type in ('chest','equipment_chest') then 'resource_chest' else r.reward_type end,
            coalesce(nullif(r.reward_code, ''), r.reward_type), greatest(1, r.amount::int))
    on conflict(user_id, item_type, item_code) do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now()
    returning quantity into v_after;
    if v_after is null then raise exception 'REWARD_NOT_DELIVERED'; end if;
    insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, item_id, quantity, inventory_after, claim_status)
    values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, coalesce(nullif(r.reward_code,''), r.reward_type), greatest(1, r.amount::int), v_after, 'PASS_REWARD_CLAIM');
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type',r.reward_type,'code',coalesce(nullif(r.reward_code,''), r.reward_type),
      'quantity',greatest(1, r.amount::int),'balance',v_after,'title',r.title));
  else
    raise exception 'REWARD_MISCONFIGURED';
  end if;

  insert into season_pass_claims(user_id, reward_id, idempotency_key) values (u.id, r.id, v_key);
  return get_season_pass_dashboard(p_telegram_id) || v_extra;
end
$function$;

-- ------------------------------------------------------------
-- Track validation: every level configured + every asset resolvable
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pass_reward_asset_ok(p_reward season_pass_rewards)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN NOT p_reward.requires_asset THEN true
    WHEN nullif(btrim(coalesce(p_reward.reward_asset,'')),'') IS NULL THEN false
    WHEN p_reward.reward_type = 'hero_random' THEN EXISTS (SELECT 1 FROM public.hero_catalog c WHERE c.hero_key = p_reward.reward_asset)
    WHEN p_reward.reward_type = 'pet_random' THEN EXISTS (SELECT 1 FROM public.pets pp WHERE pp.slug = p_reward.reward_asset OR pp.id::text = p_reward.reward_asset)
    WHEN p_reward.reward_type = 'equipment' THEN EXISTS (SELECT 1 FROM public.equipment_templates t WHERE t.code = p_reward.reward_asset OR t.id::text = p_reward.reward_asset)
    WHEN p_reward.reward_type = 'nft_equipment' THEN EXISTS (SELECT 1 FROM public.equipment_templates t WHERE t.code = p_reward.reward_asset OR t.id::text = p_reward.reward_asset)
    WHEN p_reward.reward_type = 'nft_pet' THEN EXISTS (SELECT 1 FROM public.pets pp WHERE pp.slug = p_reward.reward_asset OR pp.id::text = p_reward.reward_asset)
    WHEN p_reward.reward_type = 'pet_egg' THEN EXISTS (SELECT 1 FROM public.pet_eggs e WHERE e.slug = p_reward.reward_asset)
    ELSE true END;
$$;

CREATE OR REPLACE FUNCTION public.pass_version_rewards_status(p_season_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_levels int; v jsonb;
BEGIN
  SELECT GREATEST(levels,1) INTO v_levels FROM public.season_pass_seasons WHERE id = p_season_id;
  SELECT jsonb_object_agg(tier, info) INTO v FROM (
    SELECT t.tier,
      jsonb_build_object(
        'levels', v_levels,
        'levelsConfigured', (SELECT count(DISTINCT r.level) FROM public.season_pass_rewards r
                              WHERE r.season_id = p_season_id AND r.tier = t.tier AND r.enabled),
        'rewards', (SELECT count(*) FROM public.season_pass_rewards r
                     WHERE r.season_id = p_season_id AND r.tier = t.tier AND r.enabled),
        'highlights', (SELECT COALESCE(jsonb_agg(DISTINCT r.level ORDER BY r.level) , '[]'::jsonb)
                        FROM public.season_pass_rewards r
                       WHERE r.season_id = p_season_id AND r.tier = t.tier AND r.enabled AND r.is_highlight),
        'missingLevels', (SELECT COALESCE(jsonb_agg(lv ORDER BY lv), '[]'::jsonb) FROM generate_series(1, v_levels) lv
                           WHERE NOT EXISTS (SELECT 1 FROM public.season_pass_rewards r
                                              WHERE r.season_id = p_season_id AND r.tier = t.tier AND r.enabled AND r.level = lv)),
        'pendingAssets', (SELECT COALESCE(jsonb_agg(jsonb_build_object('rewardId', r.id, 'level', r.level, 'slot', r.reward_slot,
                                 'type', r.reward_type, 'title', r.title) ORDER BY r.level, r.reward_slot), '[]'::jsonb)
                            FROM public.season_pass_rewards r
                           WHERE r.season_id = p_season_id AND r.tier = t.tier AND r.enabled
                             AND NOT public.pass_reward_asset_ok(r))
      ) AS info
      FROM (VALUES ('adventurer'),('legendary')) AS t(tier)) x;
  RETURN jsonb_build_object('seasonId', p_season_id, 'tiers', COALESCE(v,'{}'::jsonb),
    'valid', NOT EXISTS (
      SELECT 1 FROM generate_series(1, v_levels) lv
       CROSS JOIN (VALUES ('adventurer'),('legendary')) AS t(tier)
       WHERE NOT EXISTS (SELECT 1 FROM public.season_pass_rewards r
                          WHERE r.season_id = p_season_id AND r.tier = t.tier AND r.enabled AND r.level = lv))
      AND NOT EXISTS (SELECT 1 FROM public.season_pass_rewards r
                       WHERE r.season_id = p_season_id AND r.enabled AND r.tier IN ('adventurer','legendary')
                         AND NOT public.pass_reward_asset_ok(r)));
END $$;

CREATE OR REPLACE FUNCTION public.admin_pass_version_validate(p_admin_id bigint, p_version_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_season uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT season_id INTO v_season FROM public.pass_versions WHERE id = p_version_id;
  IF v_season IS NULL THEN RAISE EXCEPTION 'VERSION_NOT_FOUND'; END IF;
  RETURN public.pass_version_rewards_status(v_season);
END $$;

-- Activation is blocked while any level/asset is missing.
CREATE OR REPLACE FUNCTION public.admin_pass_version_activate(p_admin_id bigint, p_version_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_season uuid; v_status jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT season_id INTO v_season FROM public.pass_versions WHERE id = p_version_id;
  IF v_season IS NULL THEN RAISE EXCEPTION 'VERSION_NOT_FOUND'; END IF;
  v_status := public.pass_version_rewards_status(v_season);
  IF NOT COALESCE((v_status->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'REWARDS_NOT_READY: %', v_status::text;
  END IF;
  PERFORM public.pass_version_activate_season(v_season, p_admin_id);
  RETURN public.admin_pass_versions_overview(p_admin_id);
END $$;

-- ------------------------------------------------------------
-- Admin editing of a version track (no deploy needed)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_pass_reward_track(p_admin_id bigint, p_version_id uuid, p_tier text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_season uuid; v_tier text; v_type text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT season_id, pass_type INTO v_season, v_type FROM public.pass_versions WHERE id = p_version_id;
  IF v_season IS NULL THEN RAISE EXCEPTION 'VERSION_NOT_FOUND'; END IF;
  v_tier := COALESCE(NULLIF(p_tier,''), v_type);
  RETURN jsonb_build_object('versionId', p_version_id, 'seasonId', v_season, 'tier', v_tier,
    'status', public.pass_version_rewards_status(v_season),
    'rewards', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', r.id, 'level', r.level, 'slot', r.reward_slot,
        'type', r.reward_type, 'code', r.reward_code, 'amount', r.amount, 'title', r.title,
        'asset', r.reward_asset, 'requiresAsset', r.requires_asset, 'assetOk', public.pass_reward_asset_ok(r),
        'highlight', r.is_highlight, 'enabled', r.enabled) ORDER BY r.level, r.reward_slot)
      FROM public.season_pass_rewards r WHERE r.season_id = v_season AND r.tier = v_tier), '[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.admin_pass_reward_set(
  p_admin_id bigint, p_reward_id uuid,
  p_reward_type text DEFAULT NULL, p_amount numeric DEFAULT NULL, p_reward_code text DEFAULT NULL,
  p_asset text DEFAULT NULL, p_title text DEFAULT NULL, p_highlight boolean DEFAULT NULL, p_enabled boolean DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r public.season_pass_rewards%rowtype;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO r FROM public.season_pass_rewards WHERE id = p_reward_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'REWARD_NOT_FOUND'; END IF;
  UPDATE public.season_pass_rewards SET
    reward_type = COALESCE(NULLIF(p_reward_type,''), reward_type),
    amount = COALESCE(p_amount, amount),
    reward_code = COALESCE(NULLIF(p_reward_code,''), reward_code),
    reward_asset = CASE WHEN p_asset IS NULL THEN reward_asset WHEN btrim(p_asset) = '' THEN NULL ELSE btrim(p_asset) END,
    title = COALESCE(NULLIF(p_title,''), title),
    is_highlight = COALESCE(p_highlight, is_highlight),
    enabled = COALESCE(p_enabled, enabled),
    updated_at = now()
  WHERE id = p_reward_id;
  INSERT INTO public.pass_version_audit(version_id, season_id, action, admin_id, payload)
  SELECT v.id, r.season_id, 'REWARD_EDIT', p_admin_id,
         jsonb_build_object('rewardId', p_reward_id, 'level', r.level, 'tier', r.tier,
           'type', COALESCE(p_reward_type, r.reward_type), 'amount', COALESCE(p_amount, r.amount), 'asset', p_asset)
    FROM public.pass_versions v WHERE v.season_id = r.season_id AND v.pass_type = r.tier;
  RETURN (SELECT jsonb_build_object('id', x.id, 'level', x.level, 'tier', x.tier, 'type', x.reward_type,
     'code', x.reward_code, 'amount', x.amount, 'title', x.title, 'asset', x.reward_asset,
     'assetOk', public.pass_reward_asset_ok(x), 'highlight', x.is_highlight, 'enabled', x.enabled)
   FROM public.season_pass_rewards x WHERE x.id = p_reward_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_pass_reward_assets(p_admin_id bigint, p_kind text, p_rarity text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_kind = 'hero' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('ref', c.hero_key, 'name', c.name, 'rarity', lower(c.rarity)) ORDER BY c.name), '[]'::jsonb) INTO v
      FROM public.hero_catalog c
     WHERE COALESCE(c.enabled,true) AND (p_rarity IS NULL OR lower(c.rarity) = lower(p_rarity));
  ELSIF p_kind = 'pet' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('ref', pp.slug, 'name', pp.name, 'rarity', pp.rarity) ORDER BY pp.name), '[]'::jsonb) INTO v
      FROM public.pets pp WHERE (p_rarity IS NULL OR pp.rarity = lower(p_rarity));
  ELSIF p_kind IN ('equipment','nft_equipment') THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('ref', t.code, 'name', t.name, 'rarity', t.rarity,
        'freeUnits', (SELECT count(*) FROM public.nft_equipment ne WHERE ne.template_id = t.id AND ne.owner_user_id IS NULL)) ORDER BY t.name), '[]'::jsonb) INTO v
      FROM public.equipment_templates t WHERE t.is_active AND (p_rarity IS NULL OR t.rarity = lower(p_rarity));
  ELSIF p_kind = 'nft_pet' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('ref', pp.slug, 'name', pp.name, 'rarity', pp.rarity,
        'freeUnits', (SELECT count(*) FROM public.nft_pets np WHERE np.pet_template_id = pp.id AND np.owner_user_id IS NULL)) ORDER BY pp.name), '[]'::jsonb) INTO v
      FROM public.pets pp WHERE pp.rarity IN ('nft_exclusive','mythic');
  ELSIF p_kind = 'egg' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('ref', e.slug, 'name', e.name) ORDER BY e.name), '[]'::jsonb) INTO v FROM public.pet_eggs e;
  ELSE
    v := '[]'::jsonb;
  END IF;
  RETURN jsonb_build_object('kind', p_kind, 'rarity', p_rarity, 'assets', v);
END $$;

GRANT EXECUTE ON FUNCTION public.pass_version_rewards_status(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pass_reward_asset_ok(season_pass_rewards) TO authenticated, service_role;