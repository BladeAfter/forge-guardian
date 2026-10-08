create or replace function public.nft_equipment_shop_json(p_telegram_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare u uuid; items jsonb; total int; sold int;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  select coalesce(jsonb_agg(x order by (x->>'serial')::int), '[]'::jsonb), count(*),
         count(*) filter (where x->>'status' = 'SOLD_OUT')
    into items, total, sold
  from (
    select jsonb_build_object(
      'id', n.id, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
      'name', t.name, 'code', t.code, 'image', t.image_url,
      'slot', t.slot, 'kind', t.kind, 'heroClass', t.hero_class, 'rarity', 'nft_exclusive',
      'bonusAttack', coalesce(t.bonus_attack,0), 'bonusDefense', coalesce(t.bonus_defense,0),
      'bonusHp', coalesce(t.bonus_hp,0), 'power', coalesce(t.power,0),
      'description', t.description,
      'priceTon', round(coalesce(n.price_ton,15), 9), 'supply', 1,
      'status', case when n.status = 'AVAILABLE' and n.owner_user_id is null then 'AVAILABLE' else 'SOLD_OUT' end,
      'ownedByMe', (u is not null and n.owner_user_id = u)
    ) as x
    from public.nft_equipment n
    join public.equipment_templates t on t.id = n.template_id
    where n.status <> 'BURNED'
      -- showcase keeps only units still for sale; sold units stay visible to their owner only
      and (
        (n.for_sale and n.owner_user_id is null and n.status = 'AVAILABLE')
        or (u is not null and n.owner_user_id = u)
      )
  ) q;
  return jsonb_build_object(
    'totalSupply', coalesce(total,0), 'sold', coalesce(sold,0),
    'available', coalesce(total,0) - coalesce(sold,0), 'items', items,
    'balanceTon', coalesce((select round(greatest(ton_balance - coalesce(ton_reserved,0),0), 9) from public.game_players where id = u), 0)
  );
end
$$;