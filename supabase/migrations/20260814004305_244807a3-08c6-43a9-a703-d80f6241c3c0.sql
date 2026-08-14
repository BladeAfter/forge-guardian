-- NFT EXCLUSIVE HEROES: sale + mining (mirrors the NFT pet shop, reuses hero mining/ROI cap)

alter table public.nft_heroes
  add column if not exists price_ton numeric(18,9),
  add column if not exists tier_ton numeric(18,9),
  add column if not exists mining_daily_ton numeric(18,9) not null default 0,
  add column if not exists for_sale boolean not null default true;

update public.nft_heroes n set
  nft_serial = v.serial, price_ton = v.price, tier_ton = v.price, mining_daily_ton = v.yield_ton, for_sale = true
from (values
  ('nft-eternis',1,50,1.25),('nft-seraphyne',2,50,1.25),('nft-solarius',3,50,1.25),
  ('nft-dravenor',4,30,0.75),('nft-kaelion',5,30,0.75),('nft-nyxara',6,30,0.75),
  ('nft-astrion',7,20,0.50),('nft-elyra',8,20,0.50),('nft-mordrakar',9,20,0.50),('nft-valtherion',10,20,0.50)
) as v(template, serial, price, yield_ton)
where n.hero_template_id = v.template;

update public.nft_heroes
   set price_ton = coalesce(price_ton, 20), tier_ton = coalesce(tier_ton, 20),
       mining_daily_ton = case when coalesce(mining_daily_ton,0) > 0 then mining_daily_ton
         when coalesce(tier_ton, price_ton, 20) >= 50 then 1.25
         when coalesce(tier_ton, price_ton, 20) >= 30 then 0.75 else 0.50 end
 where price_ton is null or tier_ton is null or coalesce(mining_daily_ton,0) = 0;

-- ORDERS -----------------------------------------------------------------
create table if not exists public.nft_hero_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  nft_hero_id uuid not null references public.nft_heroes(id) on delete restrict,
  price_ton numeric(18,9) not null,
  amount_nano text not null,
  payment_address text not null,
  payment_comment text not null unique,
  idempotency_key text not null unique,
  status text not null default 'pending'
    check (status in ('pending','paid','confirmed','delivered','expired','cancelled')),
  tx_hash text unique,
  paid_at timestamptz,
  confirmed_at timestamptz,
  delivered_at timestamptz,
  expires_at timestamptz not null default now() + interval '30 minutes',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists nft_hero_orders_user_idx on public.nft_hero_orders(user_id, status);
grant all on public.nft_hero_orders to service_role;
alter table public.nft_hero_orders enable row level security;

create or replace function public.nft_hero_orders_touch() returns trigger
language plpgsql set search_path = public as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists trg_nft_hero_orders_touch on public.nft_hero_orders;
create trigger trg_nft_hero_orders_touch before update on public.nft_hero_orders
for each row execute function public.nft_hero_orders_touch();

-- Spending event + one-time referral commission (same rules as NFT pets)
create or replace function public.nft_hero_purchase_finalize() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_ref text; v_amount numeric; v_new text; v_old text; v_res jsonb;
begin
  v_ref := 'nft_hero_order:' || NEW.id::text;
  v_amount := round(coalesce(NEW.price_ton, 0), 9);
  v_new := lower(coalesce(NEW.status, ''));
  v_old := case when TG_OP = 'UPDATE' then lower(coalesce(OLD.status, '')) else null end;

  if v_new in ('confirmed','completed','delivered','paid_confirmed')
     and (TG_OP = 'INSERT' or v_old is distinct from v_new) and v_amount > 0 then
    perform public.record_spending_points(NEW.user_id, 'nft_hero_purchase', v_ref, 'TON', v_amount);
    v_res := public.referral_pay_ton_commission(NEW.user_id, 'nft_hero_purchase', v_ref, v_amount);
    raise log 'NFT_HERO_PURCHASE order=% buyer=% amount_ton=% referral_commission_ton=%',
      NEW.id, NEW.user_id, v_amount, coalesce(v_res->>'totalTon','0');
  elsif TG_OP = 'UPDATE' and v_new in ('refunded','reversed','cancelled','canceled','failed','expired')
     and v_old is distinct from v_new then
    perform public.record_spending_reversal(v_ref);
  end if;
  return NEW;
end $$;
drop trigger if exists trg_nft_hero_finalize_ins on public.nft_hero_orders;
create trigger trg_nft_hero_finalize_ins after insert on public.nft_hero_orders
for each row execute function public.nft_hero_purchase_finalize();
drop trigger if exists trg_nft_hero_finalize_upd on public.nft_hero_orders;
create trigger trg_nft_hero_finalize_upd after update of status on public.nft_hero_orders
for each row execute function public.nft_hero_purchase_finalize();

-- ROI cap: a confirmed NFT hero purchase is real invested TON
create or replace function public.nft_hero_mining_track() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_ref text; v_new text; v_old text;
begin
  v_ref := 'nft_hero_order:' || NEW.id::text;
  v_new := lower(coalesce(NEW.status, ''));
  v_old := lower(coalesce(OLD.status, ''));
  if v_new = v_old then return NEW; end if;
  if v_new in ('confirmed','completed','delivered','paid_confirmed') then
    perform public.hero_mining_register_investment(NEW.user_id, 'nft_hero_purchase', v_ref, coalesce(NEW.price_ton, 0));
  elsif v_new in ('refunded','reversed','cancelled','failed') then
    perform public.hero_mining_revoke_investment(v_ref);
  end if;
  return NEW;
end $$;
drop trigger if exists trg_nft_hero_mining_track on public.nft_hero_orders;
create trigger trg_nft_hero_mining_track after update of status on public.nft_hero_orders
for each row execute function public.nft_hero_mining_track();

-- MINING: NFT heroes mine with their own fixed daily rate ------------------
create or replace function public.hero_mining_hero_rate(p_rarity text, p_nft_hero_id uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select case
    when p_nft_hero_id is not null
      then coalesce((select greatest(mining_daily_ton, 0) from nft_heroes where id = p_nft_hero_id), 0)
    else hero_mining_rate(p_rarity)
  end;
$$;

create or replace function public.hero_mining_accrue(p_user_id uuid)
 returns numeric language plpgsql security definer set search_path = public
as $function$
DECLARE v_now timestamptz := now(); v_gain numeric := 0; v_unclaimed numeric; v_room numeric;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;

  v_room := COALESCE(hero_mining_remaining(p_user_id), 0);
  IF v_room <= 0 THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;

  WITH elig AS (
    SELECT h.id,
           hero_mining_hero_rate(h.rarity, h.nft_hero_id) AS rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate * e.secs / 86400.0 AS gain
  )
  SELECT COALESCE(SUM(gain), 0) INTO v_gain FROM moved;

  v_gain := round(LEAST(GREATEST(v_gain, 0), v_room), 9);

  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
  RETURNING hero_mining_unclaimed_ton INTO v_unclaimed;

  RETURN COALESCE(v_unclaimed, 0);
END $function$;

create or replace function public.get_hero_mining_state(p_telegram_id bigint)
 returns jsonb language plpgsql security definer set search_path = public
as $function$
DECLARE v_user uuid; u game_players%rowtype; v_unclaimed numeric; v_rate numeric; v_count integer; v_min numeric;
        v_invested numeric; v_returned numeric; v_remaining numeric;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  v_unclaimed := hero_mining_accrue(v_user);
  SELECT * INTO u FROM game_players WHERE id = v_user;
  SELECT COALESCE(min_claim_ton, 0) INTO v_min FROM hero_mining_settings WHERE id;

  v_invested := round(COALESCE(u.hero_mining_invested_ton, 0), 9);
  v_returned := round(COALESCE(u.hero_mining_returned_ton, 0), 9);
  v_remaining := GREATEST(0, round(v_invested - v_returned - COALESCE(v_unclaimed, 0), 9));

  SELECT COUNT(*), COALESCE(SUM(hero_mining_hero_rate(h.rarity, h.nft_hero_id)), 0)
    INTO v_count, v_rate
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
     AND hero_mining_hero_rate(h.rarity, h.nft_hero_id) > 0;

  RETURN jsonb_build_object(
    'enabled', hero_mining_enabled(),
    'dailyRateTon', round(COALESCE(v_rate, 0), 9),
    'unclaimedTon', round(COALESCE(v_unclaimed, 0), 9),
    'lifetimeTon', round(COALESCE(u.hero_mining_lifetime_ton, 0), 9),
    'investedTon', v_invested,
    'returnedTon', v_returned,
    'remainingTon', v_remaining,
    'roiLimitReached', (v_invested > 0 AND v_remaining <= 0),
    'hasInvestment', (v_invested > 0),
    'eligibleHeroes', COALESCE(v_count, 0),
    'availableTon', round(COALESCE(u.ton_balance, 0), 9),
    'minClaimTon', COALESCE(v_min, 0),
    'lastClaimAt', u.hero_mining_claimed_at,
    'updatedAt', now(),
    'rates', COALESCE((SELECT jsonb_object_agg(rarity, ton_per_day) FROM hero_mining_rates), '{}'::jsonb),
    'investments', COALESCE((SELECT jsonb_agg(jsonb_build_object('sourceType', i.source_type, 'amountTon', i.amount_ton, 'createdAt', i.created_at) ORDER BY i.created_at DESC)
      FROM (SELECT * FROM hero_mining_investments WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) i), '[]'::jsonb),
    'claims', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'amountTon', c.amount_ton, 'heroCount', c.hero_count,
        'ratePerDay', c.rate_per_day, 'createdAt', c.created_at) ORDER BY c.created_at DESC)
      FROM (SELECT * FROM hero_mining_claims WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) c), '[]'::jsonb)
  );
END $function$;

create or replace function public.claim_hero_mining(p_telegram_id bigint)
 returns jsonb language plpgsql security definer set search_path = public
as $function$
DECLARE v_user uuid; v_unclaimed numeric; v_rate numeric; v_count integer; v_min numeric; v_claim uuid;
        v_invested numeric; v_returned numeric; v_room numeric; v_claimable numeric;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF NOT hero_mining_enabled() THEN RAISE EXCEPTION 'MINING_DISABLED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('hero_mining_claim:' || v_user::text));

  v_unclaimed := hero_mining_accrue(v_user);

  SELECT round(COALESCE(hero_mining_invested_ton, 0), 9), round(COALESCE(hero_mining_returned_ton, 0), 9)
    INTO v_invested, v_returned FROM game_players WHERE id = v_user;

  IF v_invested <= 0 THEN RAISE EXCEPTION 'NO_TON_INVESTMENT'; END IF;
  v_room := GREATEST(0, round(v_invested - v_returned, 9));
  IF v_room <= 0 THEN RAISE EXCEPTION 'ROI_LIMIT_REACHED'; END IF;

  v_claimable := round(LEAST(COALESCE(v_unclaimed, 0), v_room), 9);
  SELECT COALESCE(min_claim_ton, 0) INTO v_min FROM hero_mining_settings WHERE id;
  IF v_claimable < GREATEST(COALESCE(v_min, 0), 0.000001) THEN RAISE EXCEPTION 'NOTHING_TO_CLAIM'; END IF;

  SELECT COUNT(*), COALESCE(SUM(hero_mining_hero_rate(h.rarity, h.nft_hero_id)), 0)
    INTO v_count, v_rate
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
     AND hero_mining_hero_rate(h.rarity, h.nft_hero_id) > 0;

  INSERT INTO hero_mining_claims (user_id, amount_ton, hero_count, rate_per_day)
  VALUES (v_user, v_claimable, COALESCE(v_count, 0), round(COALESCE(v_rate, 0), 9))
  RETURNING id INTO v_claim;

  UPDATE game_players
     SET hero_mining_unclaimed_ton = GREATEST(0, round(COALESCE(hero_mining_unclaimed_ton, 0) - v_claimable, 9)),
         hero_mining_lifetime_ton = round(COALESCE(hero_mining_lifetime_ton, 0) + v_claimable, 9),
         hero_mining_returned_ton = round(COALESCE(hero_mining_returned_ton, 0) + v_claimable, 9),
         hero_mining_claimed_at = now(),
         updated_at = now()
   WHERE id = v_user;

  PERFORM credit_ton_reward(v_user, v_claimable, 'hero_mining', 'hero_mining:' || v_claim::text, 'Hero TON Mining');

  RETURN get_hero_mining_state(p_telegram_id)
       || jsonb_build_object('ok', true, 'claimedTon', v_claimable, 'claimId', v_claim);
END $function$;

-- SHOP -------------------------------------------------------------------
create or replace function public.nft_hero_shop_json(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u uuid; items jsonb; total int; sold int;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  select coalesce(jsonb_agg(x order by (x->>'serial')::int), '[]'::jsonb), count(*),
         count(*) filter (where x->>'status' = 'SOLD_OUT')
    into items, total, sold
  from (
    select jsonb_build_object(
      'id', n.id,
      'serial', n.nft_serial,
      'instance', n.unique_instance_id,
      'name', c.name,
      'slug', c.hero_key,
      'image', c.image,
      'rarity', 'nft_exclusive',
      'priceTon', round(coalesce(n.price_ton, n.tier_ton, 20), 9),
      'tierTon', round(coalesce(n.tier_ton, n.price_ton, 20), 9),
      'dailyYieldTon', round(coalesce(n.mining_daily_ton, 0), 9),
      'supply', 1,
      'status', case when n.status = 'AVAILABLE' and n.owner_user_id is null then 'AVAILABLE' else 'SOLD_OUT' end,
      'ownedByMe', (u is not null and n.owner_user_id = u),
      'atk', round(coalesce(c.base_atk, 0)),
      'hp', round(coalesce(c.base_hp, 0))
    ) as x
    from public.nft_heroes n
    join public.hero_catalog c on c.hero_key = n.hero_template_id
    where n.for_sale and n.status <> 'BURNED'
  ) q;
  return jsonb_build_object(
    'totalSupply', coalesce(total, 0),
    'sold', coalesce(sold, 0),
    'available', coalesce(total, 0) - coalesce(sold, 0),
    'items', items,
    'balanceTon', coalesce((select round(ton_balance, 9) from public.game_players where id = u), 0)
  );
end $$;

create or replace function public.nft_hero_assign_unit(p_nft_id uuid, p_user_id uuid, p_source text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n public.nft_heroes; c public.hero_catalog; v_hero uuid; ph public.player_heroes;
begin
  select * into n from public.nft_heroes where id = p_nft_id for update;
  if n.id is null then raise exception 'NFT_HERO_NOT_FOUND'; end if;
  if n.status = 'BURNED' then raise exception 'NFT_HERO_BURNED'; end if;
  if n.owner_user_id is not null then
    if n.owner_user_id = p_user_id then
      return jsonb_build_object('status', 'already_delivered', 'playerHeroId', n.player_hero_id, 'serial', n.nft_serial);
    end if;
    raise exception 'NFT_HERO_ALREADY_OWNED';
  end if;
  select * into c from public.hero_catalog where hero_key = n.hero_template_id;

  insert into public.player_heroes (user_id, hero_key, name, rarity, level, image, archetype,
      is_nft_exclusive, nft_hero_id, nft_serial, nft_instance_id, tradable, market_locked, locked)
  values (p_user_id, c.hero_key, c.name, 'nft_exclusive', greatest(1, coalesce(n.level, 1)), c.image, c.hero_class,
      true, n.id, n.nft_serial, n.unique_instance_id, false, true, true)
  returning id into v_hero;
  select * into ph from public.player_heroes where id = v_hero;

  update public.nft_heroes set owner_user_id = p_user_id, player_hero_id = v_hero, status = 'OWNED',
      assigned_at = now(), revoked_at = null, updated_at = now()
   where id = n.id;
  insert into public.nft_hero_history (nft_hero_id, action, to_user_id, reason)
  values (n.id, 'PURCHASED', p_user_id, p_source);

  return jsonb_build_object('status', 'completed', 'playerHeroId', v_hero, 'serial', n.nft_serial,
    'heroName', c.name, 'instance', n.unique_instance_id,
    'atk', round(coalesce(ph.final_atk, 0)), 'hp', round(coalesce(ph.final_hp, 0)));
end $$;

create or replace function public.nft_hero_deliver_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.nft_hero_orders; res jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('nft_hero_order:'||p_order_id::text, 0));
  select * into o from public.nft_hero_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.delivered_at is not null then return jsonb_build_object('status', 'already_delivered', 'orderId', o.id); end if;
  if o.status not in ('paid','confirmed') then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
  res := public.nft_hero_assign_unit(o.nft_hero_id, o.user_id, 'ton_purchase');
  update public.nft_hero_orders set status = 'delivered', delivered_at = now() where id = o.id;
  return res || jsonb_build_object('orderId', o.id, 'priceTon', o.price_ton, 'paidWith', 'ton');
end $$;

create or replace function public.nft_hero_buy_with_balance(p_telegram_id bigint, p_nft_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; n public.nft_heroes; price numeric; done public.nft_hero_orders; res jsonb;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nft_hero_buy:'||p_nft_id::text, 0));

  select * into done from public.nft_hero_orders where idempotency_key = p_idempotency_key;
  if done.id is not null then return jsonb_build_object('status', 'already_processed', 'orderId', done.id); end if;

  select * into n from public.nft_heroes where id = p_nft_id for update;
  if n.id is null or not n.for_sale then raise exception 'NFT_NOT_FOR_SALE'; end if;
  if n.status <> 'AVAILABLE' or n.owner_user_id is not null then raise exception 'NFT_SOLD_OUT'; end if;
  price := round(coalesce(n.price_ton, n.tier_ton, 20), 9);

  insert into public.nft_hero_orders(user_id, nft_hero_id, price_ton, amount_nano, payment_address, payment_comment,
    idempotency_key, status, paid_at, confirmed_at)
  values (u, n.id, price, round(price * 1000000000)::text, 'internal_balance', 'internal:'||gen_random_uuid(),
    p_idempotency_key, 'confirmed', now(), now())
  returning * into done;

  perform public.debit_ton_balance(u, price, 'nft_hero_purchase', done.id::text,
    format('NFT HERO #%s purchase', n.nft_serial));

  res := public.nft_hero_assign_unit(n.id, u, 'balance_purchase');
  update public.nft_hero_orders set status = 'delivered', delivered_at = now() where id = done.id;
  return res || jsonb_build_object('orderId', done.id, 'priceTon', price, 'paidWith', 'balance');
end $$;

create or replace function public.nft_hero_create_order(p_telegram_id bigint, p_nft_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; n public.nft_heroes; o public.nft_hero_orders; price numeric; address text;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into o from public.nft_hero_orders where idempotency_key = p_idempotency_key;
  if o.id is null then
    select * into n from public.nft_heroes where id = p_nft_id for update;
    if n.id is null or not n.for_sale then raise exception 'NFT_NOT_FOR_SALE'; end if;
    if n.status <> 'AVAILABLE' or n.owner_user_id is not null then raise exception 'NFT_SOLD_OUT'; end if;
    price := round(coalesce(n.price_ton, n.tier_ton, 20), 9);
    address := public.wallet_hot_address();
    insert into public.nft_hero_orders(user_id, nft_hero_id, price_ton, amount_nano, payment_address, payment_comment, idempotency_key)
    values (u, n.id, price, round(price * 1000000000)::text, address, 'forge_nfth:'||gen_random_uuid(), p_idempotency_key)
    returning * into o;
  end if;
  return jsonb_build_object('id', o.id, 'paymentAddress', o.payment_address, 'amountNano', o.amount_nano,
    'amountTon', o.price_ton, 'paymentComment', o.payment_comment, 'expiresAt', o.expires_at);
end $$;

create or replace function public.nft_hero_confirm_purchase(p_order_id uuid, p_tx_hash text, p_amount_nano text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.nft_hero_orders; v_expected numeric; v_received numeric;
begin
  perform pg_advisory_xact_lock(hashtextextended('nft_hero_order:'||p_order_id::text, 0));
  select * into o from public.nft_hero_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.tx_hash is null then
    if nullif(trim(coalesce(p_tx_hash, '')), '') is null then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
    v_expected := coalesce(nullif(o.amount_nano, '')::numeric, 0);
    v_received := coalesce(nullif(trim(coalesce(p_amount_nano, '')), '')::numeric, v_expected);
    if v_received < v_expected * 0.97 then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
    if exists(select 1 from public.nft_hero_orders where tx_hash = p_tx_hash and id <> o.id)
       or exists(select 1 from public.nft_pet_orders where tx_hash = p_tx_hash)
       or exists(select 1 from public.pet_egg_orders where tx_hash = p_tx_hash)
       or exists(select 1 from public.wallet_deposits where tx_hash = p_tx_hash)
       or exists(select 1 from public.season_pass_orders where tx_hash = p_tx_hash)
    then raise exception 'TX_ALREADY_USED'; end if;
    update public.nft_hero_orders
       set status = 'confirmed', tx_hash = p_tx_hash, paid_at = coalesce(paid_at, now()),
           confirmed_at = coalesce(confirmed_at, now())
     where id = o.id;
  end if;
  return public.nft_hero_deliver_order(o.id);
end $$;

create or replace function public.nft_hero_reconcile_orders(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; o record; delivered jsonb := '[]'::jsonb; already jsonb := '[]'::jsonb;
        results jsonb := '[]'::jsonb; pending jsonb; res jsonb;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  for o in select * from public.nft_hero_orders
            where user_id = u and status in ('paid','confirmed') and delivered_at is null loop
    begin
      res := public.nft_hero_deliver_order(o.id);
      if res->>'status' = 'already_delivered' then already := already || to_jsonb(o.id::text);
      else delivered := delivered || to_jsonb(o.id::text); end if;
      results := results || jsonb_build_array(res);
    exception when others then
      raise log 'NFT_HERO_RECONCILE order=% error=%', o.id, sqlerrm;
    end;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('id', ord.id, 'paymentComment', ord.payment_comment,
      'amountNano', ord.amount_nano, 'priceTon', ord.price_ton, 'heroName', c.name) order by ord.created_at), '[]'::jsonb)
    into pending
  from public.nft_hero_orders ord
  join public.nft_heroes n on n.id = ord.nft_hero_id
  join public.hero_catalog c on c.hero_key = n.hero_template_id
  where ord.user_id = u and ord.status = 'pending' and ord.tx_hash is null
    and ord.expires_at > now() - interval '2 hours';

  return jsonb_build_object('delivered', delivered, 'alreadyDelivered', already, 'results', results, 'awaitingPayment', pending);
end $$;

-- The player's own NFT heroes (mining rate + collection data only)
create or replace function public.nft_hero_my_json(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u uuid; total int; items jsonb;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select count(*) into total from public.nft_heroes;
  select coalesce(jsonb_agg(x order by (x->>'serial')::int), '[]'::jsonb) into items from (
    select jsonb_build_object(
      'nftId', n.id, 'playerHeroId', ph.id, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
      'name', coalesce(ph.name, c.name), 'image', coalesce(ph.image, c.image), 'rarity', 'nft_exclusive',
      'level', coalesce(ph.level, 1), 'stars', coalesce(ph.fusion_level, 0),
      'atk', round(coalesce(ph.final_atk, 0)), 'hp', round(coalesce(ph.final_hp, 0)),
      'tierTon', round(coalesce(n.tier_ton, n.price_ton, 20), 9),
      'dailyYieldTon', round(coalesce(n.mining_daily_ton, 0), 9)
    ) as x
    from public.nft_heroes n
    join public.hero_catalog c on c.hero_key = n.hero_template_id
    left join public.player_heroes ph on ph.id = n.player_hero_id
    where n.owner_user_id = u and n.status = 'OWNED'
  ) q;
  return jsonb_build_object('totalSupply', greatest(coalesce(total, 0), 10), 'items', items);
end $$;

revoke all on function public.nft_hero_shop_json(bigint) from public, anon, authenticated;
revoke all on function public.nft_hero_my_json(bigint) from public, anon, authenticated;
revoke all on function public.nft_hero_assign_unit(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.nft_hero_deliver_order(uuid) from public, anon, authenticated;
revoke all on function public.nft_hero_buy_with_balance(bigint, uuid, text) from public, anon, authenticated;
revoke all on function public.nft_hero_create_order(bigint, uuid, text) from public, anon, authenticated;
revoke all on function public.nft_hero_confirm_purchase(uuid, text, text) from public, anon, authenticated;
revoke all on function public.nft_hero_reconcile_orders(bigint) from public, anon, authenticated;
revoke all on function public.hero_mining_hero_rate(text, uuid) from public, anon, authenticated;
revoke all on function public.nft_hero_purchase_finalize() from public, anon, authenticated;
revoke all on function public.nft_hero_mining_track() from public, anon, authenticated;
revoke all on function public.nft_hero_orders_touch() from public, anon, authenticated;
grant execute on function public.nft_hero_shop_json(bigint) to service_role;
grant execute on function public.nft_hero_my_json(bigint) to service_role;
grant execute on function public.nft_hero_buy_with_balance(bigint, uuid, text) to service_role;
grant execute on function public.nft_hero_create_order(bigint, uuid, text) to service_role;
grant execute on function public.nft_hero_confirm_purchase(uuid, text, text) to service_role;
grant execute on function public.nft_hero_reconcile_orders(bigint) to service_role;