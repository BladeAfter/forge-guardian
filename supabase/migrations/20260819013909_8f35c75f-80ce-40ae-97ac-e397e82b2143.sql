-- MYTH budget includes the immediate 150k grant: everything comes out of the funded Veteran MYTH pool.
create or replace function public.veteran_vault_myth_budget()
returns numeric language sql stable security definer set search_path to 'public' as $$
  select c.initial_myth
       + c.daily_myth * greatest(1, c.cycle_days)
       + coalesce((select sum(value::numeric) from jsonb_each_text(c.reward_schedule->'mythBonus')), 0)
       + coalesce((c.final_reward->>'myth')::numeric, 0)
  from public.veteran_vault_config c where c.id
$$;
revoke all on function public.veteran_vault_myth_budget() from public, anon, authenticated;

-- Atomic immediate delivery + activation of the 45-day cycle.
create or replace function public.veteran_vault_deliver(p_purchase_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare o public.veteran_vault_purchases; s jsonb; hc public.hero_catalog; pt public.pets;
        v_hero uuid; v_pet uuid; v_season uuid; v_delivery jsonb := '{}'::jsonb; v_myth numeric; i int;
begin
  select * into o from public.veteran_vault_purchases where id = p_purchase_id for update;
  if o.id is null then raise exception 'VETERAN_VAULT_ORDER_NOT_FOUND'; end if;
  if o.status = 'settled' then
    return jsonb_build_object('ok', true, 'alreadySettled', true, 'purchaseId', o.id, 'delivery', o.delivery);
  end if;
  if o.status <> 'paid' then raise exception 'VETERAN_VAULT_NOT_PAID'; end if;
  s := o.reward_snapshot;

  -- 1) Current premium season pass
  v_season := nullif(s->>'seasonId','')::uuid;
  if v_season is null then
    select id into v_season from public.season_pass_seasons where active order by created_at desc limit 1;
  end if;
  if v_season is not null then
    perform public.season_pass_apply_entitlement(o.user_id, v_season, coalesce(s->>'passTier','legendary'));
    v_delivery := v_delivery || jsonb_build_object('pass', jsonb_build_object('seasonId', v_season, 'tier', coalesce(s->>'passTier','legendary')));
  end if;

  -- 2) Immediate MYTH, taken from the funded Veteran MYTH pool (no new supply is minted)
  v_myth := coalesce((s->>'initialMyth')::numeric, 0);
  if v_myth > 0 then
    insert into public.myth_balances(user_id, amount) values (o.user_id, 0) on conflict (user_id) do nothing;
    update public.myth_balances set amount = amount + v_myth, updated_at = now() where user_id = o.user_id;
    insert into public.myth_ledger(user_id, direction, amount, reason)
      values (o.user_id, 'credit', v_myth, 'veteran_vault');
    update public.veteran_vault_pool
       set myth_reserved = greatest(0, myth_reserved - v_myth),
           myth_distributed = myth_distributed + v_myth, updated_at = now() where id;
    update public.veteran_vault_purchases
       set myth_reserved = greatest(0, myth_reserved - v_myth), myth_distributed = myth_distributed + v_myth
     where id = o.id;
    insert into public.veteran_vault_claims(purchase_id, user_id, reward_day, reward_type, myth_amount)
      values (o.id, o.user_id, 0, 'initial_myth', v_myth) on conflict do nothing;
    v_delivery := v_delivery || jsonb_build_object('myth', v_myth);
  end if;

  -- 3) Exclusive hero
  select * into hc from public.hero_catalog where hero_key = s->>'heroKey';
  if hc.hero_key is null then select * into hc from public.hero_catalog where rarity = 'mythic' order by random() limit 1; end if;
  if hc.hero_key is not null then
    insert into public.player_heroes(user_id, hero_key, name, rarity, level, image)
    values (o.user_id, hc.hero_key, hc.name, public.normalize_hero_rarity(hc.rarity), 1, hc.image)
    returning id into v_hero;
    v_delivery := v_delivery || jsonb_build_object('hero', jsonb_build_object('id', v_hero, 'heroKey', hc.hero_key, 'name', hc.name));
  end if;

  -- 4) Exclusive / mythic pet
  select * into pt from public.pets where slug = s->>'petSlug' and not coalesce(is_nft_exclusive,false);
  if pt.id is null then
    select * into pt from public.pets where rarity = 'mythic' and not coalesce(is_nft_exclusive,false) order by random() limit 1;
  end if;
  if pt.id is not null then
    insert into public.player_pets(user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active)
    values (o.user_id, pt.id, public.normalize_pet_rarity(pt.rarity), 1, 0, 'baby', 0, false)
    returning id into v_pet;
    v_delivery := v_delivery || jsonb_build_object('pet', jsonb_build_object('id', v_pet, 'slug', pt.slug, 'name', pt.name));
  end if;

  -- 5) Legendary equipment chest
  insert into public.player_inventory(user_id, item_type, item_code, quantity)
  values (o.user_id, 'hero_chest', coalesce(s->>'equipmentChestCode','legendary_chest'), 1)
  on conflict (user_id, item_type, item_code)
    do update set quantity = public.player_inventory.quantity + 1, updated_at = now();

  -- 6) Universal fragments
  if coalesce((s->>'fragments')::int, 0) > 0 then
    perform public.add_universal_fragments(o.user_id, (s->>'fragments')::int);
  end if;

  -- 7) Premium resource chests
  i := greatest(1, coalesce((s->>'resourceChestQty')::int, 2));
  insert into public.player_inventory(user_id, item_type, item_code, quantity)
  values (o.user_id, 'resource_chest', coalesce(s->>'resourceChestCode','premium_resource_chest'), i)
  on conflict (user_id, item_type, item_code)
    do update set quantity = public.player_inventory.quantity + i, updated_at = now();

  -- 8/9) Veteran cosmetics
  if coalesce((s->>'badge')::boolean, true) then
    insert into public.player_entitlements(user_id, code, source) values (o.user_id, 'veteran_badge', 'veteran_vault')
      on conflict (user_id, code) do nothing;
  end if;
  if coalesce((s->>'frame')::boolean, true) then
    insert into public.player_entitlements(user_id, code, source, equipped) values (o.user_id, 'veteran_frame', 'veteran_vault', true)
      on conflict (user_id, code) do nothing;
  end if;

  v_delivery := v_delivery || jsonb_build_object(
    'equipmentChest', coalesce(s->>'equipmentChestCode','legendary_chest'),
    'fragments', coalesce((s->>'fragments')::int, 0),
    'resourceChest', coalesce(s->>'resourceChestCode','premium_resource_chest'),
    'resourceChestQty', i, 'badge', coalesce((s->>'badge')::boolean, true),
    'frame', coalesce((s->>'frame')::boolean, true));

  update public.veteran_vault_purchases
     set status = 'settled', settled_at = now(), delivery = v_delivery,
         cycle_start_at = coalesce(cycle_start_at, coalesce(confirmed_at, now())),
         cycle_end_at = coalesce(cycle_end_at, coalesce(confirmed_at, now()) + make_interval(days => greatest(1, coalesce((s->>'cycleDays')::int, 45))))
   where id = o.id;

  insert into public.veteran_vault_ledger(purchase_id, user_id, kind, myth_amount, note)
    values (o.id, o.user_id, 'initial_delivery', v_myth, 'veteran vault immediate rewards');

  insert into public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  values (o.user_id, 'veteran_vault', 'VETERAN VAULT ACTIVE',
          'Your Veteran Vault rewards were delivered and the 45-day cycle started.', v_delivery, 'veteran_vault:' || o.id::text)
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'purchaseId', o.id, 'delivery', v_delivery);
end $$;
revoke all on function public.veteran_vault_deliver(uuid) from public, anon, authenticated;