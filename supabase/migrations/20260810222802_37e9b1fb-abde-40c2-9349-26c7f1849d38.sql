-- 1. Percentual configurável
ALTER TABLE public.pool_settings
  ADD COLUMN IF NOT EXISTS community_pool_percent numeric NOT NULL DEFAULT 15
    CHECK (community_pool_percent >= 0 AND community_pool_percent <= 100);

-- 2. Ledger da pool: reutiliza pool_revenue, adiciona tx_hash para auditoria
ALTER TABLE public.pool_revenue
  ADD COLUMN IF NOT EXISTS tx_hash text;

CREATE INDEX IF NOT EXISTS pool_revenue_tx_hash_idx ON public.pool_revenue(tx_hash);
CREATE INDEX IF NOT EXISTS pool_revenue_pool_created_idx ON public.pool_revenue(pool_id, created_at DESC);
-- Idempotência dura: uma mesma tx só pode contribuir uma vez por origem
CREATE UNIQUE INDEX IF NOT EXISTS pool_revenue_tx_source_uniq
  ON public.pool_revenue(tx_hash, source_type) WHERE tx_hash IS NOT NULL;

GRANT SELECT ON public.pool_revenue TO authenticated;
GRANT ALL ON public.pool_revenue TO service_role;

-- 3. Garante uma pool semanal ativa (avança período, nunca apaga histórico)
CREATE OR REPLACE FUNCTION public.ensure_active_pool()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare b public.pool_balance%rowtype; s public.pool_settings%rowtype; days int;
begin
  select * into s from public.pool_settings where id;
  days := greatest(1, coalesce(s.season_days, 7));
  select * into b from public.pool_balance where status = 'active' for update;
  if b.id is not null and b.ends_at > now() then
    return b.id;
  end if;
  if b.id is not null then
    -- período vencido sem distribuição: encerra contabilmente e abre o próximo
    update public.pool_balance
       set week_label = week_label,
           ends_at = now(),
           updated_at = now()
     where id = b.id;
    update public.pool_balance set status = 'distributing', updated_at = now() where id = b.id and balance_ton > 0;
    update public.pool_balance set status = 'distributed', distribution_key = coalesce(distribution_key,'pool_expired:'||b.id::text), updated_at = now() where id = b.id and balance_ton = 0;
  end if;
  insert into public.pool_balance(week_label, starts_at, ends_at)
  values ('Temporada '||to_char(now(),'IYYY-IW'), now(), now() + make_interval(days => days))
  returning id into b.id;
  return b.id;
end
$$;

-- 4. Função central de receita TON -> contribuição da pool
CREATE OR REPLACE FUNCTION public.record_ton_revenue(
  p_user_id uuid,
  p_amount_ton numeric,
  p_source text,
  p_reference_id text,
  p_tx_hash text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  s public.pool_settings%rowtype;
  pool uuid;
  pct numeric;
  amount numeric;
  key text;
  inserted boolean := false;
begin
  if p_amount_ton is null or p_amount_ton <= 0 then
    return jsonb_build_object('status','skipped','reason','no_ton_revenue');
  end if;
  if p_source is null or nullif(trim(p_source),'') is null then
    raise exception 'POOL_SOURCE_REQUIRED';
  end if;

  select * into s from public.pool_settings where id;
  pct := coalesce(s.community_pool_percent, 15);
  amount := round(p_amount_ton * pct / 100, 9);
  pool := public.ensure_active_pool();
  key := 'ton_revenue:'||p_source||':'||coalesce(nullif(p_tx_hash,''), coalesce(p_reference_id,''));

  insert into public.pool_revenue(pool_id, user_id, source_type, source_id, base_amount_ton, percent, amount_ton, idempotency_key, tx_hash)
  values (pool, p_user_id, p_source, coalesce(p_reference_id,'-'), p_amount_ton, pct, amount, key, nullif(p_tx_hash,''))
  on conflict do nothing;

  inserted := found;

  if inserted and amount > 0 then
    update public.pool_balance set balance_ton = balance_ton + amount, updated_at = now() where id = pool;
  end if;

  return jsonb_build_object(
    'status', case when inserted then 'recorded' else 'already_recorded' end,
    'poolId', pool,
    'source', p_source,
    'grossAmountTon', p_amount_ton,
    'poolPercent', pct,
    'poolAmountTon', amount
  );
end
$$;

-- 5. Depósito TON -> FC (jogador recebe 100%, pool contabiliza 15%)
CREATE OR REPLACE FUNCTION public.confirm_wallet_deposit(p_deposit_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  d public.wallet_deposits%rowtype;
  rate numeric;
  credit numeric;
  before_balance numeric;
  after_balance numeric;
  pool jsonb;
begin
  select * into d from public.wallet_deposits where id = p_deposit_id for update;
  if d.id is null then raise exception 'DEPOSIT_NOT_FOUND'; end if;

  if d.status = 'credited' then
    return jsonb_build_object('status','already_processed','depositId',d.id,'amountFc',d.amount_fc,'amountTon',d.amount_ton);
  end if;

  if d.expires_at < now() then
    update public.wallet_deposits set status = 'expired' where id = d.id;
    raise exception 'DEPOSIT_EXPIRED';
  end if;

  if p_amount_nano <> round(d.amount_ton * 1000000000)::text then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;

  if exists (select 1 from public.wallet_deposits where tx_hash = p_tx_hash and id <> d.id)
     or exists (select 1 from public.pet_egg_orders where tx_hash = p_tx_hash)
     or exists (select 1 from public.season_pass_orders where tx_hash = p_tx_hash) then
    raise exception 'TX_ALREADY_USED';
  end if;

  rate := public.current_ton_fc_rate();
  credit := round(d.amount_ton * rate);

  select forge_coins into before_balance from public.game_players where id = d.user_id for update;
  if before_balance is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  update public.game_players
     set forge_coins = forge_coins + credit, updated_at = now()
   where id = d.user_id
   returning forge_coins into after_balance;

  insert into public.wallet_ledger(user_id, type, amount_fc, amount_ton, conversion_rate, balance_before, balance_after, reference_id, tx_hash)
  values (d.user_id, 'deposit_credit', credit, d.amount_ton, rate, before_balance, after_balance, d.id::text, p_tx_hash);

  update public.wallet_deposits
     set status = 'credited',
         tx_hash = p_tx_hash,
         amount_fc = credit,
         conversion_rate = rate,
         confirmed_at = coalesce(confirmed_at, now()),
         credited_at = now()
   where id = d.id;

  perform public.distribute_referral_commission(d.user_id, 'deposit:'||d.id::text, 'deposit', credit, true, 'TON', d.amount_ton);

  pool := public.record_ton_revenue(d.user_id, d.amount_ton, 'deposit', d.id::text, p_tx_hash);

  return jsonb_build_object('status','credited','depositId',d.id,'amountTon',d.amount_ton,'amountFc',credit,'conversionRate',rate,'balanceBefore',before_balance,'balanceAfter',after_balance,'poolContribution',pool);
end
$$;

-- 6. Ovos premium em TON
CREATE OR REPLACE FUNCTION public.confirm_pet_egg_purchase(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare o public.pet_egg_orders%rowtype; tg bigint; key text; res jsonb; needs_credit boolean; pool jsonb;
begin
  select * into o from public.pet_egg_orders where id=p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  select telegram_id into tg from public.game_players where id=o.user_id;
  if tg is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  key:='egg_order:'||o.id::text;

  res:=public.get_pet_egg_opening(tg,key);
  if coalesce(res->>'status','')<>'not_found' then
    if o.status<>'delivered' then update public.pet_egg_orders set status='delivered',delivered_at=coalesce(delivered_at,now()),tx_hash=coalesce(tx_hash,p_tx_hash) where id=o.id; end if;
    pool:=public.record_ton_revenue(o.user_id,o.price_ton,'egg_purchase',o.id::text,coalesce(o.tx_hash,p_tx_hash));
    return jsonb_build_object('status','already_processed','orderId',o.id,'eggId',o.egg_id,'poolContribution',pool)||res;
  end if;

  if o.status in ('pending','expired') then
    if p_amount_nano is not null and p_amount_nano<>o.amount_nano then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
    if exists(select 1 from public.pet_egg_orders where tx_hash=p_tx_hash and id<>o.id)
      or exists(select 1 from public.wallet_deposits where tx_hash=p_tx_hash) then raise exception 'TX_ALREADY_USED'; end if;
    update public.pet_egg_orders set status='paid',tx_hash=p_tx_hash,paid_at=now() where id=o.id;
    needs_credit:=true;
  elsif o.status='paid' then
    needs_credit:=true;
  elsif o.status='delivered' then
    needs_credit:=false;
  else
    raise exception 'ORDER_NOT_PAYABLE';
  end if;

  if needs_credit then
    insert into public.player_pet_inventory(user_id,item_type,item_id,quantity) values(o.user_id,'egg',o.egg_id,1)
    on conflict(user_id,item_type,(coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)))
    do update set quantity=public.player_pet_inventory.quantity+1,updated_at=now();
  end if;

  res:=public.hatch_pet_egg(tg,o.egg_id,key);
  update public.pet_egg_orders set status='delivered',delivered_at=now() where id=o.id;
  pool:=public.record_ton_revenue(o.user_id,o.price_ton,'egg_purchase',o.id::text,coalesce(p_tx_hash,o.tx_hash));
  return jsonb_build_object('status','completed','orderId',o.id,'eggId',o.egg_id,'poolContribution',pool)||res;
end
$$;

-- 7. Legacy egg order flow
CREATE OR REPLACE FUNCTION public.confirm_pet_egg_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare o public.pet_egg_orders%rowtype;
begin
  select * into o from public.pet_egg_orders where id=p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.status='delivered' then return; end if;
  if o.expires_at<now() then update public.pet_egg_orders set status='expired' where id=o.id; raise exception 'ORDER_EXPIRED'; end if;
  if p_amount_nano<>o.amount_nano then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
  if exists(select 1 from public.pet_egg_orders where tx_hash=p_tx_hash and id<>o.id)
     or exists(select 1 from public.wallet_deposits where tx_hash=p_tx_hash) then raise exception 'TX_ALREADY_USED'; end if;
  update public.pet_egg_orders set status='paid',tx_hash=p_tx_hash,paid_at=now() where id=o.id;
  insert into public.player_pet_inventory(user_id,item_type,item_id,quantity) values(o.user_id,'egg',o.egg_id,1)
  on conflict(user_id,item_type,(coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)))
  do update set quantity=public.player_pet_inventory.quantity+1,updated_at=now();
  update public.pet_egg_orders set status='delivered',delivered_at=now() where id=o.id;
  perform public.record_ton_revenue(o.user_id,o.price_ton,'egg_purchase',o.id::text,p_tx_hash);
end
$$;

-- 8. Battle Pass em TON
CREATE OR REPLACE FUNCTION public.confirm_season_pass_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare o public.season_pass_orders%rowtype; p public.player_season_pass%rowtype;
begin
  select * into o from public.season_pass_orders where id=p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.status='activated' then return; end if;
  if o.expires_at<now() or o.amount_nano<>p_amount_nano then raise exception 'INVALID_OR_EXPIRED_PAYMENT'; end if;
  if exists(select 1 from public.season_pass_orders where tx_hash=p_tx_hash and id<>o.id) then raise exception 'TX_ALREADY_USED'; end if;
  select * into p from public.player_season_pass where user_id=o.user_id and season_id=o.season_id for update;
  if p.tier='legendary' or (o.tier='adventurer' and p.tier='adventurer') then raise exception 'PASS_ALREADY_OWNED'; end if;
  update public.season_pass_orders set status='paid',tx_hash=p_tx_hash,paid_at=now() where id=o.id;
  update public.player_season_pass
     set tier=case when o.tier='legendary' then 'legendary' else 'adventurer' end,
         adventurer_owned=true,
         legendary_owned=(o.tier='legendary' or legendary_owned),
         purchased_at=coalesce(purchased_at,now()),
         upgraded_at=case when o.tier='legendary' and p.tier='adventurer' then now() else upgraded_at end,
         updated_at=now()
   where user_id=o.user_id and season_id=o.season_id;
  update public.season_pass_orders set status='activated',activated_at=now() where id=o.id;
  perform public.record_ton_revenue(o.user_id,o.price_ton,'battle_pass',o.id::text,p_tx_hash);
end
$$;

-- 9. Percentual configurável pelo admin
CREATE OR REPLACE FUNCTION public.admin_set_pool_contribution_percent(p_admin_id bigint, p_percent numeric)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  perform public.admin_assert(p_admin_id);
  if p_percent is null or p_percent < 0 or p_percent > 100 then raise exception 'INVALID_POOL_PERCENT'; end if;
  update public.pool_settings set community_pool_percent = p_percent, updated_at = now() where id;
  perform public.admin_log(p_admin_id, 'pool_contribution_percent', null, jsonb_build_object('percent', p_percent));
  return p_percent;
end
$$;

-- 10. Visão administrativa da pool com receita e origens
CREATE OR REPLACE FUNCTION public.admin_pool_overview(p_admin_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE p public.pool_balance; s public.pool_settings;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO s FROM public.pool_settings LIMIT 1;
  SELECT * INTO p FROM public.pool_balance WHERE status = 'active' ORDER BY starts_at DESC LIMIT 1;
  IF p.id IS NULL THEN
    SELECT * INTO p FROM public.pool_balance ORDER BY starts_at DESC LIMIT 1;
  END IF;
  RETURN jsonb_build_object(
    'pool', to_jsonb(p),
    'settings', to_jsonb(s),
    'contributionPercent', COALESCE(s.community_pool_percent, 15),
    'revenueToday', COALESCE((SELECT sum(base_amount_ton) FROM public.pool_revenue WHERE created_at >= date_trunc('day', now())), 0),
    'poolToday', COALESCE((SELECT sum(amount_ton) FROM public.pool_revenue WHERE created_at >= date_trunc('day', now())), 0),
    'revenuePeriod', COALESCE((SELECT sum(base_amount_ton) FROM public.pool_revenue WHERE pool_id = p.id), 0),
    'poolPeriod', COALESCE((SELECT sum(amount_ton) FROM public.pool_revenue WHERE pool_id = p.id), 0),
    'sourcesToday', COALESCE((SELECT jsonb_object_agg(source_type, totals) FROM (
        SELECT source_type, jsonb_build_object('grossTon', sum(base_amount_ton), 'poolTon', sum(amount_ton), 'count', count(*)) totals
        FROM public.pool_revenue WHERE created_at >= date_trunc('day', now()) GROUP BY source_type) x), '{}'::jsonb),
    'sourcesPeriod', COALESCE((SELECT jsonb_object_agg(source_type, totals) FROM (
        SELECT source_type, jsonb_build_object('grossTon', sum(base_amount_ton), 'poolTon', sum(amount_ton), 'count', count(*)) totals
        FROM public.pool_revenue WHERE pool_id = p.id GROUP BY source_type) x), '{}'::jsonb),
    'participants', (SELECT count(DISTINCT user_id) FROM public.pool_points WHERE pool_id = p.id),
    'eligible', (SELECT count(*) FROM (SELECT user_id, sum(points) pts FROM public.pool_points WHERE pool_id = p.id GROUP BY user_id) y
                  WHERE y.pts >= COALESCE(s.minimum_points, 0)));
END;
$$;
