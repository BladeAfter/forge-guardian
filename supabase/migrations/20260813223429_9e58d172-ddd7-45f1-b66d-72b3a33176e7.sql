-- 1. Universal per-step copy requirement (target stars -> copies)
update public.game_settings
set value = jsonb_set(coalesce(value,'{}'::jsonb), '{duplicates}',
      jsonb_build_object('1',1,'2',1,'3',2,'4',3,'5',4))
where key = 'hero_fusion_config';

-- 2. Central helper: copies required to reach the next star from p_stars
create or replace function public.hero_fusion_required_copies(p_stars integer)
returns integer language sql immutable set search_path to 'public' as $$
  select coalesce(
    (public.hero_fusion_config()->'duplicates'->>(greatest(0,coalesce(p_stars,0))+1)::text)::int,
    greatest(1, greatest(0,coalesce(p_stars,0)))
  );
$$;

-- 3. Central helper: is this hero instance usable as fusion material?
create or replace function public.hero_fusion_material_available(p_hero_id uuid)
returns boolean language sql stable set search_path to 'public' as $$
  select exists(
    select 1 from public.player_heroes ph
    where ph.id = p_hero_id
      and not ph.locked and not ph.is_nft_exclusive
      and not exists(select 1 from public.pvp_team_slots t where t.hero_id = ph.id)
      and not exists(select 1 from public.boss_team_slots b where b.player_hero_id = ph.id)
      and not exists(select 1 from public.tower_team_slots w where w.hero_id = ph.id)
      and not exists(select 1 from public.market_listings m
                     where m.item_instance_id = ph.id and m.status = 'active')
  );
$$;

revoke all on function public.hero_fusion_required_copies(integer) from public, anon, authenticated;
revoke all on function public.hero_fusion_material_available(uuid) from public, anon, authenticated;
grant execute on function public.hero_fusion_required_copies(integer) to service_role;
grant execute on function public.hero_fusion_material_available(uuid) to service_role;

-- 4. Dashboard: per-step requirement + availability that matches the backend rules
CREATE OR REPLACE FUNCTION public.get_hero_fusion_dashboard(p_telegram_id bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare u uuid; cfg jsonb := hero_fusion_config(); balance numeric := 0; heroes jsonb;
begin
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id;
  if u is null then return jsonb_build_object('config', cfg, 'balance', 0, 'heroes', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(h order by h->>'name'), '[]'::jsonb) into heroes from (
    select jsonb_build_object(
      'heroId', ph.id, 'heroKey', ph.hero_key, 'name', ph.name, 'rarity', ph.rarity, 'level', ph.level,
      'imageUrl', ph.image, 'archetype', ph.archetype, 'stars', ph.fusion_level, 'locked', ph.locked,
      'isNft', ph.is_nft_exclusive, 'nftSerial', ph.nft_serial, 'nftInstance', ph.nft_instance_id,
      'finalAtk', round(ph.final_atk), 'finalHp', round(ph.final_hp),
      'power', round(ph.final_atk * 2 + ph.final_hp),
      'maxLevel', hero_max_level(ph.fusion_level),
      'inTeam', exists(select 1 from pvp_team_slots t where t.hero_id = ph.id)
              or exists(select 1 from boss_team_slots b where b.player_hero_id = ph.id)
              or exists(select 1 from tower_team_slots w where w.hero_id = ph.id),
      'duplicates', (
        select count(*) from player_heroes d
        where d.user_id = ph.user_id and d.hero_key = ph.hero_key and d.id <> ph.id
          and public.hero_fusion_material_available(d.id)
      ),
      'next', case when ph.is_nft_exclusive or ph.fusion_level >= coalesce((cfg->>'max_stars')::int,5) then null else jsonb_build_object(
        'stars', ph.fusion_level + 1,
        'costFc', coalesce((cfg->'cost_fc'->>(ph.fusion_level+1)::text)::numeric, 0),
        'duplicatesRequired', public.hero_fusion_required_copies(ph.fusion_level),
        'bonusPercent', coalesce((cfg->'bonus_percent'->>(ph.fusion_level+1)::text)::numeric, 0),
        'maxLevel', hero_max_level(ph.fusion_level + 1),
        'finalAtk', greatest(1, round((ph.base_atk + coalesce(ph.bonus_atk,0)) * power(1+ph.attack_growth, ph.level-1) * hero_fusion_multiplier(ph.fusion_level+1))),
        'finalHp', greatest(1, round((ph.base_hp + coalesce(ph.bonus_hp,0)) * power(1+ph.hp_growth, ph.level-1) * hero_fusion_multiplier(ph.fusion_level+1)))
      ) end
    ) as h
    from player_heroes ph where ph.user_id = u
  ) s;
  return jsonb_build_object('config', cfg, 'balance', balance, 'heroes', heroes);
end $fn$;

-- 5. Atomic fuse with the new per-step requirement
CREATE OR REPLACE FUNCTION public.fuse_heroes(p_telegram_id bigint, p_main_hero_id uuid, p_material_ids uuid[])
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare u uuid; balance numeric; cfg jsonb := hero_fusion_config(); main player_heroes%rowtype;
  required int; cost numeric; max_stars int; ids uuid[]; used int; after_row player_heroes%rowtype; after_balance numeric;
begin
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into main from player_heroes where id = p_main_hero_id and user_id = u for update;
  if main.id is null then raise exception 'HERO_NOT_OWNED'; end if;
  if main.is_nft_exclusive then raise exception 'NFT_HERO_UNIQUE'; end if;
  if exists(select 1 from player_heroes where id = any(coalesce(p_material_ids,'{}'::uuid[])) and is_nft_exclusive) then
    raise exception 'NFT_HERO_UNIQUE';
  end if;
  max_stars := coalesce((cfg->>'max_stars')::int, 5);
  if main.fusion_level >= max_stars then raise exception 'HERO_MAX_STARS'; end if;
  required := public.hero_fusion_required_copies(main.fusion_level);
  cost := coalesce((cfg->'cost_fc'->>(main.fusion_level+1)::text)::numeric, 0);

  select coalesce(array_agg(id), '{}') into ids from (
    select ph.id from player_heroes ph
    where ph.user_id = u and ph.id <> main.id and ph.hero_key = main.hero_key
      and ph.id = any(coalesce(p_material_ids, '{}'::uuid[]))
      and public.hero_fusion_material_available(ph.id)
    order by ph.fusion_level, ph.level
    limit required
    for update
  ) s;
  used := coalesce(array_length(ids,1), 0);
  if used < required then raise exception 'NOT_ENOUGH_DUPLICATES'; end if;
  if balance < cost then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;

  update game_players set forge_coins = forge_coins - cost, updated_at = now() where id = u returning forge_coins into after_balance;
  delete from hero_combat_state where hero_id = any(ids);
  delete from player_heroes where id = any(ids) and user_id = u;
  update player_heroes set fusion_level = fusion_level + 1, updated_at = now() where id = main.id returning * into after_row;

  insert into hero_fusion_history(user_id, hero_id, hero_key, from_stars, to_stars, materials_consumed, material_ids, cost_fc, atk_before, atk_after, hp_before, hp_after)
  values (u, main.id, main.hero_key, main.fusion_level, after_row.fusion_level, used, ids, cost, main.final_atk, after_row.final_atk, main.final_hp, after_row.final_hp);

  return jsonb_build_object(
    'heroId', main.id, 'name', after_row.name, 'fromStars', main.fusion_level, 'toStars', after_row.fusion_level,
    'atkBefore', round(main.final_atk), 'atkAfter', round(after_row.final_atk),
    'hpBefore', round(main.final_hp), 'hpAfter', round(after_row.final_hp),
    'bonusPercent', coalesce((cfg->'bonus_percent'->>after_row.fusion_level::text)::numeric, 0),
    'maxLevel', hero_max_level(after_row.fusion_level),
    'costFc', cost, 'consumed', used, 'balance', after_balance,
    'dashboard', get_hero_fusion_dashboard(p_telegram_id)
  );
end $fn$;