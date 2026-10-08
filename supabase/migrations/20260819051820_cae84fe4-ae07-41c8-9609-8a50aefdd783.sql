drop table if exists public._diag_log;

create or replace function public.open_legend_chest(p_telegram_id bigint, p_inventory_item_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
  values (u, tpl.id, 'legend_chest', gen_random_uuid())
  returning id into v_id;

  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name)
  values(u,p_telegram_id,'inventory',inv.item_code,'legend_chest',tpl.rarity,v_id,tpl.name);

  return jsonb_build_object(
    'equipment', jsonb_build_object('instanceId',v_id,'code',tpl.code,'name',tpl.name,'slot',tpl.slot,'kind',tpl.kind,
      'heroClass',tpl.hero_class,'rarity',tpl.rarity,'tier',tpl.tier,'imageUrl',tpl.image_url,
      'bonusAttack',tpl.bonus_attack,'bonusDefense',tpl.bonus_defense,'bonusHp',tpl.bonus_hp,'power',tpl.power),
    'inventory', get_player_inventory(p_telegram_id));
end
$function$;

alter table public.pet_hatch_history drop constraint if exists pet_hatch_history_result_rarity_check;
alter table public.pet_hatch_history add constraint pet_hatch_history_result_rarity_check
  check (result_rarity = any (array['common','uncommon','rare','epic','legendary','mythic','ancestral','nft_exclusive']));

do $$
declare r record; v_id uuid;
begin
  for r in
    select i.user_id, e.id as egg_id, sum(i.quantity)::int as qty
    from public.player_inventory i
    join public.pet_eggs e on e.slug = i.item_code
    where i.item_type in ('pet_egg','mythic_egg','egg') and i.quantity > 0
    group by i.user_id, e.id
  loop
    select id into v_id from public.player_pet_inventory
      where user_id=r.user_id and item_type='egg' and item_id=r.egg_id limit 1;
    if v_id is null then
      insert into public.player_pet_inventory(user_id, item_type, item_id, quantity)
      values (r.user_id, 'egg', r.egg_id, r.qty);
    else
      update public.player_pet_inventory set quantity = quantity + r.qty, updated_at = now() where id = v_id;
    end if;
  end loop;
end $$;

delete from public.player_inventory i
using public.pet_eggs e
where e.slug = i.item_code and i.item_type in ('pet_egg','mythic_egg','egg');

update public.player_inventory i
set quantity = i.quantity - 1, updated_at = now()
from public.game_players p
where p.id = i.user_id and p.telegram_id = 5154918326
  and i.item_type = 'hero_chest' and i.quantity >= 2
  and i.item_code in ('legend-chest','legendary_chest','rare_chest');