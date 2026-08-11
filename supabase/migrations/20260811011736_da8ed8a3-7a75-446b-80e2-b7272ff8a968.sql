-- ============ 1. OFFICIAL SETTINGS ============
insert into public.game_settings(key,value,category,label) values
  ('game_timezone','"America/Sao_Paulo"'::jsonb,'general','Fuso horário oficial do jogo'),
  ('game_day_reset_hour','21'::jsonb,'general','Hora oficial da virada do dia (0-23)'),
  ('game_launch_at','"2026-08-10T21:00:00-03:00"'::jsonb,'general','Data e hora oficial de lançamento')
on conflict(key) do nothing;

-- ============ 2. CENTRAL GAME DAY FUNCTIONS ============
create or replace function public.game_timezone()
returns text language sql stable security definer set search_path to 'public' as $$
  select coalesce(nullif(trim(both '"' from (select value::text from public.game_settings where key='game_timezone')),''),'America/Sao_Paulo');
$$;

create or replace function public.game_day_reset_hour()
returns int language sql stable security definer set search_path to 'public' as $$
  select coalesce(nullif(trim(both '"' from (select value::text from public.game_settings where key='game_day_reset_hour')),'')::int,21);
$$;

-- Official game day: the calendar date (in the official timezone) of the 21:00 boundary that opened the current day.
create or replace function public.game_day_key(p_at timestamptz default now())
returns date language plpgsql stable security definer set search_path to 'public' as $$
declare tz text := public.game_timezone(); h int := public.game_day_reset_hour(); l timestamp;
begin
  l := p_at at time zone tz;
  if extract(hour from l) >= h then return l::date; else return (l::date - 1); end if;
exception when others then
  l := p_at at time zone 'UTC';
  if extract(hour from l) >= 21 then return l::date; else return (l::date - 1); end if;
end $$;

-- Absolute timestamp when the given game day started (21:00 official time).
create or replace function public.game_day_start(p_day date default null)
returns timestamptz language plpgsql stable security definer set search_path to 'public' as $$
declare tz text := public.game_timezone(); h int := public.game_day_reset_hour(); d date := coalesce(p_day, public.game_day_key());
begin
  return (d::timestamp + make_interval(hours => h)) at time zone tz;
exception when others then
  return (d::timestamp + make_interval(hours => 21)) at time zone 'UTC';
end $$;

create or replace function public.game_next_reset_at(p_at timestamptz default now())
returns timestamptz language sql stable security definer set search_path to 'public' as $$
  select public.game_day_start(public.game_day_key(p_at) + 1);
$$;

create or replace function public.game_launch_day()
returns date language sql stable security definer set search_path to 'public' as $$
  select public.game_day_key(coalesce(
    nullif(trim(both '"' from (select value::text from public.game_settings where key='game_launch_at')),'')::timestamptz,
    '2026-08-10T21:00:00-03:00'::timestamptz));
$$;

-- Day 1 is the launch game day; never below 1.
create or replace function public.game_day_number(p_at timestamptz default now())
returns int language sql stable security definer set search_path to 'public' as $$
  select greatest(1, (public.game_day_key(p_at) - public.game_launch_day()) + 1);
$$;

create or replace function public.game_day_state()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'timezone', public.game_timezone(),
    'resetHour', public.game_day_reset_hour(),
    'serverTime', now(),
    'serverLocalTime', to_char(now() at time zone public.game_timezone(),'YYYY-MM-DD HH24:MI:SS'),
    'gameDay', public.game_day_key(),
    'gameDayNumber', public.game_day_number(),
    'gameDayStartedAt', public.game_day_start(),
    'nextResetAt', public.game_next_reset_at(),
    'launchAt', public.game_day_start(public.game_launch_day()),
    'launchDay', public.game_launch_day());
$$;

-- Every daily system now shares the official boundary.
create or replace function public.quest_today()
returns date language sql stable security definer set search_path to 'public' as $$
  select public.game_day_key();
$$;

-- ============ 3. AUDIT TABLE ============
create table if not exists public.calendar_repair_audit(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  claim_id uuid not null,
  day int not null,
  calendar_cycle text not null,
  claimed_at timestamptz not null,
  game_day date,
  reason text not null,
  created_at timestamptz not null default now()
);
grant all on public.calendar_repair_audit to service_role;
alter table public.calendar_repair_audit enable row level security;
create policy "service role manages calendar repair audit" on public.calendar_repair_audit for all to service_role using (true) with check (true);

-- ============ 4. CALENDAR CLAIMS BOUND TO THE OFFICIAL GAME DAY ============
alter table public.daily_calendar_claims add column if not exists game_day date;
update public.daily_calendar_claims set game_day = public.game_day_key(claimed_at) where game_day is null;

-- Audit + remove impossible progress: pre-launch claims and duplicates within one official day.
with launch as (select public.game_launch_day() as d),
bad as (
  select c.id, c.user_id, c.day, c.calendar_cycle, c.claimed_at, c.game_day,
    case when c.game_day < (select d from launch) then 'claim antes do lançamento oficial'
         else 'mais de um resgate no mesmo dia oficial' end as reason
  from public.daily_calendar_claims c
  where c.game_day < (select d from launch)
     or c.id <> (select c2.id from public.daily_calendar_claims c2
                 where c2.user_id=c.user_id and c2.game_day=c.game_day
                 order by c2.claimed_at asc, c2.id asc limit 1)
)
insert into public.calendar_repair_audit(user_id,claim_id,day,calendar_cycle,claimed_at,game_day,reason)
select user_id,id,day,calendar_cycle,claimed_at,game_day,reason from bad;

delete from public.daily_calendar_claims c
using public.calendar_repair_audit a where a.claim_id = c.id;

-- Renumber the remaining legitimate claims so day order matches the official days.
with ordered as (
  select id, row_number() over (partition by user_id, calendar_cycle order by game_day, claimed_at) as rn
  from public.daily_calendar_claims)
update public.daily_calendar_claims c set day = o.rn from ordered o where o.id=c.id and c.day <> o.rn;

alter table public.daily_calendar_claims alter column game_day set default public.game_day_key();
alter table public.daily_calendar_claims alter column game_day set not null;
create unique index if not exists daily_calendar_claims_user_game_day_key on public.daily_calendar_claims(user_id, game_day);

-- ============ 5. DASHBOARD / CLAIM ============
create or replace function public.get_calendar_dashboard(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare u game_players%rowtype; cycle text; claimed int; today date := public.game_day_key();
  claimed_today boolean; day_number int := public.game_day_number();
begin
  select * into u from game_players where telegram_id=p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select coalesce(max(calendar_cycle::int),1)::text into cycle from daily_calendar_claims where user_id=u.id;
  select count(*) into claimed from daily_calendar_claims where user_id=u.id and calendar_cycle=cycle;
  select exists(select 1 from daily_calendar_claims where user_id=u.id and game_day=today) into claimed_today;
  if claimed>=30 and not claimed_today then cycle:=(cycle::int+1)::text; claimed:=0; end if;
  return jsonb_build_object(
    'cycle',cycle,
    'currentDay',least(claimed+1,30),
    'claimedDays',(select coalesce(jsonb_agg(day order by day),'[]') from daily_calendar_claims where user_id=u.id and calendar_cycle=cycle),
    'canClaim',(claimed<30 and not claimed_today),
    'claimedToday',claimed_today,
    'gameDay',today,
    'gameDayNumber',day_number,
    'nextResetAt',public.game_next_reset_at(),
    'serverTime',now(),
    'rewards',(select jsonb_agg(jsonb_build_object('day',day,'type',reward_type,'amountFc',amount_fc,'itemCode',item_code,'title',title,'subtitle',subtitle) order by day) from calendar_reward_config where enabled),
    'balance',u.forge_coins);
end $$;

create or replace function public.claim_calendar_day(p_telegram_id bigint, p_day integer)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u game_players%rowtype; d jsonb; cycle text; expected int; r calendar_reward_config%rowtype; key text; egg uuid; inv_id uuid; today date := public.game_day_key();
begin
  select * into u from game_players where telegram_id=p_telegram_id for update;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  d:=get_calendar_dashboard(p_telegram_id); cycle:=d->>'cycle'; expected:=(d->>'currentDay')::int;
  if not (d->>'canClaim')::boolean then raise exception 'CALENDAR_ALREADY_CLAIMED_TODAY'; end if;
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
      on conflict(user_id,item_type,(coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)))
      do update set quantity=player_pet_inventory.quantity+1, updated_at=now() returning id into inv_id;
  else
    if not exists(select 1 from chest_reward_tables where chest_code=r.item_code and enabled) then raise exception 'CALENDAR_CHEST_NOT_CONFIGURED'; end if;
    insert into player_inventory(user_id,item_type,item_code,quantity) values(u.id,'hero_chest',r.item_code,1)
      on conflict(user_id,item_type,item_code) do update set quantity=player_inventory.quantity+1, updated_at=now() returning id into inv_id;
  end if;
  insert into calendar_reward_history(user_id,day,reward_type,reward_code,amount_fc,result_data,idempotency_key)
    values(u.id,p_day,r.reward_type,r.item_code,r.amount_fc,jsonb_build_object('inventoryItemId',inv_id,'gameDay',today),key);
  return jsonb_build_object('reward',jsonb_build_object('day',r.day,'type',r.reward_type,'amountFc',r.amount_fc,'itemCode',r.item_code,'title',r.title,'subtitle',r.subtitle),
    'balance',(select forge_coins from game_players where id=u.id),'inventoryItemId',inv_id,
    'inventory',get_player_inventory(p_telegram_id),'dashboard',get_calendar_dashboard(p_telegram_id));
end $$;

-- ============ 6. ADMIN VIEW ============
create or replace function public.admin_game_day_state(p_admin_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public.admin_assert(p_admin_id);
  return public.game_day_state() || jsonb_build_object(
    'repairedClaims',(select count(*) from public.calendar_repair_audit),
    'claimsToday',(select count(*) from public.daily_calendar_claims where game_day=public.game_day_key()));
end $$;
