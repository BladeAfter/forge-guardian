-- The hero card read its TON rate only from the rarity/NFT table, so a per-instance
-- admin override (player_heroes.mining_ton_override) never showed up in the UI even
-- though accrual/claim already honoured it. The dashboard now uses the same priority
-- as hero_mining_accrue: override first, then the NFT/rarity rate.
create or replace function public.hero_mining_instance_rate(p_hero_id uuid)
returns numeric language sql stable security definer set search_path to 'public' as $$
  select round(greatest(coalesce(ph.mining_ton_override,
    public.hero_mining_hero_rate(ph.rarity, ph.nft_hero_id), 0), 0), 9)
  from player_heroes ph where ph.id = p_hero_id;
$$;

create or replace function public.get_hero_fusion_dashboard(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare u uuid; cfg jsonb := hero_fusion_config(); balance numeric := 0; heroes jsonb;
  frag_cost int := public.universal_fusion_fragment_cost();
begin
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id;
  if u is null then return jsonb_build_object('config', cfg, 'balance', 0, 'heroes', '[]'::jsonb,
    'universalFragments', 0, 'fragmentsPerFusion', frag_cost, 'fragments', 0); end if;

  with atk as (select hero_id from pvp_team_slots where user_id = u and team_type = 'attack'),
       def as (select hero_id from pvp_team_slots where user_id = u and team_type = 'defense'),
       boss as (select player_hero_id as hero_id from boss_team_slots where user_id = u),
       tower as (select hero_id from tower_team_slots where user_id = u),
       mkt as (select item_instance_id as hero_id from market_listings where status = 'active'),
       base as (
         select ph.*,
           coalesce(ph.locked,false) as f_manual,
           coalesce(ph.is_nft_exclusive,false) as f_nft,
           exists(select 1 from atk a where a.hero_id = ph.id) as f_atk,
           exists(select 1 from def d where d.hero_id = ph.id) as f_def,
           exists(select 1 from boss b where b.hero_id = ph.id) as f_boss,
           exists(select 1 from tower w where w.hero_id = ph.id) as f_tower,
           exists(select 1 from mkt m where m.hero_id = ph.id) as f_market
         from player_heroes ph
         where ph.user_id = u
       ),
       flagged as (
         select b.*, (b.f_manual or b.f_atk or b.f_def or b.f_boss or b.f_tower or b.f_market) as in_use,
           not (b.f_manual or b.f_atk or b.f_def or b.f_boss or b.f_tower or b.f_market or b.f_nft) as can_fuse
         from base b
       ),
       dups as (
         select hero_key, count(*) filter (where can_fuse) as fusable from flagged group by hero_key
       ),
       rows_json as (
         select jsonb_build_object(
           'heroId', f.id, 'heroKey', f.hero_key, 'name', f.name, 'rarity', f.rarity, 'level', f.level,
           'imageUrl', f.image, 'archetype', f.archetype, 'stars', f.fusion_level, 'locked', f.locked,
           'isNft', f.is_nft_exclusive, 'nftSerial', f.nft_serial, 'nftInstance', f.nft_instance_id,
           'finalAtk', round(f.final_atk), 'finalHp', round(f.final_hp),
           'power', round(f.final_atk * 2 + f.final_hp),
           'maxLevel', hero_max_level(f.fusion_level),
           -- Per-instance admin override wins, exactly like accrual/claim.
           'miningDailyTon', round(greatest(coalesce(f.mining_ton_override,
              public.hero_mining_hero_rate(f.rarity, f.nft_hero_id), 0), 0), 9),
           'miningDailyMyth', round(greatest(
              coalesce(f.mining_daily_myth, 0),
              coalesce(public.hero_mining_hero_myth_rate(f.rarity, f.nft_hero_id), 0)
           ), 9),
           'usage', jsonb_build_object(
             'manuallyLocked', f.f_manual, 'pvpAttack', f.f_atk, 'pvpDefense', f.f_def,
             'globalBoss', f.f_boss, 'clanBoss', false, 'tower', f.f_tower, 'marketplace', f.f_market,
             'isNft', f.f_nft, 'notTradeable', f.f_nft, 'inUse', f.in_use, 'canFuse', f.can_fuse,
             'reason', case when f.f_manual then 'MANUAL' when f.f_atk then 'PVP_ATTACK'
               when f.f_def then 'PVP_DEFENSE' when f.f_boss then 'BOSS'
               when f.f_tower then 'TOWER' when f.f_market then 'MARKET' else null end
           ),
           'lockReason', case when f.f_manual then 'MANUAL' when f.f_atk then 'PVP_ATTACK'
             when f.f_def then 'PVP_DEFENSE' when f.f_boss then 'BOSS'
             when f.f_tower then 'TOWER' when f.f_market then 'MARKET' else null end,
           'inTeam', (f.f_atk or f.f_def or f.f_boss or f.f_tower or f.f_market),
           'duplicates', greatest(coalesce(d.fusable,0) - (case when f.can_fuse then 1 else 0 end), 0),
           'next', case when f.fusion_level >= coalesce((cfg->>'max_stars')::int,5) then null else jsonb_build_object(
             'stars', f.fusion_level + 1,
             'costFc', coalesce((cfg->'cost_fc'->>(f.fusion_level+1)::text)::numeric, 0),
             'duplicatesRequired', public.hero_fusion_required_copies(f.fusion_level),
             'fragmentsRequired', frag_cost,
             'bonusPercent', coalesce((cfg->'bonus_percent'->>(f.fusion_level+1)::text)::numeric, 0),
             'maxLevel', hero_max_level(f.fusion_level + 1)
           ) end
         ) as row
         from flagged f left join dups d on d.hero_key = f.hero_key
         order by f.final_atk * 2 + f.final_hp desc
       )
  select coalesce(jsonb_agg(row), '[]'::jsonb) into heroes from rows_json;

  return jsonb_build_object('config', cfg, 'balance', coalesce(balance,0), 'heroes', heroes,
    'universalFragments', coalesce((select universal_fragments from game_players where id = u), 0),
    'fragments', coalesce((select universal_fragments from game_players where id = u), 0),
    'fragmentsPerFusion', frag_cost);
end $function$;