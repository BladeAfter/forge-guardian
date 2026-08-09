alter table public.pet_food_items add column if not exists price_fc numeric not null default 0 check (price_fc >= 0);
update public.pet_food_items set price_fc = case code when 'pet_ration' then 1000 when 'pet_food' then 2500 when 'pet_meat' then 6000 when 'pet_magic_fruit' then 15000 when 'pet_rare_food' then 30000 else price_fc end where price_fc = 0;

create table if not exists public.pet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  telegram_id bigint,
  event text not null,
  item_type text,
  item_ref text,
  item_name text,
  quantity integer not null default 1,
  fc_cost numeric not null default 0,
  balance_before numeric,
  balance_after numeric,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
grant select on public.pet_transactions to authenticated;
grant all on public.pet_transactions to service_role;
alter table public.pet_transactions enable row level security;
create policy "pet_transactions service only" on public.pet_transactions for all to service_role using (true) with check (true);
create index if not exists pet_transactions_user_idx on public.pet_transactions(user_id, created_at desc);

create or replace function public.log_pet_transaction(p_user_id uuid, p_event text, p_item_type text, p_item_ref text, p_item_name text, p_quantity integer, p_fc numeric, p_before numeric, p_after numeric, p_meta jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into pet_transactions(user_id, telegram_id, event, item_type, item_ref, item_name, quantity, fc_cost, balance_before, balance_after, metadata)
  values (p_user_id, (select telegram_id from game_players where id = p_user_id), p_event, p_item_type, p_item_ref, p_item_name, coalesce(p_quantity,1), coalesce(p_fc,0), p_before, p_after, coalesce(p_meta,'{}'::jsonb));
end $$;

create or replace function public.buy_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_quantity integer default 1, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; egg pet_eggs%rowtype; qty integer := greatest(1, least(coalesce(p_quantity,1), 50)); total numeric; before numeric; after_balance numeric; owned integer;
begin
  select id, forge_coins into u, before from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if p_idempotency_key is not null then
    insert into pet_action_idempotency(user_id, action_key) values (u, p_idempotency_key) on conflict do nothing;
    if not found then return get_pet_dashboard(p_telegram_id); end if;
  end if;
  select * into egg from pet_eggs where id = p_egg_id;
  if egg.id is null or not egg.is_enabled then raise exception 'EGG_NOT_FOUND'; end if;
  if not egg.is_purchasable then raise exception 'EGG_NOT_PURCHASABLE'; end if;
  if egg.price_fc is null or egg.price_fc <= 0 then raise exception 'EGG_REQUIRES_TON'; end if;
  if egg.per_player_limit is not null then
    select coalesce(sum(quantity),0) into owned from pet_transactions where user_id = u and event = 'egg_purchase' and item_ref = egg.id::text;
    if owned + qty > egg.per_player_limit then raise exception 'EGG_LIMIT_REACHED'; end if;
  end if;
  total := egg.price_fc * qty;
  if before < total then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;
  update game_players set forge_coins = forge_coins - total, updated_at = now() where id = u returning forge_coins into after_balance;
  insert into player_pet_inventory(user_id, item_type, item_id, quantity) values (u, 'egg', egg.id, qty)
    on conflict(user_id, item_type, (coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)))
    do update set quantity = player_pet_inventory.quantity + qty, updated_at = now();
  perform log_pet_transaction(u, 'egg_purchase', 'egg', egg.id::text, egg.name, qty, total, before, after_balance, jsonb_build_object('unitPrice', egg.price_fc));
  return get_pet_dashboard(p_telegram_id);
end $$;

create or replace function public.buy_pet_food(p_telegram_id bigint, p_food_code text, p_quantity integer default 1, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; food pet_food_items%rowtype; qty integer := greatest(1, least(coalesce(p_quantity,1), 500)); total numeric; before numeric; after_balance numeric;
begin
  select id, forge_coins into u, before from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if p_idempotency_key is not null then
    insert into pet_action_idempotency(user_id, action_key) values (u, p_idempotency_key) on conflict do nothing;
    if not found then return get_pet_dashboard(p_telegram_id); end if;
  end if;
  select * into food from pet_food_items where code = p_food_code;
  if food.code is null or not food.enabled then raise exception 'FOOD_NOT_FOUND'; end if;
  if food.price_fc <= 0 then raise exception 'FOOD_NOT_PURCHASABLE'; end if;
  total := food.price_fc * qty;
  if before < total then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;
  update game_players set forge_coins = forge_coins - total, updated_at = now() where id = u returning forge_coins into after_balance;
  insert into player_pet_food(user_id, food_code, quantity) values (u, food.code, qty)
    on conflict(user_id, food_code) do update set quantity = player_pet_food.quantity + qty, updated_at = now();
  perform log_pet_transaction(u, 'food_purchase', 'food', food.code, food.name, qty, total, before, after_balance, jsonb_build_object('unitPrice', food.price_fc, 'xpValue', food.xp_value));
  return get_pet_dashboard(p_telegram_id);
end $$;

create or replace function public.admin_set_pet_food_price(p_admin_id bigint, p_code text, p_price numeric)
returns pet_food_items language plpgsql security definer set search_path = public as $$
declare row pet_food_items;
begin
  perform admin_assert(p_admin_id);
  if p_price < 0 then raise exception 'INVALID_PRICE'; end if;
  update pet_food_items set price_fc = p_price, updated_at = now() where code = p_code returning * into row;
  if row.code is null then raise exception 'FOOD_NOT_FOUND'; end if;
  perform admin_log(p_admin_id, 'pet_food_price', 'pet_food', p_code, null, jsonb_build_object('priceFc', p_price), null, '{}'::jsonb);
  return row;
end $$;

create or replace function public.get_pet_dashboard(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
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
          'bestLevel', (SELECT max(pp.level) FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id),
          'sources', coalesce((SELECT jsonb_agg(e.name ORDER BY e.name) FROM pet_eggs e
              WHERE e.is_enabled AND (e.allowed_pet_categories IS NULL OR e.allowed_pet_categories ? p.category)), '[]'::jsonb)
        ) ORDER BY p.name) FROM pets p WHERE p.is_enabled), '[]'::jsonb),
    'foods', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'code', f.code, 'name', f.name, 'rarity', f.rarity, 'xpValue', f.xp_value, 'icon', f.icon, 'priceFc', f.price_fc,
          'quantity', coalesce((SELECT quantity FROM player_pet_food pf WHERE pf.user_id = u AND pf.food_code = f.code), 0)
        ) ORDER BY f.sort_order) FROM pet_food_items f WHERE f.enabled), '[]'::jsonb),
    'fragments', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'playerPetId', pp.id, 'petName', p.name, 'image', p.image_baby_url, 'rarity', pp.rarity, 'quantity', pp.fragments
        ) ORDER BY pp.fragments DESC) FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.user_id = u), '[]'::jsonb),
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
    'bonuses', get_pet_bonuses(u),
    'balance', coalesce((SELECT forge_coins FROM game_players WHERE id = u), 0)
  );
END $$;