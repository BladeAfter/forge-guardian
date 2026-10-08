-- ============================================================================
-- PRIVATE TRADE: lifecycle RPCs (search, create, offers, lock). Server-side only.
-- ============================================================================

create or replace function public.private_trade_guard(p_telegram_id bigint)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare g game_players%rowtype; cfg jsonb; is_admin boolean;
begin
  cfg := private_trade_settings_json();
  select * into g from game_players where telegram_id = p_telegram_id;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if coalesce(g.banned,false) then raise exception 'ACCOUNT_BANNED'; end if;
  is_admin := market_is_bypass_admin(p_telegram_id);
  if not is_admin then
    if not (cfg->>'enabled')::boolean then raise exception 'PRIVATE_TRADE_DISABLED'; end if;
    if (cfg->>'adminOnly')::boolean then raise exception 'PRIVATE_TRADE_DISABLED'; end if;
    if market_account_days(g.id) < coalesce((cfg->>'minAccountDays')::integer, 7) then
      raise exception 'ACCOUNT_TOO_NEW'; end if;
    if g.market_restricted_until is not null and g.market_restricted_until > now() then
      raise exception 'PRIVATE_TRADE_TEMPORARILY_LIMITED'; end if;
  end if;
  return g.id;
end $$;

create or replace function public.private_trade_search_player(p_telegram_id bigint, p_query text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me uuid; q text := trim(coalesce(p_query,'')); v_target uuid;
begin
  v_me := private_trade_guard(p_telegram_id);
  if length(q) < 2 then raise exception 'INVALID_QUERY'; end if;
  q := ltrim(q, '@');
  if q ~ '^[0-9]+$' then
    select id into v_target from game_players where telegram_id = q::bigint;
  elsif q ~* '^[0-9a-f-]{36}$' then
    select id into v_target from game_players where id = q::uuid;
  else
    select id into v_target from game_players where lower(username) = lower(q) limit 1;
  end if;
  if v_target is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if v_target = v_me then raise exception 'CANNOT_TRADE_WITH_YOURSELF'; end if;
  if exists (select 1 from game_players where id = v_target and coalesce(banned,false)) then
    raise exception 'PLAYER_UNAVAILABLE'; end if;
  return jsonb_build_object('ok', true, 'player', private_trade_player_card(v_target));
end $$;

create or replace function public.private_trade_state(p_user uuid, p_trade uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare t private_trades%rowtype; v_mine text; cfg jsonb;
begin
  select * into t from private_trades where id = p_trade;
  if t.id is null then raise exception 'TRADE_NOT_FOUND'; end if;
  if p_user not in (t.initiator_user_id, t.recipient_user_id) then raise exception 'TRADE_NOT_FOUND'; end if;
  v_mine := case when p_user = t.initiator_user_id then 'initiator' else 'recipient' end;
  cfg := private_trade_settings_json();
  return jsonb_build_object(
    'ok', true, 'id', t.id, 'code', t.code, 'status', t.status, 'mySide', v_mine,
    'expiresAt', t.expires_at, 'createdAt', t.created_at, 'completedAt', t.completed_at,
    'cancelReason', t.cancel_reason, 'maxItems', (cfg->>'maxItems')::integer,
    'feePercent', (cfg->>'feePercent')::numeric,
    'me', jsonb_build_object(
      'player', private_trade_player_card(case when v_mine = 'initiator' then t.initiator_user_id else t.recipient_user_id end),
      'locked', case when v_mine = 'initiator' then t.initiator_locked else t.recipient_locked end,
      'confirmed', case when v_mine = 'initiator' then t.initiator_confirmed else t.recipient_confirmed end,
      'fc', case when v_mine = 'initiator' then t.initiator_fc else t.recipient_fc end,
      'ton', case when v_mine = 'initiator' then t.initiator_ton else t.recipient_ton end,
      'myth', case when v_mine = 'initiator' then t.initiator_myth else t.recipient_myth end,
      'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'itemType', i.item_type,
          'itemCode', i.item_code, 'quantity', i.quantity, 'snapshot', i.snapshot) order by i.created_at)
        from private_trade_items i where i.trade_id = t.id and i.side = v_mine), '[]'::jsonb)),
    'partner', jsonb_build_object(
      'player', private_trade_player_card(case when v_mine = 'initiator' then t.recipient_user_id else t.initiator_user_id end),
      'locked', case when v_mine = 'initiator' then t.recipient_locked else t.initiator_locked end,
      'confirmed', case when v_mine = 'initiator' then t.recipient_confirmed else t.initiator_confirmed end,
      'fc', case when v_mine = 'initiator' then t.recipient_fc else t.initiator_fc end,
      'ton', case when v_mine = 'initiator' then t.recipient_ton else t.initiator_ton end,
      'myth', case when v_mine = 'initiator' then t.recipient_myth else t.initiator_myth end,
      'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'itemType', i.item_type,
          'itemCode', i.item_code, 'quantity', i.quantity, 'snapshot', i.snapshot) order by i.created_at)
        from private_trade_items i where i.trade_id = t.id
          and i.side = case when v_mine = 'initiator' then 'recipient' else 'initiator' end), '[]'::jsonb)),
    'balances', (select jsonb_build_object('fc', g.forge_coins, 'ton', coalesce(g.ton_balance,0),
        'myth', coalesce((select amount from myth_balances mb where mb.user_id = g.id), 0))
      from game_players g where g.id = p_user));
end $$;

create or replace function public.private_trade_list(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me uuid; cfg jsonb;
begin
  select id into v_me from game_players where telegram_id = p_telegram_id;
  if v_me is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform private_trade_expire_sweep();
  cfg := private_trade_settings_json();
  return jsonb_build_object('ok', true, 'settings', cfg,
    'canTrade', (coalesce(market_is_bypass_admin(p_telegram_id), false)
       or (market_account_days(v_me) >= (cfg->>'minAccountDays')::integer
           and (cfg->>'enabled')::boolean and not (cfg->>'adminOnly')::boolean)),
    'accountDays', market_account_days(v_me),
    'trades', coalesce((select jsonb_agg(jsonb_build_object(
        'id', t.id, 'code', t.code, 'status', t.status,
        'partner', private_trade_player_card(case when t.initiator_user_id = v_me then t.recipient_user_id else t.initiator_user_id end),
        'mySide', case when t.initiator_user_id = v_me then 'initiator' else 'recipient' end,
        'myItems', (select count(*) from private_trade_items i where i.trade_id = t.id
           and i.side = case when t.initiator_user_id = v_me then 'initiator' else 'recipient' end),
        'theirItems', (select count(*) from private_trade_items i where i.trade_id = t.id
           and i.side = case when t.initiator_user_id = v_me then 'recipient' else 'initiator' end),
        'expiresAt', t.expires_at, 'updatedAt', t.updated_at, 'createdAt', t.created_at)
      order by t.updated_at desc)
      from private_trades t
     where v_me in (t.initiator_user_id, t.recipient_user_id)
       and (t.status not in ('completed','cancelled','expired','blocked') or t.updated_at > now() - interval '7 days')
     ), '[]'::jsonb));
end $$;

create or replace function public.private_trade_create(p_telegram_id bigint, p_query text, p_request_id text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me uuid; v_target uuid; cfg jsonb; v_trade uuid; v_out jsonb;
begin
  if p_request_id is not null then
    select result into v_out from private_trade_idempotency where request_id = p_request_id;
    if v_out is not null then return v_out; end if;
  end if;
  v_me := private_trade_guard(p_telegram_id);
  v_target := ((private_trade_search_player(p_telegram_id, p_query))->'player'->>'id')::uuid;
  cfg := private_trade_settings_json();

  if exists (select 1 from private_trades t
     where t.status in ('negotiating','offer_locked','ready_for_confirmation','security_review')
       and ((t.initiator_user_id = v_me and t.recipient_user_id = v_target)
         or (t.initiator_user_id = v_target and t.recipient_user_id = v_me))) then
    raise exception 'TRADE_ALREADY_OPEN';
  end if;

  insert into private_trades(initiator_user_id, recipient_user_id, status, expires_at)
  values (v_me, v_target, 'negotiating', now() + make_interval(hours => (cfg->>'expireHours')::integer))
  returning id into v_trade;

  insert into private_trade_events(trade_id, actor_user_id, event, details)
  values (v_trade, v_me, 'trade_created', jsonb_build_object('recipient', v_target));

  insert into player_notifications(user_id, type, title, message, metadata, dedupe_key)
  values (v_target, 'private_trade', 'NEW PRIVATE TRADE',
    market_seller_label(v_me) || ' wants to trade with you.',
    jsonb_build_object('tradeId', v_trade), 'private_trade_new:' || v_trade::text)
  on conflict do nothing;

  v_out := private_trade_state(v_me, v_trade);
  if p_request_id is not null then
    insert into private_trade_idempotency(request_id, trade_id, action, result)
    values (p_request_id, v_trade, 'create', v_out) on conflict (request_id) do nothing;
  end if;
  return v_out;
end $$;

-- Any offer change invalidates both confirmations (spec 14).
create or replace function public.private_trade_touch(p_trade uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  update private_trades set initiator_confirmed = false, recipient_confirmed = false,
    status = case when initiator_locked and recipient_locked then 'ready_for_confirmation'
                  when initiator_locked or recipient_locked then 'offer_locked'
                  else 'negotiating' end,
    updated_at = now()
  where id = p_trade and status in ('negotiating','offer_locked','ready_for_confirmation');
end $$;

create or replace function public.private_trade_add_item(
  p_telegram_id bigint, p_trade uuid, p_item_type text, p_instance_id uuid,
  p_item_code text, p_quantity integer default 1)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_me uuid; t private_trades%rowtype; v_side text; cfg jsonb; v_kind text := lower(coalesce(p_item_type,''));
  v_qty integer := greatest(coalesce(p_quantity,1),1); v_count integer; v_snap jsonb; v_val numeric;
  h player_heroes%rowtype; pp player_pets%rowtype; pet_row pets%rowtype; v_nft boolean := false;
begin
  v_me := private_trade_guard(p_telegram_id);
  select * into t from private_trades where id = p_trade for update;
  if t.id is null or v_me not in (t.initiator_user_id, t.recipient_user_id) then raise exception 'TRADE_NOT_FOUND'; end if;
  if t.status not in ('negotiating','offer_locked','ready_for_confirmation') then raise exception 'TRADE_NOT_EDITABLE'; end if;
  if t.expires_at <= now() then raise exception 'TRADE_EXPIRED'; end if;
  v_side := case when v_me = t.initiator_user_id then 'initiator' else 'recipient' end;
  if (v_side = 'initiator' and t.initiator_locked) or (v_side = 'recipient' and t.recipient_locked) then
    raise exception 'OFFER_LOCKED'; end if;

  cfg := private_trade_settings_json();
  if v_kind not in ('hero','pet','item') then raise exception 'INVALID_ITEM_TYPE'; end if;
  select count(*) into v_count from private_trade_items i where i.trade_id = t.id and i.side = v_side;
  if v_count >= (cfg->>'maxItems')::integer then raise exception 'MAX_ITEMS_REACHED'; end if;

  if v_kind = 'hero' then
    select * into h from player_heroes where id = p_instance_id and user_id = v_me for update;
    if h.id is null then raise exception 'ITEM_NOT_OWNED'; end if;
    if coalesce(h.market_locked,false) then raise exception 'ALREADY_LISTED'; end if;
    if coalesce(h.locked,false) then raise exception 'HERO_LOCKED'; end if;
    if coalesce(h.tradable,true) = false then raise exception 'HERO_NOT_TRADABLE'; end if;
    if exists (select 1 from pvp_team_slots s where s.hero_id = h.id) then raise exception 'HERO_IN_PVP_TEAM'; end if;
    if exists (select 1 from boss_team_slots b where b.player_hero_id = h.id) then raise exception 'HERO_IN_BOSS_TEAM'; end if;
    v_nft := coalesce(h.is_nft_exclusive,false) or h.nft_hero_id is not null;
    v_snap := jsonb_build_object('name', h.name, 'rarity', h.rarity, 'level', h.level, 'image', h.image,
      'stars', coalesce(h.fusion_level,0), 'atk', round(coalesce(h.final_atk,0)), 'hp', round(coalesce(h.final_hp,0)),
      'nft', v_nft, 'kind', 'hero');
    v_val := private_trade_item_value(h.rarity, 'hero', 1, v_nft);
    update player_heroes set market_locked = true, updated_at = now() where id = h.id;
  elsif v_kind = 'pet' then
    select * into pp from player_pets where id = p_instance_id and user_id = v_me for update;
    if pp.id is null then raise exception 'ITEM_NOT_OWNED'; end if;
    if coalesce(pp.market_locked,false) then raise exception 'ALREADY_LISTED'; end if;
    if coalesce(pp.is_active,false) then raise exception 'PET_IS_ACTIVE'; end if;
    if coalesce(pp.tradable,true) = false then raise exception 'PET_NOT_TRADABLE'; end if;
    select * into pet_row from pets where id = pp.pet_id;
    v_snap := jsonb_build_object('name', coalesce(pet_row.name,'Pet'), 'rarity', pp.rarity, 'level', pp.level,
      'image', coalesce(pet_row.image_adult_url, pet_row.image_young_url, pet_row.image_baby_url),
      'evolution', pp.evolution_stage, 'tier', coalesce(pp.evolution_tier,0), 'nft', false, 'kind', 'pet');
    v_val := private_trade_item_value(pp.rarity, 'pet', 1, false);
    update player_pets set market_locked = true, updated_at = now() where id = pp.id;
  else
    if p_item_code is null or length(p_item_code) < 2 then raise exception 'INVALID_ITEM'; end if;
    v_snap := market_item_take(v_me, p_item_code, v_qty) || jsonb_build_object('kind','item');
    if not coalesce((v_snap->>'stackable')::boolean, true) and v_qty <> 1 then raise exception 'INVALID_QUANTITY'; end if;
    v_val := private_trade_item_value(v_snap->>'rarity', 'item', v_qty, false);
  end if;

  insert into private_trade_items(trade_id, owner_user_id, side, item_type, item_instance_id, item_code, quantity, snapshot, value_fc)
  values (t.id, v_me, v_side, v_kind,
    case when v_kind = 'item' then null else p_instance_id end,
    case when v_kind = 'item' then lower(p_item_code) else null end, v_qty, v_snap, v_val);

  insert into private_trade_events(trade_id, actor_user_id, event, details)
  values (t.id, v_me, 'item_added', jsonb_build_object('side', v_side, 'itemType', v_kind, 'quantity', v_qty, 'snapshot', v_snap));
  perform private_trade_touch(t.id);
  return private_trade_state(v_me, t.id);
end $$;

create or replace function public.private_trade_remove_item(p_telegram_id bigint, p_trade uuid, p_item_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me uuid; t private_trades%rowtype; v_side text; it private_trade_items%rowtype;
begin
  v_me := private_trade_guard(p_telegram_id);
  select * into t from private_trades where id = p_trade for update;
  if t.id is null or v_me not in (t.initiator_user_id, t.recipient_user_id) then raise exception 'TRADE_NOT_FOUND'; end if;
  if t.status not in ('negotiating','offer_locked','ready_for_confirmation') then raise exception 'TRADE_NOT_EDITABLE'; end if;
  v_side := case when v_me = t.initiator_user_id then 'initiator' else 'recipient' end;
  if (v_side = 'initiator' and t.initiator_locked) or (v_side = 'recipient' and t.recipient_locked) then
    raise exception 'OFFER_LOCKED'; end if;

  select * into it from private_trade_items where id = p_item_id and trade_id = t.id for update;
  if it.id is null then raise exception 'ITEM_NOT_IN_TRADE'; end if;
  if it.owner_user_id <> v_me then raise exception 'NOT_YOUR_ITEM'; end if;

  if it.item_type = 'hero' then
    update player_heroes set market_locked = false, updated_at = now() where id = it.item_instance_id;
  elsif it.item_type = 'pet' then
    update player_pets set market_locked = false, updated_at = now() where id = it.item_instance_id;
  else
    perform market_item_give(v_me, it.item_code, it.snapshot, it.quantity);
  end if;
  delete from private_trade_items where id = it.id;
  insert into private_trade_events(trade_id, actor_user_id, event, details)
  values (t.id, v_me, 'item_removed', jsonb_build_object('side', v_side, 'itemId', it.id));
  perform private_trade_touch(t.id);
  return private_trade_state(v_me, t.id);
end $$;

create or replace function public.private_trade_set_currency(
  p_telegram_id bigint, p_trade uuid, p_fc numeric, p_ton numeric, p_myth numeric)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me uuid; t private_trades%rowtype; v_side text; v_fc numeric; v_ton numeric; v_myth numeric;
        a_fc numeric; a_ton numeric; a_myth numeric;
begin
  v_me := private_trade_guard(p_telegram_id);
  select * into t from private_trades where id = p_trade for update;
  if t.id is null or v_me not in (t.initiator_user_id, t.recipient_user_id) then raise exception 'TRADE_NOT_FOUND'; end if;
  if t.status not in ('negotiating','offer_locked','ready_for_confirmation') then raise exception 'TRADE_NOT_EDITABLE'; end if;
  if t.expires_at <= now() then raise exception 'TRADE_EXPIRED'; end if;
  v_side := case when v_me = t.initiator_user_id then 'initiator' else 'recipient' end;
  if (v_side = 'initiator' and t.initiator_locked) or (v_side = 'recipient' and t.recipient_locked) then
    raise exception 'OFFER_LOCKED'; end if;

  v_fc := greatest(0, trunc(coalesce(p_fc,0)));
  v_ton := greatest(0, round(coalesce(p_ton,0), 9));
  v_myth := greatest(0, round(coalesce(p_myth,0), 4));

  select forge_coins, coalesce(ton_balance,0) into a_fc, a_ton from game_players where id = v_me;
  select coalesce(amount,0) into a_myth from myth_balances where user_id = v_me;
  if v_fc > a_fc then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;
  if v_ton > a_ton then raise exception 'INSUFFICIENT_TON_BALANCE'; end if;
  if v_myth > coalesce(a_myth,0) then raise exception 'INSUFFICIENT_MYTH_BALANCE'; end if;

  if v_side = 'initiator' then
    update private_trades set initiator_fc = v_fc, initiator_ton = v_ton, initiator_myth = v_myth, updated_at = now() where id = t.id;
  else
    update private_trades set recipient_fc = v_fc, recipient_ton = v_ton, recipient_myth = v_myth, updated_at = now() where id = t.id;
  end if;
  insert into private_trade_events(trade_id, actor_user_id, event, details)
  values (t.id, v_me, 'currency_changed', jsonb_build_object('side', v_side, 'fc', v_fc, 'ton', v_ton, 'myth', v_myth));
  perform private_trade_touch(t.id);
  return private_trade_state(v_me, t.id);
end $$;

-- LOCK OFFER: this side's currency moves into escrow (items already are).
create or replace function public.private_trade_lock(p_telegram_id bigint, p_trade uuid, p_locked boolean default true, p_request_id text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me uuid; t private_trades%rowtype; v_side text; v_out jsonb; v_both boolean;
begin
  if p_request_id is not null then
    select result into v_out from private_trade_idempotency where request_id = p_request_id;
    if v_out is not null then return v_out; end if;
  end if;
  v_me := private_trade_guard(p_telegram_id);
  select * into t from private_trades where id = p_trade for update;
  if t.id is null or v_me not in (t.initiator_user_id, t.recipient_user_id) then raise exception 'TRADE_NOT_FOUND'; end if;
  if t.status not in ('negotiating','offer_locked','ready_for_confirmation') then raise exception 'TRADE_NOT_EDITABLE'; end if;
  if t.expires_at <= now() then raise exception 'TRADE_EXPIRED'; end if;
  v_side := case when v_me = t.initiator_user_id then 'initiator' else 'recipient' end;

  if coalesce(p_locked, true) then
    if v_side = 'initiator' and not t.initiator_locked then
      perform private_trade_escrow_lock(v_me, t.id, t.initiator_fc, t.initiator_ton, t.initiator_myth);
      update private_trades set initiator_locked = true, initiator_escrowed = true, updated_at = now() where id = t.id;
    elsif v_side = 'recipient' and not t.recipient_locked then
      perform private_trade_escrow_lock(v_me, t.id, t.recipient_fc, t.recipient_ton, t.recipient_myth);
      update private_trades set recipient_locked = true, recipient_escrowed = true, updated_at = now() where id = t.id;
    end if;
  else
    if v_side = 'initiator' and t.initiator_locked then
      if t.initiator_escrowed then
        perform private_trade_escrow_release(v_me, t.id, t.initiator_fc, t.initiator_ton, t.initiator_myth);
      end if;
      update private_trades set initiator_locked = false, initiator_escrowed = false,
        initiator_confirmed = false, recipient_confirmed = false, updated_at = now() where id = t.id;
    elsif v_side = 'recipient' and t.recipient_locked then
      if t.recipient_escrowed then
        perform private_trade_escrow_release(v_me, t.id, t.recipient_fc, t.recipient_ton, t.recipient_myth);
      end if;
      update private_trades set recipient_locked = false, recipient_escrowed = false,
        initiator_confirmed = false, recipient_confirmed = false, updated_at = now() where id = t.id;
    end if;
  end if;

  select (initiator_locked and recipient_locked) into v_both from private_trades where id = t.id;
  update private_trades set status = case when v_both then 'ready_for_confirmation'
      when initiator_locked or recipient_locked then 'offer_locked' else 'negotiating' end,
    updated_at = now() where id = t.id and status in ('negotiating','offer_locked','ready_for_confirmation');

  insert into private_trade_events(trade_id, actor_user_id, event, details)
  values (t.id, v_me, case when coalesce(p_locked,true) then 'offer_locked' else 'offer_unlocked' end,
          jsonb_build_object('side', v_side));

  if v_both then perform private_trade_risk_assess(t.id); end if;
  v_out := private_trade_state(v_me, t.id);
  if p_request_id is not null then
    insert into private_trade_idempotency(request_id, trade_id, action, result)
    values (p_request_id, t.id, 'lock', v_out) on conflict (request_id) do nothing;
  end if;
  return v_out;
end $$;