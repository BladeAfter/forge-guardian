CREATE OR REPLACE FUNCTION public.claim_calendar_day(p_telegram_id bigint, p_day integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u game_players%rowtype; d jsonb; cycle text; expected int; r calendar_reward_config%rowtype; key text; egg uuid; inv_id uuid; today date := public.game_day_key(); v_item_type text;
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
    -- player_inventory has no provenance column: stack on (user_id,item_type,item_code) only.
    v_item_type := case when coalesce(r.reward_type,'') in ('', 'chest', 'hero_chest') then 'hero_chest' else r.reward_type end;
    if coalesce(r.item_code,'') = '' then raise exception 'CALENDAR_REWARD_DISABLED'; end if;
    insert into player_inventory(user_id,item_type,item_code,quantity)
      values(u.id,v_item_type,r.item_code,1)
      on conflict(user_id,item_type,item_code) do update set quantity=player_inventory.quantity+1, updated_at=now()
      returning id into inv_id;
  end if;
  select forge_coins into u.forge_coins from game_players where id=u.id;
  return jsonb_build_object(
    'reward',jsonb_build_object('day',r.day,'type',r.reward_type,'amountFc',r.amount_fc,'itemCode',r.item_code,'title',r.title,'subtitle',r.subtitle),
    'balance',u.forge_coins,
    'inventoryItemId',inv_id,
    'dashboard',get_calendar_dashboard(p_telegram_id));
end $function$;