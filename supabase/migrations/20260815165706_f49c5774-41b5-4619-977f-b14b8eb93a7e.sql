CREATE OR REPLACE FUNCTION public.nft_refill_stock(p_kind text, p_admin_id bigint DEFAULT NULL::bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare
  k text := lower(coalesce(p_kind, ''));
  t record; pool public.nft_stock_pool; need int; avail int; i int;
  created jsonb := '[]'::jsonb; shortages jsonb := '[]'::jsonb;
  v_serial int; v_inst text; v_gen int; v_id uuid; hc public.hero_catalog; pt public.pets;
begin
  if k not in ('hero','pet') then raise exception 'NFT_KIND_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nft_refill:'||k, 0));

  if k = 'hero' then
    update public.nft_heroes set for_sale = false, rotation_retired_at = now(), updated_at = now()
     where for_sale and rotation_retired_at is null and (owner_user_id is not null or status <> 'AVAILABLE');
  else
    update public.nft_pets set for_sale = false, rotation_retired_at = now(), updated_at = now()
     where for_sale and rotation_retired_at is null and (owner_user_id is not null or status <> 'AVAILABLE');
  end if;

  for t in select * from public.nft_rotation_targets where kind = k order by tier_ton loop
    if k = 'hero' then
      select count(*) into avail from public.nft_heroes n
       where n.for_sale and n.status = 'AVAILABLE' and n.owner_user_id is null
         and n.rotation_retired_at is null and coalesce(n.tier_ton, n.price_ton) = t.tier_ton;
    else
      select count(*) into avail from public.nft_pets n
       where n.for_sale and n.status = 'AVAILABLE' and n.owner_user_id is null
         and n.rotation_retired_at is null and coalesce(n.tier_ton, n.price_ton) = t.tier_ton;
    end if;
    need := greatest(0, t.active_slots - avail);

    for i in 1..need loop
      select * into pool from public.nft_stock_pool sp
       where sp.kind = k and sp.tier_ton = t.tier_ton and sp.released_nft_id is null
       order by sp.created_at, sp.id for update skip locked limit 1;
      if pool.id is null then
        shortages := shortages || jsonb_build_object('tierTon', t.tier_ton, 'missing', need - (i - 1));
        exit;
      end if;

      if k = 'hero' then
        select * into hc from public.hero_catalog where hero_key = pool.template_ref and is_nft_exclusive;
        if hc.hero_key is null then raise exception 'NFT_TEMPLATE_NOT_FOUND'; end if;
        if exists (select 1 from public.nft_heroes where hero_template_id = hc.hero_key) then
          raise exception 'NFT_TEMPLATE_ALREADY_RELEASED';
        end if;
        select coalesce(max(nft_serial), 0) + 1 into v_serial from public.nft_heroes;
        select coalesce(max(generation), 0) + 1 into v_gen from public.nft_heroes
         where coalesce(tier_ton, price_ton) = t.tier_ton;
        v_inst := 'NFT-HERO-' || upper(regexp_replace(pool.display_name, '[^a-zA-Z0-9]', '', 'g'))
                  || '-' || lpad(v_serial::text, 4, '0');
        insert into public.nft_heroes (hero_template_id, nft_serial, unique_instance_id, status, minted,
            price_ton, tier_ton, mining_daily_ton, for_sale, generation, created_by_admin,
            metadata)
        values (hc.hero_key, v_serial, v_inst, 'AVAILABLE', false,
            t.tier_ton, t.tier_ton, t.daily_yield_ton, true, v_gen, p_admin_id,
            jsonb_build_object('tier_ton', t.tier_ton, 'rotation_generation', v_gen, 'asset_key', pool.asset_key,
                               'mint_daily_yield_ton', t.daily_yield_ton))
        returning id into v_id;
        insert into public.nft_hero_history (nft_hero_id, action, admin_telegram_id, reason)
        values (v_id, 'CREATED', p_admin_id, 'rotation_refill');
      else
        select * into pt from public.pets where slug = pool.template_ref and is_nft_exclusive;
        if pt.id is null then raise exception 'NFT_TEMPLATE_NOT_FOUND'; end if;
        if exists (select 1 from public.nft_pets where pet_template_id = pt.id) then
          raise exception 'NFT_TEMPLATE_ALREADY_RELEASED';
        end if;
        select coalesce(max(nft_serial), 0) + 1 into v_serial from public.nft_pets;
        select coalesce(max(generation), 0) + 1 into v_gen from public.nft_pets
         where coalesce(tier_ton, price_ton) = t.tier_ton;
        v_inst := 'NFT-PET-' || upper(regexp_replace(pool.display_name, '[^a-zA-Z0-9]', '', 'g'))
                  || '-' || lpad(v_serial::text, 4, '0');
        insert into public.nft_pets (pet_template_id, nft_serial, unique_instance_id, status, minted,
            price_ton, tier_ton, daily_yield_ton, for_sale, generation, created_by_admin, element, appearance_family, metadata)
        values (pt.id, v_serial, v_inst, 'AVAILABLE', false,
            t.tier_ton, t.tier_ton, t.daily_yield_ton, true, v_gen, p_admin_id, pool.element, pool.element,
            jsonb_build_object('tier_ton', t.tier_ton, 'rotation_generation', v_gen, 'asset_key', pool.asset_key,
                               'mint_daily_yield_ton', t.daily_yield_ton))
        returning id into v_id;
        insert into public.nft_pet_history (nft_pet_id, action, admin_telegram_id, reason, metadata)
        values (v_id, 'CREATED', p_admin_id, 'rotation_refill',
                jsonb_build_object('serial', v_serial, 'instance', v_inst, 'tierTon', t.tier_ton,
                                   'dailyYieldTon', t.daily_yield_ton));
      end if;

      update public.nft_stock_pool set released_nft_id = v_id, released_at = now() where id = pool.id;
      created := created || jsonb_build_object('id', v_id, 'kind', k, 'name', pool.display_name,
        'serial', v_serial, 'instance', v_inst, 'tierTon', t.tier_ton,
        'dailyYieldTon', t.daily_yield_ton, 'generation', v_gen);
    end loop;
  end loop;

  if p_admin_id is not null then
    perform public.admin_log(p_admin_id, 'nft.refill', k, null, null,
      jsonb_build_object('created', created, 'shortages', shortages), 'NFT rotation refill');
  end if;
  return jsonb_build_object('kind', k, 'created', created, 'shortages', shortages,
    'stock', public.nft_stock_json(k));
end $function$;