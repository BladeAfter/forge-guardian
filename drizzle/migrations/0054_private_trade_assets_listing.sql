CREATE OR REPLACE FUNCTION public.private_trade_assets(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare u uuid; heroes jsonb; pets jsonb; items jsonb;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.available desc, t.created_at desc), '[]'::jsonb)
    into heroes
  from (
    select h.id, h.name, h.rarity, h.level, h.image, h.created_at,
      coalesce(h.fusion_level,0) as stars,
      round(coalesce(h.final_atk,0)) as atk,
      round(coalesce(h.final_hp,0)) as hp,
      (coalesce(h.is_nft_exclusive,false) or h.nft_hero_id is not null) as nft,
      coalesce(h.veteran_line,false) as "veteranLine",
      (
        case when coalesce(h.market_locked,false) then jsonb_build_array('listed') else '[]'::jsonb end
        || case when coalesce(h.locked,false) then jsonb_build_array('locked') else '[]'::jsonb end
        || case when coalesce(h.tradable,true) = false then jsonb_build_array('not_tradable') else '[]'::jsonb end
        || case when exists (select 1 from pvp_team_slots s where s.hero_id = h.id)
                  or exists (select 1 from tower_team_slots tt where tt.hero_id = h.id)
                then jsonb_build_array('pvp_team') else '[]'::jsonb end
        || case when exists (select 1 from boss_team_slots b where b.player_hero_id = h.id)
                then jsonb_build_array('global_boss_team') else '[]'::jsonb end
      ) as locks,
      (
        not coalesce(h.market_locked,false) and not coalesce(h.locked,false)
        and coalesce(h.tradable,true)
        and not exists (select 1 from pvp_team_slots s where s.hero_id = h.id)
        and not exists (select 1 from tower_team_slots tt where tt.hero_id = h.id)
        and not exists (select 1 from boss_team_slots b where b.player_hero_id = h.id)
      ) as available
    from player_heroes h
    where h.user_id = u
    order by h.created_at desc
    limit 300
  ) t;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.available desc, t.created_at desc), '[]'::jsonb)
    into pets
  from (
    select p.id, pet.name, p.rarity, p.level, p.created_at,
      p.evolution_stage as evolution, coalesce(p.evolution_tier,0) as tier,
      (case
        when p.sub_nft_id is not null
             and coalesce((select s.maturity_stage from sub_nfts s where s.id = p.sub_nft_id), 'EGG') <> 'EGG'
          then coalesce(nullif(pet.image_adult_url,''), nullif(pet.image_young_url,''),
                        nullif(pet.image_ancestral_url,''), public.pet_visual_image(p.pet_id, p.level))
        else public.pet_visual_image(p.pet_id, p.level)
      end) as image,
      (p.nft_pet_id is not null or p.sub_nft_id is not null or coalesce(pet.is_nft_exclusive,false)) as nft,
      coalesce(p.veteran_line,false) as "veteranLine",
      (
        case when coalesce(p.market_locked,false) then jsonb_build_array('listed') else '[]'::jsonb end
        || case when coalesce(p.is_active,false) then jsonb_build_array('active_pet') else '[]'::jsonb end
        || case when coalesce(p.tradable,true) = false then jsonb_build_array('not_tradable') else '[]'::jsonb end
      ) as locks,
      (not coalesce(p.market_locked,false) and not coalesce(p.is_active,false) and coalesce(p.tradable,true)) as available
    from player_pets p join pets pet on pet.id = p.pet_id
    where p.user_id = u
  ) t;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.available desc, t.category, t.name), '[]'::jsonb)
    into items
  from (
    select i.item_code as code,
      case when i.item_type = 'hero_chest' or i.item_code like '%chest%' then 'chest' else i.item_type end as "itemType",
      case when i.item_type = 'hero_chest' or i.item_code like '%chest%' then 'chests'
           when i.item_type ilike '%fragment%' then 'fragments' else 'other' end as category,
      coalesce(c.name, initcap(replace(i.item_code,'_',' '))) as name,
      null::text as image,
      coalesce((regexp_match(i.item_code, '(uncommon|common|improved|rare|special|epic|legendary|mythic|ancestral)'))[1], 'common') as rarity,
      i.quantity, true as stackable, false as nft,
      (case when coalesce(i.tradable,true) = false then jsonb_build_array('not_tradable') else '[]'::jsonb end
        || case when coalesce(i.is_exclusive,false) then jsonb_build_array('exclusive') else '[]'::jsonb end) as locks,
      (coalesce(i.tradable,true) and not coalesce(i.is_exclusive,false)) as available
    from player_inventory i left join chest_reward_tables c on c.chest_code = i.item_code
    where i.user_id = u and i.quantity > 0
    union all
    select 'food:' || pf.food_code, 'food', 'food', coalesce(f.name, initcap(replace(pf.food_code,'_',' '))),
      f.icon, coalesce(f.rarity,'common'), pf.quantity, true, false, '[]'::jsonb, true
    from player_pet_food pf left join pet_food_items f on f.code = pf.food_code
    where pf.user_id = u and pf.quantity > 0
    union all
    select 'ufrag', 'universal_fragment', 'fragments', 'Universal Fragment', null, 'epic', pi.quantity, true, false, '[]'::jsonb, true
    from player_pet_inventory pi
    where pi.user_id = u and pi.item_type = 'universal_fragment' and pi.item_id is null and pi.quantity > 0
    union all
    select 'pfrag:' || pp.id::text, 'pet_fragment', 'fragments', p.name || ' Fragment', p.image_baby_url,
      coalesce(pp.rarity,'common'), pp.fragments, true, false,
      (case when coalesce(pp.tradable,true) = false or coalesce(pp.is_season_exclusive,false)
            then jsonb_build_array('not_tradable') else '[]'::jsonb end),
      (coalesce(pp.tradable,true) and not coalesce(pp.is_season_exclusive,false))
    from player_pets pp join pets p on p.id = pp.pet_id
    where pp.user_id = u and coalesce(pp.fragments,0) > 0
    union all
    select 'equip:' || pe.id::text, 'equipment', 'equipment', coalesce(tpl.name,'Equipment'), tpl.image_url,
      coalesce(tpl.rarity,'rare'), 1, false, coalesce(tpl.is_nft,false),
      (case when coalesce(pe.market_locked,false) then jsonb_build_array('listed') else '[]'::jsonb end
        || case when pe.hero_id is not null then jsonb_build_array('equipped') else '[]'::jsonb end
        || case when coalesce(pe.locked,false) then jsonb_build_array('not_tradable') else '[]'::jsonb end),
      (not coalesce(pe.market_locked,false) and pe.hero_id is null and not coalesce(pe.locked,false))
    from player_equipment pe join equipment_templates tpl on tpl.id = pe.template_id
    where pe.user_id = u
  ) t;

  return jsonb_build_object('ok', true, 'heroes', heroes, 'pets', pets, 'items', items);
end $function$;

GRANT EXECUTE ON FUNCTION public.private_trade_assets(bigint) TO service_role;