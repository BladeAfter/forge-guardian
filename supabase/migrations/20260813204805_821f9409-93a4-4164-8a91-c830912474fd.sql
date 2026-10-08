-- ============================================================
-- 1) PvP reward settlement ledger (backend only)
-- ============================================================
create table if not exists public.pvp_reward_settlements(
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null unique references public.pvp_battles(id) on delete cascade,
  player_id uuid not null,
  opponent_id uuid,
  opponent_type text not null check (opponent_type in ('REAL_PLAYER','AI_BOT')),
  result text not null,
  trophies_awarded integer not null default 0,
  fc_awarded numeric not null default 0,
  xp_awarded integer not null default 0,
  status text not null default 'settled',
  note text,
  finalized_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
grant all on public.pvp_reward_settlements to service_role;
alter table public.pvp_reward_settlements enable row level security;
create index if not exists pvp_reward_settlements_player_idx on public.pvp_reward_settlements(player_id, finalized_at desc);

-- Backfill: every existing battle was already paid inline. Marking them keeps the
-- repair tool from ever paying twice.
insert into public.pvp_reward_settlements(battle_id, player_id, opponent_id, opponent_type, result, trophies_awarded, fc_awarded, status, note, finalized_at)
select b.id, b.attacker_id, coalesce(b.defender_id, b.defender_bot_id),
       case when b.is_bot_battle then 'AI_BOT' else 'REAL_PLAYER' end,
       b.result, coalesce(b.trophy_change,0), coalesce(b.reward_fc,0), 'settled', 'legacy_paid', b.created_at
from public.pvp_battles b
on conflict (battle_id) do nothing;

-- ============================================================
-- 2) start_pvp_battle: same economy, now with an idempotent settlement record
-- ============================================================
CREATE OR REPLACE FUNCTION public.start_pvp_battle(p_telegram_id bigint, p_opponent_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare attacker game_players%rowtype;defender game_players%rowtype;bot public.pvp_bots;atk jsonb;def jsonb;sim jsonb;battle_id uuid;winner uuid;result text;change int;reward numeric:=0;seed text;
  v_win int; v_loss int; v_cost int; v_reward numeric; v_turns int; v_def_power int; v_atk_power int; v_mult_atk numeric:=1; v_mult_hp numeric:=1;
  atk_buffs jsonb:='{}'::jsonb; def_buffs jsonb:='{}'::jsonb; base_atk numeric; eff_atk numeric; debug jsonb;
  v_trophies_after int; v_fc_after numeric; v_xp int; v_opp_type text;
begin
 v_win := public.setting_num('pvp_trophy_win',30)::int;
 v_loss := abs(public.setting_num('pvp_trophy_loss',-20)::int);
 v_cost := GREATEST(0, public.setting_num('pvp_ticket_cost',1)::int);
 v_reward := public.setting_num('pvp_win_reward_fc',2500);

 select * into attacker from game_players where telegram_id=p_telegram_id;
 if attacker.id is null then raise exception 'PLAYER_NOT_FOUND';end if;
 if attacker.id=p_opponent_id then raise exception 'INVALID_OPPONENT';end if;
 select * into bot from pvp_bots where id=p_opponent_id;

 if bot.id is null then
   perform 1 from game_players where id in(attacker.id,p_opponent_id) order by id for update;
   select * into attacker from game_players where id=attacker.id;
   select * into defender from game_players where id=p_opponent_id;
   if defender.id is null or defender.pvp_banned or defender.banned then raise exception 'OPPONENT_UNAVAILABLE';end if;
 else
   if bot.target_user_id is distinct from attacker.id then raise exception 'OPPONENT_UNAVAILABLE';end if;
   perform 1 from game_players where id=attacker.id for update;
   select * into attacker from game_players where id=attacker.id;
 end if;

 if attacker.pvp_banned or attacker.banned then raise exception 'PVP_BANNED';end if;

 atk:=pvp_team_json(attacker.id,'attack');
 if jsonb_array_length(atk)=0 then raise exception 'ATTACK_TEAM_EMPTY';end if;
 if public.pvp_team_has_duplicates(attacker.id,'attack') then raise exception 'PVP_DUPLICATE_HERO_TEAM';end if;

 if bot.id is null then
   if exists(select 1 from pvp_battles where attacker_id=attacker.id and defender_id=defender.id and created_at>clock_timestamp()-interval'3 seconds') then raise exception 'BATTLE_ALREADY_STARTED';end if;
   def:=public.pvp_dedupe_team(pvp_team_json(defender.id,'defense'));
   v_def_power:=(select coalesce(sum((x->>'power')::numeric),0)::int from jsonb_array_elements(def)x);
   def_buffs:=coalesce(public.get_pet_bonuses(defender.id),'{}'::jsonb);
 else
   if bot.used_at is not null then raise exception 'OPPONENT_UNAVAILABLE';end if;
   v_mult_atk:=case bot.strategy when 'aggressive' then 1.08 when 'defensive' then .95 when 'finisher' then 1.05 when 'tactical' then 1.04 else 1 end;
   v_mult_hp:=case bot.strategy when 'aggressive' then .95 when 'defensive' then 1.10 when 'finisher' then .98 when 'tactical' then 1.04 else 1 end;
   select coalesce(jsonb_agg(x||jsonb_build_object(
       'finalAtk',greatest(1,round((x->>'finalAtk')::numeric*v_mult_atk))::int,
       'finalHp',greatest(1,round((x->>'finalHp')::numeric*v_mult_hp))::int)),'[]')
     into def from jsonb_array_elements(public.pvp_dedupe_team(bot.team))x;
   if jsonb_array_length(def)=0 then raise exception 'INVALID_DEFENSE_TEAM';end if;
   v_def_power:=bot.power;
   update pvp_bots set used_at=now() where id=bot.id;
 end if;
 if jsonb_array_length(def)=0 then raise exception 'INVALID_DEFENSE_TEAM';end if;

 if attacker.pvp_tickets < v_cost then raise exception 'NO_PVP_TICKETS';end if;
 update game_players set pvp_tickets=greatest(0,pvp_tickets-v_cost) where id=attacker.id;

 atk_buffs:=coalesce(public.get_pet_bonuses(attacker.id),'{}'::jsonb);
 base_atk:=(select coalesce(sum((x->>'finalAtk')::numeric),0) from jsonb_array_elements(atk)x);
 v_atk_power:=(select coalesce(sum((x->>'power')::numeric),0)::int from jsonb_array_elements(atk)x);
 atk:=public.pvp_apply_pet_modifiers(atk,atk_buffs);
 def:=public.pvp_apply_pet_modifiers(def,def_buffs);
 eff_atk:=(select coalesce(sum((x->>'finalAtk')::numeric),0) from jsonb_array_elements(atk)x);

 seed:=gen_random_uuid()::text;sim:=simulate_pvp_battle(atk,def,seed);
 v_turns := (greatest(1, coalesce(nullif(sim->>'totalTurns','')::int, nullif(sim->>'turns','')::int, jsonb_array_length(coalesce(sim->'battleLog','[]'::jsonb)), 1)));

 debug:=jsonb_build_object('mode','pvp','attackerPetBuffs',atk_buffs,'defenderPetBuffs',def_buffs,
   'baseTeamAtk',base_atk,'arenaAtkBonusPercent',coalesce((atk_buffs->>'pvp_attack_percent')::numeric,0),
   'effectiveTeamAtk',eff_atk,'critChancePercent',coalesce((atk_buffs->>'critical_chance_percent')::numeric,0),
   'critMultiplier',1.5+coalesce((atk_buffs->>'critical_damage_percent')::numeric,0)/100,'seed',seed);

 -- Rewards are written to the database here (never only shown on screen).
 if sim->>'winnerSide'='attacker' then
   winner:=attacker.id;result:='attacker_win';change:=v_win;reward:=v_reward;
   update game_players set pvp_trophies=pvp_trophies+v_win,pvp_wins=pvp_wins+1,forge_coins=forge_coins+reward,updated_at=now()
     where id=attacker.id returning pvp_trophies, forge_coins into v_trophies_after, v_fc_after;
   if bot.id is null then
     update game_players set pvp_trophies=greatest(0,pvp_trophies-v_loss),pvp_losses=pvp_losses+1,updated_at=now() where id=defender.id;
   end if;
 else
   winner:=case when bot.id is null then defender.id else null end;
   result:='defender_win';change:=-v_loss;reward:=0;
   update game_players set pvp_trophies=greatest(0,pvp_trophies-v_loss),pvp_losses=pvp_losses+1,updated_at=now()
     where id=attacker.id returning pvp_trophies, forge_coins into v_trophies_after, v_fc_after;
   if bot.id is null then
     update game_players set pvp_trophies=pvp_trophies+v_win,pvp_wins=pvp_wins+1,updated_at=now() where id=defender.id;
   end if;
 end if;

 insert into pvp_battles(attacker_id,defender_id,defender_bot_id,is_bot_battle,winner_id,result,trophy_change,reward_fc,total_turns,battle_log,attacker_team_snapshot,defender_team_snapshot,attacker_power,defender_power,pet_debug)
 values(attacker.id,case when bot.id is null then defender.id else null end,bot.id,bot.id is not null,winner,result,change,reward,v_turns,
   coalesce(sim->'battleLog','[]'::jsonb),atk,def,coalesce(v_atk_power,0),coalesce(v_def_power,0),debug)
 returning id into battle_id;

 -- Season pass XP is granted by the quest trigger above; read it back for the log.
 select coalesce(sum(xp_amount),0)::int into v_xp from season_pass_xp_ledger
  where user_id=attacker.id and reference_id in ('pvp:'||battle_id::text,'pvp_win:'||battle_id::text);

 v_opp_type := case when bot.id is null then 'REAL_PLAYER' else 'AI_BOT' end;
 insert into pvp_reward_settlements(battle_id,player_id,opponent_id,opponent_type,result,trophies_awarded,fc_awarded,xp_awarded,status)
 values(battle_id,attacker.id,case when bot.id is null then defender.id else bot.id end,v_opp_type,result,change,reward,coalesce(v_xp,0),'settled')
 on conflict (battle_id) do nothing;

 raise notice 'PVP_REWARD_SETTLEMENT battle=% player=% result=% trophies=% xp=% fc=% opponent=% status=settled',
   battle_id, attacker.telegram_id, result, change, coalesce(v_xp,0), reward, v_opp_type;

 return jsonb_build_object('battleId',battle_id,'result',result,'winnerId',winner,'isBotBattle',bot.id is not null,
   'totalTurns',v_turns,'rewardFc',reward,'trophyChange',change,'battleLog',coalesce(sim->'battleLog','[]'::jsonb),
   'attackerState',coalesce(sim->'attackerState',atk),'defenderState',coalesce(sim->'defenderState',def),
   'defenderPower',v_def_power,
   'trophiesAfter',v_trophies_after,'balanceFc',v_fc_after,'xpAwarded',coalesce(v_xp,0),'opponentType',v_opp_type);
end$function$;

-- ============================================================
-- 3) PvP audit + idempotent repair (never pays twice)
-- ============================================================
create or replace function public.pvp_audit_unpaid_rewards(p_hours integer default 48)
returns jsonb language sql security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'battleId', b.id, 'playerId', b.attacker_id, 'result', b.result,
    'trophies', b.trophy_change, 'fc', b.reward_fc,
    'opponentType', case when b.is_bot_battle then 'AI_BOT' else 'REAL_PLAYER' end,
    'createdAt', b.created_at)), '[]'::jsonb)
  from pvp_battles b
  left join pvp_reward_settlements s on s.battle_id = b.id
  where b.created_at > now() - make_interval(hours => greatest(1, p_hours))
    and s.id is null;
$$;

create or replace function public.pvp_repair_unpaid_rewards(p_hours integer default 48)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r record; n integer := 0; fc numeric := 0; tr integer := 0;
begin
  for r in select b.* from pvp_battles b
            left join pvp_reward_settlements s on s.battle_id = b.id
           where b.created_at > now() - make_interval(hours => greatest(1, p_hours))
             and s.id is null
           order by b.created_at loop
    -- The settlement row is the idempotency lock: it is inserted first, so a
    -- second run (or a retry) can never credit the same battle twice.
    insert into pvp_reward_settlements(battle_id,player_id,opponent_id,opponent_type,result,trophies_awarded,fc_awarded,status,note)
    values(r.id,r.attacker_id,coalesce(r.defender_id,r.defender_bot_id),
           case when r.is_bot_battle then 'AI_BOT' else 'REAL_PLAYER' end,
           r.result,coalesce(r.trophy_change,0),coalesce(r.reward_fc,0),'settled','repaired')
    on conflict (battle_id) do nothing;
    if not found then continue; end if;
    update game_players
       set pvp_trophies = greatest(0, pvp_trophies + coalesce(r.trophy_change,0)),
           forge_coins = forge_coins + coalesce(r.reward_fc,0),
           updated_at = now()
     where id = r.attacker_id;
    n := n + 1; fc := fc + coalesce(r.reward_fc,0); tr := tr + coalesce(r.trophy_change,0);
    raise notice 'PVP_REWARD_SETTLEMENT battle=% player=% status=repaired trophies=% fc=%', r.id, r.attacker_id, r.trophy_change, r.reward_fc;
  end loop;
  return jsonb_build_object('repaired', n, 'fc', fc, 'trophies', tr);
end $$;

revoke all on function public.pvp_audit_unpaid_rewards(integer) from public, anon, authenticated;
revoke all on function public.pvp_repair_unpaid_rewards(integer) from public, anon, authenticated;
grant execute on function public.pvp_audit_unpaid_rewards(integer) to service_role;
grant execute on function public.pvp_repair_unpaid_rewards(integer) to service_role;

-- ============================================================
-- 4) MARKET: FC sales settle instantly. The TON branch is byte-for-byte the same.
-- ============================================================
CREATE OR REPLACE FUNCTION public.market_finalize_purchase(p_listing_id uuid, p_buyer uuid, p_external boolean DEFAULT false, p_tx_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  l market_listings%rowtype; g game_players%rowtype; settings jsonb; cur text;
  fee_amount numeric; received numeric; hold_hours integer; tx_id uuid;
  risk jsonb; score integer; flags text[]; new_status text; value_fc numeric;
  buyer_before numeric; buyer_after numeric; pair_trades integer; pair_fc numeric;
  buy_today numeric; v5 integer; v24 integer; vel jsonb; pl jsonb; nal jsonb;
  ton_before numeric; is_admin boolean; settled_now boolean := false; fee_pct numeric;
begin
  perform set_config('mythreon.market_txn', '1', true);
  settings := market_settings_json();

  select * into g from game_players where id = p_buyer for update;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  is_admin := market_is_bypass_admin(g.telegram_id);
  if coalesce(g.banned,false) then raise exception 'ACCOUNT_BANNED'; end if;
  if not is_admin then
    if g.market_cooldown_until is not null and g.market_cooldown_until > now() then raise exception 'MARKET_TEMPORARILY_LIMITED'; end if;
    if g.market_restricted_until is not null and g.market_restricted_until > now() then raise exception 'MARKET_TEMPORARILY_LIMITED'; end if;
  end if;

  -- The listing row lock is the anti-duplication guard: double taps, retries and
  -- two buyers at the same time all serialise here and only the first one wins.
  select * into l from market_listings where id = p_listing_id for update;
  if l.id is null then raise exception 'LISTING_NOT_FOUND'; end if;
  cur := coalesce(l.currency,'FC');
  if l.status = 'reserved' then
    if l.reserved_for is distinct from p_buyer and coalesce(l.reserved_until, now()) > now() then raise exception 'ITEM_RESERVED'; end if;
  elsif l.status <> 'active' then
    raise exception 'ITEM_NO_LONGER_AVAILABLE';
  end if;
  if l.seller_user_id = p_buyer then raise exception 'CANNOT_BUY_OWN_LISTING'; end if;

  value_fc := coalesce(l.price_fc, l.price_ton * 100000);

  if not is_admin then
    vel := settings->'velocity';
    select count(*) into v5 from market_transactions where buyer_user_id = p_buyer and created_at > now() - interval '5 minutes';
    select count(*) into v24 from market_transactions where buyer_user_id = p_buyer and created_at > now() - interval '24 hours';
    if v5 >= coalesce((vel->>'per5m')::integer, 5) or v24 >= coalesce((vel->>'per24h')::integer, 40) then
      update game_players set market_cooldown_until = now() + make_interval(mins => coalesce((vel->>'cooldownMinutes')::integer, 360)) where id = p_buyer;
      insert into market_security_audit(event, listing_id, buyer_user_id, seller_user_id, currency, price_fc, price_ton, risk_flags, details)
      values ('risk_flag', l.id, p_buyer, l.seller_user_id, cur, l.price_fc, l.price_ton, array['HIGH_VELOCITY'], jsonb_build_object('per5m', v5, 'per24h', v24));
      raise exception 'MARKET_TEMPORARILY_LIMITED';
    end if;

    pl := settings->'pairLimits';
    select count(*), coalesce(sum(coalesce(price_fc, price_ton * 100000)),0) into pair_trades, pair_fc
      from market_transactions
     where buyer_user_id = p_buyer and seller_user_id = l.seller_user_id
       and status <> 'reversed' and created_at > now() - interval '24 hours';
    if pair_trades >= coalesce((pl->>'tradesPerDay')::integer, 3) then raise exception 'PAIR_TRADE_LIMIT'; end if;
    if pair_fc + value_fc > coalesce((pl->>'fcPerDay')::numeric, 2000000) then raise exception 'PAIR_VALUE_LIMIT'; end if;

    if cur = 'FC' then
      nal := settings->'newAccountLimits';
      if market_account_days(p_buyer) < coalesce((nal->>'days')::integer, 7) then
        select coalesce(sum(price_fc),0) into buy_today from market_transactions
         where buyer_user_id = p_buyer and coalesce(currency,'FC') = 'FC' and status <> 'reversed' and created_at > now() - interval '24 hours';
        if buy_today + l.price_fc > coalesce((nal->>'buyFcPerDay')::numeric, 500000) then raise exception 'DAILY_BUY_LIMIT'; end if;
      end if;
    end if;
  end if;

  risk := market_risk_assess(p_buyer, l.seller_user_id, l);
  score := (risk->>'score')::integer;
  flags := array(select jsonb_array_elements_text(risk->'flags'));
  new_status := case when score >= 60 or 'SAME_WALLET' = any(flags) or 'CIRCULAR_TRADE' = any(flags)
                       or 'ITEM_RETURNED' = any(flags) then 'review' else 'pending' end;

  if cur = 'TON' then
    -- Fee ALWAYS comes from the backend config, never from the listing row or
    -- the API request, so a tampered fee (0%, 1%, ...) can never be honoured.
    fee_pct := coalesce((settings->>'feePercentTon')::numeric, 5);
    fee_amount := round(l.price_ton * fee_pct / 100, 9);
    received := round(l.price_ton - fee_amount, 9);
    hold_hours := 0;
    buyer_after := coalesce(g.ton_balance, 0);
    if not p_external then
      ton_before := coalesce(g.ton_balance, 0);
      if ton_before < l.price_ton then raise exception 'INSUFFICIENT_TON'; end if;
      buyer_after := round(ton_before - l.price_ton, 9);
      update game_players set ton_balance = buyer_after, updated_at = now() where id = p_buyer;
      insert into ton_reward_ledger(user_id, amount_ton, direction, source_type, source_id, note, balance_after)
      values (p_buyer, l.price_ton, 'debit', 'market_purchase_ton', l.id::text, 'Market purchase', buyer_after);
    end if;
    update game_players set market_pending_ton = coalesce(market_pending_ton,0) + received, updated_at = now()
      where id = l.seller_user_id;
  else
    -- FC: the buyer is debited and the seller's net FC is credited in this same
    -- transaction (no 72h hold), so the item is never delivered unpaid.
    buyer_before := g.forge_coins;
    if buyer_before < l.price_fc then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;
    fee_pct := coalesce((settings->>'feePercent')::numeric, 5);
    fee_amount := round(l.price_fc * fee_pct / 100);
    received := l.price_fc - fee_amount;
    hold_hours := 0;
    update game_players set forge_coins = forge_coins - l.price_fc, updated_at = now()
      where id = p_buyer returning forge_coins into buyer_after;
    update game_players set market_pending_fc = market_pending_fc + received, updated_at = now()
      where id = l.seller_user_id;
  end if;

  if l.item_type = 'hero' then
    delete from pvp_team_slots where hero_id = l.item_instance_id;
    delete from boss_team_slots where player_hero_id = l.item_instance_id;
    update player_heroes set user_id = p_buyer, market_locked = false, updated_at = now() where id = l.item_instance_id;
  elsif l.item_type = 'pet' then
    update player_pets set user_id = p_buyer, market_locked = false, is_active = false, updated_at = now() where id = l.item_instance_id;
  else
    perform market_item_give(p_buyer, l.item_code, l.snapshot, coalesce(l.quantity,1));
  end if;

  update market_listings set status = 'sold', buyer_user_id = p_buyer, sold_at = now(),
    reserved_for = null, reserved_until = null, updated_at = now() where id = l.id;

  insert into market_transactions(listing_id, seller_user_id, buyer_user_id, item_type, item_instance_id, item_code,
    currency, price_fc, price_ton, fee_percent, fee_fc, fee_ton, seller_received_fc, seller_received_ton,
    snapshot, status, settle_at, risk_score, risk_flags, tx_hash)
  values (l.id, l.seller_user_id, p_buyer, l.item_type, l.item_instance_id, l.item_code,
    cur,
    case when cur = 'FC' then l.price_fc else null end,
    case when cur = 'TON' then l.price_ton else null end,
    fee_pct,
    case when cur = 'FC' then fee_amount else null end,
    case when cur = 'TON' then fee_amount else null end,
    case when cur = 'FC' then received else null end,
    case when cur = 'TON' then received else null end,
    l.snapshot, new_status, now() + make_interval(hours => hold_hours), score, flags, p_tx_hash)
  returning id into tx_id;

  insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id, listing_id, transaction_id, currency, price_fc, price_ton)
  values (l.item_type, l.item_instance_id, l.item_code, l.seller_user_id, p_buyer, l.id, tx_id, cur,
          case when cur = 'FC' then l.price_fc else null end,
          case when cur = 'TON' then l.price_ton else null end);

  insert into market_pair_stats(buyer_user_id, seller_user_id, trades, total_fc)
  values (p_buyer, l.seller_user_id, 1, value_fc)
  on conflict (buyer_user_id, seller_user_id) do update
    set trades = market_pair_stats.trades + 1,
        total_fc = market_pair_stats.total_fc + excluded.total_fc,
        last_trade_at = now();

  if cur = 'FC' then
    insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
    values (p_buyer, 'market_purchase', -l.price_fc, buyer_before, buyer_after, tx_id::text);
  end if;

  insert into market_security_audit(event, listing_id, transaction_id, buyer_user_id, seller_user_id, currency, price_ton, fee_ton, price_fc, fee_fc, risk_score, risk_flags, details)
  values ('sale_created', l.id, tx_id, p_buyer, l.seller_user_id, cur,
          case when cur = 'TON' then l.price_ton else null end,
          case when cur = 'TON' then fee_amount else null end,
          case when cur = 'FC' then l.price_fc else null end,
          case when cur = 'FC' then fee_amount else null end, score, flags,
          jsonb_build_object('status', new_status, 'currency', cur, 'price', coalesce(l.price_fc, l.price_ton),
                             'external', p_external, 'txHash', p_tx_hash,
                             'settleAt', now() + make_interval(hours => hold_hours)));

  -- Neither TON nor FC sales have a hold: both settle in the SAME transaction, so
  -- the seller is credited the moment the purchase is confirmed. Sales flagged for
  -- review keep waiting for the admin, exactly as before.
  if new_status = 'pending' then
    perform market_settle_transaction(tx_id, null);
    settled_now := true;
    if cur = 'FC' then
      raise notice 'MARKET_FC_SETTLEMENT listing=% buyer=% seller=% gross=% fee=% net=% status=settled',
        l.id, p_buyer, l.seller_user_id, l.price_fc, fee_amount, received;
    end if;
  end if;

  insert into player_notifications(user_id, type, title, message, amount_fc, metadata, dedupe_key)
  values (l.seller_user_id, 'market_sale', 'MARKET',
    coalesce(l.snapshot->>'name','Item') || ' → ' ||
      case when cur = 'TON' then l.price_ton::text || ' TON' else l.price_fc::bigint::text || ' FC' end,
    case when cur = 'FC' then received else null end,
    jsonb_build_object('listingId', l.id, 'currency', cur, 'fee', fee_amount, 'holdHours', hold_hours,
                       'status', case when settled_now then 'settled' else 'pending' end),
    'market_sale:' || l.id::text)
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'currency', cur,
    'pricePaid', coalesce(l.price_fc, l.price_ton), 'priceFc', l.price_fc, 'priceTon', l.price_ton,
    'feeFc', case when cur = 'FC' then fee_amount else null end,
    'feeTon', case when cur = 'TON' then fee_amount else null end,
    'sellerReceived', received, 'balanceFc', case when cur = 'FC' then buyer_after else g.forge_coins end,
    'balanceTon', case when cur = 'TON' then buyer_after else coalesce(g.ton_balance,0) end,
    'itemType', l.item_type, 'name', l.snapshot->>'name', 'settlementHours', hold_hours,
    'settledInstantly', settled_now,
    'transactionId', tx_id, 'underReview', new_status = 'review');
end $function$;

-- ============================================================
-- 5) Audit + idempotent repair for FC sales that were left unpaid
-- ============================================================
create or replace function public.market_audit_unpaid_fc_sales()
returns jsonb language sql security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'transactionId', t.id, 'listingId', t.listing_id, 'sellerId', t.seller_user_id,
    'buyerId', t.buyer_user_id, 'grossFc', t.price_fc, 'feeFc', t.fee_fc,
    'sellerNetFc', t.seller_received_fc, 'status', t.status, 'createdAt', t.created_at)), '[]'::jsonb)
  from market_transactions t
  join market_listings l on l.id = t.listing_id
  where coalesce(t.currency,'FC') = 'FC' and t.status = 'pending' and l.status = 'sold'
    and not exists (select 1 from wallet_ledger w
                     where w.user_id = t.seller_user_id and w.type = 'market_sale' and w.reference_id = t.id::text);
$$;

create or replace function public.market_repair_unpaid_fc_sales()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r record; n integer := 0; total numeric := 0;
begin
  for r in select t.id, t.seller_user_id, t.price_fc, t.fee_fc, t.seller_received_fc
             from market_transactions t
             join market_listings l on l.id = t.listing_id
            where coalesce(t.currency,'FC') = 'FC' and t.status = 'pending' and l.status = 'sold'
              and not exists (select 1 from wallet_ledger w
                               where w.user_id = t.seller_user_id and w.type = 'market_sale' and w.reference_id = t.id::text)
            order by t.created_at loop
    -- market_settle_transaction is idempotent (status guard + ledger conflict),
    -- so nobody already paid can ever be paid a second time.
    perform market_settle_transaction(r.id, null);
    n := n + 1; total := total + coalesce(r.seller_received_fc,0);
    raise notice 'MARKET_FC_SETTLEMENT transaction=% seller=% gross=% fee=% net=% status=repaired',
      r.id, r.seller_user_id, r.price_fc, r.fee_fc, r.seller_received_fc;
  end loop;
  return jsonb_build_object('repaired', n, 'creditedFc', total);
end $$;

revoke all on function public.market_audit_unpaid_fc_sales() from public, anon, authenticated;
revoke all on function public.market_repair_unpaid_fc_sales() from public, anon, authenticated;
grant execute on function public.market_audit_unpaid_fc_sales() to service_role;
grant execute on function public.market_repair_unpaid_fc_sales() to service_role;