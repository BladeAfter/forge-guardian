-- ============================================================
-- 1. Global premium offer settings (official reset timezone)
-- ============================================================
create table if not exists public.premium_offer_settings (
  id boolean primary key default true check (id),
  reset_timezone text not null default 'UTC',
  updated_at timestamptz not null default now()
);
grant all on public.premium_offer_settings to service_role;
alter table public.premium_offer_settings enable row level security;
insert into public.premium_offer_settings(id) values (true) on conflict (id) do nothing;

create or replace function public.premium_offer_timezone()
returns text language sql stable security definer set search_path to 'public' as $$
  select coalesce((select reset_timezone from public.premium_offer_settings where id), 'UTC')
$$;

create or replace function public.premium_offer_day_key()
returns date language sql stable security definer set search_path to 'public' as $$
  select (now() at time zone public.premium_offer_timezone())::date
$$;

-- ============================================================
-- 2. Popup state (max 1 popup per offer per day per player)
-- ============================================================
create table if not exists public.premium_offer_popup_views (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  offer_type text not null check (offer_type in ('FOUNDER_PACK','VETERAN_VAULT')),
  day_key date not null,
  shown_at timestamptz not null default now(),
  dismissed_at timestamptz,
  purchase_id uuid,
  unique (user_id, offer_type, day_key)
);
grant all on public.premium_offer_popup_views to service_role;
alter table public.premium_offer_popup_views enable row level security;
create index if not exists premium_offer_popup_views_user_idx on public.premium_offer_popup_views(user_id, offer_type, day_key desc);

-- ============================================================
-- 3. MYTH mining allocations for the premium packs (no new supply)
-- ============================================================
create table if not exists public.premium_myth_mining_pools (
  offer_type text primary key check (offer_type in ('FOUNDER_PACK','VETERAN_VAULT')),
  allocated_myth numeric not null default 0,
  distributed_myth numeric not null default 0,
  updated_at timestamptz not null default now()
);
grant all on public.premium_myth_mining_pools to service_role;
alter table public.premium_myth_mining_pools enable row level security;

-- ============================================================
-- 4. Config extensions
-- ============================================================
alter table public.founder_pack_config
  add column if not exists popup_enabled boolean not null default true,
  add column if not exists popup_frequency text not null default 'ONCE_PER_DAY',
  add column if not exists start_at timestamptz not null default now(),
  add column if not exists ends_at timestamptz,
  add column if not exists require_new_account boolean not null default false,
  add column if not exists hero_daily_myth numeric not null default 10000,
  add column if not exists pet_daily_myth numeric not null default 5000,
  add column if not exists legendary_chests integer not null default 3,
  add column if not exists weapon_code text;

alter table public.founder_pack_config drop constraint if exists founder_pack_config_popup_freq_check;
alter table public.founder_pack_config add constraint founder_pack_config_popup_freq_check
  check (popup_frequency in ('ONCE_PER_SESSION','ONCE_PER_DAY','UNTIL_PURCHASED','DISABLED'));

alter table public.veteran_vault_v2_config
  add column if not exists start_at timestamptz not null default now(),
  add column if not exists ends_at timestamptz;

alter table public.equipment_templates
  add column if not exists founder_line boolean not null default false;

alter table public.player_heroes add column if not exists premium_source text;
alter table public.player_pets add column if not exists premium_source text;
alter table public.player_equipment add column if not exists premium_source text;

-- ============================================================
-- 5. Founder snapshot + state
-- ============================================================
create or replace function public.founder_pack_snapshot()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare c public.founder_pack_config; v_season uuid;
begin
  c := public.founder_pack_settings();
  select id into v_season from public.season_pass_seasons where active order by created_at desc limit 1;
  return jsonb_build_object(
    'packVersion', c.pack_version, 'priceTon', c.price_ton,
    'seasonId', v_season, 'passTier', c.pass_tier,
    'mythAmount', c.myth_amount, 'heroKey', c.hero_key, 'petSlug', c.pet_slug,
    'equipmentChestCode', c.equipment_chest_code, 'fragments', c.fragments,
    'legendaryChests', greatest(coalesce(c.legendary_chests, 1), 1),
    'weaponCode', c.weapon_code,
    'heroDailyMyth', greatest(coalesce(c.hero_daily_myth, 0), 0),
    'petDailyMyth', greatest(coalesce(c.pet_daily_myth, 0), 0),
    'resourceChestCode', c.resource_chest_code, 'resourceChest', c.resource_chest,
    'badge', c.badge_enabled, 'frame', c.frame_enabled);
end $$;

create or replace function public.founder_pack_state(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare u public.game_players; c public.founder_pack_config; v_owned boolean;
        v_expires timestamptz; v_eligible boolean; v_window boolean;
        v_pending public.founder_pack_purchases;
begin
  select * into u from public.game_players where telegram_id = p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  c := public.founder_pack_settings();

  select exists (select 1 from public.founder_pack_purchases
                  where user_id = u.id and status in ('paid','settled')) into v_owned;

  v_window := coalesce(c.enabled, false)
              and now() >= coalesce(c.start_at, now())
              and (c.ends_at is null or now() < c.ends_at);

  v_expires := u.created_at + make_interval(days => greatest(1, c.eligibility_days));
  if coalesce(c.require_new_account, false) then
    v_window := v_window and now() < v_expires and u.created_at >= c.signup_from;
  end if;

  v_eligible := v_window and not v_owned;

  select * into v_pending from public.founder_pack_purchases
   where user_id = u.id and status = 'pending' and expires_at > now()
   order by created_at desc limit 1;

  return jsonb_build_object(
    'enabled', coalesce(c.enabled, false),
    'show', v_eligible or v_owned,
    'testMode', false,
    'eligible', v_eligible,
    'purchased', v_owned,
    'popupEnabled', coalesce(c.popup_enabled, false) and v_eligible,
    'popupFrequency', c.popup_frequency,
    'requireNewAccount', coalesce(c.require_new_account, false),
    'startAt', c.start_at,
    'endsAt', c.ends_at,
    'priceTon', c.price_ton,
    'amountNano', round(c.price_ton * 1000000000)::text,
    'eligibilityDays', c.eligibility_days,
    'eligibleUntil', case when coalesce(c.require_new_account,false) then v_expires else c.ends_at end,
    'signupFrom', c.signup_from,
    'accountCreatedAt', u.created_at,
    'availableTon', round(coalesce(u.ton_balance, 0), 9),
    'mythAmount', c.myth_amount,
    'fragments', c.fragments,
    'legendaryChests', greatest(coalesce(c.legendary_chests, 1), 1),
    'weaponCode', c.weapon_code,
    'heroDailyMyth', greatest(coalesce(c.hero_daily_myth, 0), 0),
    'petDailyMyth', greatest(coalesce(c.pet_daily_myth, 0), 0),
    'passTier', c.pass_tier,
    'pendingOrder', case when v_pending.id is null then null else jsonb_build_object(
        'orderId', v_pending.id, 'paymentAddress', v_pending.payment_address,
        'amountNano', v_pending.amount_nano, 'amountTon', v_pending.price_ton,
        'paymentComment', v_pending.payment_comment, 'expiresAt', v_pending.expires_at) end);
end $$;

-- ============================================================
-- 6. Founder delivery — MYTH mining on hero/pet, chests, weapon
-- ============================================================
create or replace function public.founder_pack_deliver(p_purchase_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare o public.founder_pack_purchases; s jsonb; hc public.hero_catalog; pt public.pets;
        v_hero uuid; v_pet uuid; v_season uuid; v_delivery jsonb := '{}'::jsonb;
        v_chests int; v_hero_myth numeric; v_pet_myth numeric;
        v_weapon public.equipment_templates; v_peq uuid;
begin
  select * into o from public.founder_pack_purchases where id = p_purchase_id for update;
  if o.id is null then raise exception 'FOUNDER_PACK_ORDER_NOT_FOUND'; end if;
  if o.status = 'settled' then
    return jsonb_build_object('ok', true, 'alreadySettled', true, 'purchaseId', o.id, 'delivery', o.delivery);
  end if;
  if o.status <> 'paid' then raise exception 'FOUNDER_PACK_NOT_PAID'; end if;

  s := o.reward_snapshot;
  v_chests := greatest(coalesce((s->>'legendaryChests')::int, 1), 1);
  v_hero_myth := greatest(coalesce((s->>'heroDailyMyth')::numeric, 0), 0);
  v_pet_myth := greatest(coalesce((s->>'petDailyMyth')::numeric, 0), 0);

  v_season := nullif(s->>'seasonId','')::uuid;
  if v_season is null then
    select id into v_season from public.season_pass_seasons where active order by created_at desc limit 1;
  end if;
  if v_season is not null then
    perform public.season_pass_apply_entitlement(o.user_id, v_season, coalesce(s->>'passTier','legendary'));
    v_delivery := v_delivery || jsonb_build_object('pass', jsonb_build_object('seasonId', v_season, 'tier', coalesce(s->>'passTier','legendary')));
  end if;

  if coalesce((s->>'mythAmount')::numeric, 0) > 0 then
    insert into public.myth_balances(user_id, amount) values (o.user_id, 0) on conflict (user_id) do nothing;
    update public.myth_balances set amount = amount + (s->>'mythAmount')::numeric, updated_at = now() where user_id = o.user_id;
    insert into public.myth_ledger(user_id, direction, amount, reason)
      values (o.user_id, 'credit', (s->>'mythAmount')::numeric, 'founder_pack');
    v_delivery := v_delivery || jsonb_build_object('myth', (s->>'mythAmount')::numeric);
  end if;

  select * into hc from public.hero_catalog where hero_key = s->>'heroKey';
  if hc.hero_key is null then select * into hc from public.hero_catalog where rarity = 'mythic' order by random() limit 1; end if;
  if hc.hero_key is not null then
    insert into public.player_heroes(user_id, hero_key, name, rarity, level, image, mining_daily_myth, mining_last_at, premium_source)
    values (o.user_id, hc.hero_key, hc.name, public.normalize_hero_rarity(hc.rarity), 1, hc.image, v_hero_myth, now(), 'FOUNDER')
    returning id into v_hero;
    v_delivery := v_delivery || jsonb_build_object('hero', jsonb_build_object('id', v_hero, 'heroKey', hc.hero_key, 'name', hc.name, 'dailyMyth', v_hero_myth));
  end if;

  select * into pt from public.pets where slug = s->>'petSlug' and not coalesce(is_nft_exclusive,false);
  if pt.id is null then
    select * into pt from public.pets where rarity = 'mythic' and not coalesce(is_nft_exclusive,false) order by random() limit 1;
  end if;
  if pt.id is not null then
    insert into public.player_pets(user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active, mining_daily_myth, mining_last_at, premium_source)
    values (o.user_id, pt.id, public.normalize_pet_rarity(pt.rarity), 1, 0, 'baby', 0, false, v_pet_myth, now(), 'FOUNDER')
    returning id into v_pet;
    v_delivery := v_delivery || jsonb_build_object('pet', jsonb_build_object('id', v_pet, 'slug', pt.slug, 'name', pt.name, 'dailyMyth', v_pet_myth));
  end if;

  insert into public.player_inventory(user_id, item_type, item_code, quantity)
  values (o.user_id, 'hero_chest', coalesce(s->>'equipmentChestCode','legendary_chest'), v_chests)
  on conflict (user_id, item_type, item_code)
    do update set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();

  select * into v_weapon from public.equipment_templates
   where is_active and (code = nullif(s->>'weaponCode','') or (nullif(s->>'weaponCode','') is null and founder_line))
   order by (code = coalesce(s->>'weaponCode','')) desc, random() limit 1;
  if v_weapon.id is not null then
    insert into public.player_equipment(user_id, template_id, level, source, source_ref, premium_source)
    values (o.user_id, v_weapon.id, 1, 'founder_pack', o.id::text, 'FOUNDER')
    returning id into v_peq;
    v_delivery := v_delivery || jsonb_build_object('weapon', jsonb_build_object('id', v_peq, 'code', v_weapon.code, 'name', v_weapon.name));
  end if;

  if coalesce((s->>'fragments')::int, 0) > 0 then
    perform public.add_universal_fragments(o.user_id, (s->>'fragments')::int);
  end if;

  insert into public.player_inventory(user_id, item_type, item_code, quantity)
  values (o.user_id, 'resource_chest', coalesce(s->>'resourceChestCode','premium_resource_chest'), 1)
  on conflict (user_id, item_type, item_code)
    do update set quantity = public.player_inventory.quantity + 1, updated_at = now();

  if coalesce((s->>'badge')::boolean, true) then
    insert into public.player_entitlements(user_id, code, source) values (o.user_id, 'founder_badge', 'founder_pack')
      on conflict (user_id, code) do nothing;
  end if;
  if coalesce((s->>'frame')::boolean, true) then
    insert into public.player_entitlements(user_id, code, source, equipped) values (o.user_id, 'founder_frame', 'founder_pack', true)
      on conflict (user_id, code) do nothing;
  end if;

  v_delivery := v_delivery || jsonb_build_object(
    'equipmentChest', coalesce(s->>'equipmentChestCode','legendary_chest'),
    'legendaryChests', v_chests,
    'fragments', coalesce((s->>'fragments')::int, 0),
    'resourceChest', coalesce(s->>'resourceChestCode','premium_resource_chest'),
    'badge', coalesce((s->>'badge')::boolean, true),
    'frame', coalesce((s->>'frame')::boolean, true));

  update public.founder_pack_purchases
     set status = 'settled', settled_at = now(), delivery = v_delivery
   where id = o.id;

  update public.premium_offer_popup_views
     set purchase_id = o.id
   where user_id = o.user_id and offer_type = 'FOUNDER_PACK' and purchase_id is null;

  insert into public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  values (o.user_id, 'founder_pack', 'FOUNDER PACK PURCHASED',
          'Your Founder Pack rewards have been delivered.', v_delivery, 'founder_pack:' || o.id::text)
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'purchaseId', o.id, 'delivery', v_delivery);
end $$;

-- ============================================================
-- 7. Premium offers popup state RPCs
-- ============================================================
create or replace function public.premium_offers_state(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare u public.game_players; fc public.founder_pack_config; vc public.veteran_vault_v2_config;
        f jsonb; v jsonb; v_day date := public.premium_offer_day_key();
        v_queue text[] := array[]::text[]; v_f_seen boolean; v_v_seen boolean; v_v_window boolean;
begin
  select * into u from public.game_players where telegram_id = p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  fc := public.founder_pack_settings();
  select * into vc from public.veteran_vault_v2_config where id;

  f := public.founder_pack_state(p_telegram_id);
  v := public.veteran_v2_state(p_telegram_id);

  v_v_window := coalesce(vc.enabled,false)
                and now() >= coalesce(vc.start_at, now())
                and (vc.ends_at is null or now() < vc.ends_at);

  select exists (select 1 from public.premium_offer_popup_views
                  where user_id = u.id and offer_type = 'FOUNDER_PACK' and day_key = v_day) into v_f_seen;
  select exists (select 1 from public.premium_offer_popup_views
                  where user_id = u.id and offer_type = 'VETERAN_VAULT' and day_key = v_day) into v_v_seen;

  if coalesce(fc.popup_enabled,false) and fc.popup_frequency <> 'DISABLED'
     and coalesce((f->>'eligible')::boolean,false) and not v_f_seen then
    v_queue := v_queue || 'FOUNDER_PACK';
  end if;
  if coalesce(vc.popup_enabled,false) and vc.popup_frequency <> 'DISABLED' and v_v_window
     and coalesce((v->>'eligible')::boolean,false) and not v_v_seen then
    v_queue := v_queue || 'VETERAN_VAULT';
  end if;

  return jsonb_build_object(
    'dayKey', v_day,
    'timezone', public.premium_offer_timezone(),
    'queue', to_jsonb(v_queue),
    'founder', f || jsonb_build_object('popupSeenToday', v_f_seen, 'popupFrequency', fc.popup_frequency),
    'veteran', v || jsonb_build_object('popupSeenToday', v_v_seen, 'popupFrequency', vc.popup_frequency,
                                       'startAt', vc.start_at, 'endsAt', vc.ends_at,
                                       'windowOpen', v_v_window));
end $$;

create or replace function public.premium_offer_popup_mark(p_telegram_id bigint, p_offer_type text, p_dismissed boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_user uuid; v_day date := public.premium_offer_day_key();
begin
  if p_offer_type not in ('FOUNDER_PACK','VETERAN_VAULT') then raise exception 'INVALID_OFFER_TYPE'; end if;
  select id into v_user from public.game_players where telegram_id = p_telegram_id;
  if v_user is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  insert into public.premium_offer_popup_views(user_id, offer_type, day_key, dismissed_at)
  values (v_user, p_offer_type, v_day, case when coalesce(p_dismissed,false) then now() else null end)
  on conflict (user_id, offer_type, day_key) do update
    set dismissed_at = coalesce(public.premium_offer_popup_views.dismissed_at,
                                case when coalesce(p_dismissed,false) then now() else null end);

  return jsonb_build_object('ok', true, 'offerType', p_offer_type, 'dayKey', v_day);
end $$;

-- ============================================================
-- 8. MYTH mining: Founder items never receive the Veteran +10%
-- ============================================================
create or replace function public.hero_mining_accrue(p_user_id uuid)
returns numeric language plpgsql security definer set search_path to 'public' as $$
DECLARE v_now timestamptz := now(); v_ton_gain numeric := 0; v_myth_gain numeric := 0;
        v_myth_flat numeric := 0; v_pet_myth numeric := 0; v_pet_flat numeric := 0;
        v_eq_myth numeric := 0; v_peq_myth numeric := 0;
        v_out numeric; v_room numeric; v_boost numeric := 0;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE player_pets SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE nft_equipment SET mining_last_at = v_now WHERE owner_user_id = p_user_id;
    UPDATE player_equipment SET mining_last_at = v_now WHERE user_id = p_user_id AND COALESCE(mining_daily_myth,0) > 0;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;

  v_room := GREATEST(COALESCE(hero_mining_remaining(p_user_id), 0), 0);

  WITH elig AS (
    SELECT h.id,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_rate(h.rarity, h.nft_hero_id) END AS rate,
           GREATEST(
             COALESCE(h.mining_daily_myth, 0),
             CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                  ELSE hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) END
           ) AS myth_rate,
           COALESCE(h.premium_source, '') = 'FOUNDER' AS is_founder,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate AS rate, e.myth_rate AS myth_rate, e.secs AS secs, e.is_founder AS is_founder
  )
  SELECT
    COALESCE(SUM(CASE WHEN myth_rate <= 0 AND rate > 0 THEN rate * secs / 86400.0 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN myth_rate > 0 AND NOT is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN myth_rate > 0 AND is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0)
    INTO v_ton_gain, v_myth_gain, v_myth_flat
    FROM moved;

  WITH pelig AS (
    SELECT p.id, GREATEST(COALESCE(p.mining_daily_myth, 0), 0) AS myth_rate,
           COALESCE(p.premium_source, '') = 'FOUNDER' AS is_founder,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(p.mining_last_at, p.created_at, v_now)))) AS secs
      FROM player_pets p
     WHERE p.user_id = p_user_id
       AND COALESCE(p.mining_daily_myth, 0) > 0
       AND NOT COALESCE(p.market_locked, false)
  ), pmoved AS (
    UPDATE player_pets pp SET mining_last_at = v_now
      FROM pelig e WHERE pp.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs, e.is_founder AS is_founder
  )
  SELECT COALESCE(SUM(CASE WHEN NOT is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0)
    INTO v_pet_myth, v_pet_flat FROM pmoved;

  WITH eelig AS (
    SELECT n.id, GREATEST(COALESCE(n.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(n.mining_last_at, n.assigned_at, n.created_at, v_now)))) AS secs
      FROM nft_equipment n
     WHERE n.owner_user_id = p_user_id
       AND n.status <> 'BURNED'
       AND COALESCE(n.mining_daily_myth, 0) > 0
  ), emoved AS (
    UPDATE nft_equipment ne SET mining_last_at = v_now
      FROM eelig e WHERE ne.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_eq_myth FROM emoved;

  WITH qelig AS (
    SELECT q.id, GREATEST(COALESCE(q.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(q.mining_last_at, q.created_at, v_now)))) AS secs
      FROM player_equipment q
     WHERE q.user_id = p_user_id
       AND COALESCE(q.mining_daily_myth, 0) > 0
       AND NOT COALESCE(q.market_locked, false)
       AND NOT EXISTS (SELECT 1 FROM nft_equipment n WHERE n.player_equipment_id = q.id)
  ), qmoved AS (
    UPDATE player_equipment pq SET mining_last_at = v_now
      FROM qelig e WHERE pq.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_peq_myth FROM qmoved;

  v_ton_gain := round(LEAST(GREATEST(v_ton_gain, 0), v_room), 9);
  v_myth_gain := GREATEST(v_myth_gain, 0) + GREATEST(v_pet_myth, 0) + GREATEST(v_eq_myth, 0) + GREATEST(v_peq_myth, 0);

  v_boost := GREATEST(COALESCE(public.veteran_v2_boost_percent(p_user_id), 0), 0);
  v_myth_gain := round(v_myth_gain * (1 + v_boost / 100.0) + GREATEST(v_myth_flat, 0) + GREATEST(v_pet_flat, 0), 9);

  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_ton_gain, 9),
         hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_myth_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
  RETURNING hero_mining_unclaimed_ton INTO v_out;

  RETURN COALESCE(v_out, 0);
END $$;

-- ============================================================
-- 9. Admin Bot — PREMIUM OFFERS hub
-- ============================================================
create or replace function public.admin_premium_offers_overview(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare fc public.founder_pack_config; vc public.veteran_vault_v2_config;
begin
  perform public.admin_assert(p_admin_id);
  fc := public.founder_pack_settings();
  select * into vc from public.veteran_vault_v2_config where id;
  return jsonb_build_object(
    'timezone', public.premium_offer_timezone(),
    'dayKey', public.premium_offer_day_key(),
    'mythPoolAvailable', public.myth_mining_pool_available(),
    'pools', coalesce((select jsonb_object_agg(offer_type, jsonb_build_object(
        'allocated', allocated_myth, 'distributed', distributed_myth))
        from public.premium_myth_mining_pools), '{}'::jsonb),
    'founder', jsonb_build_object(
      'enabled', fc.enabled, 'popupEnabled', fc.popup_enabled, 'popupFrequency', fc.popup_frequency,
      'priceTon', fc.price_ton, 'startAt', fc.start_at, 'endsAt', fc.ends_at,
      'requireNewAccount', fc.require_new_account, 'mythAmount', fc.myth_amount,
      'fragments', fc.fragments, 'legendaryChests', fc.legendary_chests, 'weaponCode', fc.weapon_code,
      'heroDailyMyth', fc.hero_daily_myth, 'petDailyMyth', fc.pet_daily_myth,
      'purchases', (select count(*) from public.founder_pack_purchases where status = 'settled'),
      'popupsToday', (select count(*) from public.premium_offer_popup_views
                       where offer_type = 'FOUNDER_PACK' and day_key = public.premium_offer_day_key())),
    'veteran', jsonb_build_object(
      'enabled', vc.enabled, 'salesPaused', vc.sales_paused, 'popupEnabled', vc.popup_enabled,
      'popupFrequency', vc.popup_frequency, 'priceTon', vc.price_ton,
      'startAt', vc.start_at, 'endsAt', vc.ends_at, 'boostPercent', vc.boost_percent,
      'heroDailyMyth', vc.hero_daily_myth, 'petDailyMyth', vc.pet_daily_myth,
      'dragonDailyMyth', vc.dragon_daily_myth,
      'purchases', (select count(*) from public.veteran_vault_v2_purchases where status in ('paid','delivered')),
      'popupsToday', (select count(*) from public.premium_offer_popup_views
                       where offer_type = 'VETERAN_VAULT' and day_key = public.premium_offer_day_key())));
end $$;

create or replace function public.admin_premium_offers_set(p_admin_id bigint, p_offer text, p_field text, p_value text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_bool boolean; v_num numeric; v_ts timestamptz;
begin
  perform public.admin_assert(p_admin_id);
  v_bool := lower(coalesce(p_value,'')) in ('1','true','t','on','yes');

  if p_offer = 'TIMEZONE' then
    insert into public.premium_offer_settings(id, reset_timezone) values (true, p_value)
      on conflict (id) do update set reset_timezone = excluded.reset_timezone, updated_at = now();
  elsif p_offer = 'FOUNDER_PACK' then
    if p_field = 'enabled' then
      update public.founder_pack_config set enabled = v_bool, updated_at = now() where id;
    elsif p_field = 'popup' then
      update public.founder_pack_config set popup_enabled = v_bool, updated_at = now() where id;
    elsif p_field = 'frequency' then
      if p_value not in ('ONCE_PER_SESSION','ONCE_PER_DAY','UNTIL_PURCHASED','DISABLED') then raise exception 'INVALID_VALUE'; end if;
      update public.founder_pack_config set popup_frequency = p_value, updated_at = now() where id;
    elsif p_field = 'price' then
      v_num := p_value::numeric; if v_num <= 0 then raise exception 'INVALID_VALUE'; end if;
      update public.founder_pack_config set price_ton = v_num, pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'start' then
      v_ts := p_value::timestamptz;
      update public.founder_pack_config set start_at = v_ts, updated_at = now() where id;
    elsif p_field = 'end' then
      v_ts := nullif(p_value,'')::timestamptz;
      update public.founder_pack_config set ends_at = v_ts, updated_at = now() where id;
    elsif p_field = 'newaccount' then
      update public.founder_pack_config set require_new_account = v_bool, updated_at = now() where id;
    elsif p_field = 'heromyth' then
      update public.founder_pack_config set hero_daily_myth = greatest(0, p_value::numeric), pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'petmyth' then
      update public.founder_pack_config set pet_daily_myth = greatest(0, p_value::numeric), pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'chests' then
      update public.founder_pack_config set legendary_chests = greatest(1, p_value::int), pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'weapon' then
      if not exists (select 1 from public.equipment_templates where code = p_value) then raise exception 'WEAPON_NOT_FOUND'; end if;
      update public.founder_pack_config set weapon_code = p_value, pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'pool' then
      v_num := greatest(0, p_value::numeric);
      insert into public.premium_myth_mining_pools(offer_type, allocated_myth) values ('FOUNDER_PACK', v_num)
        on conflict (offer_type) do update set allocated_myth = public.premium_myth_mining_pools.allocated_myth + v_num, updated_at = now();
      update public.myth_mining_pool set allocated_myth = allocated_myth + v_num, updated_at = now() where id;
    else raise exception 'UNKNOWN_FIELD';
    end if;
  elsif p_offer = 'VETERAN_VAULT' then
    if p_field = 'enabled' then
      update public.veteran_vault_v2_config set enabled = v_bool, updated_at = now() where id;
    elsif p_field = 'popup' then
      update public.veteran_vault_v2_config set popup_enabled = v_bool, updated_at = now() where id;
    elsif p_field = 'frequency' then
      if p_value not in ('ONCE_PER_SESSION','ONCE_PER_DAY','UNTIL_PURCHASED','DISABLED') then raise exception 'INVALID_VALUE'; end if;
      update public.veteran_vault_v2_config set popup_frequency = p_value, updated_at = now() where id;
    elsif p_field = 'price' then
      v_num := p_value::numeric; if v_num <= 0 then raise exception 'INVALID_VALUE'; end if;
      update public.veteran_vault_v2_config set price_ton = v_num, updated_at = now() where id;
    elsif p_field = 'start' then
      update public.veteran_vault_v2_config set start_at = p_value::timestamptz, updated_at = now() where id;
    elsif p_field = 'end' then
      update public.veteran_vault_v2_config set ends_at = nullif(p_value,'')::timestamptz, updated_at = now() where id;
    elsif p_field = 'boost' then
      update public.veteran_vault_v2_config set boost_percent = greatest(0, p_value::numeric), updated_at = now() where id;
    elsif p_field = 'heromyth' then
      update public.veteran_vault_v2_config set hero_daily_myth = greatest(0, p_value::numeric), updated_at = now() where id;
    elsif p_field = 'petmyth' then
      update public.veteran_vault_v2_config set pet_daily_myth = greatest(0, p_value::numeric), updated_at = now() where id;
    elsif p_field = 'dragonmyth' then
      update public.veteran_vault_v2_config set dragon_daily_myth = greatest(0, p_value::numeric), updated_at = now() where id;
    elsif p_field = 'pool' then
      v_num := greatest(0, p_value::numeric);
      insert into public.premium_myth_mining_pools(offer_type, allocated_myth) values ('VETERAN_VAULT', v_num)
        on conflict (offer_type) do update set allocated_myth = public.premium_myth_mining_pools.allocated_myth + v_num, updated_at = now();
      update public.myth_mining_pool set allocated_myth = allocated_myth + v_num, updated_at = now() where id;
    else raise exception 'UNKNOWN_FIELD';
    end if;
  else raise exception 'UNKNOWN_OFFER';
  end if;

  perform public.admin_log(p_admin_id, 'premium_offers.set', 'config', p_offer || ':' || p_field, null,
    jsonb_build_object('offer', p_offer, 'field', p_field, 'value', p_value), null);
  return public.admin_premium_offers_overview(p_admin_id);
end $$;