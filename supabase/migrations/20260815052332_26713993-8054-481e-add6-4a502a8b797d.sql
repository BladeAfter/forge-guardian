create or replace function public.pvp_hero_block_reason(h player_heroes)
returns text language sql stable set search_path to 'public' as $$
  select case
    when h.market_locked or exists(
      select 1 from market_listings l
      where l.item_type='hero' and l.item_instance_id=h.id and l.status='active'
    ) then 'MARKET'
    when h.locked then 'LOCKED'
    when exists(select 1 from boss_team_slots b where b.player_hero_id=h.id) then 'GLOBAL_BOSS'
    when exists(select 1 from tower_team_slots tw where tw.hero_id=h.id) then 'TOWER'
    else null
  end
$$;

create or replace function public.pvp_hero_json(h player_heroes)
returns jsonb language sql stable set search_path to 'public' as $$
  select jsonb_build_object(
    'heroId',h.id,'templateId',public.pvp_hero_template_key(h),'heroKey',h.hero_key,
    'name',h.name,'imageUrl',h.image,'rarity',normalize_hero_rarity(h.rarity),'level',h.level,
    'archetype',h.archetype,'finalAtk',h.final_atk,'finalHp',h.final_hp,'defense',0,'speed',h.level,
    'power',round(h.final_atk*2.2+h.final_hp*.18+h.level*25),
    'locked',coalesce(h.locked,false),'marketLocked',coalesce(h.market_locked,false),
    'blockReason',public.pvp_hero_block_reason(h)
  )
$$;

create or replace function public.save_pvp_team_slot(p_telegram_id bigint, p_team_type text, p_slot integer, p_hero_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare u uuid; v_tpl text; v_block text;
begin
  if p_team_type not in('attack','defense') or p_slot not between 1 and 5 then raise exception 'INVALID_TEAM_SLOT';end if;
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND';end if;
  select public.pvp_hero_template_key(h), public.pvp_hero_block_reason(h) into v_tpl, v_block
    from player_heroes h where h.id=p_hero_id and h.user_id=u;
  if v_tpl is null then raise exception 'HERO_NOT_OWNED';end if;
  if coalesce(v_block,'') in ('MARKET','LOCKED') then raise exception 'HERO_UNAVAILABLE_%',v_block;end if;
  if exists(select 1 from pvp_team_slots s join player_heroes h on h.id=s.hero_id
            where s.user_id=u and s.team_type=p_team_type and s.slot<>p_slot
              and s.hero_id<>p_hero_id
              and public.pvp_hero_template_key(h)=v_tpl) then
    raise exception 'PVP_DUPLICATE_HERO';
  end if;
  delete from pvp_team_slots where user_id=u and team_type=p_team_type and hero_id=p_hero_id and slot<>p_slot;
  insert into pvp_team_slots(user_id,team_type,slot,hero_id) values(u,p_team_type,p_slot,p_hero_id)
    on conflict(user_id,team_type,slot) do update set hero_id=excluded.hero_id,updated_at=now();
  return get_pvp_dashboard(p_telegram_id);
end$function$;

revoke all on function public.pvp_hero_block_reason(player_heroes) from public, anon, authenticated;
revoke all on function public.pvp_hero_json(player_heroes) from public, anon, authenticated;
revoke all on function public.save_pvp_team_slot(bigint,text,integer,uuid) from public, anon, authenticated;
grant execute on function public.pvp_hero_block_reason(player_heroes) to service_role;
grant execute on function public.pvp_hero_json(player_heroes) to service_role;
grant execute on function public.save_pvp_team_slot(bigint,text,integer,uuid) to service_role;