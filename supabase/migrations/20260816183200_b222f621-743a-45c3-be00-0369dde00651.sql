-- Tower entry: keep 100k FC option, add 0.50 TON (internal balance) option.
CREATE OR REPLACE FUNCTION public.tower_entry_cost_ton()
RETURNS numeric LANGUAGE sql STABLE SET search_path TO 'public'
AS $function$ SELECT round(greatest(0, public.setting_num('tower_entry_cost_ton', 0.5)), 9) $function$;

CREATE OR REPLACE FUNCTION public.get_tower_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare pl public.game_players; p public.tower_progress; v_limit int; v_boss jsonb; v_team jsonb; v_hist jsonb;
begin
  select * into pl from public.game_players where telegram_id = p_telegram_id;
  if pl.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  p := public.tower_ensure_progress(pl.id);
  v_limit := greatest(1, public.setting_num('tower_daily_attempts', 5)::int);
  v_boss := public.tower_boss_for_floor(p.current_floor);
  v_team := public.tower_team_json(pl.id);
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'floor',r.floor,'bossKey',r.boss_key,'result',r.result,
      'turns',r.turns,'rewards',r.rewards,'createdAt',r.created_at) order by r.created_at desc),'[]'::jsonb)
    into v_hist from (select * from public.tower_runs where user_id = pl.id order by created_at desc limit 10) r;
  return jsonb_build_object(
    'floor', p.current_floor, 'totalFloors', 100, 'highestFloor', p.highest_floor,
    'attemptsUsed', p.attempts_used, 'attemptsLimit', v_limit,
    'attemptsRemaining', greatest(0, v_limit - p.attempts_used),
    'entryCost', public.tower_entry_cost(p.current_floor),
    'entryCostTon', public.tower_entry_cost_ton(),
    'balanceFc', round(coalesce(pl.forge_coins,0)),
    'balanceTon', round(greatest(0, coalesce(pl.ton_balance,0) - coalesce(pl.ton_reserved,0)), 9),
    'boss', v_boss,
    'firstClear', p.current_floor > p.highest_floor,
    'rewards', public.tower_floor_rewards(p.current_floor, p.current_floor > p.highest_floor),
    'replayRewards', public.tower_floor_rewards(p.current_floor, false),
    'team', v_team,
    'teamPower', (select coalesce(sum((x->>'power')::numeric),0)::bigint from jsonb_array_elements(v_team) x),
    'history', v_hist
  );
end $function$;

CREATE OR REPLACE FUNCTION public.tower_enter_floor(p_telegram_id bigint, p_pay_currency text DEFAULT 'fc')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare pl public.game_players; p public.tower_progress; v_limit int; v_cost numeric; v_floor int;
  v_boss jsonb; v_team jsonb; sim jsonb; v_win boolean; v_first boolean; v_rewards jsonb := '{}'::jsonb;
  v_buffs jsonb; seed text; v_pay text; v_cost_ton numeric := 0; v_avail numeric; v_before numeric; v_after numeric;
begin
  v_pay := case when lower(coalesce(p_pay_currency,'fc')) = 'ton' then 'ton' else 'fc' end;
  select * into pl from public.game_players where telegram_id = p_telegram_id for update;
  if pl.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if pl.banned then raise exception 'PLAYER_BANNED'; end if;
  p := public.tower_ensure_progress(pl.id);
  v_limit := greatest(1, public.setting_num('tower_daily_attempts', 5)::int);
  if p.attempts_used >= v_limit then raise exception 'TOWER_NO_ATTEMPTS'; end if;

  v_floor := p.current_floor;
  v_cost := public.tower_entry_cost(v_floor);
  if v_pay = 'ton' then
    v_cost_ton := public.tower_entry_cost_ton();
    v_avail := round(greatest(0, coalesce(pl.ton_balance,0) - coalesce(pl.ton_reserved,0)), 9);
    if v_avail < v_cost_ton then raise exception 'INSUFFICIENT_TON'; end if;
  else
    if coalesce(pl.forge_coins,0) < v_cost then raise exception 'INSUFFICIENT_FC'; end if;
  end if;

  v_team := public.tower_team_json(pl.id);
  if jsonb_array_length(v_team) = 0 then raise exception 'TOWER_TEAM_EMPTY'; end if;
  if (select count(distinct public.pvp_hero_template_key(h)) from public.tower_team_slots s
        join public.player_heroes h on h.id = s.hero_id where s.user_id = pl.id) <> jsonb_array_length(v_team)
  then raise exception 'TOWER_DUPLICATE_HERO_TEAM'; end if;

  -- only the ACTIVE pet grants bonuses, resolved server-side
  v_buffs := coalesce(public.get_pet_bonuses(pl.id), '{}'::jsonb);
  v_team := public.pvp_apply_pet_modifiers(v_team, v_buffs);

  v_boss := public.tower_boss_for_floor(v_floor);
  seed := gen_random_uuid()::text;
  sim := public.simulate_tower_battle(v_team, v_boss, seed);
  v_win := (sim->>'winnerSide') = 'attacker';
  v_first := v_floor > p.highest_floor;

  if v_pay = 'ton' then
    v_before := round(coalesce(pl.ton_balance,0), 9);
    v_after := round(v_before - v_cost_ton, 9);
    if v_after < 0 then raise exception 'INSUFFICIENT_TON'; end if;
    update public.game_players set ton_balance = v_after, updated_at = now() where id = pl.id;
    insert into public.wallet_ledger(user_id, type, amount_fc, amount_ton, balance_before, balance_after, reference_id)
    values (pl.id, 'tower_entry_ton', 0, -v_cost_ton, v_before, v_after, 'tower:floor:' || v_floor);
    v_cost := 0;
  else
    update public.game_players set forge_coins = greatest(0, coalesce(forge_coins,0) - v_cost), updated_at = now()
      where id = pl.id;
  end if;
  update public.tower_progress set attempts_used = attempts_used + 1, updated_at = now() where user_id = pl.id;

  if v_win then
    v_rewards := public.tower_grant_rewards(pl.id, v_floor, v_first);
    update public.tower_progress
      set highest_floor = greatest(highest_floor, v_floor),
          current_floor = least(100, v_floor + 1),
          updated_at = now()
      where user_id = pl.id;
  end if;

  insert into public.tower_runs(user_id,floor,boss_key,result,turns,cost_fc,first_clear,rewards)
  values (pl.id, v_floor, v_boss->>'bossKey', case when v_win then 'win' else 'loss' end,
          greatest(1,(sim->>'totalTurns')::int), v_cost, v_win and v_first, v_rewards);

  return jsonb_build_object(
    'result', case when v_win then 'win' else 'loss' end,
    'floor', v_floor, 'boss', v_boss, 'costFc', v_cost,
    'costTon', v_cost_ton, 'paidWith', v_pay,
    'firstClear', v_win and v_first,
    'rewards', v_rewards,
    'totalTurns', greatest(1,(sim->>'totalTurns')::int),
    'battleLog', sim->'battleLog',
    'attackerState', sim->'attackerState',
    'defenderState', sim->'defenderState',
    'team', v_team,
    'dashboard', public.get_tower_dashboard(p_telegram_id)
  );
end $function$;