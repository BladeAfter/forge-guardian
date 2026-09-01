CREATE OR REPLACE FUNCTION public.market_get_sellable(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; heroes jsonb; pets jsonb; items jsonb; g game_players%rowtype;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  select * into g from game_players where telegram_id = p_telegram_id;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  u := g.id;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.rank_rarity desc, t.level desc, t.created_at desc), '[]'::jsonb) into heroes
  from (
    select h.id, h.name, h.rarity, h.level, h.image, h.created_at,
      coalesce(h.fusion_level,0) as stars,
      round(coalesce(h.final_atk,0)) as atk,
      round(coalesce(h.final_hp,0)) as hp,
      market_hero_locks(h.*) as locks,
      true as available,
      h.rank_rarity,
      market_price_range('hero', h.rarity, h.level, 'FC') as "priceRange",
      market_price_range('hero', h.rarity, h.level, 'TON') as "priceRangeTon",
      market_min_price_ton('hero', h.rarity) as "minPriceTon"
    from (
      select ph.*,
        case lower(coalesce(ph.rarity,'common'))
          when 'celestial' then 100
          when 'nft_exclusive' then 95
          when 'divine' then 92
          when 'ancestral' then 90
          when 'mythic' then 80
          when 'legendary' then 70
          when 'epic' then 60
          when 'rare' then 50
          when 'uncommon' then 40
          else 30
        end as rank_rarity
      from player_heroes ph
      where ph.user_id = u
        and jsonb_array_length(market_hero_locks(ph.*)) = 0
      order by 
        case lower(coalesce(ph.rarity,'common'))
          when 'celestial' then 100
          when 'nft_exclusive' then 95
          when 'divine' then 92
          when 'ancestral' then 90
          when 'mythic' then 80
          when 'legendary' then 70
          when 'epic' then 60
          when 'rare' then 50
          when 'uncommon' then 40
          else 30
        end desc,
        coalesce(ph.level,1) desc,
        ph.created_at desc
      limit 600
    ) h
  ) t;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.available desc, t.created_at desc), '[]'::jsonb) into pets
  from (
    select p.id, pet.name, p.rarity, p.level, p.created_at,
      public.pet_visual_image(p.pet_id, p.level) as image,
      p.evolution_stage as evolution, coalesce(p.evolution_tier,0) as tier,
      (
        case when coalesce(p.market_locked,false) then jsonb_build_array('listed') else '[]'::jsonb end
        || case when coalesce(p.is_active,false) then jsonb_build_array('active_pet') else '[]'::jsonb end
        || case when coalesce(p.tradable,true) = false then jsonb_build_array('not_tradable') else '[]'::jsonb end
      ) as locks,
      (not coalesce(p.market_locked,false) and not coalesce(p.is_active,false) and coalesce(p.tradable,true)) as available,
      market_price_range('pet', p.rarity, p.level, 'FC') as "priceRange",
      market_price_range('pet', p.rarity, p.level, 'TON') as "priceRangeTon",
      market_min_price_ton('pet', p.rarity) as "minPriceTon"
    from player_pets p join pets pet on pet.id = p.pet_id
    where p.user_id = u
  ) t;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.available desc, t.category, t.name), '[]'::jsonb) into items
  from (
    select i.item_code as code,
      case when i.item_type = 'hero_chest' or i.item_code like '%chest%' then 'chest' else i.item_type end as "itemType",
      case when i.item_type = 'hero_chest' or i.item_code like '%chest%' then 'chests'
           when i.item_type ilike '%fragment%' then 'fragments' else 'other' end as category,
      coalesce(c.name, initcap(replace(i.item_code,'_',' '))) as name,
      null::text as image,
      coalesce((regexp_match(i.item_code, '(uncommon|common|improved|rare|special|epic|legendary|mythic|ancestral)'))[1], 'common') as rarity,
      i.quantity, true as stackable,
      (case when coalesce(i.tradable,true) = false then jsonb_build_array('not_tradable') else '[]'::jsonb end
        || case when coalesce(i.is_exclusive,false) then jsonb_build_array('exclusive') else '[]'::jsonb end) as locks,
      (coalesce(i.tradable,true) and not coalesce(i.is_exclusive,false)) as available
    from player_inventory i left join chest_reward_tables c on c.chest_code = i.item_code
     where i.user_id = u and i.quantity > 0
    union all
    select 'food:' || pf.food_code, 'food', 'food', coalesce(f.name, initcap(replace(pf.food_code,'_',' '))),
      f.icon, coalesce(f.rarity,'common'), pf.quantity, true, '[]'::jsonb, true
    from player_pet_food pf left join pet_food_items f on f.code = pf.food_code
    where pf.user_id = u and pf.quantity > 0
    union all
    select 'ufrag', 'universal_fragment', 'fragments', 'Universal Fragment', null, 'epic', pi.quantity, true, '[]'::jsonb, true
    from player_pet_inventory pi
    where pi.user_id = u and pi.item_type = 'universal_fragment' and pi.item_id is null and pi.quantity > 0
    union all
    select 'pfrag:' || pp.id::text, 'pet_fragment', 'fragments', p.name || ' Fragment', p.image_baby_url,
      coalesce(pp.rarity,'common'), pp.fragments, true,
      (case when coalesce(pp.tradable,true) = false or coalesce(pp.is_season_exclusive,false)
            then jsonb_build_array('not_tradable') else '[]'::jsonb end),
      (coalesce(pp.tradable,true) and not coalesce(pp.is_season_exclusive,false))
    from player_pets pp join pets p on p.id = pp.pet_id
    where pp.user_id = u and coalesce(pp.fragments,0) > 0
    union all
    select 'equip:' || pe.id::text, 'equipment', 'equipment', coalesce(tpl.name,'Equipment'), tpl.image_url,
      coalesce(tpl.rarity,'rare'), 1, false,
      (case when coalesce(pe.market_locked,false) then jsonb_build_array('listed') else '[]'::jsonb end
        || case when pe.hero_id is not null then jsonb_build_array('equipped') else '[]'::jsonb end
        || case when coalesce(pe.locked,false) then jsonb_build_array('not_tradable') else '[]'::jsonb end),
      (not coalesce(pe.market_locked,false) and pe.hero_id is null and not coalesce(pe.locked,false))
    from player_equipment pe join equipment_templates tpl on tpl.id = pe.template_id
    where pe.user_id = u
  ) t;

  items := (
    select coalesce(jsonb_agg(e || jsonb_build_object(
      'priceRange', market_price_range('item','default',1,'FC'),
      'priceRangeTon', market_price_range('item','default',1,'TON'),
      'minPriceTon', market_min_price_ton('item', e->>'rarity')
    )), '[]'::jsonb)
    from jsonb_array_elements(items) as e
  );

  return jsonb_build_object('heroes', heroes, 'pets', pets, 'items', items,
    'balanceFc', coalesce(g.forge_coins,0),
    'availableTon', greatest(coalesce(g.ton_balance,0) - coalesce(g.ton_reserved,0), 0),
    'settings', market_settings_json(), 'eligibility', market_sell_eligibility(u),
    'status', market_status(p_telegram_id));
end $function$;