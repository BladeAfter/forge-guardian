-- Remove any remaining duplicate claims inside the same official game day (keeps the first, audits the rest).
with bad as (
  select c.id, c.user_id, c.day, c.calendar_cycle, c.claimed_at, c.game_day
  from public.daily_calendar_claims c
  where c.id <> (select c2.id from public.daily_calendar_claims c2
                 where c2.user_id=c.user_id and c2.game_day=c.game_day
                 order by c2.claimed_at asc, c2.id asc limit 1)
)
insert into public.calendar_repair_audit(user_id,claim_id,day,calendar_cycle,claimed_at,game_day,reason)
select user_id,id,day,calendar_cycle,claimed_at,game_day,'avanço indevido: mais de um resgate no mesmo dia oficial' from bad;

delete from public.daily_calendar_claims c
using public.calendar_repair_audit a where a.claim_id = c.id;

with ordered as (
  select id, row_number() over (partition by user_id, calendar_cycle order by game_day, claimed_at) as rn
  from public.daily_calendar_claims)
update public.daily_calendar_claims c set day = o.rn from ordered o where o.id=c.id and c.day <> o.rn;

-- Dashboard: the claimed day never advances the pointer. One official game day = exactly one claimable day.
create or replace function public.get_calendar_dashboard(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare u game_players%rowtype; cycle text; claimed int; today date := public.game_day_key();
  claimed_today boolean; day_number int := public.game_day_number();
  current_day int; available_day int; claimed_days jsonb;
begin
  select * into u from game_players where telegram_id=p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select coalesce(max(calendar_cycle::int),1)::text into cycle from daily_calendar_claims where user_id=u.id;
  select count(*) into claimed from daily_calendar_claims where user_id=u.id and calendar_cycle=cycle;
  select exists(select 1 from daily_calendar_claims where user_id=u.id and game_day=today) into claimed_today;
  if claimed>=30 and not claimed_today then cycle:=(cycle::int+1)::text; claimed:=0; end if;
  select count(*) into claimed from daily_calendar_claims where user_id=u.id and calendar_cycle=cycle;

  -- Claiming marks the current day only; the next day opens on the next 21:00 rollover.
  if claimed_today then
    current_day := greatest(1, least(claimed, 30));
    available_day := null;
  else
    current_day := least(claimed + 1, 30);
    available_day := current_day;
  end if;

  claimed_days := (select coalesce(jsonb_agg(day order by day),'[]'::jsonb) from daily_calendar_claims where user_id=u.id and calendar_cycle=cycle);

  return jsonb_build_object(
    'cycle',cycle,
    'currentDay',current_day,
    'availableDay',available_day,
    'claimedDays',claimed_days,
    'dayStatuses',(select jsonb_object_agg(d::text,
        case when claimed_days ? to_jsonb(d)::text or claimed_days @> to_jsonb(array[d]) then 'CLAIMED'
             when d = available_day then 'AVAILABLE'
             else 'LOCKED' end)
      from generate_series(1,30) d),
    'canClaim',(claimed<30 and not claimed_today),
    'claimedToday',claimed_today,
    'gameDay',today,
    'gameDayNumber',day_number,
    'nextResetAt',public.game_next_reset_at(),
    'serverTime',now(),
    'rewards',(select jsonb_agg(jsonb_build_object('day',day,'type',reward_type,'amountFc',amount_fc,'itemCode',item_code,'title',title,'subtitle',subtitle) order by day) from calendar_reward_config where enabled),
    'balance',u.forge_coins);
end $$;

-- Claim: atomic, one per (user, official game day), and it validates against the single available day.
create or replace function public.claim_calendar_day(p_telegram_id bigint, p_day integer)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u game_players%rowtype; d jsonb; cycle text; expected int; r calendar_reward_config%rowtype; key text; egg uuid; inv_id uuid; today date := public.game_day_key();
begin
  select * into u from game_players where telegram_id=p_telegram_id for update;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  d:=get_calendar_dashboard(p_telegram_id); cycle:=d->>'cycle';
  if not (d->>'canClaim')::boolean then raise exception 'CALENDAR_ALREADY_CLAIMED_TODAY'; end if;
  expected:=(d->>'availableDay')::int;
  if expected is null then raise exception 'CALENDAR_ALREADY_CLAIMED_TODAY'; end if;
  if p_day<>expected then raise exception 'CALENDAR_DAY_LOCKED'; end if;
  select * into r from calendar_reward_config where day=p_day and enabled for share;
  if r.day is null then raise exception 'CALENDAR_REWARD_DISABLED'; end if;
  key:='calendar_claim:'||today::text||':'||u.id;
  begin
    insert into daily_calendar_claims(user_id,calendar_cycle,day,reward_type,reward_code,amount_fc,idempotency_key,game_day)
      values(u.id,cycle,p_day,r.reward_type,r.item_code,r.amount_fc,key,today);
  exception when unique_violation then raise exception 'CALENDAR_ALREADY_CLAIMED_TODAY';
  end;
  if r.reward_type='fc' then
    update game_players set forge_coins=forge_coins+r.amount_fc, updated_at=now() where id=u.id;
  elsif r.reward_type='pet_egg' then
    select id into egg from pet_eggs where slug=r.item_code and is_enabled;
    if egg is null then raise exception 'CALENDAR_EGG_NOT_FOUND'; end if;
    insert into player_pet_inventory(user_id,item_type,item_id,quantity) values(u.id,'egg',egg,1)
      on conflict(user_id,item_type,(coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)),(coalesce(item_code,''))) do update set quantity=player_pet_inventory.quantity+1
      returning id into inv_id;
  else
    insert into player_inventory(user_id,item_type,item_code,quantity,source)
      values(u.id,'hero_chest',r.item_code,1,'calendar')
      on conflict(user_id,item_type,item_code) do update set quantity=player_inventory.quantity+1, updated_at=now()
      returning id into inv_id;
  end if;
  select forge_coins into u.forge_coins from game_players where id=u.id;
  return jsonb_build_object(
    'reward',jsonb_build_object('day',r.day,'type',r.reward_type,'amountFc',r.amount_fc,'itemCode',r.item_code,'title',r.title,'subtitle',r.subtitle),
    'balance',u.forge_coins,
    'inventoryItemId',inv_id,
    'dashboard',get_calendar_dashboard(p_telegram_id));
end $$;