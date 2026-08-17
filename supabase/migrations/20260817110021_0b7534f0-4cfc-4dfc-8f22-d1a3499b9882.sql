insert into public.chest_reward_tables(chest_code,name,subtitle,rarity_rates,enabled)
values('legend-chest','BAÚ LENDÁRIO','Equipamento lendário garantido','{"legendary":100}'::jsonb,true)
on conflict (chest_code) do update set name=excluded.name, subtitle=excluded.subtitle, rarity_rates=excluded.rarity_rates, enabled=true, updated_at=now();

create or replace function public.open_legend_chest(p_telegram_id bigint, p_inventory_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  u uuid; inv player_inventory%rowtype; tpl public.equipment_templates; v_slot text; v_id uuid;
begin
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('legend_chest:'||u::text,0));

  select * into inv from player_inventory where id=p_inventory_item_id and user_id=u for update;
  if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_FOUND'; end if;

  v_slot := (array['weapon','weapon','armor','ring'])[1+floor(random()*4)::int];

  select * into tpl from public.equipment_templates t
  where t.is_active and not coalesce(t.is_nft,false) and t.slot=v_slot and t.rarity='legendary'
  order by random() limit 1;

  if tpl.id is null then
    select * into tpl from public.equipment_templates t
    where t.is_active and not coalesce(t.is_nft,false) and t.rarity='legendary'
    order by random() limit 1;
  end if;
  if tpl.id is null then raise exception 'NO_EQUIPMENT_AVAILABLE'; end if;

  update player_inventory set quantity=quantity-1, updated_at=now() where id=inv.id;

  insert into public.player_equipment(user_id, template_id, source, source_ref)
  values (u, tpl.id, 'legend_chest', gen_random_uuid()::text)
  returning id into v_id;

  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name)
  values(u,p_telegram_id,'inventory',inv.item_code,'legend_chest',tpl.rarity,v_id,tpl.name);

  return jsonb_build_object(
    'equipment', jsonb_build_object('instanceId',v_id,'code',tpl.code,'name',tpl.name,'slot',tpl.slot,'kind',tpl.kind,
      'heroClass',tpl.hero_class,'rarity',tpl.rarity,'tier',tpl.tier,'imageUrl',tpl.image_url,
      'bonusAttack',tpl.bonus_attack,'bonusDefense',tpl.bonus_defense,'bonusHp',tpl.bonus_hp,'power',tpl.power),
    'inventory', get_player_inventory(p_telegram_id));
end
$$;

revoke all on function public.open_legend_chest(bigint, uuid) from public;
grant execute on function public.open_legend_chest(bigint, uuid) to service_role;