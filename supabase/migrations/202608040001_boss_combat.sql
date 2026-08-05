create extension if not exists pgcrypto;

create table if not exists public.game_players (
  id uuid primary key default gen_random_uuid(), telegram_id bigint not null unique,
  forge_coins numeric not null default 0 check (forge_coins >= 0),
  boss_defeats integer not null default 0 check (boss_defeats >= 0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.player_heroes (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.game_players(id) on delete cascade,
  hero_key text not null, name text not null, rarity text not null, level integer not null default 1 check(level >= 1),
  image text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.hero_catalog (
  hero_key text primary key,name text not null,rarity text not null,image text not null,enabled boolean not null default true
);
insert into public.hero_catalog(hero_key,name,rarity,image) values
('common-1','Espadachim da Forja','common','/assets/game/heroes/common-warrior.png'),('common-2','Guarda da Lança','common','/assets/game/heroes/shop/common-2.webp'),('common-3','Batedor da Besta','common','/assets/game/heroes/shop/common-3.webp'),('common-4','Médica da Vila','common','/assets/game/heroes/shop/common-4.webp'),('common-5','Portador do Escudo','common','/assets/game/heroes/shop/common-5.webp'),
('uncommon-1','Arqueira Élfica','uncommon','/assets/game/heroes/uncommon-archer.png'),('uncommon-2','Lâminas do Deserto','uncommon','/assets/game/heroes/shop/uncommon-2.webp'),('uncommon-3','Caçador de Gelo','uncommon','/assets/game/heroes/shop/uncommon-3.webp'),('uncommon-4','Rastreadora Feral','uncommon','/assets/game/heroes/shop/uncommon-4.webp'),('uncommon-5','Ladino Esmeralda','uncommon','/assets/game/heroes/shop/uncommon-5.webp'),
('rare-1','Guardião Rúnico','rare','/assets/game/heroes/rare-guardian.png'),('rare-2','Lanceira Real','rare','/assets/game/heroes/shop/rare-2.webp'),('rare-3','Ferreiro das Runas','rare','/assets/game/heroes/shop/rare-3.webp'),('rare-4','Clériga da Tempestade','rare','/assets/game/heroes/shop/rare-4.webp'),('rare-5','Cavaleiro Leão','rare','/assets/game/heroes/shop/rare-5.webp'),
('epic-1','Maga Rúnica','epic','/assets/game/heroes/epic-mage.png'),('epic-2','Mago Carmesim','epic','/assets/game/heroes/shop/epic-2.webp'),('epic-3','Paladina Sombria','epic','/assets/game/heroes/shop/epic-3.webp'),('epic-4','Artífice Arcano','epic','/assets/game/heroes/shop/epic-4.webp'),('epic-5','Lanceira Celestial','epic','/assets/game/heroes/shop/epic-5.webp'),
('legendary-1','Cavaleiro Dragão','legendary','/assets/game/heroes/legendary-dragon-knight.png'),('legendary-2','Rainha Fênix','legendary','/assets/game/heroes/shop/legendary-2.webp'),('legendary-3','Rei Titã','legendary','/assets/game/heroes/shop/legendary-3.webp'),('legendary-4','Imperatriz Lunar','legendary','/assets/game/heroes/shop/legendary-4.webp'),('legendary-5','Imperador da Forja','legendary','/assets/game/heroes/shop/legendary-5.webp') on conflict(hero_key) do update set name=excluded.name,rarity=excluded.rarity,image=excluded.image;
create table if not exists public.boss_combats (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.game_players(id) on delete cascade,
  boss_id uuid default gen_random_uuid(), boss_name text not null default 'Dragão Ancestral', boss_level integer not null default 1,
  boss_max_hp numeric not null default 67500, boss_current_hp numeric not null default 67500, boss_attack numeric not null default 8,
  boss_attack_interval_seconds integer not null default 60, reward_amount numeric not null default 120000,
  status text not null default 'active' check(status in ('active','defeated','rewarded')),
  total_damage_dealt numeric not null default 0, started_at timestamptz not null default now(), last_processed_at timestamptz not null default now(),
  next_hero_attack_at timestamptz not null default now() + interval '10 seconds', boss_last_attack_at timestamptz not null default now(),
  boss_next_attack_at timestamptz not null default now() + interval '60 seconds', defeated_at timestamptz,
  reward_claimed_at timestamptz, team_change_available_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check(boss_level >= 1 and boss_max_hp > 0 and boss_current_hp >= 0 and boss_current_hp <= boss_max_hp and boss_attack > 0)
);
create unique index if not exists boss_combats_one_active_per_user on public.boss_combats(user_id) where status = 'active';
create index if not exists boss_combats_user_status_idx on public.boss_combats(user_id,status);
create table if not exists public.hero_combat_state (
  id uuid primary key default gen_random_uuid(), combat_id uuid not null references public.boss_combats(id) on delete cascade,
  hero_id uuid not null references public.player_heroes(id), slot integer check(slot between 1 and 5), rarity text not null,
  level integer not null check(level >= 1), base_atk numeric not null check(base_atk > 0), final_atk numeric not null check(final_atk > 0),
  base_hp integer not null check(base_hp > 0), max_hp integer not null check(max_hp > 0), current_hp integer not null check(current_hp >= 0),
  is_alive boolean not null default true, knocked_out_at timestamptz, revive_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(combat_id,slot), unique(combat_id,hero_id)
);
create index if not exists hero_combat_state_combat_idx on public.hero_combat_state(combat_id);
create index if not exists hero_combat_state_hero_idx on public.hero_combat_state(hero_id);
create table if not exists public.boss_reward_transactions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.game_players(id), combat_id uuid not null references public.boss_combats(id),
  amount numeric not null check(amount > 0), currency text not null default 'FC', idempotency_key text not null unique, created_at timestamptz not null default now()
);
create index if not exists boss_reward_idempotency_idx on public.boss_reward_transactions(idempotency_key);

alter table public.game_players enable row level security;
alter table public.player_heroes enable row level security;
alter table public.hero_catalog enable row level security;
alter table public.boss_combats enable row level security;
alter table public.hero_combat_state enable row level security;
alter table public.boss_reward_transactions enable row level security;
revoke all on public.game_players, public.player_heroes, public.hero_catalog, public.boss_combats, public.hero_combat_state, public.boss_reward_transactions from anon, authenticated;

create or replace function public.normalize_hero_rarity(value text) returns text language sql immutable as $$
  select case lower(trim(coalesce(value,'common')))
    when 'common' then 'common' when 'comum' then 'common' when 'uncommon' then 'uncommon' when 'incomum' then 'uncommon'
    when 'rare' then 'rare' when 'raro' then 'rare' when 'rara' then 'rare' when 'epic' then 'epic' when 'épico' then 'epic'
    when 'epico' then 'epic' when 'épica' then 'epic' when 'epica' then 'epic' when 'legendary' then 'legendary'
    when 'lendário' then 'legendary' when 'lendario' then 'legendary' when 'lendária' then 'legendary' when 'lendaria' then 'legendary' else 'common' end
$$;
create or replace function public.rarity_base_atk(r text) returns numeric language sql immutable as $$ select case public.normalize_hero_rarity(r) when 'uncommon' then 1.975 when 'rare' then 2.165 when 'epic' then 2.395 when 'legendary' then 2.680 else 1.875 end $$;
create or replace function public.rarity_base_hp(r text) returns integer language sql immutable as $$ select case public.normalize_hero_rarity(r) when 'uncommon' then 130 when 'rare' then 170 when 'epic' then 220 when 'legendary' then 300 else 100 end $$;
create or replace function public.rarity_resistance(r text) returns numeric language sql immutable as $$ select case public.normalize_hero_rarity(r) when 'uncommon' then .95 when 'rare' then .90 when 'epic' then .85 when 'legendary' then .80 else 1 end $$;

create or replace function public.ensure_boss_combat(p_telegram_id bigint) returns uuid language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_combat uuid;
begin
  insert into game_players(telegram_id) values(p_telegram_id) on conflict(telegram_id) do update set updated_at=now() returning id into v_user;
  select id into v_combat from boss_combats where user_id=v_user and status='active';
  if v_combat is null then insert into boss_combats(user_id) values(v_user) returning id into v_combat; end if;
  return v_combat;
end $$;

-- Forward declaration replaced below after the processor is defined.
create or replace function public.get_boss_combat(p_telegram_id bigint) returns jsonb language sql security definer set search_path=public as $$ select '{}'::jsonb $$;

create or replace function public.process_boss_combat(p_telegram_id bigint, p_now timestamptz default clock_timestamp()) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c boss_combats%rowtype; event_at timestamptz; special_at timestamptz; revive_event timestamptz; cutoff timestamptz; team_damage numeric; target hero_combat_state%rowtype; dealt numeric; hero_count int; cycles bigint; kill_cycles bigint;
begin
  select * into c from boss_combats where id=public.ensure_boss_combat(p_telegram_id) for update;
  if c.status <> 'active' then return public.get_boss_combat(p_telegram_id); end if;
  cutoff := greatest(c.last_processed_at,least(p_now, c.last_processed_at + interval '7 days'));
  loop
    exit when c.boss_current_hp <= 0;
    select min(revive_at) into revive_event from hero_combat_state where combat_id=c.id and not is_alive;
    special_at := least(c.boss_next_attack_at,coalesce(revive_event,'infinity'),cutoff);
    if c.next_hero_attack_at <= special_at then
      select coalesce(sum(final_atk),0),count(*) into team_damage,hero_count from hero_combat_state where combat_id=c.id and slot is not null and is_alive;
      cycles := floor(extract(epoch from (special_at-c.next_hero_attack_at))/10)::bigint+1;
      if team_damage>0 then
        kill_cycles:=ceil(c.boss_current_hp/team_damage)::bigint;
        if kill_cycles<=cycles then
          event_at:=c.next_hero_attack_at+make_interval(secs=>((kill_cycles-1)*10)::int); dealt:=c.boss_current_hp;
          c.total_damage_dealt:=c.total_damage_dealt+dealt;c.boss_current_hp:=0;c.status:='defeated';c.defeated_at:=event_at;c.next_hero_attack_at:=event_at+interval '10 seconds';exit;
        end if;
        dealt:=least(c.boss_current_hp,team_damage*cycles);c.boss_current_hp:=greatest(0,c.boss_current_hp-dealt);c.total_damage_dealt:=c.total_damage_dealt+dealt;
      end if;
      c.next_hero_attack_at:=c.next_hero_attack_at+make_interval(secs=>(cycles*10)::int);
    end if;
    exit when special_at>=cutoff;
    event_at:=special_at;
    update hero_combat_state set is_alive=true,current_hp=max_hp,knocked_out_at=null,revive_at=null,updated_at=event_at where combat_id=c.id and not is_alive and revive_at <= event_at;
    if c.boss_next_attack_at <= event_at then
      select * into target from hero_combat_state where combat_id=c.id and slot is not null and is_alive order by random() limit 1 for update;
      if found then
        target.current_hp := greatest(0,target.current_hp-greatest(1,round(c.boss_attack*public.rarity_resistance(target.rarity))));
        update hero_combat_state set current_hp=target.current_hp,is_alive=(target.current_hp>0),knocked_out_at=case when target.current_hp=0 then event_at else null end,
          revive_at=case when target.current_hp=0 then event_at+interval '5 minutes' else null end,updated_at=event_at where id=target.id;
      end if;
      c.boss_last_attack_at:=event_at; c.boss_next_attack_at:=c.boss_next_attack_at+make_interval(secs=>c.boss_attack_interval_seconds);
    end if;
  end loop;
  update boss_combats set boss_current_hp=c.boss_current_hp,total_damage_dealt=c.total_damage_dealt,status=c.status,defeated_at=c.defeated_at,
    last_processed_at=cutoff,next_hero_attack_at=c.next_hero_attack_at,boss_last_attack_at=c.boss_last_attack_at,boss_next_attack_at=c.boss_next_attack_at,updated_at=clock_timestamp() where id=c.id;
  return public.get_boss_combat(p_telegram_id);
end $$;

create or replace function public.get_boss_combat(p_telegram_id bigint) returns jsonb language plpgsql security definer set search_path=public as $$
declare c boss_combats%rowtype; defeats_count int; v_user uuid;
begin
 select id into v_user from game_players where telegram_id=p_telegram_id;
 if v_user is null then c.id:=public.ensure_boss_combat(p_telegram_id); select id into v_user from game_players where telegram_id=p_telegram_id; end if;
 select * into c from boss_combats where user_id=v_user and status in ('active','defeated') order by case status when 'defeated' then 0 else 1 end,created_at desc limit 1;
 select boss_defeats into defeats_count from game_players where id=c.user_id;
 return jsonb_build_object('id',c.id,'bossId',c.boss_id,'bossName',c.boss_name,'bossLevel',c.boss_level,'bossMaxHp',c.boss_max_hp,'bossCurrentHp',c.boss_current_hp,'bossAttack',c.boss_attack,'bossAttackIntervalSeconds',c.boss_attack_interval_seconds,'rewardAmount',c.reward_amount,'status',c.status,'totalDamageDealt',c.total_damage_dealt,'defeats',defeats_count,'startedAt',c.started_at,'lastProcessedAt',c.last_processed_at,'nextHeroAttackAt',c.next_hero_attack_at,'bossLastAttackAt',c.boss_last_attack_at,'bossNextAttackAt',c.boss_next_attack_at,'defeatedAt',c.defeated_at,'rewardClaimedAt',c.reward_claimed_at,'teamChangeAvailableAt',c.team_change_available_at,'serverNow',clock_timestamp(),'heroes',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'heroId',s.hero_id,'name',h.name,'image',h.image,'rarity',s.rarity,'slot',s.slot,'level',s.level,'baseAtk',s.base_atk,'finalAtk',s.final_atk,'baseHp',s.base_hp,'maxHp',s.max_hp,'currentHp',s.current_hp,'isAlive',s.is_alive,'knockedOutAt',s.knocked_out_at,'reviveAt',s.revive_at) order by s.slot) from hero_combat_state s join player_heroes h on h.id=s.hero_id where s.combat_id=c.id and s.slot is not null),'[]'::jsonb),'ownedHeroes',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'heroKey',h.hero_key,'name',h.name,'image',h.image,'rarity',public.normalize_hero_rarity(h.rarity),'level',h.level) order by h.created_at) from player_heroes h where h.user_id=c.user_id),'[]'::jsonb));
end $$;

create or replace function public.set_boss_team(p_telegram_id bigint,p_hero_ids uuid[]) returns jsonb language plpgsql security definer set search_path=public as $$
declare c boss_combats%rowtype; v_user uuid; h player_heroes%rowtype; i int; old hero_combat_state%rowtype; bhp int; mhp int; batk numeric;
begin
 perform public.process_boss_combat(p_telegram_id);
 select id into v_user from game_players where telegram_id=p_telegram_id;
 select * into c from boss_combats where user_id=v_user and status='active' for update;
 if c.id is null then raise exception 'Boss is not active'; end if;
 if c.status<>'active' then raise exception 'Boss is not active'; end if;
 if c.team_change_available_at is not null and c.team_change_available_at>clock_timestamp() then raise exception 'TEAM_COOLDOWN'; end if;
 if cardinality(p_hero_ids)>5 or cardinality(p_hero_ids)<>cardinality(array(select distinct unnest(p_hero_ids))) then raise exception 'Invalid team'; end if;
 if (select count(*) from player_heroes where user_id=v_user and id=any(p_hero_ids))<>cardinality(p_hero_ids) then raise exception 'Hero ownership validation failed'; end if;
 update hero_combat_state set slot=null,updated_at=clock_timestamp() where combat_id=c.id and slot is not null;
 for i in 1..cardinality(p_hero_ids) loop
   select * into h from player_heroes where id=p_hero_ids[i] and user_id=v_user; select * into old from hero_combat_state where combat_id=c.id and hero_id=h.id;
   bhp:=public.rarity_base_hp(h.rarity); mhp:=round(bhp*(1+(greatest(1,h.level)-1)*.05)); batk:=round((public.rarity_base_atk(h.rarity)*(1+(greatest(1,h.level)-1)*.03))::numeric,3);
   insert into hero_combat_state(combat_id,hero_id,slot,rarity,level,base_atk,final_atk,base_hp,max_hp,current_hp,is_alive,knocked_out_at,revive_at)
   values(c.id,h.id,i,public.normalize_hero_rarity(h.rarity),h.level,public.rarity_base_atk(h.rarity),batk,bhp,mhp,case when old.id is null then mhp else least(mhp,round(old.current_hp::numeric/nullif(old.max_hp,0)*mhp)) end,coalesce(old.is_alive,true),old.knocked_out_at,old.revive_at)
   on conflict(combat_id,hero_id) do update set slot=excluded.slot,rarity=excluded.rarity,level=excluded.level,base_atk=excluded.base_atk,final_atk=excluded.final_atk,base_hp=excluded.base_hp,max_hp=excluded.max_hp,current_hp=least(excluded.max_hp,round(hero_combat_state.current_hp::numeric/nullif(hero_combat_state.max_hp,0)*excluded.max_hp)),is_alive=hero_combat_state.is_alive,knocked_out_at=hero_combat_state.knocked_out_at,revive_at=hero_combat_state.revive_at,updated_at=now();
 end loop;
 update boss_combats set team_change_available_at=clock_timestamp()+interval '60 seconds',updated_at=clock_timestamp() where id=c.id;
 return public.get_boss_combat(p_telegram_id);
end $$;

create or replace function public.claim_boss_reward(p_telegram_id bigint) returns jsonb language plpgsql security definer set search_path=public as $$
declare c boss_combats%rowtype; key text; next_hp numeric; next_attack numeric; next_reward numeric; v_user uuid;
begin
 perform public.process_boss_combat(p_telegram_id); select id into v_user from game_players where telegram_id=p_telegram_id; select * into c from boss_combats where user_id=v_user and status='defeated' order by defeated_at desc limit 1 for update;
 if c.status<>'defeated' then raise exception 'Boss is not defeated'; end if; key:='boss_reward:'||c.id;
 insert into boss_reward_transactions(user_id,combat_id,amount,idempotency_key) values(c.user_id,c.id,c.reward_amount,key) on conflict(idempotency_key) do nothing;
 if found then update game_players set forge_coins=forge_coins+c.reward_amount,boss_defeats=boss_defeats+1,updated_at=now() where id=c.user_id; end if;
 update boss_combats set status='rewarded',reward_claimed_at=coalesce(reward_claimed_at,now()),updated_at=now() where id=c.id;
 next_hp:=least(9000000000000000,round(c.boss_max_hp*1.08)); next_attack:=least(9000000000000000,round(c.boss_attack*1.05)); next_reward:=least(9000000000000000,round(c.reward_amount*1.05));
 insert into boss_combats(user_id,boss_level,boss_max_hp,boss_current_hp,boss_attack,reward_amount) values(c.user_id,c.boss_level+1,next_hp,next_hp,next_attack,next_reward);
 return public.process_boss_combat(p_telegram_id);
end $$;

create or replace function public.recruit_heroes(p_telegram_id bigint,p_count integer) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_cost numeric; i int; roll numeric; rarity_pick text; picked hero_catalog%rowtype; new_hero_id uuid; result jsonb:='[]'::jsonb;
begin
 if p_count not in (1,5,10) then raise exception 'Invalid recruitment count'; end if; v_cost:=25000*p_count;
 insert into game_players(telegram_id) values(p_telegram_id) on conflict(telegram_id) do update set updated_at=now() returning id into v_user;
 if (select forge_coins from game_players where id=v_user for update)<v_cost then raise exception 'NOT_ENOUGH_FC'; end if;
 update game_players set forge_coins=forge_coins-v_cost,updated_at=now() where id=v_user;
 for i in 1..p_count loop
   roll:=random()*100; rarity_pick:=case when roll<.3 then 'legendary' when roll<3 then 'epic' when roll<13 then 'rare' when roll<38 then 'uncommon' else 'common' end;
   select * into picked from hero_catalog where rarity=rarity_pick and enabled order by random() limit 1;
   insert into player_heroes(user_id,hero_key,name,rarity,level,image) values(v_user,picked.hero_key,picked.name,picked.rarity,1,picked.image) returning id into new_hero_id;
   result:=result||jsonb_build_array(jsonb_build_object('id',new_hero_id,'heroKey',picked.hero_key,'name',picked.name,'rarity',picked.rarity,'level',1,'image',picked.image));
 end loop;
 return jsonb_build_object('heroes',result,'balance',(select forge_coins from game_players where id=v_user));
end $$;

revoke all on function public.ensure_boss_combat(bigint),public.process_boss_combat(bigint,timestamptz),public.get_boss_combat(bigint),public.set_boss_team(bigint,uuid[]),public.claim_boss_reward(bigint),public.recruit_heroes(bigint,integer) from public,anon,authenticated;
grant execute on function public.process_boss_combat(bigint,timestamptz),public.get_boss_combat(bigint),public.set_boss_team(bigint,uuid[]),public.claim_boss_reward(bigint),public.recruit_heroes(bigint,integer) to service_role;
