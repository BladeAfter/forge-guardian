-- Diagnostic log for every TON payment verification attempt
CREATE TABLE IF NOT EXISTS public.ton_payment_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_kind text NOT NULL,
  order_id uuid,
  user_id uuid,
  telegram_id bigint,
  product_id text,
  expected_amount_nano text,
  received_amount_nano text,
  destination_wallet text,
  payment_reference text,
  tx_hash text,
  blockchain_status text,
  fulfillment_status text,
  error_detail text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ton_payment_logs_order ON public.ton_payment_logs(order_id, created_at DESC);
GRANT ALL ON public.ton_payment_logs TO service_role;
ALTER TABLE public.ton_payment_logs ENABLE ROW LEVEL SECURITY;

-- 1. Orders no longer die of a short timeout: only truly abandoned ones (30d) are closed.
CREATE OR REPLACE FUNCTION public.expire_stale_pet_egg_orders(p_user_id uuid DEFAULT NULL::uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare n integer;
begin
  with x as (
    update public.pet_egg_orders
      set status='expired'
      where status='pending' and tx_hash is null
        and created_at < now() - interval '30 days'
        and (p_user_id is null or user_id=p_user_id)
      returning 1)
  select count(*) into n from x;
  return coalesce(n,0);
end $$;

-- Recover every order wrongly expired by the old 15 minute rule.
UPDATE public.pet_egg_orders
SET status='pending'
WHERE status='expired' AND tx_hash IS NULL AND created_at >= now() - interval '30 days';

-- 2. Awaiting-payment list keeps orders verifiable for 30 days.
CREATE OR REPLACE FUNCTION public.pending_pet_egg_orders(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare u uuid;
begin
  select id into u from public.game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.expire_stale_pet_egg_orders(u);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id',o.id,'eggId',o.egg_id,'eggName',e.name,'priceTon',o.price_ton,'amountNano',o.amount_nano,
      'paymentComment',o.payment_comment,'paymentAddress',o.payment_address,'status',o.status,'createdAt',o.created_at)
      order by o.created_at desc),'[]')
    from public.pet_egg_orders o join public.pet_eggs e on e.id=o.egg_id
    where o.user_id=u and o.tx_hash is null
      and o.status in ('pending','expired')
      and o.created_at >= now() - interval '30 days');
end $$;

-- 3. Confirmation: unique reference decides the order, amount only needs to cover it (3% tolerance).
CREATE OR REPLACE FUNCTION public.confirm_pet_egg_purchase(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare o public.pet_egg_orders%rowtype; v_received numeric; v_expected numeric;
begin
  perform pg_advisory_xact_lock(hashtextextended('pet_egg_order:'||p_order_id::text, 0));
  select * into o from public.pet_egg_orders where id=p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;

  if o.tx_hash is null then
    if nullif(trim(coalesce(p_tx_hash,'')),'') is null then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
    v_expected := coalesce(nullif(o.amount_nano,'')::numeric, 0);
    v_received := coalesce(nullif(trim(coalesce(p_amount_nano,'')),'')::numeric, v_expected);
    if v_received < v_expected * 0.97 then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
    if exists(select 1 from public.pet_egg_orders where tx_hash=p_tx_hash and id<>o.id)
       or exists(select 1 from public.wallet_deposits where tx_hash=p_tx_hash)
       or exists(select 1 from public.season_pass_orders where tx_hash=p_tx_hash)
    then raise exception 'TX_ALREADY_USED'; end if;
    update public.pet_egg_orders
      set status='confirmed', tx_hash=p_tx_hash, paid_at=coalesce(paid_at, now()), confirmed_at=coalesce(confirmed_at, now())
      where id=o.id;
  end if;

  return public.deliver_pet_egg_order(o.id);
end $$;

-- 4. Pass orders must stay verifiable too (never failed by a short timeout).
CREATE OR REPLACE FUNCTION public.ton_pending_purchase_orders(p_max_age_days integer DEFAULT 30)
RETURNS TABLE(
  order_kind text, order_id uuid, user_id uuid, telegram_id bigint, product_id text,
  amount_nano text, payment_comment text, payment_address text, created_at timestamptz)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT 'egg'::text, o.id, o.user_id, g.telegram_id, e.name::text,
         o.amount_nano, o.payment_comment, o.payment_address, o.created_at
  FROM public.pet_egg_orders o
  JOIN public.pet_eggs e ON e.id = o.egg_id
  JOIN public.game_players g ON g.id = o.user_id
  WHERE o.tx_hash IS NULL
    AND o.status IN ('pending','expired')
    AND o.created_at >= now() - make_interval(days => GREATEST(1, COALESCE(p_max_age_days, 30)))
  ORDER BY o.created_at DESC
$$;

REVOKE ALL ON FUNCTION public.ton_pending_purchase_orders(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expire_stale_pet_egg_orders(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.confirm_pet_egg_purchase(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pending_pet_egg_orders(bigint) FROM PUBLIC, anon, authenticated;