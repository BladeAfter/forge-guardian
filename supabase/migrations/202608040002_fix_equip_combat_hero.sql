create or replace function public.equip_combat_hero(
  p_telegram_id bigint,
  p_hero_id uuid,
  p_slot integer
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_user_id uuid;
  v_combat public.boss_combats%rowtype;
  v_hero public.player_heroes%rowtype;
  v_state public.hero_combat_state%rowtype;
  v_occupant_id uuid;
  v_base_hp integer;
  v_max_hp integer;
  v_base_atk numeric;
  v_final_atk numeric;
begin
  if p_slot is null or p_slot < 1 or p_slot > 5 then
    raise exception 'INVALID_SLOT: slot must be an integer between 1 and 5';
  end if;

  perform public.process_boss_combat(p_telegram_id);

  select id into v_user_id
  from public.game_players
  where telegram_id=p_telegram_id;

  if v_user_id is null then
    raise exception 'PLAYER_NOT_FOUND';
  end if;

  select * into v_combat
  from public.boss_combats
  where user_id=v_user_id and status='active'
  for update;

  if v_combat.id is null then
    raise exception 'BOSS_NOT_ACTIVE';
  end if;

  select * into v_hero
  from public.player_heroes
  where id=p_hero_id and user_id=v_user_id;

  if v_hero.id is null then
    raise exception 'HERO_NOT_OWNED';
  end if;

  if exists (
    select 1 from public.hero_combat_state
    where combat_id=v_combat.id and hero_id=p_hero_id
      and slot is not null and slot<>p_slot
  ) then
    raise exception 'HERO_ALREADY_EQUIPPED';
  end if;

  select hero_id into v_occupant_id
  from public.hero_combat_state
  where combat_id=v_combat.id and slot=p_slot;

  if v_occupant_id=p_hero_id then
    return public.get_boss_combat(p_telegram_id);
  end if;

  if v_occupant_id is not null
     and v_combat.team_change_available_at is not null
     and v_combat.team_change_available_at>clock_timestamp() then
    raise exception 'TEAM_COOLDOWN';
  end if;

  select * into v_state
  from public.hero_combat_state
  where combat_id=v_combat.id and hero_id=p_hero_id
  for update;

  v_base_hp:=public.rarity_base_hp(v_hero.rarity);
  v_max_hp:=round(v_base_hp*(1+(greatest(1,v_hero.level)-1)*.05));
  v_base_atk:=public.rarity_base_atk(v_hero.rarity);
  v_final_atk:=round((v_base_atk*(1+(greatest(1,v_hero.level)-1)*.03))::numeric,3);

  update public.hero_combat_state
  set slot=null,updated_at=clock_timestamp()
  where combat_id=v_combat.id and slot=p_slot and hero_id<>p_hero_id;

  insert into public.hero_combat_state(
    combat_id,hero_id,slot,rarity,level,base_atk,final_atk,
    base_hp,max_hp,current_hp,is_alive,knocked_out_at,revive_at
  ) values (
    v_combat.id,v_hero.id,p_slot,public.normalize_hero_rarity(v_hero.rarity),
    greatest(1,v_hero.level),v_base_atk,v_final_atk,v_base_hp,v_max_hp,
    case when v_state.id is null then v_max_hp else least(v_max_hp,round(v_state.current_hp::numeric/nullif(v_state.max_hp,0)*v_max_hp)) end,
    coalesce(v_state.is_alive,true),v_state.knocked_out_at,v_state.revive_at
  )
  on conflict(combat_id,hero_id) do update set
    slot=excluded.slot,rarity=excluded.rarity,level=excluded.level,
    base_atk=excluded.base_atk,final_atk=excluded.final_atk,
    base_hp=excluded.base_hp,max_hp=excluded.max_hp,
    current_hp=least(excluded.max_hp,round(public.hero_combat_state.current_hp::numeric/nullif(public.hero_combat_state.max_hp,0)*excluded.max_hp)),
    is_alive=public.hero_combat_state.is_alive,
    knocked_out_at=public.hero_combat_state.knocked_out_at,
    revive_at=public.hero_combat_state.revive_at,
    updated_at=clock_timestamp();

  if v_occupant_id is not null then
    update public.boss_combats
    set team_change_available_at=clock_timestamp()+interval '60 seconds',updated_at=clock_timestamp()
    where id=v_combat.id;
  end if;

  return public.get_boss_combat(p_telegram_id);
end $$;

revoke all on function public.equip_combat_hero(bigint,uuid,integer) from public,anon,authenticated;
grant execute on function public.equip_combat_hero(bigint,uuid,integer) to service_role;
