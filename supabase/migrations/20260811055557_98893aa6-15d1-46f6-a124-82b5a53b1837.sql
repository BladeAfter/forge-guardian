-- 1) Unify universal fragment stock into player_pet_inventory (single source of truth)
INSERT INTO public.player_pet_inventory (user_id, item_type, item_id, quantity)
SELECT pi.user_id, 'universal_fragment', NULL, sum(pi.quantity)
  FROM public.player_inventory pi
 WHERE pi.item_type = 'fragments' AND pi.item_code LIKE 'universal_fragment%'
 GROUP BY pi.user_id
ON CONFLICT (user_id, item_type, (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid)))
DO UPDATE SET quantity = public.player_pet_inventory.quantity + excluded.quantity, updated_at = now();

DELETE FROM public.player_inventory WHERE item_type = 'fragments' AND item_code LIKE 'universal_fragment%';

-- 2) Helpers for the single universal fragment balance
CREATE OR REPLACE FUNCTION public.universal_fragment_balance(p_user_id uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT coalesce((SELECT quantity FROM player_pet_inventory
                    WHERE user_id = p_user_id AND item_type = 'universal_fragment' AND item_id IS NULL), 0);
$$;

CREATE OR REPLACE FUNCTION public.add_universal_fragments(p_user_id uuid, p_quantity integer)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_qty integer;
BEGIN
  INSERT INTO player_pet_inventory(user_id, item_type, item_id, quantity)
  VALUES (p_user_id, 'universal_fragment', NULL, greatest(0, coalesce(p_quantity,0)))
  ON CONFLICT (user_id, item_type, (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid)))
  DO UPDATE SET quantity = greatest(0, player_pet_inventory.quantity + coalesce(p_quantity,0)), updated_at = now()
  RETURNING quantity INTO v_qty;
  RETURN coalesce(v_qty, 0);
END $$;

REVOKE ALL ON FUNCTION public.universal_fragment_balance(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.add_universal_fragments(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.universal_fragment_balance(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.add_universal_fragments(uuid, integer) TO service_role;

-- 3) Battle Pass claim credits the unified universal fragment balance
CREATE OR REPLACE FUNCTION public.claim_season_pass_reward(p_telegram_id bigint, p_reward_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare
  u game_players%rowtype; r season_pass_rewards%rowtype; p player_season_pass%rowtype; s season_pass_seasons%rowtype;
  egg uuid; v_key text; v_rarity text; v_qty integer; v_extra jsonb := '{}'::jsonb; v_food text; v_total integer;
begin
  select * into u from game_players where telegram_id = p_telegram_id for update;
  select * into r from season_pass_rewards where id = p_reward_id and enabled and tier in ('adventurer','legendary');
  if r.id is null then raise exception 'REWARD_LOCKED'; end if;
  select * into s from season_pass_seasons where id = r.season_id and active;
  select * into p from player_season_pass where user_id = u.id and season_id = s.id for update;
  if u.id is null or s.id is null or p.tier = 'none' or r.level > least(s.levels, floor(p.xp / s.xp_per_level)::int + 1) then raise exception 'REWARD_LOCKED'; end if;
  if r.tier = 'adventurer' and p.tier not in ('adventurer','legendary') or r.tier = 'legendary' and p.tier <> 'legendary' then raise exception 'PASS_NOT_OWNED'; end if;

  perform pg_advisory_xact_lock(hashtextextended(u.id::text || ':' || r.id::text, 42));
  if exists (select 1 from season_pass_claims where user_id = u.id and reward_id = r.id) then
    return get_season_pass_dashboard(p_telegram_id);
  end if;
  v_key := 'season_reward:' || u.id || ':' || r.id;

  if r.reward_code = 'universal_fragment' then
    v_rarity := roll_universal_fragment_rarity();
    select coalesce((gs.value)::text::numeric, 25)::int into v_qty from game_settings gs where gs.key = 'universal_fragment_quantity';
    v_qty := greatest(1, coalesce(v_qty, r.amount::int));
    v_total := add_universal_fragments(u.id, v_qty);
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','fragments','code','universal_fragment','rarity',v_rarity,
      'quantity',v_qty,'balance',v_total,
      'title', upper(v_rarity) || ' UNIVERSAL FRAGMENT x' || v_qty));
  elsif r.reward_type = 'fc' then
    update game_players set forge_coins = forge_coins + r.amount, updated_at = now() where id = u.id;
  elsif r.reward_type = 'pvp_ticket' then
    update game_players set pvp_tickets = pvp_tickets + r.amount::int, updated_at = now() where id = u.id;
  elsif r.reward_type = 'pet_egg' then
    select pe.id into egg from pet_eggs pe where pe.slug = r.reward_code;
    if egg is null then raise exception 'REWARD_MISCONFIGURED'; end if;
    insert into player_pet_inventory(user_id, item_type, item_id, quantity) values (u.id, 'egg', egg, r.amount::int)
    on conflict(user_id, item_type, (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid))) do update set quantity = player_pet_inventory.quantity + excluded.quantity, updated_at = now();
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
  elsif r.reward_type in ('fragments','hero_chest','skin') then
    insert into player_inventory(user_id, item_type, item_code, quantity) values (u.id, r.reward_type, coalesce(nullif(r.reward_code, ''), r.reward_type), r.amount::int)
    on conflict(user_id, item_type, item_code) do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now();
  else
    raise exception 'REWARD_MISCONFIGURED';
  end if;

  insert into season_pass_claims(user_id, reward_id, idempotency_key) values (u.id, r.id, v_key);
  return get_season_pass_dashboard(p_telegram_id) || v_extra;
end
$function$;

-- 4) Pet evolution: pet-specific fragments first, universal fragments cover the rest
CREATE OR REPLACE FUNCTION public.evolve_pet(p_telegram_id bigint, p_player_pet_id uuid, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE u uuid; balance numeric; pet player_pets%rowtype; cat text; base jsonb; nxt pet_evolution_tiers%rowtype;
        before_primary numeric; pkey text; buffs jsonb; payload jsonb;
        used int; roll numeric; newkey text; newval numeric; newrarity text; cand text[]; pick jsonb; acc numeric; total numeric;
        spec_spend int; uni_spend int; uni_have int;
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

  -- Specific fragments are always consumed first; universal fragments only cover the shortfall.
  SELECT quantity INTO uni_have FROM player_pet_inventory
    WHERE user_id = u AND item_type = 'universal_fragment' AND item_id IS NULL FOR UPDATE;
  uni_have := coalesce(uni_have, 0);
  spec_spend := least(pet.fragments, nxt.fragment_cost);
  uni_spend := nxt.fragment_cost - spec_spend;
  IF uni_spend > uni_have THEN RAISE EXCEPTION 'NOT_ENOUGH_PET_FRAGMENTS'; END IF;

  buffs := player_pet_buffs(pet.id);
  SELECT key INTO pkey FROM jsonb_each(coalesce(base,'{}'::jsonb)) ORDER BY (value#>>'{}')::numeric DESC LIMIT 1;
  before_primary := coalesce((buffs->>pkey)::numeric, 0);

  UPDATE game_players SET forge_coins = forge_coins - nxt.fc_cost, updated_at = now() WHERE id = u;
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
  VALUES (u, pet.id, pet.evolution_tier, nxt.tier, pet.level, nxt.fc_cost, nxt.fragment_cost, newkey, newval, newrarity, p_idempotency_key);

  buffs := player_pet_buffs(pet.id);
  payload := jsonb_build_object('dashboard', get_pet_dashboard(p_telegram_id),
    'evolveResult', jsonb_build_object('petName', (SELECT name FROM pets WHERE id = pet.pet_id),
      'tier', nxt.tier, 'label', nxt.label, 'primaryBuffKey', pkey,
      'primaryBefore', before_primary, 'primaryAfter', coalesce((buffs->>pkey)::numeric, 0),
      'newBuff', CASE WHEN newkey IS NULL THEN NULL ELSE jsonb_build_object('key', newkey, 'value', newval, 'rarity', newrarity) END,
      'fcSpent', nxt.fc_cost, 'fragmentsSpent', nxt.fragment_cost,
      'petFragmentsSpent', spec_spend, 'universalFragmentsSpent', uni_spend,
      'universalFragmentsLeft', uni_have - uni_spend));
  INSERT INTO pet_action_idempotency VALUES (p_idempotency_key, u, pet.id, 'evolve', payload, now());
  RETURN payload;
END $function$;

REVOKE ALL ON FUNCTION public.evolve_pet(bigint, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_season_pass_reward(bigint, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.evolve_pet(bigint, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_season_pass_reward(bigint, uuid) TO service_role;