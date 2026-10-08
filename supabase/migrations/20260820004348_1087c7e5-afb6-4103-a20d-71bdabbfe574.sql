create or replace function public.market_hero_details_json(p_hero_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare h record; c record; sk jsonb := '[]'::jsonb; pas jsonb := '[]'::jsonb; supply int;
begin
  select * into h from player_heroes where id = p_hero_id;
  if not found then return null; end if;
  select * into c from hero_catalog
   where hero_key = coalesce(h.hero_template_id, h.hero_key) or hero_key = h.hero_key
   limit 1;

  if c.skills is not null and jsonb_typeof(c.skills) = 'array' then sk := c.skills; end if;

  if c.nft_passive is not null and jsonb_typeof(c.nft_passive) = 'object' and c.nft_passive <> '{}'::jsonb then
    pas := pas || jsonb_build_array(c.nft_passive);
  end if;
  if h.exclusive_passive is not null and jsonb_typeof(h.exclusive_passive) = 'object' and h.exclusive_passive <> '{}'::jsonb then
    pas := pas || jsonb_build_array(h.exclusive_passive);
  end if;

  select count(*)::int into supply from nft_heroes n
   where n.hero_template_id = coalesce(h.hero_template_id, h.hero_key);

  return jsonb_build_object(
    'kind', 'hero',
    'name', h.name,
    'rarity', normalize_hero_rarity(h.rarity),
    'level', h.level,
    'image', h.image,
    'power', hero_power_value(h.final_atk, h.final_hp, coalesce(h.defense,0), h.level),
    'heroClass', coalesce(c.nft_class_label, c.hero_class, h.archetype),
    'role', h.archetype,
    'description', c.description,
    'fusionLevel', coalesce(h.fusion_level, 0),
    'stats', jsonb_strip_nulls(jsonb_build_object(
      'atk', round(coalesce(h.final_atk,0)),
      'hp', round(coalesce(h.final_hp,0)),
      'def', round(coalesce(h.defense,0)),
      'speed', round(coalesce(h.speed, h.level)),
      'critRate', round(coalesce(h.crit_rate,0)::numeric, 2),
      'skillPower', round(coalesce(h.skill_power,0)),
      'equipAtk', nullif(round(coalesce(h.equip_atk,0)),0),
      'equipDef', nullif(round(coalesce(h.equip_def,0)),0),
      'equipHp', nullif(round(coalesce(h.equip_hp,0)),0)
    )),
    'skills', sk,
    'passives', pas,
    'buffs', coalesce(c.buffs, '[]'::jsonb),
    'badges', (select coalesce(jsonb_agg(b), '[]'::jsonb) from (
        select 'nft_exclusive' as b where coalesce(h.is_nft_exclusive,false)
        union all select 'veteran' where coalesce(h.veteran_line,false)
        union all select 'founder' where lower(coalesce(h.premium_source,'')) like 'founder%'
        union all select 'pass_exclusive' where coalesce(h.pass_exclusive,false) or coalesce(h.is_season_exclusive,false)
      ) x),
    'miningMyth', round(coalesce(h.mining_daily_myth,0)::numeric, 4),
    'nft', case when coalesce(h.is_nft_exclusive,false) or h.nft_hero_id is not null
      then jsonb_build_object('serial', h.nft_serial, 'supply', nullif(supply,0), 'instanceId', h.nft_instance_id)
      else null end
  );
end $$;

create or replace function public.market_equipment_details_json(p_equipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare e record; t record; n record; lvl int; mult numeric;
begin
  select * into e from player_equipment where id = p_equipment_id;
  if not found then return null; end if;
  select * into t from equipment_templates where id = e.template_id;
  if not found then return null; end if;
  select * into n from nft_equipment where player_equipment_id = e.id limit 1;

  lvl := greatest(1, coalesce(e.level, 1));
  mult := 1 + (lvl - 1) * 0.1;

  return jsonb_build_object(
    'kind', 'equipment',
    'name', t.name,
    'rarity', lower(coalesce(t.rarity,'common')),
    'level', lvl,
    'image', t.image_url,
    'slot', t.slot,
    'category', t.kind,
    'heroClass', t.hero_class,
    'tier', t.tier,
    'description', t.description,
    'power', round(coalesce(t.power,0) * mult),
    'stats', jsonb_strip_nulls(jsonb_build_object(
      'atk', nullif(round(coalesce(t.bonus_attack,0) * mult), 0),
      'def', nullif(round(coalesce(t.bonus_defense,0) * mult), 0),
      'hp', nullif(round(coalesce(t.bonus_hp,0) * mult), 0)
    )),
    'skills', '[]'::jsonb,
    'passives', '[]'::jsonb,
    'badges', (select coalesce(jsonb_agg(b), '[]'::jsonb) from (
        select 'nft_exclusive' as b where coalesce(t.is_nft,false) or n.id is not null
        union all select 'veteran' where coalesce(t.veteran_line,false)
        union all select 'founder' where coalesce(t.founder_line,false)
      ) x),
    'miningMyth', round(coalesce(e.mining_daily_myth,0)::numeric, 4),
    'nft', case when n.id is null then null else jsonb_build_object(
        'serial', n.nft_serial,
        'supply', (select count(*)::int from nft_equipment ne where ne.template_id = n.template_id),
        'instanceId', n.unique_instance_id) end
  );
end $$;

create or replace function public.market_stack_details_json(p_item_code text, p_snapshot jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare v_code text := lower(coalesce(p_item_code,'')); t record; f record;
begin
  select * into t from equipment_templates et where et.code = v_code limit 1;
  if found then
    return jsonb_build_object(
      'kind', 'equipment',
      'name', t.name, 'rarity', lower(coalesce(t.rarity,'common')), 'level', 1,
      'image', t.image_url, 'slot', t.slot, 'category', t.kind, 'heroClass', t.hero_class,
      'tier', t.tier, 'description', t.description, 'power', round(coalesce(t.power,0)),
      'stats', jsonb_strip_nulls(jsonb_build_object(
        'atk', nullif(round(coalesce(t.bonus_attack,0)),0),
        'def', nullif(round(coalesce(t.bonus_defense,0)),0),
        'hp', nullif(round(coalesce(t.bonus_hp,0)),0))),
      'skills', '[]'::jsonb, 'passives', '[]'::jsonb,
      'badges', case when coalesce(t.is_nft,false) then '["nft_exclusive"]'::jsonb else '[]'::jsonb end,
      'miningMyth', 0, 'nft', null);
  end if;

  select * into f from pet_food_items pf where pf.code = v_code limit 1;
  if found then
    return jsonb_build_object(
      'kind', 'item',
      'name', f.name, 'rarity', lower(coalesce(f.rarity,'common')), 'level', 1,
      'image', coalesce(p_snapshot->>'image', f.icon),
      'power', 0,
      'stats', jsonb_strip_nulls(jsonb_build_object('petXp', nullif(coalesce(f.xp_value,0),0))),
      'skills', '[]'::jsonb, 'passives', '[]'::jsonb, 'badges', '[]'::jsonb,
      'miningMyth', 0, 'nft', null);
  end if;

  return jsonb_build_object(
    'kind', 'item',
    'name', coalesce(p_snapshot->>'name', 'Item'),
    'rarity', lower(coalesce(p_snapshot->>'rarity','common')),
    'level', coalesce((p_snapshot->>'level')::int, 1),
    'image', p_snapshot->>'image',
    'power', 0,
    'stats', jsonb_strip_nulls(jsonb_build_object(
      'atk', nullif(coalesce((p_snapshot->>'atk')::numeric,0),0),
      'hp', nullif(coalesce((p_snapshot->>'hp')::numeric,0),0))),
    'skills', '[]'::jsonb, 'passives', '[]'::jsonb, 'badges', '[]'::jsonb,
    'miningMyth', 0, 'nft', null);
end $$;

create or replace function public.market_pet_details_json(p_player_pet_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare pet jsonb;
begin
  pet := player_pet_json(p_player_pet_id);
  if pet is null then return null; end if;
  return jsonb_build_object(
    'kind','pet','name',pet->>'name','rarity',pet->>'rarity',
    'level',(pet->>'level')::int,'maxLevel',pet->'maxLevel','image',pet->>'image',
    'power',pet->'power',
    'buffs',pet->'buffs','primaryBuffKey',pet->>'primaryBuffKey',
    'primaryBuffValue',pet->'primaryBuffValue','secondaryBuffs',pet->'secondaryBuffs',
    'evolutionTier',pet->'evolutionTier','evolutionLabel',pet->>'evolutionLabel',
    'activeSkill',pet->'activeSkill','species',pet->>'species','category',pet->>'category',
    'stats','{}'::jsonb,'skills','[]'::jsonb,'passives','[]'::jsonb,
    'badges', case when coalesce((pet->>'isNft')::boolean,false) then '["nft_exclusive"]'::jsonb else '[]'::jsonb end,
    'miningMyth', 0,
    'nft', case when pet->'nft' is null or pet->'nft' = 'null'::jsonb then null else pet->'nft' end);
end $$;

create or replace function public.market_item_details(p_telegram_id bigint, p_source text, p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare u uuid; src text := lower(coalesce(p_source,'market'));
        l record; a record; item jsonb; sale jsonb;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  if src = 'auction' then
    select * into a from auctions where id = p_id;
    if not found then raise exception 'AUCTION_NOT_FOUND'; end if;
    if a.item_type = 'hero' then item := market_hero_details_json(a.item_instance_id);
    elsif a.item_type = 'pet' then item := market_pet_details_json(a.item_instance_id);
    else item := market_equipment_details_json(a.item_instance_id);
    end if;
    if item is null then item := market_stack_details_json('', a.snapshot); end if;
    sale := jsonb_build_object(
      'source','auction','id',a.id,'status',a.status,'itemType',a.item_type,
      'currency','TON','priceTon',coalesce(a.current_bid_ton,a.starting_bid_ton),'priceFc',null,
      'quantity',1,'seller',market_seller_label(a.seller_user_id),'mine',(a.seller_user_id = u),
      'endsAt',a.ends_at,'bidCount',a.bid_count,'createdAt',a.created_at,
      'sold',(a.status <> 'active'));
    return jsonb_build_object('ok', true, 'listing', sale, 'item', item);
  end if;

  select * into l from market_listings where id = p_id;
  if not found then raise exception 'LISTING_NOT_FOUND'; end if;

  if l.item_type = 'hero' then item := market_hero_details_json(l.item_instance_id);
  elsif l.item_type = 'pet' then item := market_pet_details_json(l.item_instance_id);
  elsif coalesce(l.item_code,'') like 'equip:%' then
    item := market_equipment_details_json(nullif(split_part(l.item_code, ':', 2), '')::uuid);
  else
    item := market_stack_details_json(l.item_code, l.snapshot);
  end if;

  if item is null then item := market_stack_details_json(coalesce(l.item_code,''), l.snapshot); end if;

  sale := jsonb_build_object(
    'source','market','id',l.id,'status',l.status,'itemType',l.item_type,
    'currency',coalesce(l.currency,'FC'),'priceFc',l.price_fc,'priceTon',l.price_ton,
    'quantity',l.quantity,'seller',coalesce(l.snapshot->>'seller', market_seller_label(l.seller_user_id)),
    'mine',(l.seller_user_id = u),'createdAt',l.created_at,
    'reserved',(l.status = 'reserved'),
    'reservedForMe',(l.reserved_for = u),
    'sold',(l.status not in ('active','reserved')));

  return jsonb_build_object('ok', true, 'listing', sale, 'item', item);
end $$;

grant execute on function public.market_item_details(bigint, text, uuid) to service_role;
grant execute on function public.market_hero_details_json(uuid) to service_role;
grant execute on function public.market_pet_details_json(uuid) to service_role;
grant execute on function public.market_equipment_details_json(uuid) to service_role;
grant execute on function public.market_stack_details_json(text, jsonb) to service_role;