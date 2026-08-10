create or replace function public.get_reward_history(p_telegram_id bigint, p_limit integer default 20, p_offset integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_items jsonb;
  v_total bigint;
begin
  select id into v_user from public.game_players where telegram_id = p_telegram_id;
  if v_user is null then
    return jsonb_build_object('items', '[]'::jsonb, 'total', 0);
  end if;

  create temp table if not exists tmp_reward_history (
    reward_type text,
    reward_key text,
    reward_name text,
    rarity text,
    quantity numeric,
    image_url text,
    source text,
    created_at timestamptz
  ) on commit drop;
  delete from tmp_reward_history;

  insert into tmp_reward_history
  select 'hero', ph.hero_key, coalesce(ph.name, hc.name, 'Hero'), lower(coalesce(ph.rarity,'common')), 1,
         coalesce(ph.image, hc.image), 'shop', ph.created_at
  from public.player_heroes ph
  left join public.hero_catalog hc on hc.hero_key = ph.hero_key
  where ph.user_id = v_user;

  insert into tmp_reward_history
  select 'pet', p.slug, coalesce(p.name,'Pet'), lower(coalesce(pp.rarity,'common')), 1,
         coalesce(p.image_baby_url, p.image_young_url, p.image_adult_url), 'egg_opening',
         coalesce(pp.obtained_at, pp.created_at)
  from public.player_pets pp
  join public.pets p on p.id = pp.pet_id
  where pp.user_id = v_user;

  insert into tmp_reward_history
  select case pt.item_type when 'egg' then 'egg' when 'food' then 'food' when 'fragments' then 'fragment' else coalesce(pt.item_type,'item') end,
         pt.item_ref, coalesce(pt.item_name, pt.item_ref, 'Item'), null, coalesce(pt.quantity,1),
         coalesce(e.image_url, f.icon), case when pt.event ilike 'buy%' then 'shop' else 'other' end, pt.created_at
  from public.pet_transactions pt
  left join public.pet_eggs e on e.slug = pt.item_ref or e.id::text = pt.item_ref
  left join public.pet_food_items f on f.code = pt.item_ref
  where pt.user_id = v_user and coalesce(pt.quantity,1) > 0 and pt.item_type is distinct from 'pet';

  insert into tmp_reward_history
  select 'fragment', 'pet_fragments', 'Pet Fragments', null, h.duplicate_fragments, null, 'egg_opening', h.created_at
  from public.pet_hatch_history h
  where h.user_id = v_user and coalesce(h.duplicate_fragments,0) > 0;

  insert into tmp_reward_history
  select 'fc', 'forge_coins', 'Forge Coins', null, b.amount, null, 'boss', b.created_at
  from public.boss_reward_transactions b
  where b.user_id = v_user and coalesce(b.amount,0) > 0;

  insert into tmp_reward_history
  select case when coalesce(c.reward_type,'fc') = 'fc' then 'fc' else c.reward_type end,
         coalesce(c.reward_code, c.reward_type, 'reward'),
         case when coalesce(c.reward_type,'fc') = 'fc' then 'Forge Coins' else initcap(replace(coalesce(c.reward_code, c.reward_type,'Reward'),'_',' ')) end,
         null, coalesce(nullif(c.amount_fc,0), 1), null, 'calendar', coalesce(c.claimed_at, c.created_at)
  from public.daily_calendar_claims c
  where c.user_id = v_user;

  insert into tmp_reward_history
  select case when spr.reward_type = 'fc' then 'fc' else 'pass_reward' end,
         coalesce(spr.reward_code, spr.reward_type), coalesce(spr.title, 'Battle Pass Reward'),
         spr.tier::text, coalesce(spr.amount,1), null, 'battle_pass', spc.claimed_at
  from public.season_pass_claims spc
  join public.season_pass_rewards spr on spr.id = spc.reward_id
  where spc.user_id = v_user;

  insert into tmp_reward_history
  select 'fc', 'forge_coins', 'Forge Coins', null, pb.reward_fc, null, 'pvp', coalesce(pb.completed_at, pb.created_at)
  from public.pvp_battles pb
  where pb.attacker_id = v_user and pb.winner_id = v_user and coalesce(pb.reward_fc,0) > 0;

  select count(*) into v_total from tmp_reward_history where created_at is not null;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.created_at desc), '[]'::jsonb)
  into v_items
  from (
    select reward_type, reward_key, reward_name, rarity, quantity, image_url, source, created_at
    from tmp_reward_history
    where created_at is not null
    order by created_at desc
    limit v_limit offset v_offset
  ) t;

  return jsonb_build_object('items', coalesce(v_items,'[]'::jsonb), 'total', coalesce(v_total,0));
end;
$$;

revoke all on function public.get_reward_history(bigint, integer, integer) from public;
grant execute on function public.get_reward_history(bigint, integer, integer) to service_role;