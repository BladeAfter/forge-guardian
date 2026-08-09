create table if not exists public.pet_purchase_idempotency (
  idempotency_key text primary key,
  user_id uuid not null references public.game_players(id) on delete cascade,
  created_at timestamptz not null default now()
);
grant all on public.pet_purchase_idempotency to service_role;
alter table public.pet_purchase_idempotency enable row level security;
create policy "pet purchase keys service only" on public.pet_purchase_idempotency for all to service_role using (true) with check (true);

create or replace function public.buy_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_quantity integer default 1, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; egg pet_eggs%rowtype; qty integer := greatest(1, least(coalesce(p_quantity,1), 50)); total numeric; before numeric; after_balance numeric; owned integer;
begin
  select id, forge_coins into u, before from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if p_idempotency_key is not null then
    insert into pet_purchase_idempotency(idempotency_key, user_id) values (p_idempotency_key, u) on conflict do nothing;
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
    insert into pet_purchase_idempotency(idempotency_key, user_id) values (p_idempotency_key, u) on conflict do nothing;
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