CREATE OR REPLACE FUNCTION public.familiar_hunt_resolve(p_instance_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
declare
  inst public.familiar_hunt_instances; def jsonb; u uuid;
  pet_hp numeric[] := '{}'; pet_max numeric[] := '{}'; pet_atk numeric[] := '{}';
  pet_name text[] := '{}'; pet_img text[] := '{}'; pet_pow numeric[] := '{}';
  en_hp numeric[] := '{}'; en_max numeric[] := '{}'; en_atk numeric[] := '{}';
  en_name text[] := '{}'; en_img text[] := '{}'; en_elite boolean[] := '{}';
  row_json jsonb; i int; j int; k int; v_rounds int := 0; dmg numeric; crit boolean;
  log jsonb := '[]'::jsonb; total_dmg numeric := 0; won boolean := false;
  alive_pets int; alive_en int; target int; low numeric; def_cut numeric;
  loot jsonb; result jsonb; team_power numeric := 0;
begin
  select * into inst from public.familiar_hunt_instances where id = p_instance_id for update;
  if inst.id is null then raise exception 'HUNT_NOT_FOUND'; end if;
  if inst.status = 'settled' then return inst.result_json; end if;
  if inst.status <> 'paid_pending_hunt' then raise exception 'HUNT_NOT_PAID'; end if;
  u := inst.user_id;

  def := public.familiar_hunt_stage_def(inst.stage);
  def_cut := coalesce((def->>'defReduction')::numeric, 0);

  for row_json in select * from jsonb_array_elements(inst.team_snapshot) loop
    pet_name := pet_name || coalesce(row_json->>'name','Pet');
    pet_img := pet_img || coalesce(row_json->>'image','');
    pet_pow := pet_pow || coalesce((row_json->>'power')::numeric, 1);
    pet_max := pet_max || round(coalesce((row_json->>'power')::numeric,1) * 4.5);
    pet_hp := pet_hp || round(coalesce((row_json->>'power')::numeric,1) * 4.5);
    pet_atk := pet_atk || round(coalesce((row_json->>'power')::numeric,1) * 0.25);
    team_power := team_power + coalesce((row_json->>'power')::numeric, 1);
  end loop;
  if coalesce(array_length(pet_hp,1),0) = 0 then raise exception 'TEAM_MUST_HAVE_3_PETS'; end if;

  for row_json in select * from jsonb_array_elements(def->'enemies') loop
    en_name := en_name || coalesce(row_json->>'name','Monstro');
    en_img := en_img || coalesce(row_json->>'image','');
    en_max := en_max || coalesce((row_json->>'hp')::numeric, 1);
    en_hp := en_hp || coalesce((row_json->>'hp')::numeric, 1);
    en_atk := en_atk || coalesce((row_json->>'atk')::numeric, 1);
    en_elite := en_elite || coalesce((row_json->>'elite')::boolean, false);
  end loop;

  while v_rounds < 40 loop
    v_rounds := v_rounds + 1;
    for i in 1 .. array_length(pet_hp,1) loop
      if pet_hp[i] <= 0 then continue; end if;
      target := null; low := null;
      for j in 1 .. array_length(en_hp,1) loop
        if en_hp[j] > 0 and (low is null or en_hp[j] < low) then low := en_hp[j]; target := j; end if;
      end loop;
      exit when target is null;
      crit := random() < 0.18;
      dmg := greatest(1, round(pet_atk[i] * (0.85 + random() * 0.3) * (1 - def_cut)
              * (case when crit then 1.9 else 1 end)));
      en_hp[target] := greatest(0, en_hp[target] - dmg);
      total_dmg := total_dmg + dmg;
      log := log || jsonb_build_array(jsonb_build_object('round', v_rounds, 'side', 'pet', 'actor', i - 1,
        'target', target - 1, 'damage', dmg, 'crit', crit, 'ko', en_hp[target] <= 0,
        'targetHp', en_hp[target], 'targetMax', en_max[target]));
    end loop;

    alive_en := 0;
    for j in 1 .. array_length(en_hp,1) loop if en_hp[j] > 0 then alive_en := alive_en + 1; end if; end loop;
    if alive_en = 0 then won := true; exit; end if;

    for j in 1 .. array_length(en_hp,1) loop
      if en_hp[j] <= 0 then continue; end if;
      target := null;
      for k in 1 .. array_length(pet_hp,1) loop
        if pet_hp[k] > 0 and (target is null or random() < 0.5) then target := k; end if;
      end loop;
      exit when target is null;
      crit := random() < 0.10;
      dmg := greatest(1, round(en_atk[j] * (0.85 + random() * 0.3) * (case when crit then 1.7 else 1 end)));
      pet_hp[target] := greatest(0, pet_hp[target] - dmg);
      log := log || jsonb_build_array(jsonb_build_object('round', v_rounds, 'side', 'enemy', 'actor', j - 1,
        'target', target - 1, 'damage', dmg, 'crit', crit, 'ko', pet_hp[target] <= 0,
        'targetHp', pet_hp[target], 'targetMax', pet_max[target]));
    end loop;

    alive_pets := 0;
    for k in 1 .. array_length(pet_hp,1) loop if pet_hp[k] > 0 then alive_pets := alive_pets + 1; end if; end loop;
    exit when alive_pets = 0;
  end loop;

  loot := case when won then public.familiar_hunt_roll_loot(u, inst.loot_pool, inst.is_boss)
               else jsonb_build_object('tier', null, 'rewards', '[]'::jsonb) end;

  insert into public.familiar_hunt_progress(user_id, current_familiar_hunt_stage, highest_stage_completed, total_runs, total_wins)
  values (u, case when won then inst.stage + 1 else inst.stage end,
             case when won then inst.stage else 0 end, 1, case when won then 1 else 0 end)
  on conflict (user_id) do update set
    current_familiar_hunt_stage = case when won then greatest(public.familiar_hunt_progress.current_familiar_hunt_stage, inst.stage + 1)
                                       else public.familiar_hunt_progress.current_familiar_hunt_stage end,
    highest_stage_completed = case when won then greatest(public.familiar_hunt_progress.highest_stage_completed, inst.stage)
                                   else public.familiar_hunt_progress.highest_stage_completed end,
    total_runs = public.familiar_hunt_progress.total_runs + 1,
    total_wins = public.familiar_hunt_progress.total_wins + case when won then 1 else 0 end,
    updated_at = now();

  result := jsonb_build_object('ok', true, 'runId', inst.id, 'stage', inst.stage,
    'stageName', coalesce(inst.stage_name, def->>'name'), 'isBoss', inst.is_boss,
    'victory', won, 'rounds', v_rounds, 'teamPower', round(team_power)::int,
    'recommendedPower', inst.recommended_power, 'totalDamage', total_dmg,
    'lootTier', loot->>'tier', 'rewards', coalesce(loot->'rewards','[]'::jsonb), 'log', log,
    'paymentCurrency', inst.payment_currency, 'paymentAmount', inst.payment_amount,
    'team', (select jsonb_agg(jsonb_build_object('name', pet_name[x], 'image', pet_img[x],
              'maxHp', pet_max[x], 'hp', pet_hp[x], 'atk', pet_atk[x], 'power', pet_pow[x]) order by x)
             from generate_subscripts(pet_hp, 1) x),
    'enemies', (select jsonb_agg(jsonb_build_object('name', en_name[y], 'image', en_img[y],
              'maxHp', en_max[y], 'hp', en_hp[y], 'atk', en_atk[y], 'elite', en_elite[y]) order by y)
             from generate_subscripts(en_hp, 1) y));

  update public.familiar_hunt_instances set status = 'settled', victory = won, rounds = v_rounds,
    total_damage = total_dmg, rewards = coalesce(loot->'rewards','[]'::jsonb),
    result_json = result, settled_at = now(), updated_at = now()
  where id = inst.id;

  return result;
end
$$;