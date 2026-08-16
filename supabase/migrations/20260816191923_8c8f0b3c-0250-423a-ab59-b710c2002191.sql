-- Internal TON balance purchase for premium eggs (same delivery pipeline as the on-chain flow).
create or replace function public.pet_egg_buy_with_balance(p_telegram_id bigint, p_egg_id uuid, p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare u uuid; e pet_eggs%rowtype; o pet_egg_orders%rowtype; paid_count int; v_tx text;
begin
  if length(trim(coalesce(p_idempotency_key,''))) < 8 or length(p_idempotency_key) > 180 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  perform pg_advisory_xact_lock(hashtextextended('pet_egg_balance:'||u::text||':'||p_idempotency_key, 0));

  select * into o from pet_egg_orders where idempotency_key = p_idempotency_key;
  if o.id is not null then
    if o.status = 'delivered' then
      return jsonb_build_object('status','already_processed','orderId',o.id,'eggId',o.egg_id,'priceTon',o.price_ton);
    end if;
    return public.deliver_pet_egg_order(o.id);
  end if;

  select * into e from pet_eggs where id = p_egg_id and is_enabled for share;
  if e.id is null or not e.is_purchasable or e.price_ton is null then raise exception 'EGG_NOT_AVAILABLE_FOR_TON'; end if;

  if e.daily_quantity is not null and (
      select count(*) from pet_egg_orders
       where egg_id = e.id and status in ('paid','confirmed','delivered') and created_at >= date_trunc('day', now())
    ) >= e.daily_quantity then raise exception 'DAILY_EGG_LIMIT_REACHED'; end if;

  if e.per_player_limit is not null then
    select count(*) into paid_count from pet_egg_orders
      where egg_id = e.id and user_id = u and status in ('paid','confirmed','delivered');
    if paid_count >= e.per_player_limit then raise exception 'PLAYER_EGG_LIMIT_REACHED'; end if;
  end if;

  v_tx := 'internal_balance:'||gen_random_uuid()::text;

  insert into pet_egg_orders(user_id, egg_id, price_ton, amount_nano, payment_address, payment_comment,
    idempotency_key, status, tx_hash, paid_at, confirmed_at)
  values (u, e.id, round(e.price_ton, 9), round(e.price_ton * 1000000000)::text, 'internal_balance',
    'forge_egg_balance:'||gen_random_uuid(), p_idempotency_key, 'confirmed', v_tx, now(), now())
  returning * into o;

  -- Debits the internal TON balance (raises INSUFFICIENT_TON_BALANCE when there is not enough).
  perform public.debit_ton_balance(u, o.price_ton, 'pet_egg_purchase', o.id::text,
    format('EGG %s purchase (internal balance)', e.name));

  return public.deliver_pet_egg_order(o.id) || jsonb_build_object('paidWith','balance','priceTon',o.price_ton);
end $function$;

revoke all on function public.pet_egg_buy_with_balance(bigint, uuid, text) from public, anon, authenticated;
grant execute on function public.pet_egg_buy_with_balance(bigint, uuid, text) to service_role;

-- Expose the internal TON balance to the pets dashboard so the shop can offer it as a payment method.
create or replace function public.get_pet_dashboard(p_telegram_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE u uuid; base jsonb;
BEGIN
  SELECT id INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  base := jsonb_build_object(
    'activePet', (SELECT player_pet_json(id) FROM player_pets WHERE user_id = u AND is_active AND NOT coalesce(market_locked,false) LIMIT 1),
    'playerPets', coalesce((SELECT jsonb_agg(player_pet_json(t.id))
        FROM (SELECT id FROM player_pets WHERE user_id = u AND NOT coalesce(market_locked,false) ORDER BY is_active DESC, level DESC, created_at) t), '[]'::jsonb),
    'catalog', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'id', p.id, 'name', p.name, 'slug', p.slug,
          'species', CASE WHEN d.found THEN p.species ELSE '???' END,
          'category', p.category,
          'description', CASE WHEN d.found THEN coalesce(p.description,'') ELSE '' END,
          'basePassives', CASE WHEN d.found THEN p.base_passives ELSE '{}'::jsonb END,
          'activeSkill', CASE WHEN d.found THEN p.active_skill ELSE NULL END,
          'rarity', p.rarity, 'availabilityType', p.availability_type,
          'hideName', p.hide_name_until_discovered,
          'images', jsonb_build_object('baby',p.image_baby_url,'young',p.image_young_url,'adult',p.image_adult_url,'ancestral',p.image_ancestral_url), 'image', public.pet_visual_image(p.id, coalesce((SELECT max(pp.level) FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id AND NOT coalesce(pp.market_locked,false)), 1)),
          'discovered', d.found,
          'bestRarity', (SELECT pp.rarity FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id AND NOT coalesce(pp.market_locked,false) ORDER BY pet_rarity_order(pp.rarity) DESC LIMIT 1),
          'bestLevel', (SELECT max(pp.level) FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id AND NOT coalesce(pp.market_locked,false)),
          'sources', coalesce((SELECT jsonb_agg(DISTINCT e.name) FROM reward_pet_pool rp
                JOIN pet_eggs e ON e.id::text = rp.source_key
               WHERE rp.source_type='EGG' AND rp.pet_id = p.id AND rp.enabled AND e.is_enabled),
             coalesce((SELECT jsonb_agg(e.name ORDER BY e.name) FROM pet_eggs e
               WHERE e.is_enabled AND p.availability_type='NORMAL'
                 AND NOT EXISTS (SELECT 1 FROM reward_pet_pool rp2 WHERE rp2.source_type='EGG' AND rp2.source_key=e.id::text)
                 AND (e.allowed_pet_categories IS NULL OR e.allowed_pet_categories ? p.category)), '[]'::jsonb))
        ) ORDER BY p.name)
        FROM pets p
        CROSS JOIN LATERAL (SELECT (exists(SELECT 1 FROM pet_discoveries pd WHERE pd.user_id = u AND pd.pet_id = p.id)
              OR exists(SELECT 1 FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id)) AS found) d
        WHERE p.show_in_catalog AND (p.is_enabled OR d.found)), '[]'::jsonb),
    'foods', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'code', f.code, 'name', f.name, 'rarity', f.rarity, 'xpValue', f.xp_value, 'icon', f.icon, 'priceFc', f.price_fc,
          'quantity', coalesce((SELECT quantity FROM player_pet_food pf WHERE pf.user_id = u AND pf.food_code = f.code), 0)
        ) ORDER BY f.sort_order) FROM pet_food_items f WHERE f.enabled), '[]'::jsonb),
    'fragments', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'playerPetId', pp.id, 'petName', p.name, 'image', p.image_baby_url, 'rarity', pp.rarity, 'quantity', pp.fragments
        ) ORDER BY pp.fragments DESC) FROM player_pets pp JOIN pets p ON p.id = pp.pet_id
        WHERE pp.user_id = u AND NOT coalesce(pp.market_locked,false)), '[]'::jsonb),
    'inventory', jsonb_build_object(
        'food', coalesce((SELECT sum(quantity) FROM player_pet_food WHERE user_id = u), 0),
        'universalFragments', coalesce((SELECT quantity FROM player_pet_inventory WHERE user_id = u AND item_type = 'universal_fragment' AND item_id IS NULL), 0)),
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
    'rarities', coalesce((SELECT jsonb_agg(jsonb_build_object('rarity',c.rarity,'label',c.label,'order',c.sort_order,
          'primary',c.color_primary,'secondary',c.color_secondary,'glow',c.glow) ORDER BY c.sort_order)
        FROM pet_rarity_config c WHERE c.enabled), '[]'::jsonb),
    'bonuses', get_pet_bonuses(u),
    'balance', coalesce((SELECT forge_coins FROM game_players WHERE id = u), 0),
    'tonBalance', coalesce((SELECT ton_balance FROM game_players WHERE id = u), 0)
  );
  RETURN base;
END $function$;

revoke all on function public.get_pet_dashboard(bigint) from public, anon, authenticated;
grant execute on function public.get_pet_dashboard(bigint) to service_role;