drop function if exists public.admin_boss_control(bigint,text,text,text);

create table if not exists public.boss_team_slots (
  user_id uuid not null references public.game_players(id) on delete cascade,
  slot integer not null check (slot between 1 and 5),
  player_hero_id uuid not null references public.player_heroes(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, slot),
  unique (user_id, player_hero_id)
);
grant all on public.boss_team_slots to service_role;
alter table public.boss_team_slots enable row level security;

alter table public.boss_templates add column if not exists duration_seconds integer not null default 86400;

create or replace function public.active_boss_template()
returns public.boss_templates language sql stable security definer set search_path=public as $$
  select * from public.boss_templates
  where active
    and (starts_at is null or starts_at <= now())
    and (ends_at is null or ends_at > now())
  order by updated_at desc limit 1
$$;

create or replace function public.boss_team_json(p_user uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',h.id,'heroId',h.id,'name',h.name,'image',h.image,
    'rarity',public.normalize_hero_rarity(h.rarity),'slot',ts.slot,'level',greatest(1,h.level),
    'baseAtk',public.rarity_base_atk(h.rarity),
    'finalAtk',round((public.rarity_base_atk(h.rarity)*(1+(greatest(1,h.level)-1)*.03))::numeric,3),
    'baseHp',public.rarity_base_hp(h.rarity),
    'maxHp',round(public.rarity_base_hp(h.rarity)*(1+(greatest(1,h.level)-1)*.05)),
    'currentHp',round(public.rarity_base_hp(h.rarity)*(1+(greatest(1,h.level)-1)*.05)),
    'isAlive',true,'knockedOutAt',null,'reviveAt',null) order by ts.slot),'[]'::jsonb)
  from public.boss_team_slots ts join public.player_heroes h on h.id=ts.player_hero_id
  where ts.user_id=p_user
$$;

create or replace function public.sync_boss_team_state(p_user uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_combat uuid; r record; bhp int; mhp int; batk numeric; old public.hero_combat_state%rowtype;
begin
  select id into v_combat from public.boss_combats where user_id=p_user and status='active' limit 1;
  if v_combat is null then return; end if;
  update public.hero_combat_state s set slot=null,updated_at=clock_timestamp()
  where s.combat_id=v_combat and s.slot is not null
    and not exists (select 1 from public.boss_team_slots ts where ts.user_id=p_user and ts.player_hero_id=s.hero_id);
  for r in select ts.slot as team_slot, h.* from public.boss_team_slots ts join public.player_heroes h on h.id=ts.player_hero_id where ts.user_id=p_user loop
    bhp:=public.rarity_base_hp(r.rarity);
    mhp:=round(bhp*(1+(greatest(1,r.level)-1)*.05));
    batk:=round((public.rarity_base_atk(r.rarity)*(1+(greatest(1,r.level)-1)*.03))::numeric,3);
    select * into old from public.hero_combat_state where combat_id=v_combat and hero_id=r.id;
    insert into public.hero_combat_state(combat_id,hero_id,slot,rarity,level,base_atk,final_atk,base_hp,max_hp,current_hp,is_alive,knocked_out_at,revive_at)
    values(v_combat,r.id,r.team_slot,public.normalize_hero_rarity(r.rarity),greatest(1,r.level),public.rarity_base_atk(r.rarity),batk,bhp,mhp,
      case when old.id is null then mhp else least(mhp,round(old.current_hp::numeric/nullif(old.max_hp,0)*mhp)) end,
      coalesce(old.is_alive,true),old.knocked_out_at,old.revive_at)
    on conflict(combat_id,hero_id) do update set slot=excluded.slot,rarity=excluded.rarity,level=excluded.level,
      base_atk=excluded.base_atk,final_atk=excluded.final_atk,base_hp=excluded.base_hp,max_hp=excluded.max_hp,
      current_hp=least(excluded.max_hp,round(hero_combat_state.current_hp::numeric/nullif(hero_combat_state.max_hp,0)*excluded.max_hp)),
      is_alive=hero_combat_state.is_alive,knocked_out_at=hero_combat_state.knocked_out_at,
      revive_at=hero_combat_state.revive_at,updated_at=clock_timestamp();
  end loop;
end $$;

create or replace function public.ensure_boss_combat(p_telegram_id bigint)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_combat uuid; b public.boss_templates;
begin
  insert into public.game_players(telegram_id) values(p_telegram_id)
  on conflict(telegram_id) do update set updated_at=now() returning id into v_user;
  select id into v_combat from public.boss_combats where user_id=v_user and status='active';
  if v_combat is not null then return v_combat; end if;
  b:=public.active_boss_template();
  if b.code is null then return null; end if;
  insert into public.boss_combats(user_id,boss_id,boss_name,boss_level,boss_max_hp,boss_current_hp,boss_attack,boss_attack_interval_seconds,reward_amount)
  values(v_user,b.id,b.name,b.level,b.max_hp,b.max_hp,b.attack,greatest(1,b.attack_interval_seconds),b.reward_amount)
  returning id into v_combat;
  perform public.sync_boss_team_state(v_user);
  return v_combat;
end $$;

create or replace function public.get_boss_combat(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.boss_combats%rowtype; defeats_count int; v_user uuid; b public.boss_templates; v_active boolean;
begin
  insert into public.game_players(telegram_id) values(p_telegram_id)
  on conflict(telegram_id) do update set updated_at=now() returning id into v_user;
  b:=public.active_boss_template();
  v_active:=b.code is not null;
  select * into c from public.boss_combats where user_id=v_user and status in ('active','defeated')
  order by case status when 'defeated' then 0 else 1 end, created_at desc limit 1;
  select boss_defeats into defeats_count from public.game_players where id=v_user;
  if c.id is null then
    return jsonb_build_object('id',null,'bossId',b.id,'bossName',coalesce(b.name,'Nenhum chefe ativo'),
      'bossLevel',coalesce(b.level,1),'bossMaxHp',coalesce(b.max_hp,0),'bossCurrentHp',coalesce(b.max_hp,0),
      'bossAttack',coalesce(b.attack,0),'bossAttackIntervalSeconds',coalesce(b.attack_interval_seconds,60),
      'rewardAmount',coalesce(b.reward_amount,0),'status','inactive','bossActive',v_active,
      'bossStartsAt',b.starts_at,'bossEndsAt',b.ends_at,
      'totalDamageDealt',0,'defeats',coalesce(defeats_count,0),'startedAt',now(),'lastProcessedAt',now(),
      'nextHeroAttackAt',null,'bossLastAttackAt',null,'bossNextAttackAt',null,'defeatedAt',null,
      'rewardClaimedAt',null,'teamChangeAvailableAt',null,'serverNow',clock_timestamp(),
      'heroes',public.boss_team_json(v_user),
      'ownedHeroes',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'heroKey',h.hero_key,'name',h.name,'image',h.image,'rarity',public.normalize_hero_rarity(h.rarity),'level',h.level) order by h.created_at) from public.player_heroes h where h.user_id=v_user),'[]'::jsonb));
  end if;
  return jsonb_build_object('id',c.id,'bossId',c.boss_id,'bossName',c.boss_name,'bossLevel',c.boss_level,
    'bossMaxHp',c.boss_max_hp,'bossCurrentHp',c.boss_current_hp,'bossAttack',c.boss_attack,
    'bossAttackIntervalSeconds',c.boss_attack_interval_seconds,'rewardAmount',c.reward_amount,'status',c.status,
    'bossActive',v_active,'bossStartsAt',b.starts_at,'bossEndsAt',b.ends_at,
    'totalDamageDealt',c.total_damage_dealt,'defeats',defeats_count,'startedAt',c.started_at,
    'lastProcessedAt',c.last_processed_at,'nextHeroAttackAt',c.next_hero_attack_at,'bossLastAttackAt',c.boss_last_attack_at,
    'bossNextAttackAt',c.boss_next_attack_at,'defeatedAt',c.defeated_at,'rewardClaimedAt',c.reward_claimed_at,
    'teamChangeAvailableAt',c.team_change_available_at,'serverNow',clock_timestamp(),
    'heroes',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'heroId',s.hero_id,'name',h.name,'image',h.image,'rarity',s.rarity,'slot',s.slot,'level',s.level,'baseAtk',s.base_atk,'finalAtk',s.final_atk,'baseHp',s.base_hp,'maxHp',s.max_hp,'currentHp',s.current_hp,'isAlive',s.is_alive,'knockedOutAt',s.knocked_out_at,'reviveAt',s.revive_at) order by s.slot) from public.hero_combat_state s join public.player_heroes h on h.id=s.hero_id where s.combat_id=c.id and s.slot is not null),public.boss_team_json(v_user)),
    'ownedHeroes',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'heroKey',h.hero_key,'name',h.name,'image',h.image,'rarity',public.normalize_hero_rarity(h.rarity),'level',h.level) order by h.created_at) from public.player_heroes h where h.user_id=v_user),'[]'::jsonb));
end $$;

create or replace function public.equip_combat_hero(p_telegram_id bigint,p_hero_id uuid,p_slot integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid;
begin
  if p_slot is null or p_slot<1 or p_slot>5 then raise exception 'INVALID_SLOT'; end if;
  insert into public.game_players(telegram_id) values(p_telegram_id)
  on conflict(telegram_id) do update set updated_at=now() returning id into v_user;
  if not exists (select 1 from public.player_heroes where id=p_hero_id and user_id=v_user) then
    raise exception 'HERO_NOT_OWNED';
  end if;
  delete from public.boss_team_slots where user_id=v_user and player_hero_id=p_hero_id;
  insert into public.boss_team_slots(user_id,slot,player_hero_id) values(v_user,p_slot,p_hero_id)
  on conflict(user_id,slot) do update set player_hero_id=excluded.player_hero_id,updated_at=now();
  perform public.sync_boss_team_state(v_user);
  perform public.process_boss_combat(p_telegram_id);
  return public.get_boss_combat(p_telegram_id);
end $$;

create or replace function public.unequip_combat_hero(p_telegram_id bigint,p_slot integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid;
begin
  if p_slot is null or p_slot<1 or p_slot>5 then raise exception 'INVALID_SLOT'; end if;
  select id into v_user from public.game_players where telegram_id=p_telegram_id;
  if v_user is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  delete from public.boss_team_slots where user_id=v_user and slot=p_slot;
  perform public.sync_boss_team_state(v_user);
  return public.get_boss_combat(p_telegram_id);
end $$;

create or replace function public.set_boss_team(p_telegram_id bigint,p_hero_ids uuid[])
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid; i int;
begin
  insert into public.game_players(telegram_id) values(p_telegram_id)
  on conflict(telegram_id) do update set updated_at=now() returning id into v_user;
  if coalesce(cardinality(p_hero_ids),0)>5
     or coalesce(cardinality(p_hero_ids),0)<>coalesce(cardinality(array(select distinct unnest(p_hero_ids))),0) then
    raise exception 'INVALID_TEAM';
  end if;
  if (select count(*) from public.player_heroes where user_id=v_user and id=any(p_hero_ids))<>coalesce(cardinality(p_hero_ids),0) then
    raise exception 'HERO_NOT_OWNED';
  end if;
  delete from public.boss_team_slots where user_id=v_user;
  for i in 1..coalesce(cardinality(p_hero_ids),0) loop
    insert into public.boss_team_slots(user_id,slot,player_hero_id) values(v_user,i,p_hero_ids[i]);
  end loop;
  perform public.sync_boss_team_state(v_user);
  perform public.process_boss_combat(p_telegram_id);
  return public.get_boss_combat(p_telegram_id);
end $$;

create or replace function public.process_boss_combat(p_telegram_id bigint,p_now timestamptz default clock_timestamp())
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_id uuid; b public.boss_templates;
 c public.boss_combats%rowtype;event_at timestamptz;special_at timestamptz;revive_event timestamptz;cutoff timestamptz;team_damage numeric;target public.hero_combat_state%rowtype;dealt numeric;hero_count int;cycles bigint;kill_cycles bigint;bonuses jsonb;damage_bonus numeric:=0;damage_reduction numeric:=0;revive_speed numeric:=0;pet_slug text;skill_at timestamptz;skill_damage numeric;
begin
 b:=public.active_boss_template();
 if b.code is null then
   update public.boss_combats set status='expired',updated_at=clock_timestamp() where status='active'
     and user_id=(select id from public.game_players where telegram_id=p_telegram_id);
   return public.get_boss_combat(p_telegram_id);
 end if;
 v_id:=public.ensure_boss_combat(p_telegram_id);
 if v_id is null then return public.get_boss_combat(p_telegram_id); end if;
 select * into c from public.boss_combats where id=v_id for update;
 if c.status<>'active' then return public.get_boss_combat(p_telegram_id);end if;
 bonuses:=public.get_pet_bonuses(c.user_id);damage_bonus:=coalesce((bonuses->>'boss_damage_percent')::numeric,0);damage_reduction:=coalesce((bonuses->>'boss_damage_reduction_percent')::numeric,0);revive_speed:=least(90,coalesce((bonuses->>'revive_speed_percent')::numeric,0));
 select p.slug into pet_slug from public.player_pets pp join public.pets p on p.id=pp.pet_id where pp.user_id=c.user_id and pp.is_active;
 skill_at:=case when pet_slug='pyron' then coalesce(c.pet_next_skill_at,c.started_at+interval '60 seconds') else 'infinity'::timestamptz end;
 cutoff:=greatest(c.last_processed_at,least(p_now,c.last_processed_at+interval '7 days'));
 loop
  exit when c.boss_current_hp<=0;
  select min(revive_at) into revive_event from public.hero_combat_state where combat_id=c.id and not is_alive;
  special_at:=least(c.boss_next_attack_at,coalesce(revive_event,'infinity'),skill_at,cutoff);
  if c.next_hero_attack_at<=special_at then
   select coalesce(sum(final_atk),0)*(1+damage_bonus/100),count(*) into team_damage,hero_count from public.hero_combat_state where combat_id=c.id and slot is not null and is_alive;
   cycles:=floor(extract(epoch from(special_at-c.next_hero_attack_at))/10)::bigint+1;
   if team_damage>0 then kill_cycles:=ceil(c.boss_current_hp/team_damage)::bigint;if kill_cycles<=cycles then event_at:=c.next_hero_attack_at+make_interval(secs=>((kill_cycles-1)*10)::int);dealt:=c.boss_current_hp;c.total_damage_dealt:=c.total_damage_dealt+dealt;c.boss_current_hp:=0;c.status:='defeated';c.defeated_at:=event_at;c.next_hero_attack_at:=event_at+interval '10 seconds';exit;end if;dealt:=least(c.boss_current_hp,team_damage*cycles);c.boss_current_hp:=greatest(0,c.boss_current_hp-dealt);c.total_damage_dealt:=c.total_damage_dealt+dealt;end if;
   c.next_hero_attack_at:=c.next_hero_attack_at+make_interval(secs=>(cycles*10)::int);
  end if;
  exit when special_at>=cutoff;event_at:=special_at;
  update public.hero_combat_state set is_alive=true,current_hp=max_hp,knocked_out_at=null,revive_at=null,updated_at=event_at where combat_id=c.id and not is_alive and revive_at<=event_at;
  if skill_at<=event_at then select coalesce(sum(final_atk),0)*3 into skill_damage from public.hero_combat_state where combat_id=c.id and slot is not null and is_alive;if skill_damage>0 then dealt:=least(c.boss_current_hp,skill_damage);c.boss_current_hp:=c.boss_current_hp-dealt;c.total_damage_dealt:=c.total_damage_dealt+dealt;if c.boss_current_hp=0 then c.status:='defeated';c.defeated_at:=event_at;exit;end if;end if;skill_at:=skill_at+interval '60 seconds';end if;
  if c.boss_next_attack_at<=event_at then select * into target from public.hero_combat_state where combat_id=c.id and slot is not null and is_alive order by random() limit 1 for update;if found then target.current_hp:=greatest(0,target.current_hp-greatest(1,round(c.boss_attack*public.rarity_resistance(target.rarity)*(1-damage_reduction/100))));update public.hero_combat_state set current_hp=target.current_hp,is_alive=(target.current_hp>0),knocked_out_at=case when target.current_hp=0 then event_at end,revive_at=case when target.current_hp=0 then event_at+make_interval(secs=>round(300*(1-revive_speed/100))::int) end,updated_at=event_at where id=target.id;end if;c.boss_last_attack_at:=event_at;c.boss_next_attack_at:=c.boss_next_attack_at+make_interval(secs=>c.boss_attack_interval_seconds);end if;
 end loop;
 update public.boss_combats set boss_current_hp=c.boss_current_hp,total_damage_dealt=c.total_damage_dealt,status=c.status,defeated_at=c.defeated_at,last_processed_at=cutoff,next_hero_attack_at=c.next_hero_attack_at,boss_last_attack_at=c.boss_last_attack_at,boss_next_attack_at=c.boss_next_attack_at,pet_next_skill_at=case when pet_slug='pyron' then skill_at end,updated_at=clock_timestamp() where id=c.id;
 return public.get_boss_combat(p_telegram_id);
end $$;

create or replace function public.attack_boss(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.boss_templates;
begin
  b:=public.active_boss_template();
  if b.code is null then raise exception 'BOSS_NOT_ACTIVE'; end if;
  if not exists (select 1 from public.boss_team_slots ts join public.game_players g on g.id=ts.user_id where g.telegram_id=p_telegram_id) then
    raise exception 'BOSS_TEAM_EMPTY';
  end if;
  return public.process_boss_combat(p_telegram_id);
end $$;

revoke all on function public.equip_combat_hero(bigint,uuid,integer) from public,anon,authenticated;
revoke all on function public.unequip_combat_hero(bigint,integer) from public,anon,authenticated;
revoke all on function public.set_boss_team(bigint,uuid[]) from public,anon,authenticated;
revoke all on function public.attack_boss(bigint) from public,anon,authenticated;
revoke all on function public.process_boss_combat(bigint,timestamptz) from public,anon,authenticated;
revoke all on function public.get_boss_combat(bigint) from public,anon,authenticated;
revoke all on function public.ensure_boss_combat(bigint) from public,anon,authenticated;
revoke all on function public.sync_boss_team_state(uuid) from public,anon,authenticated;
revoke all on function public.boss_team_json(uuid) from public,anon,authenticated;
revoke all on function public.active_boss_template() from public,anon,authenticated;
grant execute on function public.equip_combat_hero(bigint,uuid,integer),public.unequip_combat_hero(bigint,integer),public.set_boss_team(bigint,uuid[]),public.attack_boss(bigint),public.process_boss_combat(bigint,timestamptz),public.get_boss_combat(bigint),public.ensure_boss_combat(bigint),public.sync_boss_team_state(uuid),public.boss_team_json(uuid),public.active_boss_template() to service_role;

create or replace function public.admin_boss_overview(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.boss_templates;
begin
  perform public.admin_assert(p_admin_id);
  b:=public.active_boss_template();
  return jsonb_build_object(
    'active',b.code is not null,
    'boss',case when b.code is null then null else jsonb_build_object('code',b.code,'name',b.name,'level',b.level,'maxHp',b.max_hp,'attack',b.attack,'reward',b.reward_amount,'durationSeconds',b.duration_seconds,'startsAt',b.starts_at,'endsAt',b.ends_at) end,
    'currentHp',(select coalesce(sum(boss_current_hp),0) from public.boss_combats where status='active'),
    'maxHp',(select coalesce(sum(boss_max_hp),0) from public.boss_combats where status='active'),
    'participants',(select count(*) from public.boss_combats where status='active'),
    'totalDamage',(select coalesce(sum(total_damage_dealt),0) from public.boss_combats where status='active'),
    'templates',(select coalesce(jsonb_agg(jsonb_build_object('code',t.code,'name',t.name,'level',t.level,'maxHp',t.max_hp,'active',t.active,'durationSeconds',t.duration_seconds) order by t.level),'[]'::jsonb) from public.boss_templates t),
    'top_damage',(select coalesce(jsonb_agg(jsonb_build_object('name',coalesce(g.display_name,g.username,'Jogador'),'damage',c.total_damage_dealt) order by c.total_damage_dealt desc),'[]'::jsonb)
      from (select * from public.boss_combats where status='active' order by total_damage_dealt desc limit 10) c
      join public.game_players g on g.id=c.user_id));
end $$;

create or replace function public.admin_boss_control(p_admin_id bigint,p_action text,p_code text default null,p_reason text default null,p_value numeric default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_action text:=lower(coalesce(p_action,'')); v_count int:=0; b public.boss_templates; v_code text;
begin
  perform public.admin_assert(p_admin_id);
  if v_action in ('activate','spawn','switch') then
    v_code:=coalesce(p_code,(select code from public.boss_templates order by active desc,level limit 1));
    select * into b from public.boss_templates where code=v_code;
    if b.code is null then raise exception 'boss_not_found'; end if;
    update public.boss_templates set active=false,updated_at=now() where active and code<>v_code;
    delete from public.hero_combat_state where combat_id in (select id from public.boss_combats where status='active');
    delete from public.boss_combats where status='active';
    update public.boss_templates set active=true,starts_at=now(),
      ends_at=now()+make_interval(secs=>greatest(300,coalesce(duration_seconds,86400))),updated_at=now()
    where code=v_code returning * into b;
    v_count:=1;
  elsif v_action in ('deactivate','end') then
    update public.boss_templates set active=false,ends_at=now(),updated_at=now() where active;
    update public.boss_combats set status='expired',updated_at=now() where status='active';
    get diagnostics v_count=row_count;
    select * into b from public.boss_templates order by updated_at desc limit 1;
  elsif v_action in ('reset','reset_hp') then
    update public.boss_combats set boss_current_hp=boss_max_hp,total_damage_dealt=0,defeated_at=null,status='active',updated_at=now() where status in ('active','defeated');
    get diagnostics v_count=row_count;
    b:=public.active_boss_template();
  elsif v_action='set_hp' then
    if coalesce(p_value,0)<1 then raise exception 'invalid_value'; end if;
    v_code:=coalesce(p_code,(select code from public.boss_templates where active limit 1));
    update public.boss_templates set max_hp=p_value,updated_at=now() where code=v_code returning * into b;
    update public.boss_combats set boss_max_hp=p_value,boss_current_hp=least(boss_current_hp,p_value),updated_at=now() where status='active';
    get diagnostics v_count=row_count;
  elsif v_action='set_duration' then
    if coalesce(p_value,0)<300 then raise exception 'invalid_value'; end if;
    v_code:=coalesce(p_code,(select code from public.boss_templates where active limit 1));
    update public.boss_templates set duration_seconds=p_value::int,
      ends_at=case when active then coalesce(starts_at,now())+make_interval(secs=>p_value::int) else ends_at end,
      updated_at=now() where code=v_code returning * into b;
    v_count:=1;
  elsif v_action='set_reward' then
    if coalesce(p_value,0)<0 then raise exception 'invalid_value'; end if;
    v_code:=coalesce(p_code,(select code from public.boss_templates where active limit 1));
    update public.boss_templates set reward_amount=p_value,updated_at=now() where code=v_code returning * into b;
    update public.boss_combats set reward_amount=p_value,updated_at=now() where status='active';
    v_count:=1;
  else
    raise exception 'invalid_action';
  end if;
  perform public.admin_log(p_admin_id,'boss.'||v_action,'boss',coalesce(v_code,p_code),null,jsonb_build_object('affected',v_count,'value',p_value),p_reason,jsonb_build_object('dangerous',true));
  return jsonb_build_object('action',v_action,'affected',v_count,'active',coalesce(b.active,false),'code',b.code,'name',b.name,
    'maxHp',b.max_hp,'durationSeconds',b.duration_seconds,'startsAt',b.starts_at,'endsAt',b.ends_at);
end $$;

grant execute on function public.admin_boss_control(bigint,text,text,text,numeric),public.admin_boss_overview(bigint) to service_role;