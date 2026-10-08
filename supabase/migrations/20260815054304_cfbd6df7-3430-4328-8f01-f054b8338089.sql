-- ============================================================================
-- MYTHREON 0027 — NFT EXCLUSIVE EQUIPMENT (ARSENAL)
-- Reuses the existing equipment stack (equipment_templates + player_equipment +
-- hero_recalc_equipment) so effective hero stats stay a single source of truth.
-- ============================================================================

alter table public.equipment_templates drop constraint if exists equipment_templates_rarity_check;
alter table public.equipment_templates add constraint equipment_templates_rarity_check
  check (rarity = any (array['common','uncommon','rare','epic','legendary','nft_exclusive']));
alter table public.equipment_templates add column if not exists is_nft boolean not null default false;

-- ---------------------------------------------------------------------------
-- 1/1 units
-- ---------------------------------------------------------------------------
create table if not exists public.nft_equipment (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.equipment_templates(id) on delete restrict,
  nft_serial integer not null unique,
  unique_instance_id text not null unique,
  owner_user_id uuid references public.game_players(id) on delete set null,
  player_equipment_id uuid references public.player_equipment(id) on delete set null,
  status text not null default 'AVAILABLE' check (status = any (array['AVAILABLE','OWNED','BURNED'])),
  for_sale boolean not null default true,
  price_ton numeric(20,9) not null default 15,
  created_by_admin bigint,
  assigned_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists nft_equipment_template_unique on public.nft_equipment(template_id);
create index if not exists nft_equipment_owner_idx on public.nft_equipment(owner_user_id);

grant all on public.nft_equipment to service_role;
alter table public.nft_equipment enable row level security;

create table if not exists public.nft_equipment_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  nft_equipment_id uuid not null references public.nft_equipment(id) on delete cascade,
  price_ton numeric(20,9) not null,
  amount_nano text not null,
  payment_address text not null,
  payment_comment text not null,
  idempotency_key text not null unique,
  status text not null default 'pending',
  tx_hash text,
  paid_at timestamptz,
  confirmed_at timestamptz,
  delivered_at timestamptz,
  expires_at timestamptz not null default now() + interval '1 hour',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists nft_equipment_orders_user_idx on public.nft_equipment_orders(user_id, status);

grant all on public.nft_equipment_orders to service_role;
alter table public.nft_equipment_orders enable row level security;

drop trigger if exists trg_nft_equipment_updated on public.nft_equipment;
create trigger trg_nft_equipment_updated before update on public.nft_equipment
  for each row execute function public.update_updated_at_column();
drop trigger if exists trg_nft_equipment_orders_updated on public.nft_equipment_orders;
create trigger trg_nft_equipment_orders_updated before update on public.nft_equipment_orders
  for each row execute function public.update_updated_at_column();

-- ---------------------------------------------------------------------------
-- Shop (sale data only)
-- ---------------------------------------------------------------------------
create or replace function public.nft_equipment_shop_json(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare u uuid; items jsonb; total int; sold int;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  select coalesce(jsonb_agg(x order by (x->>'serial')::int), '[]'::jsonb), count(*),
         count(*) filter (where x->>'status' = 'SOLD_OUT')
    into items, total, sold
  from (
    select jsonb_build_object(
      'id', n.id, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
      'name', t.name, 'code', t.code, 'image', t.image_url,
      'slot', t.slot, 'kind', t.kind, 'heroClass', t.hero_class, 'rarity', 'nft_exclusive',
      'bonusAttack', coalesce(t.bonus_attack,0), 'bonusDefense', coalesce(t.bonus_defense,0),
      'bonusHp', coalesce(t.bonus_hp,0), 'power', coalesce(t.power,0),
      'description', t.description,
      'priceTon', round(coalesce(n.price_ton,15), 9), 'supply', 1,
      'status', case when n.status = 'AVAILABLE' and n.owner_user_id is null then 'AVAILABLE' else 'SOLD_OUT' end,
      'ownedByMe', (u is not null and n.owner_user_id = u)
    ) as x
    from public.nft_equipment n
    join public.equipment_templates t on t.id = n.template_id
    where n.status <> 'BURNED' and (n.for_sale or n.owner_user_id is not null)
  ) q;
  return jsonb_build_object(
    'totalSupply', coalesce(total,0), 'sold', coalesce(sold,0),
    'available', coalesce(total,0) - coalesce(sold,0), 'items', items,
    'balanceTon', coalesce((select round(greatest(ton_balance - coalesce(ton_reserved,0),0), 9) from public.game_players where id = u), 0)
  );
end $$;

-- ---------------------------------------------------------------------------
-- ARSENAL: every equipment instance owned by the player (normal + NFT)
-- ---------------------------------------------------------------------------
create or replace function public.arsenal_json(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare u uuid; items jsonb;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select coalesce(jsonb_agg(x order by (x->>'isNft')::boolean desc, x->>'slot', x->>'name'), '[]'::jsonb) into items
  from (
    select jsonb_build_object(
      'instanceId', pe.id, 'code', t.code, 'name', t.name, 'slot', t.slot, 'kind', t.kind,
      'rarity', t.rarity, 'image', t.image_url, 'level', coalesce(pe.level,1),
      'heroClass', t.hero_class,
      'bonusAttack', coalesce(t.bonus_attack,0), 'bonusDefense', coalesce(t.bonus_defense,0),
      'bonusHp', coalesce(t.bonus_hp,0), 'power', coalesce(t.power,0),
      'isNft', coalesce(t.is_nft,false), 'serial', n.nft_serial, 'instance', n.unique_instance_id,
      'tradable', not coalesce(t.is_nft,false) and not coalesce(pe.locked,false),
      'listed', coalesce(pe.market_locked,false),
      'equippedHeroId', pe.hero_id, 'equippedHeroName', ph.name
    ) as x
    from public.player_equipment pe
    join public.equipment_templates t on t.id = pe.template_id
    left join public.nft_equipment n on n.player_equipment_id = pe.id
    left join public.player_heroes ph on ph.id = pe.hero_id
    where pe.user_id = u
  ) q;
  return jsonb_build_object('items', items);
end $$;

-- ---------------------------------------------------------------------------
-- Delivery of one 1/1 unit
-- ---------------------------------------------------------------------------
create or replace function public.nft_equipment_assign_unit(p_nft_id uuid, p_user_id uuid, p_source text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare n public.nft_equipment; t public.equipment_templates; v_inst uuid;
begin
  select * into n from public.nft_equipment where id = p_nft_id for update;
  if n.id is null then raise exception 'NFT_EQUIPMENT_NOT_FOUND'; end if;
  if n.status = 'BURNED' then raise exception 'NFT_EQUIPMENT_BURNED'; end if;
  if n.owner_user_id is not null then
    if n.owner_user_id = p_user_id then
      return jsonb_build_object('status','already_delivered','instanceId', n.player_equipment_id, 'serial', n.nft_serial);
    end if;
    raise exception 'NFT_EQUIPMENT_ALREADY_OWNED';
  end if;
  select * into t from public.equipment_templates where id = n.template_id;

  -- NFT units are never tradable on the player market (locked), but stay equipable.
  insert into public.player_equipment (user_id, template_id, level, locked, source, source_ref, market_locked)
  values (p_user_id, t.id, 1, true, 'nft', n.id, false)
  returning id into v_inst;

  update public.nft_equipment
     set owner_user_id = p_user_id, player_equipment_id = v_inst, status = 'OWNED',
         for_sale = false, assigned_at = now(), updated_at = now()
   where id = n.id;

  return jsonb_build_object('status','completed','instanceId', v_inst, 'serial', n.nft_serial,
    'name', t.name, 'slot', t.slot, 'heroClass', t.hero_class, 'instance', n.unique_instance_id);
end $$;

create or replace function public.nft_equipment_deliver_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare o public.nft_equipment_orders; res jsonb;
begin
  select * into o from public.nft_equipment_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.delivered_at is not null then return jsonb_build_object('status','already_delivered','orderId', o.id); end if;
  if o.status not in ('paid','confirmed') then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
  res := public.nft_equipment_assign_unit(o.nft_equipment_id, o.user_id, 'ton_purchase');
  update public.nft_equipment_orders set status = 'delivered', delivered_at = now() where id = o.id;
  return res || jsonb_build_object('orderId', o.id, 'priceTon', o.price_ton);
end $$;

create or replace function public.nft_equipment_buy_with_balance(p_telegram_id bigint, p_nft_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid; n public.nft_equipment; price numeric; done public.nft_equipment_orders; res jsonb;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nft_equip_buy:'||p_nft_id::text, 0));

  select * into done from public.nft_equipment_orders where idempotency_key = p_idempotency_key;
  if done.id is not null then return jsonb_build_object('status','already_processed','orderId', done.id); end if;

  select * into n from public.nft_equipment where id = p_nft_id for update;
  if n.id is null or not n.for_sale then raise exception 'NFT_NOT_FOR_SALE'; end if;
  if n.status <> 'AVAILABLE' or n.owner_user_id is not null then raise exception 'NFT_SOLD_OUT'; end if;
  price := round(coalesce(n.price_ton, 15), 9);

  insert into public.nft_equipment_orders(user_id, nft_equipment_id, price_ton, amount_nano, payment_address,
    payment_comment, idempotency_key, status, paid_at, confirmed_at)
  values (u, n.id, price, round(price * 1000000000)::text, 'internal_balance', 'internal:'||gen_random_uuid(),
    p_idempotency_key, 'confirmed', now(), now())
  returning * into done;

  perform public.debit_ton_balance(u, price, 'nft_equipment_purchase', done.id::text,
    format('NFT EQUIPMENT #%s purchase', n.nft_serial));

  res := public.nft_equipment_assign_unit(n.id, u, 'balance_purchase');
  update public.nft_equipment_orders set status = 'delivered', delivered_at = now() where id = done.id;
  return res || jsonb_build_object('orderId', done.id, 'priceTon', price, 'paidWith', 'balance');
end $$;

create or replace function public.nft_equipment_create_order(p_telegram_id bigint, p_nft_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid; n public.nft_equipment; o public.nft_equipment_orders; price numeric; address text;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into o from public.nft_equipment_orders where idempotency_key = p_idempotency_key;
  if o.id is null then
    select * into n from public.nft_equipment where id = p_nft_id for update;
    if n.id is null or not n.for_sale then raise exception 'NFT_NOT_FOR_SALE'; end if;
    if n.status <> 'AVAILABLE' or n.owner_user_id is not null then raise exception 'NFT_SOLD_OUT'; end if;
    price := round(coalesce(n.price_ton, 15), 9);
    address := public.wallet_hot_address();
    insert into public.nft_equipment_orders(user_id, nft_equipment_id, price_ton, amount_nano, payment_address,
      payment_comment, idempotency_key)
    values (u, n.id, price, round(price * 1000000000)::text, address, 'forge_nftq:'||gen_random_uuid(), p_idempotency_key)
    returning * into o;
  end if;
  return jsonb_build_object('id', o.id, 'paymentAddress', o.payment_address, 'amountNano', o.amount_nano,
    'amountTon', o.price_ton, 'paymentComment', o.payment_comment, 'expiresAt', o.expires_at);
end $$;

create or replace function public.nft_equipment_confirm_purchase(p_order_id uuid, p_tx_hash text, p_amount_nano text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare o public.nft_equipment_orders; v_expected numeric; v_received numeric;
begin
  perform pg_advisory_xact_lock(hashtextextended('nft_equip_order:'||p_order_id::text, 0));
  select * into o from public.nft_equipment_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.tx_hash is null then
    if nullif(trim(coalesce(p_tx_hash,'')), '') is null then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
    v_expected := coalesce(nullif(o.amount_nano,'')::numeric, 0);
    v_received := coalesce(nullif(trim(coalesce(p_amount_nano,'')),'')::numeric, v_expected);
    if v_received < v_expected * 0.97 then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
    if exists(select 1 from public.nft_equipment_orders where tx_hash = p_tx_hash and id <> o.id)
       or exists(select 1 from public.nft_hero_orders where tx_hash = p_tx_hash)
       or exists(select 1 from public.nft_pet_orders where tx_hash = p_tx_hash)
       or exists(select 1 from public.pet_egg_orders where tx_hash = p_tx_hash)
       or exists(select 1 from public.wallet_deposits where tx_hash = p_tx_hash)
       or exists(select 1 from public.season_pass_orders where tx_hash = p_tx_hash)
    then raise exception 'TX_ALREADY_USED'; end if;
    update public.nft_equipment_orders
       set status = 'confirmed', tx_hash = p_tx_hash, paid_at = coalesce(paid_at, now()),
           confirmed_at = coalesce(confirmed_at, now())
     where id = o.id;
  end if;
  return public.nft_equipment_deliver_order(o.id);
end $$;

create or replace function public.nft_equipment_reconcile_orders(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid; o record; delivered jsonb := '[]'::jsonb; already jsonb := '[]'::jsonb;
        results jsonb := '[]'::jsonb; pending jsonb; res jsonb;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  for o in select * from public.nft_equipment_orders
            where user_id = u and status in ('paid','confirmed') and delivered_at is null loop
    begin
      res := public.nft_equipment_deliver_order(o.id);
      if res->>'status' = 'already_delivered' then already := already || to_jsonb(o.id::text);
      else delivered := delivered || to_jsonb(o.id::text); end if;
      results := results || jsonb_build_array(res);
    exception when others then
      raise log 'NFT_EQUIPMENT_RECONCILE order=% error=%', o.id, sqlerrm;
    end;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('id', ord.id, 'paymentComment', ord.payment_comment,
      'amountNano', ord.amount_nano, 'priceTon', ord.price_ton, 'itemName', t.name) order by ord.created_at), '[]'::jsonb)
    into pending
  from public.nft_equipment_orders ord
  join public.nft_equipment n on n.id = ord.nft_equipment_id
  join public.equipment_templates t on t.id = n.template_id
  where ord.user_id = u and ord.status = 'pending' and ord.tx_hash is null
    and ord.expires_at > now() - interval '2 hours';

  return jsonb_build_object('delivered', delivered, 'alreadyDelivered', already, 'results', results, 'awaitingPayment', pending);
end $$;

-- ---------------------------------------------------------------------------
-- Admin (master bot): stock, sold list and creation of new 1/1 units
-- ---------------------------------------------------------------------------
create or replace function public.admin_nft_equipment_overview(p_admin_id bigint, p_slot text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare rows jsonb;
begin
  perform public.admin_assert(p_admin_id);
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', n.id, 'serial', n.nft_serial, 'name', t.name, 'slot', t.slot, 'kind', t.kind,
      'heroClass', t.hero_class, 'priceTon', round(n.price_ton,9), 'status', n.status,
      'atk', t.bonus_attack, 'def', t.bonus_defense, 'hp', t.bonus_hp, 'power', t.power,
      'ownerTelegramId', g.telegram_id, 'ownerName', g.first_name, 'assignedAt', n.assigned_at
    ) order by n.nft_serial), '[]'::jsonb) into rows
  from public.nft_equipment n
  join public.equipment_templates t on t.id = n.template_id
  left join public.game_players g on g.id = n.owner_user_id
  where (p_slot is null or t.slot = p_slot);
  return jsonb_build_object('items', rows);
end $$;

create or replace function public.admin_nft_equipment_create(
  p_admin_id bigint, p_slot text, p_name text, p_hero_class text, p_image text,
  p_atk integer, p_def integer, p_hp integer, p_price_ton numeric)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare slot text := lower(trim(coalesce(p_slot,''))); cls text := nullif(lower(trim(coalesce(p_hero_class,''))), '');
        kind text; serial int; tpl uuid; code text; n public.nft_equipment;
begin
  perform public.admin_assert(p_admin_id);
  if slot not in ('weapon','armor','ring') then raise exception 'INVALID_SLOT'; end if;
  if slot = 'weapon' then
    if cls is null then raise exception 'CLASS_REQUIRED'; end if;
    if cls not in ('warrior','archer','tank','mage','support','assassin') then raise exception 'INVALID_CLASS'; end if;
    kind := case cls when 'archer' then 'bow' when 'mage' then 'staff' when 'support' then 'scepter'
                     when 'warrior' then 'axe' else 'sword' end;
  else
    kind := slot; cls := null;
  end if;

  select coalesce(max(nft_serial),0) + 1 into serial from public.nft_equipment;
  code := 'nfteq_' || slot || '_' || lpad(serial::text, 3, '0');

  insert into public.equipment_templates(code, name, slot, kind, hero_class, rarity, tier, image_url,
      bonus_attack, bonus_defense, bonus_hp, power, description, is_active, is_nft)
  values (code, trim(p_name), slot, kind, cls, 'nft_exclusive', 6, nullif(trim(coalesce(p_image,'')), ''),
      greatest(coalesce(p_atk,0),0), greatest(coalesce(p_def,0),0), greatest(coalesce(p_hp,0),0),
      round(greatest(coalesce(p_atk,0),0)*2.2 + greatest(coalesce(p_hp,0),0)*0.18 + greatest(coalesce(p_def,0),0)*1.2),
      'NFT EXCLUSIVE 1/1', true, true)
  returning id into tpl;

  insert into public.nft_equipment(template_id, nft_serial, unique_instance_id, price_ton, created_by_admin)
  values (tpl, serial, 'MYTHREON-EQ-' || lpad(serial::text, 4, '0'), greatest(coalesce(p_price_ton,15),0.1), p_admin_id)
  returning * into n;

  return jsonb_build_object('id', n.id, 'serial', n.nft_serial, 'code', code, 'name', trim(p_name), 'slot', slot,
    'heroClass', cls, 'priceTon', round(n.price_ton,9));
end $$;

revoke all on function public.nft_equipment_shop_json(bigint) from anon, authenticated;
revoke all on function public.arsenal_json(bigint) from anon, authenticated;
revoke all on function public.nft_equipment_assign_unit(uuid, uuid, text) from anon, authenticated;
revoke all on function public.nft_equipment_deliver_order(uuid) from anon, authenticated;
revoke all on function public.nft_equipment_buy_with_balance(bigint, uuid, text) from anon, authenticated;
revoke all on function public.nft_equipment_create_order(bigint, uuid, text) from anon, authenticated;
revoke all on function public.nft_equipment_confirm_purchase(uuid, text, text) from anon, authenticated;
revoke all on function public.nft_equipment_reconcile_orders(bigint) from anon, authenticated;
revoke all on function public.admin_nft_equipment_overview(bigint, text) from anon, authenticated;
revoke all on function public.admin_nft_equipment_create(bigint, text, text, text, text, integer, integer, integer, numeric) from anon, authenticated;