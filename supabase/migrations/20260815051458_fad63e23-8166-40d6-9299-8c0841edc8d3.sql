-- ============================================================
-- NFT EXCLUSIVE: rotação de vitrine + reabastecimento sem reciclagem
-- ============================================================

-- 1. Slots ativos por faixa (rotação da loja)
CREATE TABLE IF NOT EXISTS public.nft_rotation_targets (
  kind text NOT NULL CHECK (kind IN ('hero','pet')),
  tier_ton numeric NOT NULL,
  active_slots integer NOT NULL CHECK (active_slots >= 0),
  daily_yield_ton numeric,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (kind, tier_ton)
);
GRANT ALL ON public.nft_rotation_targets TO service_role;
ALTER TABLE public.nft_rotation_targets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rotation_targets_service" ON public.nft_rotation_targets FOR ALL TO service_role USING (true) WITH CHECK (true);

INSERT INTO public.nft_rotation_targets (kind, tier_ton, active_slots, daily_yield_ton) VALUES
  ('hero', 20, 4, 0.50), ('hero', 30, 3, 0.75), ('hero', 50, 3, 1.25),
  ('pet', 20, 5, 0.35), ('pet', 30, 5, 0.60)
ON CONFLICT (kind, tier_ton) DO UPDATE
  SET active_slots = excluded.active_slots, daily_yield_ton = excluded.daily_yield_ton, updated_at = now();

-- 2. Reserva de unidades inéditas (nome/arte nunca usados)
CREATE TABLE IF NOT EXISTS public.nft_stock_pool (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('hero','pet')),
  tier_ton numeric NOT NULL,
  template_ref text NOT NULL,
  asset_key text NOT NULL,
  display_name text NOT NULL,
  name_norm text NOT NULL,
  element text,
  released_nft_id uuid,
  released_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS nft_stock_pool_asset_uidx ON public.nft_stock_pool (asset_key);
CREATE UNIQUE INDEX IF NOT EXISTS nft_stock_pool_name_uidx ON public.nft_stock_pool (kind, name_norm);
CREATE UNIQUE INDEX IF NOT EXISTS nft_stock_pool_ref_uidx ON public.nft_stock_pool (kind, template_ref);
GRANT ALL ON public.nft_stock_pool TO service_role;
ALTER TABLE public.nft_stock_pool ENABLE ROW LEVEL SECURITY;
CREATE POLICY "stock_pool_service" ON public.nft_stock_pool FOR ALL TO service_role USING (true) WITH CHECK (true);

-- 3. Geração / retirada da vitrine (o NFT vendido nunca volta)
ALTER TABLE public.nft_heroes ADD COLUMN IF NOT EXISTS generation integer NOT NULL DEFAULT 1;
ALTER TABLE public.nft_heroes ADD COLUMN IF NOT EXISTS rotation_retired_at timestamptz;
ALTER TABLE public.nft_pets ADD COLUMN IF NOT EXISTS generation integer NOT NULL DEFAULT 1;
ALTER TABLE public.nft_pets ADD COLUMN IF NOT EXISTS rotation_retired_at timestamptz;

-- 4. Travas de unicidade permanente
CREATE UNIQUE INDEX IF NOT EXISTS nft_heroes_instance_uidx ON public.nft_heroes (unique_instance_id);
CREATE UNIQUE INDEX IF NOT EXISTS nft_pets_instance_uidx ON public.nft_pets (unique_instance_id);
CREATE UNIQUE INDEX IF NOT EXISTS hero_catalog_nft_name_uidx ON public.hero_catalog (lower(name)) WHERE is_nft_exclusive;
CREATE UNIQUE INDEX IF NOT EXISTS hero_catalog_nft_image_uidx ON public.hero_catalog (image) WHERE is_nft_exclusive;
CREATE UNIQUE INDEX IF NOT EXISTS pets_nft_name_uidx ON public.pets (lower(name)) WHERE is_nft_exclusive;
CREATE UNIQUE INDEX IF NOT EXISTS pets_nft_image_uidx ON public.pets (image_base_url) WHERE is_nft_exclusive;

-- 5. Estoque por faixa
CREATE OR REPLACE FUNCTION public.nft_stock_json(p_kind text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
declare res jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
      'kind', t.kind, 'tierTon', round(t.tier_ton, 9), 'slots', t.active_slots,
      'dailyYieldTon', round(coalesce(t.daily_yield_ton, 0), 9),
      'available', coalesce(a.available, 0),
      'soldTotal', coalesce(s.sold_total, 0),
      'poolLeft', coalesce(p.pool_left, 0),
      'missing', greatest(0, t.active_slots - coalesce(a.available, 0))
    ) order by t.kind, t.tier_ton), '[]'::jsonb) into res
  from public.nft_rotation_targets t
  left join lateral (
    select count(*) available from (
      select 1 from public.nft_heroes n
       where t.kind = 'hero' and n.for_sale and n.status = 'AVAILABLE' and n.owner_user_id is null
         and n.rotation_retired_at is null and coalesce(n.tier_ton, n.price_ton) = t.tier_ton
      union all
      select 1 from public.nft_pets n
       where t.kind = 'pet' and n.for_sale and n.status = 'AVAILABLE' and n.owner_user_id is null
         and n.rotation_retired_at is null and coalesce(n.tier_ton, n.price_ton) = t.tier_ton
    ) q
  ) a on true
  left join lateral (
    select count(*) sold_total from (
      select 1 from public.nft_heroes n
       where t.kind = 'hero' and n.owner_user_id is not null and coalesce(n.tier_ton, n.price_ton) = t.tier_ton
      union all
      select 1 from public.nft_pets n
       where t.kind = 'pet' and n.owner_user_id is not null and coalesce(n.tier_ton, n.price_ton) = t.tier_ton
    ) q
  ) s on true
  left join lateral (
    select count(*) pool_left from public.nft_stock_pool sp
     where sp.kind = t.kind and sp.tier_ton = t.tier_ton and sp.released_nft_id is null
  ) p on true
  where p_kind is null or t.kind = p_kind;
  return jsonb_build_object('tiers', res);
end $$;
REVOKE ALL ON FUNCTION public.nft_stock_json(text) FROM PUBLIC, anon, authenticated;

-- 6. Reabastecimento (nunca recicla NFT vendido)
CREATE OR REPLACE FUNCTION public.nft_refill_stock(p_kind text, p_admin_id bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare
  k text := lower(coalesce(p_kind, ''));
  t record; pool public.nft_stock_pool; need int; avail int; i int;
  created jsonb := '[]'::jsonb; shortages jsonb := '[]'::jsonb;
  v_serial int; v_inst text; v_gen int; v_id uuid; hc public.hero_catalog; pt public.pets;
begin
  if k not in ('hero','pet') then raise exception 'NFT_KIND_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nft_refill:'||k, 0));

  -- vendidos saem da vitrine (ownership, série, instância e histórico intactos)
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
            jsonb_build_object('tier_ton', t.tier_ton, 'rotation_generation', v_gen, 'asset_key', pool.asset_key))
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
            price_ton, tier_ton, for_sale, generation, created_by_admin, element, appearance_family, metadata)
        values (pt.id, v_serial, v_inst, 'AVAILABLE', false,
            t.tier_ton, t.tier_ton, true, v_gen, p_admin_id, pool.element, pool.element,
            jsonb_build_object('tier_ton', t.tier_ton, 'rotation_generation', v_gen, 'asset_key', pool.asset_key))
        returning id into v_id;
        insert into public.nft_pet_history (nft_pet_id, action, admin_telegram_id, reason, metadata)
        values (v_id, 'CREATED', p_admin_id, 'rotation_refill',
                jsonb_build_object('serial', v_serial, 'instance', v_inst, 'tierTon', t.tier_ton));
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
end $$;
REVOKE ALL ON FUNCTION public.nft_refill_stock(text, bigint) FROM PUBLIC, anon, authenticated;

-- 7. Reabastecimento automático após cada venda
CREATE OR REPLACE FUNCTION public.nft_rotation_after_sale(p_kind text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
begin
  begin
    perform public.nft_refill_stock(p_kind, null);
  exception when others then
    raise warning 'NFT_REFILL_FAILED %', sqlerrm;
  end;
end $$;
REVOKE ALL ON FUNCTION public.nft_rotation_after_sale(text) FROM PUBLIC, anon, authenticated;

-- 8. Admin: visão de estoque + refill manual
CREATE OR REPLACE FUNCTION public.admin_nft_stock_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
begin
  perform public.admin_assert(p_admin_id);
  return jsonb_build_object('hero', public.nft_stock_json('hero'), 'pet', public.nft_stock_json('pet'));
end $$;
REVOKE ALL ON FUNCTION public.admin_nft_stock_overview(bigint) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_nft_stock_refill(p_admin_id bigint, p_kind text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
begin
  perform public.admin_assert(p_admin_id);
  return public.nft_refill_stock(p_kind, p_admin_id);
end $$;
REVOKE ALL ON FUNCTION public.admin_nft_stock_refill(bigint, text) FROM PUBLIC, anon, authenticated;
