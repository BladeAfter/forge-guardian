CREATE OR REPLACE FUNCTION public.claim_daily_quest_chest(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE u uuid; v_date date; v_total int; v_completed int; v_bonus jsonb;
        v_type text; v_code text; v_qty int; v_item uuid; v_name text;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  -- serialize concurrent CLAIM taps for this player
  PERFORM pg_advisory_xact_lock(hashtextextended('quest_chest:' || u::text, 0));

  v_date := public.quest_today();

  SELECT count(*) INTO v_total FROM public.quest_definitions WHERE enabled;
  SELECT count(*) INTO v_completed
    FROM public.quest_definitions q
    JOIN public.player_quest_progress p ON p.quest_code = q.code AND p.user_id = u AND p.quest_date = v_date
   WHERE q.enabled AND p.completed_at IS NOT NULL;
  IF v_total = 0 OR v_completed < v_total THEN RAISE EXCEPTION 'QUESTS_NOT_COMPLETED'; END IF;

  IF EXISTS (SELECT 1 FROM public.player_quest_bonus WHERE user_id = u AND quest_date = v_date) THEN
    RAISE EXCEPTION 'BONUS_ALREADY_CLAIMED';
  END IF;

  SELECT value INTO v_bonus FROM public.game_settings WHERE key = 'quest_bonus_chest';
  v_type := COALESCE(v_bonus->>'item_type','hero_chest');
  v_code := COALESCE(v_bonus->>'item_code','common_hero_chest');
  v_qty := GREATEST(1, COALESCE((v_bonus->>'quantity')::int, 1));

  -- the configured chest must exist, otherwise the player could never open it
  IF v_type = 'hero_chest' AND NOT EXISTS (SELECT 1 FROM public.chest_reward_tables WHERE chest_code = v_code AND enabled) THEN
    RAISE EXCEPTION 'CHEST_NOT_CONFIGURED';
  END IF;

  INSERT INTO public.player_quest_bonus (user_id, quest_date, item_type, item_code, quantity)
  VALUES (u, v_date, v_type, v_code, v_qty);

  INSERT INTO public.player_inventory (user_id, item_type, item_code, quantity)
  VALUES (u, v_type, v_code, v_qty)
  ON CONFLICT (user_id, item_type, item_code)
  DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now()
  RETURNING id INTO v_item;

  SELECT name INTO v_name FROM public.chest_reward_tables WHERE chest_code = v_code;

  RETURN jsonb_build_object('claimed', true, 'itemType', v_type, 'itemCode', v_code,
                            'itemName', COALESCE(v_name, v_code), 'quantity', v_qty,
                            'inventoryItemId', v_item,
                            'quests', public.get_daily_quests(p_telegram_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_reward_history(p_telegram_id bigint, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  with feed as (
    select 'hero'::text as reward_type, ph.hero_key as reward_key, coalesce(ph.name, hc.name, 'Hero') as reward_name,
           lower(coalesce(ph.rarity,'common')) as rarity, 1::numeric as quantity,
           coalesce(ph.image, hc.image) as image_url, 'shop'::text as source, ph.created_at as created_at
    from public.player_heroes ph
    left join public.hero_catalog hc on hc.hero_key = ph.hero_key
    where ph.user_id = v_user

    union all
    select 'pet', p.slug, coalesce(p.name,'Pet'), lower(coalesce(pp.rarity,'common')), 1,
           coalesce(p.image_baby_url, p.image_young_url, p.image_adult_url), 'egg_opening',
           coalesce(pp.obtained_at, pp.created_at)
    from public.player_pets pp
    join public.pets p on p.id = pp.pet_id
    where pp.user_id = v_user

    union all
    select case pt.item_type when 'egg' then 'egg' when 'food' then 'food' when 'fragments' then 'fragment' else coalesce(pt.item_type,'item') end,
           pt.item_ref, coalesce(pt.item_name, pt.item_ref, 'Item'), null, coalesce(pt.quantity,1),
           coalesce(e.image_url, f.icon), case when pt.event ilike 'buy%' then 'shop' else 'other' end, pt.created_at
    from public.pet_transactions pt
    left join public.pet_eggs e on e.slug = pt.item_ref or e.id::text = pt.item_ref
    left join public.pet_food_items f on f.code = pt.item_ref
    where pt.user_id = v_user and coalesce(pt.quantity,1) > 0 and pt.item_type is distinct from 'pet'

    union all
    select 'fragment', 'pet_fragments', 'Pet Fragments', null, h.duplicate_fragments, null, 'egg_opening', h.created_at
    from public.pet_hatch_history h
    where h.user_id = v_user and coalesce(h.duplicate_fragments,0) > 0

    union all
    select 'fc', 'fc', 'FC', null, b.amount, null, 'boss', b.created_at
    from public.boss_reward_transactions b
    where b.user_id = v_user and coalesce(b.amount,0) > 0

    union all
    select case when coalesce(c.reward_type,'fc') = 'fc' then 'fc' else c.reward_type end,
           coalesce(c.reward_code, c.reward_type, 'reward'),
           case when coalesce(c.reward_type,'fc') = 'fc' then 'FC' else initcap(replace(coalesce(c.reward_code, c.reward_type,'Reward'),'_',' ')) end,
           null, coalesce(nullif(c.amount_fc,0), 1), null, 'calendar', coalesce(c.claimed_at, c.created_at)
    from public.daily_calendar_claims c
    where c.user_id = v_user

    union all
    select case when spr.reward_type = 'fc' then 'fc' else 'pass_reward' end,
           coalesce(spr.reward_code, spr.reward_type), coalesce(spr.title, 'Battle Pass Reward'),
           spr.tier::text, coalesce(spr.amount,1), null, 'battle_pass', spc.claimed_at
    from public.season_pass_claims spc
    join public.season_pass_rewards spr on spr.id = spc.reward_id
    where spc.user_id = v_user

    union all
    select 'fragment', pi.item_code,
           initcap(replace(replace(pi.item_code,'universal_fragment_',''),'_',' ')) || ' Universal Fragment',
           replace(pi.item_code,'universal_fragment_','') , pi.quantity, null, 'battle_pass', pi.updated_at
    from public.player_inventory pi
    where pi.user_id = v_user and pi.item_code like 'universal_fragment_%' and pi.quantity > 0

    union all
    select 'chest', qb.item_code, coalesce(crt.name, initcap(replace(qb.item_code,'_',' '))),
           null, coalesce(qb.quantity,1), null, 'daily_quest', qb.claimed_at
    from public.player_quest_bonus qb
    left join public.chest_reward_tables crt on crt.chest_code = qb.item_code
    where qb.user_id = v_user

    union all
    select 'fc', 'channel_' || ucr.channel_key, initcap(ucr.channel_key) || ' Channel Reward',
           null, ucr.reward_amount, null, 'channel', ucr.claimed_at
    from public.user_channel_rewards ucr
    where ucr.user_id = v_user and ucr.reward_claimed and coalesce(ucr.reward_amount,0) > 0

    union all
    select 'fc', 'fc', 'FC', null, pb.reward_fc, null, 'pvp', coalesce(pb.completed_at, pb.created_at)
    from public.pvp_battles pb
    where pb.attacker_id = v_user and pb.winner_id = v_user and coalesce(pb.reward_fc,0) > 0
  ), valid as (
    select * from feed where created_at is not null
  )
  select
    (select count(*) from valid),
    coalesce((
      select jsonb_agg(row_to_json(t)::jsonb)
      from (select * from valid order by created_at desc limit v_limit offset v_offset) t
    ), '[]'::jsonb)
  into v_total, v_items;

  return jsonb_build_object('items', coalesce(v_items,'[]'::jsonb), 'total', coalesce(v_total,0));
end;
$$;