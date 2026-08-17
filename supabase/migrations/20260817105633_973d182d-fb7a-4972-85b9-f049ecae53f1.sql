create or replace function public.tower_roll_equipment_drop(p_user uuid, p_floor int, p_first boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  rule jsonb := public.tower_equipment_drop_rule(p_floor, p_first);
  v_order text[] := array['common','uncommon','rare','epic','legendary'];
  v_min int; v_slot text; v_rarity text; v_weights jsonb := '{}'::jsonb;
  tpl public.equipment_templates; v_classes text[]; v_id uuid; v_claim uuid;
begin
  insert into public.tower_equipment_drops(user_id, floor)
  values (p_user, p_floor)
  on conflict (user_id, floor) do nothing
  returning id into v_claim;
  if v_claim is null then return null; end if;

  if not (rule->>'guaranteed')::boolean and random() > (rule->>'chance')::numeric then
    delete from public.tower_equipment_drops where id = v_claim;
    return null;
  end if;

  v_min := coalesce(array_position(v_order, rule->>'minRarity'), 1);
  if (rule->>'guaranteed')::boolean then
    select jsonb_object_agg(key, value) into v_weights
    from jsonb_each_text(rule->'rarityWeights')
    where coalesce(array_position(v_order, key), 1) >= v_min;
  end if;
  if v_weights is null or v_weights = '{}'::jsonb then v_weights := rule->'rarityWeights'; end if;

  v_slot := coalesce(public.weighted_pick(rule->'slotWeights'), 'weapon');
  v_rarity := coalesce(public.weighted_pick(v_weights), rule->>'minRarity');

  select array_agg(distinct lower(c.hero_class)) into v_classes
  from public.tower_team_slots s
  join public.player_heroes h on h.id = s.hero_id
  join public.hero_catalog c on lower(c.hero_key) = lower(h.hero_key)
  where s.user_id = p_user and c.hero_class is not null;

  select * into tpl from public.equipment_templates t
  where t.is_active and t.slot = v_slot and t.rarity = v_rarity
    and (v_slot <> 'weapon' or t.hero_class is null or v_classes is null
         or lower(t.hero_class) = any(v_classes))
  order by random() limit 1;

  if tpl.id is null then
    select * into tpl from public.equipment_templates t
    where t.is_active and t.slot = v_slot and t.rarity = v_rarity
    order by random() limit 1;
  end if;
  if tpl.id is null then
    delete from public.tower_equipment_drops where id = v_claim;
    return null;
  end if;

  insert into public.player_equipment(user_id, template_id, source)
  values (p_user, tpl.id, 'tower_floor_' || p_floor)
  returning id into v_id;

  update public.tower_equipment_drops
    set template_id = tpl.id, instance_id = v_id, rarity = tpl.rarity, slot = tpl.slot
    where id = v_claim;

  return jsonb_build_object(
    'instanceId', v_id, 'code', tpl.code, 'name', tpl.name,
    'slot', tpl.slot, 'kind', tpl.kind, 'heroClass', tpl.hero_class,
    'rarity', tpl.rarity, 'tier', tpl.tier, 'imageUrl', tpl.image_url,
    'bonusAttack', tpl.bonus_attack, 'bonusDefense', tpl.bonus_defense,
    'bonusHp', tpl.bonus_hp, 'power', tpl.power,
    'firstDropForFloor', true, 'floor', p_floor
  );
end
$fn$;

revoke all on function public.tower_roll_equipment_drop(uuid, int, boolean) from public;
grant execute on function public.tower_roll_equipment_drop(uuid, int, boolean) to service_role;