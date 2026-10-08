-- 1. Ledger: one equipment drop per (player, floor) -> anti-duplicate protection
CREATE TABLE IF NOT EXISTS public.tower_equipment_drops (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  floor int NOT NULL,
  template_id uuid REFERENCES public.equipment_templates(id),
  instance_id uuid REFERENCES public.player_equipment(id) ON DELETE SET NULL,
  rarity text,
  slot text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, floor)
);

GRANT SELECT ON public.tower_equipment_drops TO authenticated;
GRANT ALL ON public.tower_equipment_drops TO service_role;
ALTER TABLE public.tower_equipment_drops ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Players read their own tower drops" ON public.tower_equipment_drops;
CREATE POLICY "Players read their own tower drops" ON public.tower_equipment_drops
  FOR SELECT TO authenticated
  USING (user_id IS NOT NULL AND user_id = auth.uid());

-- 2. Roll with anti-duplicate guard
CREATE OR REPLACE FUNCTION public.tower_roll_equipment_drop(p_user uuid, p_floor int, p_first boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare
  rule jsonb := public.tower_equipment_drop_rule(p_floor, p_first);
  v_order text[] := array['common','uncommon','rare','epic','legendary'];
  v_min int; v_slot text; v_rarity text; v_weights jsonb := '{}'::jsonb;
  tpl public.equipment_templates; v_classes text[]; v_id uuid; v_claim uuid;
begin
  -- anti-duplicate: a floor can only ever yield ONE equipment instance per player
  insert into public.tower_equipment_drops(user_id, floor)
  values (p_user, p_floor)
  on conflict (user_id, floor) do nothing
  returning id into v_claim;
  if v_claim is null then return null; end if;

  if not (rule->>'guaranteed')::boolean and random() > (rule->>'chance')::numeric then
    -- no drop this time: release the claim so a later clear can still roll
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
end $$;

-- 3. Audit: validates chance / guarantee / rarity progression for every floor
CREATE OR REPLACE FUNCTION public.tower_equipment_drop_audit()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
declare
  v_order text[] := array['common','uncommon','rare','epic','legendary'];
  f int; rule jsonb; issues jsonb := '[]'::jsonb; rows jsonb := '[]'::jsonb;
  v_chance numeric; v_guar boolean; v_min text; v_min_idx int; v_prev numeric := -1; v_prev_min int := 0;
  v_pool int; k text;
begin
  for f in 1..100 loop
    rule := public.tower_equipment_drop_rule(f, true);
    v_chance := (rule->>'chance')::numeric;
    v_guar := (rule->>'guaranteed')::boolean;
    v_min := rule->>'minRarity';
    v_min_idx := coalesce(array_position(v_order, v_min), 0);

    if v_chance <= 0 or v_chance > 1 then
      issues := issues || jsonb_build_object('floor', f, 'issue', 'CHANCE_OUT_OF_RANGE', 'chance', v_chance);
    end if;
    if v_chance < v_prev then
      issues := issues || jsonb_build_object('floor', f, 'issue', 'CHANCE_NOT_MONOTONIC', 'chance', v_chance, 'previous', v_prev);
    end if;
    if v_min_idx = 0 then
      issues := issues || jsonb_build_object('floor', f, 'issue', 'UNKNOWN_MIN_RARITY', 'minRarity', v_min);
    elsif v_min_idx < v_prev_min then
      issues := issues || jsonb_build_object('floor', f, 'issue', 'MIN_RARITY_REGRESSION', 'minRarity', v_min);
    end if;
    if (f % 10 = 0) <> v_guar then
      issues := issues || jsonb_build_object('floor', f, 'issue', 'GUARANTEE_RULE_MISMATCH', 'guaranteed', v_guar);
    end if;
    if f = 100 and (not v_guar or v_min <> 'legendary' or v_chance < 1) then
      issues := issues || jsonb_build_object('floor', 100, 'issue', 'FINAL_FLOOR_RULE_INVALID');
    end if;

    -- every rarity in the weight table must have items, and guaranteed floors must
    -- keep at least one rarity at/above the minimum
    for k in select key from jsonb_each_text(rule->'rarityWeights') loop
      select count(*) into v_pool from public.equipment_templates t where t.is_active and t.rarity = k;
      if v_pool = 0 then
        issues := issues || jsonb_build_object('floor', f, 'issue', 'EMPTY_TEMPLATE_POOL', 'rarity', k);
      end if;
    end loop;
    if v_guar and not exists (
      select 1 from jsonb_each_text(rule->'rarityWeights') e
      where coalesce(array_position(v_order, e.key), 0) >= v_min_idx
    ) then
      issues := issues || jsonb_build_object('floor', f, 'issue', 'GUARANTEE_HAS_NO_VALID_RARITY');
    end if;

    if f % 10 = 0 or f = 1 then
      rows := rows || jsonb_build_object('floor', f, 'chance', v_chance, 'guaranteed', v_guar, 'minRarity', v_min);
    end if;

    v_prev := v_chance; v_prev_min := v_min_idx;
  end loop;

  return jsonb_build_object(
    'ok', jsonb_array_length(issues) = 0,
    'floorsChecked', 100,
    'issues', issues,
    'sample', rows,
    'duplicateGuard', 'unique(user_id, floor) on tower_equipment_drops'
  );
end $$;

REVOKE ALL ON FUNCTION public.tower_roll_equipment_drop(uuid, int, boolean) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.tower_equipment_drop_audit() FROM anon, authenticated;
