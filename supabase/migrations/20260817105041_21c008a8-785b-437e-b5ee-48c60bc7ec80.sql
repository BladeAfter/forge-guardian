CREATE OR REPLACE FUNCTION public.tower_boss_for_floor(p_floor integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'public'
AS $function$
declare f int := greatest(1, least(100, coalesce(p_floor,1)));
  b public.tower_bosses; tier int; step int; mult numeric; hp numeric; atk numeric; def numeric; dmult numeric; n int;
begin
  select count(*) into n from public.tower_bosses;
  if coalesce(n,0) = 0 then raise exception 'TOWER_BOSS_MISSING'; end if;
  select * into b from public.tower_bosses order by floor_index offset ((f - 1) % n) limit 1;
  if b.boss_key is null then raise exception 'TOWER_BOSS_MISSING'; end if;
  tier := ceil(f / 10.0)::int;
  step := ((f - 1) % 10);
  dmult := case when f <= 10 then 0.50 else 1.0 end;
  if f <= 10 then
    hp  := round(13000 * (1 + 0.1350 * step));
    atk := round(390 * (1 + 0.1408 * step));
    def := round(90 * (1 + 0.0690 * step));
  else
    mult := power(1.55, tier - 1) * (1 + 0.06 * step);
    hp  := round(b.base_hp * mult * dmult);
    atk := round(b.base_atk * power(1.34, tier - 1) * (1 + 0.04 * step) * dmult);
    def := round(b.base_def * power(1.22, tier - 1) * (1 + 0.03 * step) * dmult);
  end if;
  return jsonb_build_object(
    'heroId','tower-boss','name',b.name,'bossKey',b.boss_key,'theme',b.theme,'role',b.role,
    'behavior',b.behavior,'floor',f,'tier',tier,'rarity','boss',
    'finalHp',hp,'finalAtk',atk,'defense',def,'speed',b.base_speed + tier,
    'level',f,'imageUrl',null,'difficultyMultiplier',dmult,
    'recommendedPower', round(hp * 0.35 + atk * 6)::bigint,
    'entryCost', public.tower_entry_cost(f)
  );
end $function$;

CREATE OR REPLACE FUNCTION public.tower_enter_floor(p_telegram_id bigint, p_pay_currency text DEFAULT 'fc'::text)
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
    -- unique reference per attempt (the same floor can be entered many times)
    insert into public.wallet_ledger(user_id, type, amount_fc, amount_ton, balance_before, balance_after, reference_id)
    values (pl.id, 'tower_entry_ton', 0, -v_cost_ton, v_before, v_after,
            'tower:floor:' || v_floor || ':' || seed);
    v_cost := 0;
  else
    update public.game_players set forge_coins = forge_coins - v_cost, updated_at = now() where id = pl.id;
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

REVOKE ALL ON FUNCTION public.tower_enter_floor(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tower_enter_floor(bigint, text) TO service_role;