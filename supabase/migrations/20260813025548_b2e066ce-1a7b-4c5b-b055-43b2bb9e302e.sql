-- Tower of Eternity: equipment drop rules by floor
CREATE OR REPLACE FUNCTION public.tower_equipment_drop_rule(p_floor int, p_first boolean)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  select jsonb_build_object(
    'chance', case
      when p_floor >= 100 then 1.00
      when p_floor >= 75 then 0.70
      when p_floor >= 50 then 0.55
      when p_floor >= 25 then 0.40
      when p_floor >= 10 then 0.30
      else 0.20 end
      * (case when p_first then 1.0 else 0.6 end),
    'guaranteed', (p_floor % 10 = 0),
    'minRarity', case
      when p_floor >= 100 then 'legendary'
      when p_floor >= 75 then 'epic'
      when p_floor >= 50 then 'rare'
      when p_floor >= 25 then 'uncommon'
      else 'common' end,
    'rarityWeights', case
      when p_floor >= 100 then '{"epic":40,"legendary":60}'::jsonb
      when p_floor >= 75 then '{"rare":30,"epic":45,"legendary":25}'::jsonb
      when p_floor >= 50 then '{"uncommon":25,"rare":40,"epic":30,"legendary":5}'::jsonb
      when p_floor >= 25 then '{"common":20,"uncommon":40,"rare":30,"epic":10}'::jsonb
      when p_floor >= 10 then '{"common":50,"uncommon":35,"rare":15}'::jsonb
      else '{"common":80,"uncommon":20}'::jsonb end,
    'slotWeights', '{"weapon":50,"armor":30,"ring":20}'::jsonb
  );
$$;

-- Weighted pick helper: {"key": weight, ...} -> key
CREATE OR REPLACE FUNCTION public.weighted_pick(p_weights jsonb)
RETURNS text LANGUAGE plpgsql VOLATILE SET search_path TO 'public' AS $$
declare total numeric := 0; r numeric; acc numeric := 0; k text; v numeric;
begin
  if p_weights is null then return null; end if;
  select coalesce(sum((value)::numeric),0) into total from jsonb_each_text(p_weights);
  if total <= 0 then return null; end if;
  r := random() * total;
  for k, v in select key, (value)::numeric from jsonb_each_text(p_weights) order by key loop
    acc := acc + v;
    if r <= acc then return k; end if;
  end loop;
  return k;
end $$;

-- Rolls (and grants) an equipment drop for a cleared tower floor.
CREATE OR REPLACE FUNCTION public.tower_roll_equipment_drop(p_user uuid, p_floor int, p_first boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare
  rule jsonb := public.tower_equipment_drop_rule(p_floor, p_first);
  v_order text[] := array['common','uncommon','rare','epic','legendary'];
  v_min int; v_slot text; v_rarity text; v_weights jsonb := '{}'::jsonb;
  tpl public.equipment_templates; v_classes text[]; v_id uuid;
begin
  if not (rule->>'guaranteed')::boolean and random() > (rule->>'chance')::numeric then
    return null;
  end if;

  v_min := coalesce(array_position(v_order, rule->>'minRarity'), 1);
  -- when guaranteed, never roll below the floor's minimum rarity
  if (rule->>'guaranteed')::boolean then
    select jsonb_object_agg(key, value) into v_weights
    from jsonb_each_text(rule->'rarityWeights')
    where coalesce(array_position(v_order, key), 1) >= v_min;
  end if;
  if v_weights is null or v_weights = '{}'::jsonb then v_weights := rule->'rarityWeights'; end if;

  v_slot := coalesce(public.weighted_pick(rule->'slotWeights'), 'weapon');
  v_rarity := coalesce(public.weighted_pick(v_weights), rule->>'minRarity');

  -- weapons prefer the classes of the heroes used in the tower team
  select array_agg(distinct lower(coalesce(h.hero_class, ''))) into v_classes
  from public.tower_team_slots s join public.player_heroes h on h.id = s.hero_id
  where s.user_id = p_user;

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
  if tpl.id is null then return null; end if;

  insert into public.player_equipment(user_id, template_id, source)
  values (p_user, tpl.id, 'tower_floor_' || p_floor)
  returning id into v_id;

  return jsonb_build_object(
    'instanceId', v_id, 'code', tpl.code, 'name', tpl.name,
    'slot', tpl.slot, 'kind', tpl.kind, 'heroClass', tpl.hero_class,
    'rarity', tpl.rarity, 'tier', tpl.tier, 'imageUrl', tpl.image_url,
    'bonusAttack', tpl.bonus_attack, 'bonusDefense', tpl.bonus_defense,
    'bonusHp', tpl.bonus_hp, 'power', tpl.power
  );
end $$;

-- Include the drop in the tower reward payload
CREATE OR REPLACE FUNCTION public.tower_grant_rewards(p_user uuid, p_floor int, p_first boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare r jsonb := public.tower_floor_rewards(p_floor, p_first); v_food text; v_gear jsonb;
begin
  if (r->>'fragments')::int > 0 then
    insert into public.player_inventory(user_id,item_type,item_code,quantity)
    values (p_user,'fragments','fragments',(r->>'fragments')::int)
    on conflict (user_id,item_type,item_code) do update set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;
  if (r->>'heroChest')::int > 0 then
    insert into public.player_inventory(user_id,item_type,item_code,quantity)
    values (p_user,'hero_chest','common_chest',(r->>'heroChest')::int)
    on conflict (user_id,item_type,item_code) do update set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;
  if (r->>'towerKey')::int > 0 then
    insert into public.player_inventory(user_id,item_type,item_code,quantity)
    values (p_user,'tower_key','eternity_key',(r->>'towerKey')::int)
    on conflict (user_id,item_type,item_code) do update set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;
  if (r->>'petFood')::int > 0 then
    select code into v_food from public.pet_food_items order by coalesce(nullif(code,''),'') limit 1;
    if v_food is not null then
      insert into public.player_pet_food(user_id,food_code,quantity)
      values (p_user,v_food,(r->>'petFood')::int)
      on conflict (user_id,food_code) do update set quantity = public.player_pet_food.quantity + excluded.quantity, updated_at = now();
    end if;
  end if;

  v_gear := public.tower_roll_equipment_drop(p_user, p_floor, p_first);
  r := r || jsonb_build_object('equipment', v_gear);
  return r;
end $$;

REVOKE ALL ON FUNCTION public.tower_equipment_drop_rule(int, boolean) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.weighted_pick(jsonb) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.tower_roll_equipment_drop(uuid, int, boolean) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.tower_grant_rewards(uuid, int, boolean) FROM anon, authenticated;
