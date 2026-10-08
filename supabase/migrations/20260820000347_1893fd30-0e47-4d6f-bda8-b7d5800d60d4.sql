-- ===== PET FOOD =====
drop function if exists public.buy_pet_food(bigint, text, integer, text);
create or replace function public.buy_pet_food(p_telegram_id bigint, p_food_code text, p_quantity integer default 1,
  p_idempotency_key text default null, p_currency text default 'FC')
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid; food pet_food_items%rowtype; qty integer := greatest(1, least(coalesce(p_quantity,1), 500));
  total numeric; before numeric; after_balance numeric; v_cur text; v_unit_myth numeric; v_myth numeric; v_burn jsonb;
begin
  v_cur := case when upper(coalesce(p_currency,'FC')) = 'MYTH' then 'MYTH' else 'FC' end;
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
  after_balance := before;

  if v_cur = 'MYTH' then
    v_unit_myth := public.myth_utility_price('FOOD_PURCHASE', food.price_fc, 0);
    if v_unit_myth is null then raise exception 'MYTH_PAYMENT_NOT_ENABLED'; end if;
    v_myth := v_unit_myth * qty;
    v_burn := public.myth_utility_charge(u, 'FOOD_PURCHASE', v_myth, food.code,
      coalesce(p_idempotency_key, 'food:'||u::text||':'||gen_random_uuid()::text),
      jsonb_build_object('foodCode', food.code, 'quantity', qty, 'unitMyth', v_unit_myth, 'fcEquivalent', total));
  else
    if before < total then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;
    update game_players set forge_coins = forge_coins - total, updated_at = now() where id = u returning forge_coins into after_balance;
  end if;

  insert into player_pet_food(user_id, food_code, quantity) values (u, food.code, qty)
    on conflict(user_id, food_code) do update set quantity = player_pet_food.quantity + qty, updated_at = now();
  perform log_pet_transaction(u, 'food_purchase', 'food', food.code, food.name, qty,
    case when v_cur = 'MYTH' then 0 else total end, before, after_balance,
    jsonb_build_object('unitPrice', food.price_fc, 'xpValue', food.xp_value, 'currency', v_cur,
      'mythSpent', coalesce(v_myth, 0), 'unitMyth', v_unit_myth));
  return get_pet_dashboard(p_telegram_id)
    || jsonb_build_object('paidWith', v_cur, 'mythSpent', coalesce(v_myth, 0), 'mythBurn', v_burn);
end $$;

-- ===== PET EGG (FC store) =====
drop function if exists public.buy_pet_egg(bigint, uuid, integer, text);
create or replace function public.buy_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_quantity integer default 1,
  p_idempotency_key text default null, p_currency text default 'FC')
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid; egg pet_eggs%rowtype; qty integer := greatest(1, least(coalesce(p_quantity,1), 50));
  total numeric; before numeric; after_balance numeric; owned integer;
  v_cur text; v_unit_myth numeric; v_myth numeric; v_burn jsonb;
begin
  v_cur := case when upper(coalesce(p_currency,'FC')) = 'MYTH' then 'MYTH' else 'FC' end;
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
  after_balance := before;

  if v_cur = 'MYTH' then
    v_unit_myth := public.myth_utility_price('EGG_PURCHASE', egg.price_fc, 0);
    if v_unit_myth is null then raise exception 'MYTH_PAYMENT_NOT_ENABLED'; end if;
    v_myth := v_unit_myth * qty;
    v_burn := public.myth_utility_charge(u, 'EGG_PURCHASE', v_myth, egg.id::text,
      coalesce(p_idempotency_key, 'egg:'||u::text||':'||gen_random_uuid()::text),
      jsonb_build_object('eggId', egg.id, 'quantity', qty, 'unitMyth', v_unit_myth, 'fcEquivalent', total));
  else
    if before < total then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;
    update game_players set forge_coins = forge_coins - total, updated_at = now() where id = u returning forge_coins into after_balance;
  end if;

  insert into player_pet_inventory(user_id, item_type, item_id, quantity) values (u, 'egg', egg.id, qty)
    on conflict(user_id, item_type, (coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)))
    do update set quantity = player_pet_inventory.quantity + qty, updated_at = now();
  perform log_pet_transaction(u, 'egg_purchase', 'egg', egg.id::text, egg.name, qty,
    case when v_cur = 'MYTH' then 0 else total end, before, after_balance,
    jsonb_build_object('unitPrice', egg.price_fc, 'currency', v_cur, 'mythSpent', coalesce(v_myth,0), 'unitMyth', v_unit_myth));
  return get_pet_dashboard(p_telegram_id)
    || jsonb_build_object('paidWith', v_cur, 'mythSpent', coalesce(v_myth, 0), 'mythBurn', v_burn);
end $$;

-- ===== PET UPGRADE (level) =====
drop function if exists public.upgrade_pet_v2(bigint, uuid, text);
create or replace function public.upgrade_pet_v2(p_telegram_id bigint, p_player_pet_id uuid, p_idempotency_key text,
  p_currency text default 'FC')
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u game_players%rowtype; pet player_pets%rowtype; needed int; cost numeric; next_stage text; payload jsonb;
  v_cur text; v_myth numeric; v_burn jsonb;
begin
  if length(coalesce(p_idempotency_key,'')) < 8 then raise exception 'INVALID_EVOLUTION_REQUEST'; end if;
  v_cur := case when upper(coalesce(p_currency,'FC')) = 'MYTH' then 'MYTH' else 'FC' end;
  select * into u from game_players where telegram_id = p_telegram_id for update;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select result into payload from pet_action_idempotency where idempotency_key = p_idempotency_key and user_id = u.id;
  if payload is not null then return payload; end if;
  select * into pet from player_pets where id = p_player_pet_id and user_id = u.id for update;
  if pet.id is null then raise exception 'PET_NOT_OWNED'; end if;
  if pet.level >= 30 then raise exception 'PET_MAX_LEVEL'; end if;
  needed := pet_xp_required(pet.level);
  if pet.xp < needed then raise exception 'PET_XP_REQUIRED'; end if;
  cost := pet_evolution_cost(pet.level, pet.rarity);
  next_stage := pet_evolution_stage(pet.level + 1);

  if v_cur = 'MYTH' then
    v_myth := public.myth_utility_price('PET_UPGRADE', cost, 0);
    if v_myth is null then raise exception 'MYTH_PAYMENT_NOT_ENABLED'; end if;
    v_burn := public.myth_utility_charge(u.id, 'PET_UPGRADE', v_myth, pet.id::text, p_idempotency_key,
      jsonb_build_object('petId', pet.id, 'level', pet.level, 'fcEquivalent', cost, 'kind', 'level_up'));
  else
    if u.forge_coins < cost then raise exception 'NOT_ENOUGH_FC'; end if;
    update game_players set forge_coins = forge_coins - cost, updated_at = now() where id = u.id;
  end if;

  update player_pets set level = pet.level + 1, xp = pet.xp - needed, evolution_stage = next_stage, updated_at = now()
    where id = pet.id;
  insert into pet_evolution_history(user_id, player_pet_id, old_level, new_level, xp_before, xp_spent, xp_after,
    fc_cost, rarity, old_stage, new_stage, idempotency_key)
  values (u.id, pet.id, pet.level, pet.level + 1, pet.xp, needed, pet.xp - needed,
    case when v_cur = 'MYTH' then 0 else cost end, pet.rarity, pet.evolution_stage, next_stage, p_idempotency_key);
  payload := get_pet_dashboard(p_telegram_id)
    || jsonb_build_object('paidWith', v_cur, 'mythSpent', coalesce(v_myth, 0), 'mythBurn', v_burn);
  insert into pet_action_idempotency values (p_idempotency_key, u.id, pet.id, 'upgrade', payload, now());
  return payload;
end $$;

-- ===== TOWER ENTRY (adds myth) =====
create or replace function public.tower_enter_floor(p_telegram_id bigint, p_pay_currency text default 'fc'::text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare pl public.game_players; p public.tower_progress; v_limit int; v_cost numeric; v_floor int;
  v_boss jsonb; v_team jsonb; sim jsonb; v_win boolean; v_first boolean; v_rewards jsonb := '{}'::jsonb;
  v_buffs jsonb; seed text; v_pay text; v_cost_ton numeric := 0; v_avail numeric; v_before numeric; v_after numeric;
  v_cost_myth numeric := 0; v_burn jsonb; v_myth_avail numeric;
begin
  v_pay := case lower(coalesce(p_pay_currency,'fc')) when 'ton' then 'ton' when 'myth' then 'myth' else 'fc' end;
  select * into pl from public.game_players where telegram_id = p_telegram_id for update;
  if pl.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if pl.banned then raise exception 'PLAYER_BANNED'; end if;
  p := public.tower_ensure_progress(pl.id);
  v_limit := greatest(1, public.setting_num('tower_daily_attempts', 5)::int);
  if p.attempts_used >= v_limit then raise exception 'TOWER_NO_ATTEMPTS'; end if;

  v_floor := p.current_floor;
  v_cost := public.tower_entry_cost(v_floor);
  if v_pay = 'ton' then
    v_cost_ton := public.tower_entry_cost_ton();
    v_avail := round(greatest(0, coalesce(pl.ton_balance,0) - coalesce(pl.ton_reserved,0)), 9);
    if v_avail < v_cost_ton then raise exception 'INSUFFICIENT_TON'; end if;
  elsif v_pay = 'myth' then
    v_cost_myth := public.myth_utility_price('TOWER_ENTRY', v_cost, public.tower_entry_cost_ton());
    if v_cost_myth is null then raise exception 'MYTH_PAYMENT_NOT_ENABLED'; end if;
    select coalesce(amount, 0) into v_myth_avail from public.myth_balances where user_id = pl.id;
    if coalesce(v_myth_avail, 0) < v_cost_myth then raise exception 'INSUFFICIENT_MYTH'; end if;
  else
    if coalesce(pl.forge_coins,0) < v_cost then raise exception 'INSUFFICIENT_FC'; end if;
  end if;

  v_team := public.tower_team_json(pl.id);
  if jsonb_array_length(v_team) = 0 then raise exception 'TOWER_TEAM_EMPTY'; end if;
  if (select count(distinct public.pvp_hero_template_key(h)) from public.tower_team_slots s
        join public.player_heroes h on h.id = s.hero_id where s.user_id = pl.id) <> jsonb_array_length(v_team)
  then raise exception 'TOWER_DUPLICATE_HERO_TEAM'; end if;

  v_buffs := coalesce(public.get_pet_bonuses(pl.id), '{}'::jsonb);
  v_team := public.pvp_apply_pet_modifiers(v_team, v_buffs);

  v_boss := public.tower_boss_for_floor(v_floor);
  seed := gen_random_uuid()::text;
  sim := public.simulate_tower_battle(v_team, v_boss, seed);
  v_win := (sim->>'winnerSide') = 'attacker';
  v_first := v_floor > p.highest_floor;

  if v_pay = 'ton' then
    v_before := round(coalesce(pl.ton_balance,0), 9);
    v_after := round(v_before - v_cost_ton, 9);
    if v_after < 0 then raise exception 'INSUFFICIENT_TON'; end if;
    update public.game_players set ton_balance = v_after, updated_at = now() where id = pl.id;
    insert into public.wallet_ledger(user_id, type, amount_fc, amount_ton, balance_before, balance_after, reference_id)
    values (pl.id, 'tower_entry_ton', 0, -v_cost_ton, v_before, v_after,
            'tower:floor:' || v_floor || ':' || seed);
    v_cost := 0;
  elsif v_pay = 'myth' then
    v_burn := public.myth_utility_charge(pl.id, 'TOWER_ENTRY', v_cost_myth, 'floor:' || v_floor,
      'tower:' || pl.id::text || ':' || seed,
      jsonb_build_object('floor', v_floor, 'fcEquivalent', v_cost, 'tonReference', public.tower_entry_cost_ton()));
    v_cost := 0;
  else
    update public.game_players set forge_coins = forge_coins - v_cost, updated_at = now() where id = pl.id;
  end if;

  update public.tower_progress set attempts_used = attempts_used + 1, updated_at = now() where user_id = pl.id;

  if v_win then
    v_rewards := public.tower_grant_rewards(pl.id, v_floor, v_first);
    update public.tower_progress
      set highest_floor = greatest(highest_floor, v_floor),
          current_floor = least(100, v_floor + 1),
          updated_at = now()
      where user_id = pl.id;
  end if;

  insert into public.tower_runs(user_id,floor,boss_key,result,turns,cost_fc,first_clear,rewards)
  values (pl.id, v_floor, v_boss->>'bossKey', case when v_win then 'win' else 'loss' end,
          greatest(1,(sim->>'totalTurns')::int), v_cost, v_win and v_first, v_rewards);

  return jsonb_build_object(
    'result', case when v_win then 'win' else 'loss' end,
    'floor', v_floor, 'boss', v_boss, 'costFc', v_cost,
    'costTon', v_cost_ton, 'costMyth', v_cost_myth, 'paidWith', v_pay, 'mythBurn', v_burn,
    'firstClear', v_win and v_first,
    'rewards', v_rewards,
    'totalTurns', greatest(1,(sim->>'totalTurns')::int),
    'battleLog', sim->'battleLog',
    'attackerState', sim->'attackerState',
    'defenderState', sim->'defenderState',
    'team', v_team,
    'dashboard', public.get_tower_dashboard(p_telegram_id)
  );
end $$;