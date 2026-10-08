-- ============================================================================
-- PRIVATE TRADE: atomic settlement, cancel/expiry, admin security review
-- ============================================================================

-- Returns every escrowed asset (items + FC/TON/MYTH) to its original owner.
create or replace function public.private_trade_release_all(p_trade uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare t private_trades%rowtype; it private_trade_items%rowtype;
begin
  select * into t from private_trades where id = p_trade for update;
  if t.id is null then raise exception 'TRADE_NOT_FOUND'; end if;
  for it in select * from private_trade_items where trade_id = t.id loop
    if it.item_type = 'hero' then
      update player_heroes set market_locked = false, updated_at = now() where id = it.item_instance_id;
    elsif it.item_type = 'pet' then
      update player_pets set market_locked = false, updated_at = now() where id = it.item_instance_id;
    else
      perform market_item_give(it.owner_user_id, it.item_code, it.snapshot, it.quantity);
    end if;
  end loop;
  if t.initiator_escrowed then
    perform private_trade_escrow_release(t.initiator_user_id, t.id, t.initiator_fc, t.initiator_ton, t.initiator_myth);
  end if;
  if t.recipient_escrowed then
    perform private_trade_escrow_release(t.recipient_user_id, t.id, t.recipient_fc, t.recipient_ton, t.recipient_myth);
  end if;
  update private_trades set initiator_escrowed = false, recipient_escrowed = false, updated_at = now() where id = t.id;
  delete from private_trade_items where trade_id = t.id;
end $$;

-- ATOMIC SETTLEMENT. Runs inside the caller's transaction: any failure rolls the
-- whole trade back, so a half-executed trade is impossible.
create or replace function public.private_trade_settle(p_trade uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  t private_trades%rowtype; it private_trade_items%rowtype; a uuid; b uuid;
  cfg jsonb; fee numeric; a_items jsonb := '[]'; b_items jsonb := '[]';
  a_fc numeric; a_ton numeric; a_myth numeric; b_fc numeric; b_ton numeric; b_myth numeric;
begin
  select * into t from private_trades where id = p_trade for update;
  if t.id is null then raise exception 'TRADE_NOT_FOUND'; end if;
  if t.status = 'completed' then
    return jsonb_build_object('ok', true, 'duplicate', true, 'status', 'completed');
  end if;
  if t.status not in ('ready_for_confirmation','security_review') then raise exception 'TRADE_NOT_READY'; end if;
  if not (t.initiator_locked and t.recipient_locked) then raise exception 'OFFERS_NOT_LOCKED'; end if;
  if not (t.initiator_confirmed and t.recipient_confirmed) then raise exception 'TRADE_NOT_CONFIRMED'; end if;

  a := t.initiator_user_id; b := t.recipient_user_id;
  cfg := private_trade_settings_json();
  fee := coalesce((cfg->>'feePercent')::numeric, 0);

  -- Balance rows are locked in a deterministic order to avoid deadlocks.
  perform 1 from game_players where id in (a, b) order by id for update;

  for it in select * from private_trade_items where trade_id = t.id order by created_at for update loop
    if it.item_type = 'hero' then
      if not exists (select 1 from player_heroes where id = it.item_instance_id and user_id = it.owner_user_id) then
        raise exception 'OWNERSHIP_CHANGED';
      end if;
      delete from pvp_team_slots where hero_id = it.item_instance_id;
      delete from boss_team_slots where player_hero_id = it.item_instance_id;
      update player_heroes set user_id = case when it.side = 'initiator' then b else a end,
        market_locked = false, updated_at = now() where id = it.item_instance_id;
    elsif it.item_type = 'pet' then
      if not exists (select 1 from player_pets where id = it.item_instance_id and user_id = it.owner_user_id) then
        raise exception 'OWNERSHIP_CHANGED';
      end if;
      if exists (select 1 from player_pets mine
                  where mine.user_id = case when it.side = 'initiator' then b else a end
                    and mine.id <> it.item_instance_id
                    and mine.pet_id = (select pp.pet_id from player_pets pp where pp.id = it.item_instance_id)) then
        raise exception 'PET_ALREADY_OWNED';
      end if;
      update player_pets set user_id = case when it.side = 'initiator' then b else a end,
        market_locked = false, is_active = false, updated_at = now() where id = it.item_instance_id;
    else
      perform market_item_give(case when it.side = 'initiator' then b else a end, it.item_code, it.snapshot, it.quantity);
    end if;

    insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id)
    values (it.item_type, it.item_instance_id, it.item_code, it.owner_user_id,
            case when it.side = 'initiator' then b else a end);

    if it.side = 'initiator' then a_items := a_items || jsonb_build_array(it.snapshot);
    else b_items := b_items || jsonb_build_array(it.snapshot); end if;
  end loop;

  -- Currencies: escrowed amounts move to the other player (minus the configurable fee).
  a_fc := trunc(t.initiator_fc * (100 - fee) / 100);
  a_ton := round(t.initiator_ton * (100 - fee) / 100, 9);
  a_myth := round(t.initiator_myth * (100 - fee) / 100, 4);
  b_fc := trunc(t.recipient_fc * (100 - fee) / 100);
  b_ton := round(t.recipient_ton * (100 - fee) / 100, 9);
  b_myth := round(t.recipient_myth * (100 - fee) / 100, 4);

  perform private_trade_escrow_deliver(a, b, t.id, a_fc, a_ton, a_myth);
  perform private_trade_escrow_deliver(b, a, t.id, b_fc, b_ton, b_myth);
  -- Fee remainder leaves the escrow permanently (0% by default).
  if fee > 0 then
    update game_players set ton_reserved = greatest(0, round(coalesce(ton_reserved,0) - round(t.initiator_ton - a_ton, 9), 9))
      where id = a;
    update game_players set ton_reserved = greatest(0, round(coalesce(ton_reserved,0) - round(t.recipient_ton - b_ton, 9), 9))
      where id = b;
  end if;

  insert into private_trade_ledger(trade_id, from_user_id, to_user_id, fc, ton, myth, items, risk_score, risk_flags)
  values (t.id, a, b, a_fc, a_ton, a_myth, a_items, t.risk_score, t.risk_flags),
         (t.id, b, a, b_fc, b_ton, b_myth, b_items, t.risk_score, t.risk_flags);

  delete from private_trade_items where trade_id = t.id;
  update private_trades set status = 'completed', completed_at = now(),
    initiator_escrowed = false, recipient_escrowed = false, updated_at = now() where id = t.id;

  insert into private_trade_events(trade_id, actor_user_id, event, details)
  values (t.id, null, 'trade_completed', jsonb_build_object('feePercent', fee,
    'initiatorGave', jsonb_build_object('fc', t.initiator_fc, 'ton', t.initiator_ton, 'myth', t.initiator_myth, 'items', a_items),
    'recipientGave', jsonb_build_object('fc', t.recipient_fc, 'ton', t.recipient_ton, 'myth', t.recipient_myth, 'items', b_items)));

  insert into player_notifications(user_id, type, title, message, metadata, dedupe_key)
  values (a, 'private_trade', 'TRADE COMPLETED', 'Private trade with ' || market_seller_label(b) || ' completed.',
          jsonb_build_object('tradeId', t.id), 'private_trade_done:' || t.id::text || ':a'),
         (b, 'private_trade', 'TRADE COMPLETED', 'Private trade with ' || market_seller_label(a) || ' completed.',
          jsonb_build_object('tradeId', t.id), 'private_trade_done:' || t.id::text || ':b')
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'status', 'completed', 'tradeId', t.id);
end $$;

create or replace function public.private_trade_confirm(p_telegram_id bigint, p_trade uuid, p_request_id text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me uuid; t private_trades%rowtype; v_side text; v_out jsonb; risk jsonb; cfg jsonb; v_both boolean;
begin
  if p_request_id is not null then
    select result into v_out from private_trade_idempotency where request_id = p_request_id;
    if v_out is not null then return v_out; end if;
  end if;
  v_me := private_trade_guard(p_telegram_id);
  select * into t from private_trades where id = p_trade for update;
  if t.id is null or v_me not in (t.initiator_user_id, t.recipient_user_id) then raise exception 'TRADE_NOT_FOUND'; end if;
  if t.status = 'completed' then return private_trade_state(v_me, t.id); end if;
  if t.status <> 'ready_for_confirmation' then raise exception 'OFFERS_NOT_LOCKED'; end if;
  if t.expires_at <= now() then raise exception 'TRADE_EXPIRED'; end if;
  v_side := case when v_me = t.initiator_user_id then 'initiator' else 'recipient' end;

  if v_side = 'initiator' then
    update private_trades set initiator_confirmed = true, updated_at = now() where id = t.id;
  else
    update private_trades set recipient_confirmed = true, updated_at = now() where id = t.id;
  end if;
  insert into private_trade_events(trade_id, actor_user_id, event, details)
  values (t.id, v_me, 'confirmed', jsonb_build_object('side', v_side));

  select (initiator_confirmed and recipient_confirmed) into v_both from private_trades where id = t.id;
  if v_both then
    cfg := private_trade_settings_json();
    risk := private_trade_risk_assess(t.id);
    if (risk->>'score')::integer >= (cfg->>'riskCritical')::integer then
      -- Strong self-transfer evidence: the trade is blocked and every asset returns.
      perform private_trade_release_all(t.id);
      update private_trades set status = 'blocked', updated_at = now() where id = t.id;
      insert into private_trade_events(trade_id, actor_user_id, event, details)
      values (t.id, null, 'trade_blocked', risk);
    elsif (risk->>'score')::integer >= (cfg->>'riskHigh')::integer then
      -- Assets stay in escrow until an admin approves or rejects the trade.
      update private_trades set status = 'security_review', updated_at = now() where id = t.id;
      insert into private_trade_events(trade_id, actor_user_id, event, details)
      values (t.id, null, 'security_review', risk);
    else
      perform private_trade_settle(t.id);
    end if;
  end if;

  v_out := private_trade_state(v_me, t.id);
  if p_request_id is not null then
    insert into private_trade_idempotency(request_id, trade_id, action, result)
    values (p_request_id, t.id, 'confirm', v_out) on conflict (request_id) do nothing;
  end if;
  return v_out;
end $$;

create or replace function public.private_trade_cancel(p_telegram_id bigint, p_trade uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me uuid; t private_trades%rowtype; v_other uuid;
begin
  select id into v_me from game_players where telegram_id = p_telegram_id;
  if v_me is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into t from private_trades where id = p_trade for update;
  if t.id is null or v_me not in (t.initiator_user_id, t.recipient_user_id) then raise exception 'TRADE_NOT_FOUND'; end if;
  if t.status in ('completed','cancelled','expired','blocked') then return private_trade_state(v_me, t.id); end if;
  if t.status = 'security_review' then raise exception 'TRADE_UNDER_REVIEW'; end if;

  perform private_trade_release_all(t.id);
  update private_trades set status = 'cancelled', cancelled_by = v_me,
    cancel_reason = nullif(p_reason,''), initiator_locked = false, recipient_locked = false,
    initiator_confirmed = false, recipient_confirmed = false, updated_at = now() where id = t.id;
  insert into private_trade_events(trade_id, actor_user_id, event, details)
  values (t.id, v_me, 'trade_cancelled', jsonb_build_object('reason', p_reason));

  v_other := case when v_me = t.initiator_user_id then t.recipient_user_id else t.initiator_user_id end;
  insert into player_notifications(user_id, type, title, message, metadata, dedupe_key)
  values (v_other, 'private_trade', 'TRADE CANCELLED',
    market_seller_label(v_me) || ' cancelled the private trade. Every asset was returned.',
    jsonb_build_object('tradeId', t.id), 'private_trade_cancel:' || t.id::text)
  on conflict do nothing;
  return private_trade_state(v_me, t.id);
end $$;

create or replace function public.private_trade_expire_sweep()
returns integer language plpgsql security definer set search_path to 'public' as $$
declare r record; n integer := 0;
begin
  for r in select id, initiator_user_id, recipient_user_id from private_trades
            where status in ('negotiating','offer_locked','ready_for_confirmation') and expires_at <= now()
            order by expires_at limit 100 loop
    perform private_trade_release_all(r.id);
    update private_trades set status = 'expired', initiator_locked = false, recipient_locked = false,
      initiator_confirmed = false, recipient_confirmed = false, updated_at = now() where id = r.id;
    insert into private_trade_events(trade_id, actor_user_id, event, details)
    values (r.id, null, 'trade_expired', '{}'::jsonb);
    insert into player_notifications(user_id, type, title, message, metadata, dedupe_key)
    values (r.initiator_user_id, 'private_trade', 'TRADE EXPIRED', 'Private trade expired. Assets returned.',
              jsonb_build_object('tradeId', r.id), 'private_trade_exp:' || r.id::text || ':a'),
           (r.recipient_user_id, 'private_trade', 'TRADE EXPIRED', 'Private trade expired. Assets returned.',
              jsonb_build_object('tradeId', r.id), 'private_trade_exp:' || r.id::text || ':b')
    on conflict do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.private_trade_view(p_telegram_id bigint, p_trade uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me uuid;
begin
  select id into v_me from game_players where telegram_id = p_telegram_id;
  if v_me is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform private_trade_expire_sweep();
  return private_trade_state(v_me, p_trade);
end $$;

-- ============================================================================
-- ADMIN SECURITY (Admin Bot)
-- ============================================================================
create or replace function public.admin_private_trade_overview(p_admin_id bigint, p_status text default null, p_limit integer default 15)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_limit integer := least(greatest(coalesce(p_limit,15),1),50);
begin
  perform admin_assert(p_admin_id);
  perform private_trade_expire_sweep();
  return jsonb_build_object('ok', true, 'settings', private_trade_settings_json(),
    'counts', (select jsonb_object_agg(status, c) from (select status, count(*) c from private_trades group by status) x),
    'trades', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'status', t.status,
        'riskScore', t.risk_score, 'riskFlags', to_jsonb(t.risk_flags),
        'a', private_trade_player_card(t.initiator_user_id), 'b', private_trade_player_card(t.recipient_user_id),
        'aItems', (select count(*) from private_trade_items i where i.trade_id = t.id and i.side = 'initiator'),
        'bItems', (select count(*) from private_trade_items i where i.trade_id = t.id and i.side = 'recipient'),
        'aCurrency', jsonb_build_object('fc', t.initiator_fc, 'ton', t.initiator_ton, 'myth', t.initiator_myth),
        'bCurrency', jsonb_build_object('fc', t.recipient_fc, 'ton', t.recipient_ton, 'myth', t.recipient_myth),
        'createdAt', t.created_at, 'updatedAt', t.updated_at) order by t.updated_at desc)
      from (select * from private_trades
             where p_status is null or status = p_status
             order by updated_at desc limit v_limit) t), '[]'::jsonb),
    'highRiskPlayers', coalesce((select jsonb_agg(x) from (
        select jsonb_build_object('player', private_trade_player_card(u), 'trades', c, 'avgRisk', round(avg_risk)) x
        from (select initiator_user_id u, count(*) c, avg(risk_score) avg_risk from private_trades
               where risk_score >= 60 group by initiator_user_id
              union all
              select recipient_user_id, count(*), avg(risk_score) from private_trades
               where risk_score >= 60 group by recipient_user_id) y
        limit 10) z), '[]'::jsonb));
end $$;

create or replace function public.admin_private_trade_detail(p_admin_id bigint, p_trade uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare t private_trades%rowtype;
begin
  perform admin_assert(p_admin_id);
  select * into t from private_trades where id = p_trade;
  if t.id is null then raise exception 'TRADE_NOT_FOUND'; end if;
  return jsonb_build_object('ok', true, 'id', t.id, 'code', t.code, 'status', t.status,
    'riskScore', t.risk_score, 'riskFlags', to_jsonb(t.risk_flags),
    'a', private_trade_player_card(t.initiator_user_id), 'b', private_trade_player_card(t.recipient_user_id),
    'aGives', jsonb_build_object('fc', t.initiator_fc, 'ton', t.initiator_ton, 'myth', t.initiator_myth,
      'items', coalesce((select jsonb_agg(i.snapshot) from private_trade_items i where i.trade_id = t.id and i.side='initiator'),'[]'::jsonb)),
    'bGives', jsonb_build_object('fc', t.recipient_fc, 'ton', t.recipient_ton, 'myth', t.recipient_myth,
      'items', coalesce((select jsonb_agg(i.snapshot) from private_trade_items i where i.trade_id = t.id and i.side='recipient'),'[]'::jsonb)),
    'pairHistory', (select count(*) from private_trades p where p.status='completed'
       and ((p.initiator_user_id=t.initiator_user_id and p.recipient_user_id=t.recipient_user_id)
         or (p.initiator_user_id=t.recipient_user_id and p.recipient_user_id=t.initiator_user_id))),
    'events', coalesce((select jsonb_agg(jsonb_build_object('event', e.event, 'at', e.created_at, 'details', e.details)
       order by e.created_at desc) from (select * from private_trade_events where trade_id = t.id
         order by created_at desc limit 15) e), '[]'::jsonb));
end $$;

-- APPROVE (settle a reviewed trade) / REJECT (return every asset) / RECHECK.
create or replace function public.admin_private_trade_action(p_admin_id bigint, p_trade uuid, p_action text, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare t private_trades%rowtype; act text := lower(coalesce(p_action,'')); res jsonb;
begin
  perform admin_assert(p_admin_id);
  select * into t from private_trades where id = p_trade for update;
  if t.id is null then raise exception 'TRADE_NOT_FOUND'; end if;

  if act = 'approve' then
    if t.status <> 'security_review' then raise exception 'TRADE_NOT_UNDER_REVIEW'; end if;
    res := private_trade_settle(t.id);
    update private_trades set admin_note = p_note, updated_at = now() where id = t.id;
  elsif act = 'reject' or act = 'block' then
    if t.status in ('completed','cancelled','expired','blocked') then raise exception 'TRADE_ALREADY_CLOSED'; end if;
    perform private_trade_release_all(t.id);
    update private_trades set status = case when act = 'block' then 'blocked' else 'cancelled' end,
      cancel_reason = coalesce(p_note, 'ADMIN_' || upper(act)), admin_note = p_note,
      initiator_locked = false, recipient_locked = false,
      initiator_confirmed = false, recipient_confirmed = false, updated_at = now() where id = t.id;
    res := jsonb_build_object('ok', true, 'status', case when act = 'block' then 'blocked' else 'cancelled' end);
  elsif act = 'recheck' then
    res := private_trade_risk_assess(t.id);
  else
    raise exception 'INVALID_ACTION';
  end if;

  insert into private_trade_events(trade_id, actor_user_id, event, details)
  values (t.id, null, 'admin_' || act, jsonb_build_object('adminId', p_admin_id, 'note', p_note, 'result', res));
  return jsonb_build_object('ok', true, 'action', act, 'result', res);
end $$;

create or replace function public.admin_private_trade_set(p_admin_id bigint, p_field text, p_value numeric)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare f text := lower(coalesce(p_field,''));
begin
  perform admin_assert(p_admin_id);
  if f = 'enabled' then update private_trade_settings set enabled = p_value > 0, updated_at = now() where id = 1;
  elsif f = 'admin_only' then update private_trade_settings set admin_only = p_value > 0, updated_at = now() where id = 1;
  elsif f = 'max_items' then update private_trade_settings set max_items = greatest(1, least(12, p_value::integer)), updated_at = now() where id = 1;
  elsif f = 'expire_hours' then update private_trade_settings set expire_hours = greatest(1, least(168, p_value::integer)), updated_at = now() where id = 1;
  elsif f = 'min_account_days' then update private_trade_settings set min_account_days = greatest(0, least(30, p_value::integer)), updated_at = now() where id = 1;
  elsif f = 'fee_percent' then update private_trade_settings set fee_percent = greatest(0, least(20, p_value)), updated_at = now() where id = 1;
  elsif f = 'risk_medium' then update private_trade_settings set risk_medium = p_value::integer, updated_at = now() where id = 1;
  elsif f = 'risk_high' then update private_trade_settings set risk_high = p_value::integer, updated_at = now() where id = 1;
  elsif f = 'risk_critical' then update private_trade_settings set risk_critical = p_value::integer, updated_at = now() where id = 1;
  elsif f = 'require_deposit' then update private_trade_settings set require_deposit_for_high_value = p_value > 0, updated_at = now() where id = 1;
  elsif f = 'cooldown_hours' then update private_trade_settings set suspicious_cooldown_hours = greatest(0, p_value::integer), updated_at = now() where id = 1;
  else raise exception 'INVALID_FIELD'; end if;
  return jsonb_build_object('ok', true, 'settings', private_trade_settings_json());
end $$;