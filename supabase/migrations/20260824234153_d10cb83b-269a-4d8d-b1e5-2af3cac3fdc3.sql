-- ════════════════════════════════════════════════════════════════════
-- FAMILIAR HUNT · ENTRY COST (FC / internal TON)
-- ════════════════════════════════════════════════════════════════════
alter table public.familiar_hunt_missions
  add column if not exists entry_cost_fc bigint not null default 0,
  add column if not exists entry_cost_ton numeric(12,4) not null default 0;

update public.familiar_hunt_missions set entry_cost_fc = v.fc, entry_cost_ton = v.ton
from (values
  ('fh_forest',   8000::bigint, 0.05::numeric),
  ('fh_cave',    20000::bigint, 0.10::numeric),
  ('fh_shadow',  45000::bigint, 0.18::numeric),
  ('fh_fire',    80000::bigint, 0.30::numeric),
  ('fh_frost',  130000::bigint, 0.45::numeric),
  ('fh_elite',  200000::bigint, 0.60::numeric)
) as v(code, fc, ton)
where familiar_hunt_missions.code = v.code;

-- ── state: expose entry cost + player balances ──────────────────────
create or replace function public.familiar_hunt_state(p_telegram_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare u uuid; v_day date := public.game_day_key(); v_fc numeric; v_ton numeric;
begin
  select id, coalesce(forge_coins,0), coalesce(ton_balance,0) into u, v_fc, v_ton
    from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.sub_nft_sync(u);

  return jsonb_build_object(
    'gameDay', v_day,
    'balances', jsonb_build_object('fc', v_fc, 'ton', v_ton),
    'pets', coalesce((select jsonb_agg(jsonb_build_object(
        'playerPetId', pp.id, 'name', p.name,
        'image', coalesce(sn_t.image_url, p.image_adult_url, p.image_baby_url),
        'rarity', pp.rarity, 'level', pp.level,
        'power', public.pet_instance_power(pp.id),
        'isSubNft', sn.id is not null,
        'stage', sn.maturity_stage) order by public.pet_instance_power(pp.id) desc)
      from public.player_pets pp
      join public.pets p on p.id = pp.pet_id
      left join public.sub_nfts sn on sn.player_pet_id = pp.id or sn.id = pp.sub_nft_id
      left join public.sub_nft_templates sn_t on sn_t.id = sn.template_id
      where pp.user_id = u), '[]'::jsonb),
    'missions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'code', m.code, 'name', m.name, 'theme', m.theme, 'rarity', m.rarity,
        'description', m.description, 'background', m.background,
        'recommendedPower', m.recommended_power,
        'maxRunsPerDay', m.max_runs_per_day,
        'entryCostFc', m.entry_cost_fc,
        'entryCostTon', m.entry_cost_ton,
        'runsToday', (select count(*)::int from public.familiar_hunt_runs r
                       where r.user_id = u and r.mission_id = m.id and r.game_day = v_day),
        'enemies', (select jsonb_agg(jsonb_build_object(
              'name', e->>'name', 'image', e->>'image',
              'hp', round(m.recommended_power * coalesce((e->>'hpRatio')::numeric, 1)),
              'atk', round(m.recommended_power * coalesce((e->>'atkRatio')::numeric, 0.3)),
              'elite', coalesce((e->>'elite')::boolean, false)))
            from jsonb_array_elements(m.enemies) e),
        'rewards', m.reward_pool) order by m.sort_order)
      from public.familiar_hunt_missions m where m.enabled), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'missionName', m.name, 'victory', r.victory, 'rounds', r.rounds,
        'totalDamage', r.total_damage, 'rewards', r.rewards, 'createdAt', r.created_at)
        order by r.created_at desc)
      from (select * from public.familiar_hunt_runs where user_id = u order by created_at desc limit 10) r
      join public.familiar_hunt_missions m on m.id = r.mission_id), '[]'::jsonb));
end $function$;

-- ── battle: charge the entry cost in the chosen currency ────────────
create or replace function public.familiar_hunt_battle(
  p_telegram_id bigint,
  p_mission_id uuid,
  p_pet_ids uuid[],
  p_idempotency_key text default null,
  p_currency text default 'fc'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  u uuid; m public.familiar_hunt_missions; prev public.familiar_hunt_runs;
  pid uuid; i int; j int; k int; rounds int := 0; dmg numeric; crit boolean;
  pet_hp numeric[] := '{}'; pet_max numeric[] := '{}'; pet_atk numeric[] := '{}';
  pet_name text[] := '{}'; pet_img text[] := '{}'; pet_pow numeric[] := '{}';
  en_hp numeric[] := '{}'; en_max numeric[] := '{}'; en_atk numeric[] := '{}';
  en_name text[] := '{}'; en_img text[] := '{}'; en_elite boolean[] := '{}';
  entry jsonb; log jsonb := '[]'::jsonb; total_dmg numeric := 0;
  team_power numeric := 0; won boolean := false; alive_pets int; alive_en int;
  target int; low numeric; qty int; out_rewards jsonb := '[]'::jsonb;
  tpl public.equipment_templates; v_food text; runs_today int; v_pow numeric;
  v_name text; v_img text; v_run public.familiar_hunt_runs;
  v_currency text := lower(coalesce(nullif(p_currency,''), 'fc'));
  v_cost numeric := 0; v_before numeric; v_after numeric;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  if p_idempotency_key is not null then
    select * into prev from public.familiar_hunt_runs where user_id = u and idempotency_key = p_idempotency_key;
    if prev.id is not null then
      return jsonb_build_object('ok', true, 'replay', true, 'runId', prev.id, 'victory', prev.victory,
        'rounds', prev.rounds, 'totalDamage', prev.total_damage, 'rewards', prev.rewards, 'log', prev.battle_log);
    end if;
  end if;

  select * into m from public.familiar_hunt_missions where id = p_mission_id and enabled;
  if m.id is null then raise exception 'MISSION_NOT_FOUND'; end if;
  if array_length(p_pet_ids, 1) is distinct from 3 then raise exception 'TEAM_MUST_HAVE_3_PETS'; end if;
  if (select count(distinct x) from unnest(p_pet_ids) x) <> 3 then raise exception 'DUPLICATED_PET'; end if;

  select count(*)::int into runs_today from public.familiar_hunt_runs
   where user_id = u and mission_id = m.id and game_day = public.game_day_key();
  if runs_today >= m.max_runs_per_day then raise exception 'HUNT_DAILY_LIMIT'; end if;

  -- ═══ ENTRY COST ═══ charged before the fight, in the chosen currency only.
  if v_currency not in ('fc','ton') then raise exception 'INVALID_CURRENCY'; end if;
  v_cost := case when v_currency = 'fc' then coalesce(m.entry_cost_fc,0) else coalesce(m.entry_cost_ton,0) end;
  if v_cost <= 0 then
    -- the mission does not accept this currency
    raise exception 'ENTRY_CURRENCY_UNAVAILABLE';
  end if;

  if v_currency = 'fc' then
    select coalesce(forge_coins,0) into v_before from public.game_players where id = u for update;
    if v_before < v_cost then raise exception 'INSUFFICIENT_FC'; end if;
    v_after := v_before - v_cost;
    update public.game_players set forge_coins = v_after, updated_at = now() where id = u;
  else
    select coalesce(ton_balance,0) into v_before from public.game_players where id = u for update;
    if v_before < v_cost then raise exception 'INSUFFICIENT_TON'; end if;
    v_after := round(v_before - v_cost, 6);
    update public.game_players set ton_balance = v_after, updated_at = now() where id = u;
    insert into public.wallet_ledger(user_id, type, amount_fc, amount_ton, balance_before, balance_after, reference_id)
    values (u, 'familiar_hunt_entry', 0, -v_cost, v_before, v_after, m.code);
  end if;

  foreach pid in array p_pet_ids loop
    if not exists (select 1 from public.player_pets where id = pid and user_id = u) then raise exception 'PET_NOT_YOURS'; end if;
    v_pow := greatest(1, coalesce(public.pet_instance_power(pid), 1));
    team_power := team_power + v_pow;
    pet_pow := pet_pow || v_pow;
    pet_max := pet_max || round(v_pow * 4.5);
    pet_hp := pet_hp || round(v_pow * 4.5);
    pet_atk := pet_atk || round(v_pow * 0.25);
    select coalesce(p.name, 'Pet'), coalesce(snt.image_url, p.image_adult_url, p.image_baby_url, '')
      into v_name, v_img
      from public.player_pets pp join public.pets p on p.id = pp.pet_id
      left join public.sub_nfts sn on sn.player_pet_id = pp.id or sn.id = pp.sub_nft_id
      left join public.sub_nft_templates snt on snt.id = sn.template_id
      where pp.id = pid limit 1;
    pet_name := pet_name || coalesce(v_name, 'Pet');
    pet_img := pet_img || coalesce(v_img, '');
  end loop;

  for entry in select * from jsonb_array_elements(m.enemies) loop
    en_name := en_name || coalesce(entry->>'name', 'Monstro');
    en_img := en_img || coalesce(entry->>'image', '');
    en_max := en_max || round(m.recommended_power * coalesce((entry->>'hpRatio')::numeric, 1) * 4.5);
    en_hp := en_hp || round(m.recommended_power * coalesce((entry->>'hpRatio')::numeric, 1) * 4.5);
    en_atk := en_atk || round(m.recommended_power * coalesce((entry->>'atkRatio')::numeric, 0.3));
    en_elite := en_elite || coalesce((entry->>'elite')::boolean, false);
  end loop;
  if coalesce(array_length(en_hp,1),0) = 0 then raise exception 'MISSION_NOT_FOUND'; end if;

  while rounds < 40 loop
    rounds := rounds + 1;
    for i in 1 .. array_length(pet_hp,1) loop
      if pet_hp[i] <= 0 then continue; end if;
      target := null; low := null;
      for j in 1 .. array_length(en_hp,1) loop
        if en_hp[j] > 0 and (low is null or en_hp[j] < low) then low := en_hp[j]; target := j; end if;
      end loop;
      exit when target is null;
      crit := random() < 0.18;
      dmg := greatest(1, round(pet_atk[i] * (0.85 + random() * 0.3) * (case when crit then 1.9 else 1 end)));
      en_hp[target] := greatest(0, en_hp[target] - dmg);
      total_dmg := total_dmg + dmg;
      log := log || jsonb_build_array(jsonb_build_object('round', rounds, 'side', 'pet', 'actor', i - 1,
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
      log := log || jsonb_build_array(jsonb_build_object('round', rounds, 'side', 'enemy', 'actor', j - 1,
        'target', target - 1, 'damage', dmg, 'crit', crit, 'ko', pet_hp[target] <= 0,
        'targetHp', pet_hp[target], 'targetMax', pet_max[target]));
    end loop;

    alive_pets := 0;
    for k in 1 .. array_length(pet_hp,1) loop if pet_hp[k] > 0 then alive_pets := alive_pets + 1; end if; end loop;
    exit when alive_pets = 0;
  end loop;

  if won then
    for entry in select * from jsonb_array_elements(m.reward_pool) loop
      if (random() * 100) > coalesce((entry->>'chance')::numeric, 100) then continue; end if;
      qty := floor(random() * (coalesce((entry->>'max')::int,1) - coalesce((entry->>'min')::int,1) + 1))::int + coalesce((entry->>'min')::int,1);
      if qty <= 0 then continue; end if;
      case entry->>'type'
        when 'pet_food' then
          select f.code into v_food from public.pet_food_items f where f.code = nullif(entry->>'code','');
          if v_food is null then select f.code into v_food from public.pet_food_items f where f.code = 'pet_ration'; end if;
          if v_food is null then select f.code into v_food from public.pet_food_items f order by coalesce(f.xp_value,0) asc limit 1; end if;
          if v_food is not null then
            insert into public.player_pet_food(user_id, food_code, quantity) values (u, v_food, qty)
            on conflict (user_id, food_code) do update set quantity = public.player_pet_food.quantity + excluded.quantity, updated_at = now();
          end if;
        when 'universal_fragment' then perform public.add_universal_fragments(u, qty);
        when 'fc' then update public.game_players set forge_coins = coalesce(forge_coins,0) + qty, updated_at = now() where id = u;
        when 'pvp_ticket' then update public.game_players set pvp_tickets = coalesce(pvp_tickets,0) + qty, updated_at = now() where id = u;
        when 'equipment' then
          select * into tpl from public.equipment_templates
            where is_active and rarity = coalesce(entry->>'rarity','rare') order by random() limit 1;
          if tpl.id is not null then
            insert into public.player_equipment(user_id, template_id, source, source_ref) values (u, tpl.id, 'familiar_hunt', null);
          end if;
        else null;
      end case;
      out_rewards := out_rewards || jsonb_build_array(jsonb_build_object('type', entry->>'type',
        'code', coalesce(nullif(entry->>'code',''), entry->>'rarity', ''), 'quantity', qty));
    end loop;
  end if;

  insert into public.familiar_hunt_runs(user_id, mission_id, pet_ids, team_power, victory, rounds,
                                       total_damage, rewards, battle_log, idempotency_key)
  values (u, m.id, p_pet_ids, round(team_power)::int, won, rounds, total_dmg, out_rewards, log, p_idempotency_key)
  returning * into v_run;

  return jsonb_build_object('ok', true, 'runId', v_run.id, 'victory', won, 'rounds', rounds,
    'teamPower', round(team_power)::int, 'totalDamage', total_dmg, 'rewards', out_rewards, 'log', log,
    'entryCurrency', v_currency, 'entryCost', v_cost,
    'team', (select jsonb_agg(jsonb_build_object('name', pet_name[x], 'image', pet_img[x],
              'maxHp', pet_max[x], 'hp', pet_hp[x], 'atk', pet_atk[x], 'power', pet_pow[x]) order by x)
             from generate_subscripts(pet_hp, 1) x),
    'enemies', (select jsonb_agg(jsonb_build_object('name', en_name[y], 'image', en_img[y],
              'maxHp', en_max[y], 'hp', en_hp[y], 'atk', en_atk[y], 'elite', en_elite[y]) order by y)
             from generate_subscripts(en_hp, 1) y),
    'runsToday', runs_today + 1, 'maxRunsPerDay', m.max_runs_per_day);
end $function$;

revoke all on function public.familiar_hunt_state(bigint) from public, anon, authenticated;
revoke all on function public.familiar_hunt_battle(bigint, uuid, uuid[], text, text) from public, anon, authenticated;
grant execute on function public.familiar_hunt_state(bigint) to service_role;
grant execute on function public.familiar_hunt_battle(bigint, uuid, uuid[], text, text) to service_role;