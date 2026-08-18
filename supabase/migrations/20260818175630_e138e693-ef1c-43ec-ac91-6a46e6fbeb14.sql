CREATE OR REPLACE FUNCTION public.nft_hero_my_json(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; total int; items jsonb;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select count(*) into total from public.nft_heroes;
  select coalesce(jsonb_agg(x order by (x->>'serial')::int), '[]'::jsonb) into items from (
    select jsonb_build_object(
      'nftId', n.id, 'playerHeroId', ph.id, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
      'name', coalesce(ph.name, c.name), 'image', coalesce(ph.image, c.image), 'rarity', 'nft_exclusive',
      'level', coalesce(ph.level, 1), 'stars', coalesce(ph.fusion_level, 0),
      'atk', round(coalesce(ph.final_atk, 0)), 'hp', round(coalesce(ph.final_hp, 0)),
      'tierTon', round(coalesce(n.tier_ton, n.price_ton, 20), 9),
      'dailyYieldTon', round(coalesce(n.mining_daily_ton, 0), 9),
      'dailyYieldMyth', round(coalesce(n.mining_daily_myth, 0), 9)
    ) as x
    from public.nft_heroes n
    join public.hero_catalog c on c.hero_key = n.hero_template_id
    left join public.player_heroes ph on ph.id = n.player_hero_id
    where n.owner_user_id = u and n.status = 'OWNED'
  ) q;
  return jsonb_build_object('totalSupply', greatest(coalesce(total, 0), 10), 'items', items);
end $function$;