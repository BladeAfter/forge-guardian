-- Season Pass exclusive chests: drop the "MÍTICO" wording and make the HERO chest
-- award heroes carrying the EXCLUSIVE tag (hero_catalog.rarity = 'nft_exclusive').
UPDATE public.season_pass_rewards
   SET title = 'BAÚ EXCLUSIVO DE HERÓI'
 WHERE reward_type = 'exclusive_chest' AND reward_code = 'exclusive-hero-chest';

UPDATE public.season_pass_rewards
   SET title = 'BAÚ EXCLUSIVO DE PET'
 WHERE reward_type = 'exclusive_chest' AND reward_code = 'exclusive-pet-chest';

CREATE OR REPLACE FUNCTION public.open_exclusive_chest(p_telegram_id bigint, p_inventory_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u uuid; inv player_inventory%rowtype; v_kind text; hc hero_catalog%rowtype; pt pets%rowtype;
  v_id uuid; v_seed int; v_reward jsonb; v_chest_code text; v_frag int;
begin
  select id into u from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('exclusive_chest:'||u::text, 7));

  select * into inv from player_inventory
    where id = p_inventory_item_id and user_id = u and item_type = 'exclusive_chest' for update;
  if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_FOUND'; end if;
  v_kind := case when inv.item_code ilike '%pet%' then 'pet' else 'hero' end;
  v_seed := (random()*1000000)::int;

  update player_inventory set quantity = quantity - 1, updated_at = now() where id = inv.id;
  delete from player_inventory where id = inv.id and quantity <= 0;

  if v_kind = 'hero' then
    -- EXCLUSIVE tag pool. The 1/1 NFT stock is untouched: the pass grants a
    -- collection copy only (pass_exclusive = true => no TON/MYTH mining, no NFT link).
    select * into hc from hero_catalog c
      where c.rarity = 'nft_exclusive' and coalesce(c.enabled, true)
        and not exists (select 1 from player_heroes h where h.user_id = u and h.hero_key = c.hero_key)
      order by random() limit 1;
    if hc.hero_key is null then
      select * into hc from hero_catalog c
        where c.rarity = 'nft_exclusive' and coalesce(c.enabled, true)
        order by random() limit 1;
    end if;
    if hc.hero_key is not null then
      insert into player_heroes(user_id, hero_key, name, rarity, level, image, attribute_seed, pass_exclusive)
      values (u, hc.hero_key, hc.name, 'nft_exclusive', 1, hc.image, v_seed, true) returning id into v_id;
      v_reward := jsonb_build_object('kind','hero','exclusive',true,'heroId',v_id,'heroKey',hc.hero_key,
        'name',hc.name,'rarity','nft_exclusive','image',hc.image,'title',hc.name,'mining',false);
    end if;
  else
    select * into pt from pets p
      where p.rarity = 'mythic' and coalesce(p.is_pass_exclusive, false) = false and coalesce(p.is_enabled, true)
        and not exists (select 1 from player_pets pp where pp.user_id = u and pp.pet_id = p.id)
      order by random() limit 1;
    if pt.id is null then
      select * into pt from pets p
        where p.rarity = 'mythic' and coalesce(p.is_pass_exclusive, false) = false and coalesce(p.is_enabled, true)
        order by random() limit 1;
    end if;
    if pt.id is not null then
      insert into player_pets(user_id, pet_id, rarity, level, xp, evolution_stage,
        is_season_exclusive, exclusive_badge, tradable, pass_exclusive)
      values (u, pt.id, 'mythic', 1, 0, 'baby', false, 'EXCLUSIVE', true, true) returning id into v_id;
      v_reward := jsonb_build_object('kind','pet','exclusive',true,'petId',v_id,'petSlug',pt.slug,
        'name',pt.name,'rarity','mythic','image',coalesce(pt.image_base_url, pt.image_baby_url),'title',pt.name,'mining',false);
    end if;
  end if;

  if v_reward is null then
    v_frag := add_universal_fragments(u, 100);
    select chest_code into v_chest_code from chest_reward_tables
      where enabled order by coalesce((rarity_rates->>'legendary')::numeric, 0) desc nulls last limit 1;
    if v_chest_code is not null then
      insert into player_inventory(user_id, item_type, item_code, quantity)
      values (u, 'hero_chest', v_chest_code, 1)
      on conflict(user_id, item_type, item_code)
        do update set quantity = player_inventory.quantity + 1, updated_at = now();
    end if;
    update game_players set forge_coins = forge_coins + 50000, updated_at = now() where id = u;
    v_reward := jsonb_build_object('kind','fallback','exclusive',true,'title','COLEÇÃO COMPLETA',
      'fragments',100,'fragmentBalance',v_frag,'chestCode',v_chest_code,'forgeCoins',50000);
  end if;

  insert into reward_open_logs(user_id, telegram_id, source, item_key, item_type, rolled_rarity, reward_id, reward_name)
  values (u, p_telegram_id, 'season_pass', inv.item_code, 'exclusive_chest',
          case when v_kind = 'hero' then 'nft_exclusive' else 'mythic' end, v_id, v_reward->>'name');

  return jsonb_build_object('reward', v_reward, 'chestCode', inv.item_code,
    'inventory', get_player_inventory(p_telegram_id));
end $function$;