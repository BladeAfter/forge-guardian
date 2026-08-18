CREATE OR REPLACE FUNCTION public.get_hero_fusion_dashboard(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; cfg jsonb := hero_fusion_config(); balance numeric := 0; heroes jsonb;
  frag_cost int := public.universal_fusion_fragment_cost();
begin
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id;
  if u is null then return jsonb_build_object('config', cfg, 'balance', 0, 'heroes', '[]'::jsonb,
    'universalFragments', 0, 'fragmentsPerFusion', frag_cost, 'fragments', 0); end if;
  select coalesce(jsonb_agg(h order by h->>'name'), '[]'::jsonb) into heroes from (
    select jsonb_build_object(
      'heroId', ph.id, 'heroKey', ph.hero_key, 'name', ph.name, 'rarity', ph.rarity, 'level', ph.level,
      'imageUrl', ph.image, 'archetype', ph.archetype, 'stars', ph.fusion_level, 'locked', ph.locked,
      'isNft', ph.is_nft_exclusive, 'nftSerial', ph.nft_serial, 'nftInstance', ph.nft_instance_id,
      'finalAtk', round(ph.final_atk), 'finalHp', round(ph.final_hp),
      'power', round(ph.final_atk * 2 + ph.final_hp),
      'maxLevel', hero_max_level(ph.fusion_level),
      'miningDailyTon', round(coalesce(public.hero_mining_hero_rate(ph.rarity, ph.nft_hero_id), 0), 9),
      'usage', usage,
      'lockReason', usage->>'reason',
      'inTeam', coalesce((usage->>'pvpAttack')::boolean,false)
              or coalesce((usage->>'pvpDefense')::boolean,false)
              or coalesce((usage->>'globalBoss')::boolean,false)
              or coalesce((usage->>'tower')::boolean,false)
              or coalesce((usage->>'marketplace')::boolean,false),
      'duplicates', (
        select count(*) from player_heroes d
        where d.user_id = ph.user_id and d.hero_key = ph.hero_key and d.id <> ph.id
          and public.hero_fusion_material_available(d.id)
      ),
      -- Preview must mirror ensure_pvp_hero_stats() exactly (equipment bonuses included),
      -- otherwise an equipped hero shows a LOWER value than its current stats.
      'next', case when ph.is_nft_exclusive or ph.fusion_level >= coalesce((cfg->>'max_stars')::int,5) then null else jsonb_build_object(
        'stars', ph.fusion_level + 1,
        'costFc', coalesce((cfg->'cost_fc'->>(ph.fusion_level+1)::text)::numeric, 0),
        'duplicatesRequired', public.hero_fusion_required_copies(ph.fusion_level),
        'fragmentsRequired', frag_cost,
        'bonusPercent', coalesce((cfg->'bonus_percent'->>(ph.fusion_level+1)::text)::numeric, 0),
        'maxLevel', hero_max_level(ph.fusion_level + 1),
        'finalAtk', greatest(round(ph.final_atk), greatest(1, round((ph.base_atk + coalesce(ph.bonus_atk,0)) * power(1+ph.attack_growth, ph.level-1) * hero_fusion_multiplier(ph.fusion_level+1)) + coalesce(ph.equip_atk,0))),
        'finalHp', greatest(round(ph.final_hp), greatest(1, round((ph.base_hp + coalesce(ph.bonus_hp,0)) * power(1+ph.hp_growth, ph.level-1) * hero_fusion_multiplier(ph.fusion_level+1)) + coalesce(ph.equip_hp,0)))
      ) end
    ) as h
    from player_heroes ph
    cross join lateral (select public.hero_usage_status(ph.id) as usage) us
    where ph.user_id = u
  ) s;
  return jsonb_build_object('config', cfg, 'balance', balance, 'heroes', heroes,
    'universalFragments', public.universal_fragment_balance(u),
    'fragmentsPerFusion', frag_cost,
    'summonConfig', public.fragment_summon_config(),
    'fragments', coalesce((select quantity from player_inventory
       where user_id = u and item_type = 'fragments' and item_code = 'fragments'), 0));
end $function$;