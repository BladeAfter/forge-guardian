-- 1) NFT delivery must NOT flag heroes/pets as market-locked (that flag means "listed in marketplace"
--    and blocks equipping via market guard triggers). Non-tradable is enforced by tradable=false.

CREATE OR REPLACE FUNCTION public.nft_hero_assign_unit(p_nft_id uuid, p_user_id uuid, p_source text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
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

  update public.nft_heroes set owner_user_id = p_user_id, player_hero_id = v_hero, status = 'OWNED',
      assigned_at = now(), revoked_at = null, updated_at = now()
   where id = n.id;
  insert into public.nft_hero_history (nft_hero_id, action, to_user_id, reason)
  values (n.id, 'PURCHASED', p_user_id, p_source);

  return jsonb_build_object('status', 'completed', 'playerHeroId', v_hero, 'serial', n.nft_serial,
    'heroName', c.name, 'instance', n.unique_instance_id,
    'atk', round(coalesce(ph.final_atk, 0)), 'hp', round(coalesce(ph.final_hp, 0)));
end $fn$;

CREATE OR REPLACE FUNCTION public.admin_nft_hero_give(p_admin_id bigint, p_ref text, p_nft_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
declare v_uid uuid; n public.nft_heroes; c public.hero_catalog; v_hero uuid; g record; ph public.player_heroes;
begin
  perform public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  select * into n from nft_heroes where id = p_nft_id for update;
  if n.id is null then raise exception 'NFT_HERO_NOT_FOUND'; end if;
  if n.status = 'OWNED' or n.owner_user_id is not null then raise exception 'NFT_HERO_ALREADY_OWNED'; end if;
  if n.status = 'BURNED' then raise exception 'NFT_HERO_BURNED'; end if;
  select * into c from hero_catalog where hero_key = n.hero_template_id;

  insert into player_heroes (user_id, hero_key, name, rarity, level, image, archetype,
      is_nft_exclusive, nft_hero_id, nft_serial, nft_instance_id, tradable, market_locked, locked)
    values (v_uid, c.hero_key, c.name, 'nft_exclusive', greatest(1, coalesce(n.level,1)), c.image, c.hero_class,
      true, n.id, n.nft_serial, n.unique_instance_id, false, false, false)
    returning id into v_hero;
  select * into ph from player_heroes where id = v_hero;

  update nft_heroes set owner_user_id = v_uid, player_hero_id = v_hero, status = 'OWNED',
      assigned_at = now(), revoked_at = null, updated_at = now()
   where id = n.id;
  insert into nft_hero_history (nft_hero_id, action, admin_telegram_id, to_user_id, reason)
    values (n.id, 'DELIVERED', p_admin_id, v_uid, p_reason);
  perform public.admin_log(p_admin_id,'nft_hero.give','player',v_uid::text,null,
    jsonb_build_object('nft', n.unique_instance_id, 'hero', c.hero_key, 'player_hero_id', v_hero), p_reason);

  select name, telegram_id into g from game_players where id = v_uid;
  return jsonb_build_object('hero', c.name, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
    'playerName', g.name, 'telegramId', g.telegram_id, 'playerHeroId', v_hero,
    'atk', round(ph.final_atk), 'hp', round(ph.final_hp),
    'power', round(ph.final_atk * 2 + ph.final_hp));
end $fn$;

CREATE OR REPLACE FUNCTION public.nft_assign_unit(p_nft_id uuid, p_user_id uuid, p_source text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
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
         assigned_at = now(), revoked_at = null, for_sale = for_sale, updated_at = now(),
         metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('tier_ton', coalesce(tier_ton, 20))
   where id = n.id;

  insert into public.nft_pet_history (nft_pet_id, action, to_user_id, reason, metadata)
  values (n.id, 'PURCHASED', p_user_id, p_source, jsonb_build_object('serial', n.nft_serial, 'priceTon', n.price_ton));

  perform public.nft_pool_sync_positions();

  return jsonb_build_object('status', 'completed', 'playerPetId', v_pp, 'serial', n.nft_serial,
    'petName', pt.name, 'instance', n.unique_instance_id);
end $fn$;

CREATE OR REPLACE FUNCTION public.admin_nft_give(p_admin_id bigint, p_ref text, p_nft_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
declare v_uid uuid; n public.nft_pets; pt public.pets; v_pp uuid; g record;
begin
  perform public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  select * into n from nft_pets where id = p_nft_id for update;
  if n.id is null then raise exception 'NFT_NOT_FOUND'; end if;
  if n.status = 'OWNED' or n.owner_user_id is not null then raise exception 'NFT_ALREADY_OWNED'; end if;
  if n.status = 'BURNED' then raise exception 'NFT_BURNED'; end if;
  select * into pt from pets where id = n.pet_template_id;

  insert into player_pets (user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active, tradable, market_locked, nft_pet_id)
  values (v_uid, pt.id, pt.rarity, 1, 0, 'baby', 0, false, false, false, n.id)
  returning id into v_pp;

  update nft_pets set owner_user_id = v_uid, player_pet_id = v_pp, status = 'OWNED',
      assigned_at = now(), revoked_at = null, updated_at = now()
   where id = n.id;
  insert into nft_pet_history (nft_pet_id, action, admin_telegram_id, to_user_id, reason)
    values (n.id, 'DELIVERED', p_admin_id, v_uid, p_reason);
  perform public.admin_log(p_admin_id,'nft.give','player',v_uid::text,null,
    jsonb_build_object('nft', n.unique_instance_id, 'pet', pt.slug, 'player_pet_id', v_pp), p_reason);

  select name, telegram_id into g from game_players where id = v_uid;
  return jsonb_build_object('pet', pt.name, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
    'playerName', g.name, 'telegramId', g.telegram_id, 'playerPetId', v_pp);
end $fn$;

-- 2) Repair existing NFT heroes/pets stuck as market-locked without an active listing.
UPDATE public.player_heroes h
   SET market_locked = false, locked = false, updated_at = now()
 WHERE h.is_nft_exclusive
   AND (h.market_locked OR h.locked)
   AND NOT EXISTS (
     SELECT 1 FROM public.market_listings l
      WHERE l.item_instance_id = h.id AND l.status = 'active');

UPDATE public.player_pets p
   SET market_locked = false, updated_at = now()
 WHERE p.nft_pet_id IS NOT NULL
   AND p.market_locked
   AND NOT EXISTS (
     SELECT 1 FROM public.market_listings l
      WHERE l.item_instance_id = p.id AND l.status = 'active');