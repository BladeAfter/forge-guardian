-- Pending / paid-but-not-activated battle pass orders for one player (reconciliation source).
CREATE OR REPLACE FUNCTION public.pending_season_pass_orders(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare u uuid;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id, 'tier', o.tier, 'priceTon', o.price_ton, 'amountNano', o.amount_nano,
      'paymentComment', o.payment_comment, 'status', o.status, 'createdAt', o.created_at
    ) order by o.created_at desc), '[]')
    from season_pass_orders o
    where o.user_id = u
      and o.status in ('pending', 'paid', 'expired')
      and o.created_at > now() - interval '30 days');
end $$;

-- Atomic, idempotent activation. A confirmed payment ALWAYS ends with the pass owned.
DROP FUNCTION IF EXISTS public.confirm_season_pass_order(uuid, text, text);
CREATE OR REPLACE FUNCTION public.confirm_season_pass_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare o public.season_pass_orders%rowtype; p public.player_season_pass%rowtype; target text;
begin
  select * into o from public.season_pass_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.status = 'activated' then
    return jsonb_build_object('status', 'already_processed', 'orderId', o.id, 'tier', o.tier);
  end if;
  if o.amount_nano <> p_amount_nano then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;
  if exists (select 1 from public.season_pass_orders where tx_hash = p_tx_hash and id <> o.id) then
    raise exception 'TX_ALREADY_USED';
  end if;

  insert into public.player_season_pass(user_id, season_id, tier)
  values (o.user_id, o.season_id, 'none')
  on conflict (user_id, season_id) do nothing;
  select * into p from public.player_season_pass where user_id = o.user_id and season_id = o.season_id for update;

  -- Legendary always wins; adventurer never downgrades an existing legendary.
  target := case when o.tier = 'legendary' or p.tier = 'legendary' then 'legendary' else 'adventurer' end;

  if p.tier = target and p.tier <> 'none' and o.tier = p.tier then
    -- Pass already owned at this tier: settle the order instead of failing.
    update public.season_pass_orders
       set status = 'activated', tx_hash = coalesce(tx_hash, p_tx_hash), paid_at = coalesce(paid_at, now()), activated_at = now()
     where id = o.id;
    return jsonb_build_object('status', 'already_processed', 'orderId', o.id, 'tier', p.tier);
  end if;

  update public.season_pass_orders set status = 'paid', tx_hash = p_tx_hash, paid_at = coalesce(paid_at, now()) where id = o.id;

  -- XP, level and claimed rewards are untouched: only ownership changes.
  update public.player_season_pass
     set tier = target,
         adventurer_owned = true,
         legendary_owned = (target = 'legendary'),
         purchased_at = coalesce(purchased_at, now()),
         upgraded_at = case when target = 'legendary' and p.tier = 'adventurer' then now() else upgraded_at end,
         updated_at = now()
   where user_id = o.user_id and season_id = o.season_id;

  update public.season_pass_orders set status = 'activated', activated_at = now() where id = o.id;
  perform public.record_ton_revenue(o.user_id, o.price_ton, 'battle_pass', o.id::text, p_tx_hash);
  return jsonb_build_object('status', 'completed', 'orderId', o.id, 'tier', target, 'priceTon', o.price_ton);
end $$;