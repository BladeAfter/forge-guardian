CREATE OR REPLACE FUNCTION public.nft_hero_assign_unit(p_nft_id uuid, p_user_id uuid, p_source text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
      true, n.id, n.nft_serial, n.unique_instance_id, false, false, false)
  returning id into v_hero;
  select * into ph from public.player_heroes where id = v_hero;

  -- Unidade 1/1 permanece do comprador e sai da vitrine (nunca volta a AVAILABLE)
  update public.nft_heroes set owner_user_id = p_user_id, player_hero_id = v_hero, status = 'OWNED',
      assigned_at = now(), revoked_at = null, updated_at = now(),
      for_sale = false, rotation_retired_at = coalesce(rotation_retired_at, now())
   where id = n.id;
  insert into public.nft_hero_history (nft_hero_id, action, to_user_id, reason)
  values (n.id, 'PURCHASED', p_user_id, p_source);

  perform public.nft_rotation_after_sale('hero');

  return jsonb_build_object('status', 'completed', 'playerHeroId', v_hero, 'serial', n.nft_serial,
    'heroName', c.name, 'instance', n.unique_instance_id,
    'atk', round(coalesce(ph.final_atk, 0)), 'hp', round(coalesce(ph.final_hp, 0)));
end $function$;

CREATE OR REPLACE FUNCTION public.nft_assign_unit(p_nft_id uuid, p_user_id uuid, p_source text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare n public.nft_pets; pt public.pets; v_pp uuid;
begin
  select * into n from public.nft_pets where id = p_nft_id for update;
  if n.id is null then raise exception 'NFT_NOT_FOUND'; end if;
  if n.status = 'BURNED' then raise exception 'NFT_BURNED'; end if;
  if n.owner_user_id is not null then
    if n.owner_user_id = p_user_id then
      return jsonb_build_object('status', 'already_delivered', 'playerPetId', n.player_pet_id, 'serial', n.nft_serial);
    end if;
    raise exception 'NFT_ALREADY_OWNED';
  end if;
  select * into pt from public.pets where id = n.pet_template_id;

  insert into public.player_pets (user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active, tradable, market_locked, nft_pet_id)
  values (p_user_id, pt.id, pt.rarity, 1, 0, 'baby', 0, false, false, false, n.id)
  returning id into v_pp;

  update public.nft_pets
     set owner_user_id = p_user_id, player_pet_id = v_pp, status = 'OWNED',
         assigned_at = now(), revoked_at = null, updated_at = now(),
         for_sale = false, rotation_retired_at = coalesce(rotation_retired_at, now()),
         metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('tier_ton', coalesce(tier_ton, 20))
   where id = n.id;

  insert into public.nft_pet_history (nft_pet_id, action, to_user_id, reason, metadata)
  values (n.id, 'PURCHASED', p_user_id, p_source, jsonb_build_object('serial', n.nft_serial, 'priceTon', n.price_ton));

  perform public.nft_pool_sync_positions();
  perform public.nft_rotation_after_sale('pet');

  return jsonb_build_object('status', 'completed', 'playerPetId', v_pp, 'serial', n.nft_serial,
    'petName', pt.name, 'instance', n.unique_instance_id);
end $function$;