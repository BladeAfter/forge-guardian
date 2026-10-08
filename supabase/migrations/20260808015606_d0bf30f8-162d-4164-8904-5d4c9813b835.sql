-- Single source of truth for how one owned pet is presented to the player.
CREATE OR REPLACE FUNCTION public.player_pet_json(p_player_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE pp record; nxt record; buffs jsonb; pkey text; pbase numeric; maxlvl int; totals numeric;
BEGIN
  SELECT pp.*, p.name, p.slug, p.species, p.category, p.base_passives, p.active_skill,
         p.image_baby_url, p.image_young_url, p.image_adult_url, p.image_ancestral_url
    INTO pp FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.id = p_player_pet_id;
  IF NOT found THEN RETURN NULL; END IF;
  maxlvl := pet_max_level();
  buffs := player_pet_buffs(pp.id);
  SELECT key, (value#>>'{}')::numeric INTO pkey, pbase
    FROM jsonb_each(coalesce(pp.base_passives,'{}'::jsonb)) ORDER BY (value#>>'{}')::numeric DESC LIMIT 1;
  SELECT * INTO nxt FROM pet_evolution_tiers WHERE tier = pp.evolution_tier + 1 AND enabled;
  SELECT coalesce(sum((value#>>'{}')::numeric),0) INTO totals FROM jsonb_each(buffs);
  RETURN jsonb_build_object(
    'id', pp.id, 'petId', pp.pet_id, 'name', pp.name, 'slug', pp.slug, 'species', pp.species,
    'category', pp.category, 'rarity', pp.rarity, 'level', pp.level, 'maxLevel', maxlvl,
    'xp', pp.xp, 'xpRequired', CASE WHEN pp.level >= maxlvl THEN 0 ELSE pet_level_xp_required(pp.level) END,
    'isMaxLevel', pp.level >= maxlvl,
    'evolutionTier', pp.evolution_tier,
    'evolutionLabel', coalesce((SELECT label FROM pet_evolution_tiers WHERE tier = pp.evolution_tier), 'Forma Base'),
    'evolutionStage', pp.evolution_stage,
    'fragments', pp.fragments, 'isActive', pp.is_active,
    'image', CASE pp.evolution_stage
       WHEN 'ancestral' THEN pp.image_ancestral_url WHEN 'adult' THEN pp.image_adult_url
       WHEN 'young' THEN pp.image_young_url ELSE pp.image_baby_url END,
    'buffs', buffs,
    'primaryBuffKey', pkey,
    'primaryBuffValue', coalesce((buffs->>pkey)::numeric, 0),
    'secondaryBuffs', coalesce(pp.secondary_buffs,'[]'::jsonb),
    'power', (CASE pp.rarity WHEN 'legendary' THEN 8000 WHEN 'epic' THEN 4000 WHEN 'rare' THEN 2000
              WHEN 'uncommon' THEN 1000 ELSE 500 END) + pp.level * 100 + round(totals * 250),
    'activeSkill', pp.active_skill,
    'nextEvolution', CASE WHEN nxt.tier IS NULL THEN NULL ELSE jsonb_build_object(
        'tier', nxt.tier, 'label', nxt.label, 'requiredLevel', nxt.required_level,
        'fcCost', nxt.fc_cost, 'fragmentCost', nxt.fragment_cost,
        'newBuffChance', round(nxt.new_buff_chance * 100),
        'maxSecondaryBuffs', nxt.max_secondary_buffs,
        'primaryFrom', coalesce((buffs->>pkey)::numeric, 0),
        'primaryTo', round(coalesce(pbase,0) * pet_rarity_multiplier(pp.rarity)
                     * (1 + (pp.level - 1) * 0.02) * nxt.primary_multiplier, 2)
      ) END,
    'canEvolve', nxt.tier IS NOT NULL AND pp.level >= nxt.required_level
  );
END $$;

CREATE OR REPLACE FUNCTION public.get_pet_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN jsonb_build_object(
    'activePet', (SELECT player_pet_json(id) FROM player_pets WHERE user_id = u AND is_active LIMIT 1),
    'playerPets', coalesce((SELECT jsonb_agg(player_pet_json(t.id))
        FROM (SELECT id FROM player_pets WHERE user_id = u ORDER BY is_active DESC, level DESC, created_at) t), '[]'::jsonb),
    'catalog', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'id', p.id, 'name', p.name, 'slug', p.slug, 'species', p.species, 'category', p.category,
          'description', coalesce(p.description,''), 'basePassives', p.base_passives, 'activeSkill', p.active_skill,
          'images', jsonb_build_object('baby',p.image_baby_url,'young',p.image_young_url,'adult',p.image_adult_url,'ancestral',p.image_ancestral_url),
          'discovered', exists(SELECT 1 FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id),
          'bestRarity', (SELECT pp.rarity FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id ORDER BY pet_rarity_multiplier(pp.rarity) DESC LIMIT 1),
          'bestLevel', (SELECT max(pp.level) FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id)
        ) ORDER BY p.name) FROM pets p WHERE p.is_enabled), '[]'::jsonb),
    'foods', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'code', f.code, 'name', f.name, 'rarity', f.rarity, 'xpValue', f.xp_value, 'icon', f.icon,
          'quantity', coalesce((SELECT quantity FROM player_pet_food pf WHERE pf.user_id = u AND pf.food_code = f.code), 0)
        ) ORDER BY f.sort_order) FROM pet_food_items f WHERE f.enabled), '[]'::jsonb),
    'fragments', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'playerPetId', pp.id, 'petName', p.name, 'image', p.image_baby_url, 'rarity', pp.rarity, 'quantity', pp.fragments
        ) ORDER BY pp.fragments DESC) FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.user_id = u), '[]'::jsonb),
    'inventory', jsonb_build_object(
        'food', coalesce((SELECT sum(quantity) FROM player_pet_food WHERE user_id = u), 0),
        'universalFragments', coalesce((SELECT quantity FROM player_pet_inventory WHERE user_id = u AND item_type = 'fragment' AND item_id IS NULL), 0)),
    'history', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'id', h.id, 'eggName', e.name, 'petName', p.name, 'rarity', h.result_rarity,
          'duplicateFragments', h.duplicate_fragments, 'createdAt', h.created_at
        ) ORDER BY h.created_at DESC) FROM pet_hatch_history h
        JOIN pet_eggs e ON e.id = h.egg_id LEFT JOIN pets p ON p.id = h.result_pet_id
        WHERE h.user_id = u), '[]'::jsonb),
    'evolutionTiers', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'tier', t.tier, 'label', t.label, 'requiredLevel', t.required_level, 'fcCost', t.fc_cost,
          'fragmentCost', t.fragment_cost, 'newBuffChance', round(t.new_buff_chance*100)
        ) ORDER BY t.tier) FROM pet_evolution_tiers t WHERE t.enabled), '[]'::jsonb),
    'bonuses', get_pet_bonuses(u),
    'balance', coalesce((SELECT forge_coins FROM game_players WHERE id = u), 0)
  );
END $$;

-- ============ FEEDING ============
CREATE OR REPLACE FUNCTION public.feed_pet_item(p_telegram_id bigint, p_player_pet_id uuid, p_food_code text, p_quantity integer, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; pet player_pets%rowtype; food pet_food_items%rowtype; have int; gain int;
        lvl int; xp int; need int; gained int := 0; maxlvl int; payload jsonb;
BEGIN
  IF p_quantity IS NULL OR p_quantity < 1 OR p_quantity > 100 OR length(coalesce(p_idempotency_key,'')) < 8 THEN
    RAISE EXCEPTION 'INVALID_FEED_REQUEST';
  END IF;
  SELECT id INTO u FROM game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT result INTO payload FROM pet_action_idempotency WHERE idempotency_key = p_idempotency_key AND user_id = u;
  IF payload IS NOT NULL THEN RETURN payload; END IF;

  SELECT * INTO pet FROM player_pets WHERE id = p_player_pet_id AND user_id = u FOR UPDATE;
  IF pet.id IS NULL THEN RAISE EXCEPTION 'PET_NOT_OWNED'; END IF;
  SELECT * INTO food FROM pet_food_items WHERE code = p_food_code AND enabled;
  IF food.code IS NULL THEN RAISE EXCEPTION 'FOOD_NOT_FOUND'; END IF;
  maxlvl := pet_max_level();
  IF pet.level >= maxlvl THEN RAISE EXCEPTION 'PET_MAX_LEVEL'; END IF;

  SELECT quantity INTO have FROM player_pet_food WHERE user_id = u AND food_code = food.code FOR UPDATE;
  IF coalesce(have,0) < p_quantity THEN RAISE EXCEPTION 'NOT_ENOUGH_PET_FOOD'; END IF;
  UPDATE player_pet_food SET quantity = quantity - p_quantity, updated_at = now()
    WHERE user_id = u AND food_code = food.code;

  gain := food.xp_value * p_quantity;
  lvl := pet.level; xp := pet.xp + gain;
  LOOP
    EXIT WHEN lvl >= maxlvl;
    need := pet_level_xp_required(lvl);
    EXIT WHEN xp < need;
    xp := xp - need; lvl := lvl + 1; gained := gained + 1;
  END LOOP;
  IF lvl >= maxlvl THEN xp := 0; END IF;
  UPDATE player_pets SET level = lvl, xp = xp, updated_at = now() WHERE id = pet.id;

  payload := jsonb_build_object('dashboard', get_pet_dashboard(p_telegram_id),
    'feedResult', jsonb_build_object('xpGained', gain, 'levelsGained', gained, 'level', lvl, 'xp', xp,
      'foodName', food.name, 'quantity', p_quantity));
  INSERT INTO pet_action_idempotency VALUES (p_idempotency_key, u, pet.id, 'feed_item', payload, now());
  RETURN payload;
END $$;

-- ============ EVOLUTION ============
CREATE OR REPLACE FUNCTION public.evolve_pet(p_telegram_id bigint, p_player_pet_id uuid, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; balance numeric; pet player_pets%rowtype; cat text; base jsonb; nxt pet_evolution_tiers%rowtype;
        before_primary numeric; pkey text; buffs jsonb; payload jsonb;
        used int; roll numeric; newkey text; newval numeric; newrarity text; cand text[]; pick jsonb; acc numeric; total numeric;
BEGIN
  IF length(coalesce(p_idempotency_key,'')) < 8 THEN RAISE EXCEPTION 'INVALID_EVOLVE_REQUEST'; END IF;
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
  IF balance < nxt.fc_cost THEN RAISE EXCEPTION 'NOT_ENOUGH_FORGE_COINS'; END IF;
  IF pet.fragments < nxt.fragment_cost THEN RAISE EXCEPTION 'NOT_ENOUGH_PET_FRAGMENTS'; END IF;

  buffs := player_pet_buffs(pet.id);
  SELECT key INTO pkey FROM jsonb_each(coalesce(base,'{}'::jsonb)) ORDER BY (value#>>'{}')::numeric DESC LIMIT 1;
  before_primary := coalesce((buffs->>pkey)::numeric, 0);

  UPDATE game_players SET forge_coins = forge_coins - nxt.fc_cost, updated_at = now() WHERE id = u;
  UPDATE player_pets SET fragments = fragments - nxt.fragment_cost, evolution_tier = nxt.tier,
         evolution_stage = nxt.evolution_stage, updated_at = now() WHERE id = pet.id;

  -- Secondary buff roll happens only here, on the server.
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
  VALUES (u, pet.id, pet.evolution_tier, nxt.tier, pet.level, nxt.fc_cost, nxt.fragment_cost, newkey, newval, newrarity, p_idempotency_key);

  buffs := player_pet_buffs(pet.id);
  payload := jsonb_build_object('dashboard', get_pet_dashboard(p_telegram_id),
    'evolveResult', jsonb_build_object('petName', (SELECT name FROM pets WHERE id = pet.pet_id),
      'tier', nxt.tier, 'label', nxt.label, 'primaryBuffKey', pkey,
      'primaryBefore', before_primary, 'primaryAfter', coalesce((buffs->>pkey)::numeric, 0),
      'newBuff', CASE WHEN newkey IS NULL THEN NULL ELSE jsonb_build_object('key', newkey, 'value', newval, 'rarity', newrarity) END,
      'fcSpent', nxt.fc_cost, 'fragmentsSpent', nxt.fragment_cost));
  INSERT INTO pet_action_idempotency VALUES (p_idempotency_key, u, pet.id, 'evolve', payload, now());
  RETURN payload;
END $$;

-- ============ ADMIN CONFIG ============
CREATE OR REPLACE FUNCTION public.admin_update_pet_food(p_code text, p_name text, p_xp integer, p_rarity text, p_enabled boolean)
RETURNS pet_food_items LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE row pet_food_items;
BEGIN
  UPDATE pet_food_items SET name = coalesce(p_name,name), xp_value = coalesce(p_xp,xp_value),
    rarity = coalesce(p_rarity,rarity), enabled = coalesce(p_enabled,enabled), updated_at = now()
    WHERE code = p_code RETURNING * INTO row;
  IF row.code IS NULL THEN RAISE EXCEPTION 'FOOD_NOT_FOUND'; END IF;
  RETURN row;
END $$;

CREATE OR REPLACE FUNCTION public.admin_update_pet_evolution_tier(p_tier integer, p_required_level integer, p_fc numeric, p_fragments integer, p_multiplier numeric, p_chance numeric, p_max_buffs integer, p_enabled boolean)
RETURNS pet_evolution_tiers LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE row pet_evolution_tiers;
BEGIN
  UPDATE pet_evolution_tiers SET required_level = coalesce(p_required_level,required_level),
    fc_cost = coalesce(p_fc,fc_cost), fragment_cost = coalesce(p_fragments,fragment_cost),
    primary_multiplier = coalesce(p_multiplier,primary_multiplier), new_buff_chance = coalesce(p_chance,new_buff_chance),
    max_secondary_buffs = coalesce(p_max_buffs,max_secondary_buffs), enabled = coalesce(p_enabled,enabled), updated_at = now()
    WHERE tier = p_tier RETURNING * INTO row;
  IF row.tier IS NULL THEN RAISE EXCEPTION 'TIER_NOT_FOUND'; END IF;
  RETURN row;
END $$;

CREATE OR REPLACE FUNCTION public.admin_set_pet_setting(p_key text, p_value jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO pet_settings (key,value) VALUES (p_key,p_value)
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now();
END $$;

CREATE OR REPLACE FUNCTION public.admin_grant_pet_food(p_telegram_id bigint, p_code text, p_quantity integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  INSERT INTO player_pet_food (user_id, food_code, quantity) VALUES (u, p_code, greatest(0,p_quantity))
  ON CONFLICT (user_id, food_code) DO UPDATE SET quantity = player_pet_food.quantity + greatest(0,p_quantity), updated_at = now();
  RETURN get_pet_dashboard(p_telegram_id);
END $$;

REVOKE ALL ON FUNCTION public.player_pet_json(uuid) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_pet_dashboard(bigint) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.feed_pet_item(bigint,uuid,text,integer,text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.evolve_pet(bigint,uuid,text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_update_pet_food(text,text,integer,text,boolean) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_update_pet_evolution_tier(integer,integer,numeric,integer,numeric,numeric,integer,boolean) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_pet_setting(text,jsonb) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_grant_pet_food(bigint,text,integer) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.player_pet_json(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_pet_dashboard(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.feed_pet_item(bigint,uuid,text,integer,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.evolve_pet(bigint,uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_update_pet_food(text,text,integer,text,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_update_pet_evolution_tier(integer,integer,numeric,integer,numeric,numeric,integer,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_pet_setting(text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_grant_pet_food(bigint,text,integer) TO service_role;
