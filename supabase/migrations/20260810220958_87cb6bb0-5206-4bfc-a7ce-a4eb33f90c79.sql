-- 1. columns
alter table public.player_heroes
  add column if not exists fusion_level integer not null default 0,
  add column if not exists locked boolean not null default false;
do $$ begin
  alter table public.player_heroes add constraint player_heroes_fusion_level_check check (fusion_level >= 0 and fusion_level <= 10);
exception when duplicate_object then null; end $$;

-- 2. configuration
insert into public.game_settings(key, value, category, label) values (
  'hero_fusion_config',
  jsonb_build_object(
    'max_stars', 5,
    'bonus_percent', jsonb_build_object('1',5,'2',5,'3',7,'4',8,'5',10),
    'cost_fc', jsonb_build_object('1',5000,'2',15000,'3',35000,'4',75000,'5',150000),
    'duplicates', jsonb_build_object('1',1,'2',1,'3',2,'4',2,'5',3),
    'level_cap', jsonb_build_object('0',20,'1',20,'2',25,'3',25,'4',30,'5',35)
  ),
  'heroes', 'Fusão de heróis (estrelas)'
) on conflict (key) do nothing;

create or replace function public.hero_fusion_config()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select value from game_settings where key = 'hero_fusion_config'),
    jsonb_build_object('max_stars',5,
      'bonus_percent', jsonb_build_object('1',5,'2',5,'3',7,'4',8,'5',10),
      'cost_fc', jsonb_build_object('1',5000,'2',15000,'3',35000,'4',75000,'5',150000),
      'duplicates', jsonb_build_object('1',1,'2',1,'3',2,'4',2,'5',3),
      'level_cap', jsonb_build_object('0',20,'1',20,'2',25,'3',25,'4',30,'5',35)));
$$;

-- deterministic multiplier: product of the per-star bonuses (never compounded on stored values)
create or replace function public.hero_fusion_multiplier(p_stars integer)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare cfg jsonb := hero_fusion_config(); m numeric := 1; i integer;
begin
  for i in 1..greatest(0, coalesce(p_stars,0)) loop
    m := m * (1 + coalesce((cfg->'bonus_percent'->>i::text)::numeric, 0) / 100);
  end loop;
  return m;
end $$;

create or replace function public.hero_max_level(p_stars integer)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce((hero_fusion_config()->'level_cap'->>greatest(0,coalesce(p_stars,0))::text)::int, 20);
$$;

-- 3. stat recalculation now includes the fusion multiplier
create or replace function public.ensure_pvp_hero_stats()
returns trigger language plpgsql security definer set search_path = public as $$
declare r text;seed text;min_atk numeric;max_atk numeric;min_hp numeric;max_hp numeric;min_ag numeric;max_ag numeric;min_hg numeric;max_hg numeric;atk_mult numeric:=1;hp_mult numeric:=1;fuse numeric:=1;kinds text[]:=array['warrior','assassin','tank','mage','archer','support'];
begin
  r:=normalize_hero_rarity(new.rarity);new.hero_template_id:=coalesce(new.hero_template_id,new.hero_key,new.name);seed:=coalesce(new.stats_seed,new.id::text||':'||new.hero_template_id||':'||new.user_id::text||':'||new.created_at::text);new.stats_seed:=seed;new.archetype:=coalesce(new.archetype,kinds[1+(abs(hashtextextended(seed||':kind',0))%6)::int]);
  select s.min_atk,s.max_atk,s.min_hp,s.max_hp,s.min_ag,s.max_ag,s.min_hg,s.max_hg into min_atk,max_atk,min_hp,max_hp,min_ag,max_ag,min_hg,max_hg from(values('common',80,110,800,1100,.025,.030,.040,.045),('uncommon',105,140,1050,1400,.028,.033,.042,.048),('rare',135,180,1350,1800,.031,.036,.045,.051),('epic',175,235,1750,2350,.034,.039,.048,.054),('legendary',230,310,2300,3100,.037,.042,.051,.057))s(rarity,min_atk,max_atk,min_hp,max_hp,min_ag,max_ag,min_hg,max_hg)where s.rarity=r;
  case new.archetype when 'warrior' then hp_mult:=1.15;when 'assassin' then atk_mult:=1.15;hp_mult:=.9;when 'tank' then atk_mult:=.85;hp_mult:=1.3;when 'mage' then atk_mult:=1.2;hp_mult:=.85;when 'archer' then atk_mult:=1.1;when 'support' then atk_mult:=.9;hp_mult:=1.1;else new.archetype:='warrior';hp_mult:=1.15;end case;
  if new.base_atk is null then new.base_atk:=greatest(1,round((min_atk+pvp_stat_unit(seed||':atk')*(max_atk-min_atk))*atk_mult));end if;
  if new.base_hp is null then new.base_hp:=greatest(1,round((min_hp+pvp_stat_unit(seed||':hp')*(max_hp-min_hp))*hp_mult));end if;
  if new.attack_growth is null then new.attack_growth:=round(min_ag+pvp_stat_unit(seed||':ag')*(max_ag-min_ag),5);end if;
  if new.hp_growth is null then new.hp_growth:=round(min_hg+pvp_stat_unit(seed||':hg')*(max_hg-min_hg),5);end if;
  new.level:=greatest(1,coalesce(new.level,1));
  new.fusion_level:=greatest(0,coalesce(new.fusion_level,0));
  fuse:=hero_fusion_multiplier(new.fusion_level);
  new.final_atk:=greatest(1,round((new.base_atk+coalesce(new.bonus_atk,0))*power(1+new.attack_growth,new.level-1)*fuse));
  new.final_hp:=greatest(1,round((new.base_hp+coalesce(new.bonus_hp,0))*power(1+new.hp_growth,new.level-1)*fuse));
  new.stats_generated_at:=coalesce(new.stats_generated_at,now());return new;
end $$;

drop trigger if exists player_heroes_pvp_stats on public.player_heroes;
create trigger player_heroes_pvp_stats before insert or update of level, rarity, base_atk, base_hp, bonus_atk, bonus_hp, attack_growth, hp_growth, fusion_level
on public.player_heroes for each row execute function public.ensure_pvp_hero_stats();

-- 4. audit history
create table if not exists public.hero_fusion_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  hero_id uuid not null,
  hero_key text not null,
  from_stars integer not null,
  to_stars integer not null,
  materials_consumed integer not null,
  material_ids uuid[] not null default '{}',
  cost_fc numeric not null default 0,
  atk_before numeric not null,
  atk_after numeric not null,
  hp_before numeric not null,
  hp_after numeric not null,
  created_at timestamptz not null default now()
);
grant select on public.hero_fusion_history to authenticated;
grant all on public.hero_fusion_history to service_role;
alter table public.hero_fusion_history enable row level security;
create index if not exists hero_fusion_history_user_idx on public.hero_fusion_history(user_id, created_at desc);

-- 5. player operations
create or replace function public.set_hero_lock(p_telegram_id bigint, p_hero_id uuid, p_locked boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  update player_heroes set locked = coalesce(p_locked,false), updated_at = now() where id = p_hero_id and user_id = u;
  if not found then raise exception 'HERO_NOT_OWNED'; end if;
  return jsonb_build_object('heroId', p_hero_id, 'locked', coalesce(p_locked,false));
end $$;

create or replace function public.get_hero_fusion_dashboard(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; cfg jsonb := hero_fusion_config(); balance numeric := 0; heroes jsonb;
begin
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id;
  if u is null then return jsonb_build_object('config', cfg, 'balance', 0, 'heroes', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(h order by h->>'name'), '[]'::jsonb) into heroes from (
    select jsonb_build_object(
      'heroId', ph.id, 'heroKey', ph.hero_key, 'name', ph.name, 'rarity', ph.rarity, 'level', ph.level,
      'imageUrl', ph.image, 'archetype', ph.archetype, 'stars', ph.fusion_level, 'locked', ph.locked,
      'finalAtk', round(ph.final_atk), 'finalHp', round(ph.final_hp),
      'power', round(ph.final_atk * 2 + ph.final_hp),
      'maxLevel', hero_max_level(ph.fusion_level),
      'inTeam', exists(select 1 from pvp_team_slots t where t.hero_id = ph.id)
              or exists(select 1 from boss_team_slots b where b.player_hero_id = ph.id),
      'duplicates', (
        select count(*) from player_heroes d
        where d.user_id = ph.user_id and d.hero_key = ph.hero_key and d.id <> ph.id and not d.locked
          and not exists(select 1 from pvp_team_slots t where t.hero_id = d.id)
          and not exists(select 1 from boss_team_slots b where b.player_hero_id = d.id)
      ),
      'next', case when ph.fusion_level >= coalesce((cfg->>'max_stars')::int,5) then null else jsonb_build_object(
        'stars', ph.fusion_level + 1,
        'costFc', coalesce((cfg->'cost_fc'->>(ph.fusion_level+1)::text)::numeric, 0),
        'duplicatesRequired', coalesce((cfg->'duplicates'->>(ph.fusion_level+1)::text)::int, 1),
        'bonusPercent', coalesce((cfg->'bonus_percent'->>(ph.fusion_level+1)::text)::numeric, 0),
        'maxLevel', hero_max_level(ph.fusion_level + 1),
        'finalAtk', greatest(1, round((ph.base_atk + coalesce(ph.bonus_atk,0)) * power(1+ph.attack_growth, ph.level-1) * hero_fusion_multiplier(ph.fusion_level+1))),
        'finalHp', greatest(1, round((ph.base_hp + coalesce(ph.bonus_hp,0)) * power(1+ph.hp_growth, ph.level-1) * hero_fusion_multiplier(ph.fusion_level+1)))
      ) end
    ) as h
    from player_heroes ph where ph.user_id = u
  ) s;
  return jsonb_build_object('config', cfg, 'balance', balance, 'heroes', heroes);
end $$;

create or replace function public.fuse_heroes(p_telegram_id bigint, p_main_hero_id uuid, p_material_ids uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; balance numeric; cfg jsonb := hero_fusion_config(); main player_heroes%rowtype;
  required int; cost numeric; max_stars int; ids uuid[]; used int; after_row player_heroes%rowtype; after_balance numeric;
begin
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into main from player_heroes where id = p_main_hero_id and user_id = u for update;
  if main.id is null then raise exception 'HERO_NOT_OWNED'; end if;
  max_stars := coalesce((cfg->>'max_stars')::int, 5);
  if main.fusion_level >= max_stars then raise exception 'HERO_MAX_STARS'; end if;
  required := coalesce((cfg->'duplicates'->>(main.fusion_level+1)::text)::int, 1);
  cost := coalesce((cfg->'cost_fc'->>(main.fusion_level+1)::text)::numeric, 0);

  select coalesce(array_agg(id), '{}') into ids from (
    select ph.id from player_heroes ph
    where ph.user_id = u and ph.id <> main.id and ph.hero_key = main.hero_key
      and ph.id = any(coalesce(p_material_ids, '{}'::uuid[]))
      and not ph.locked
      and not exists(select 1 from pvp_team_slots t where t.hero_id = ph.id)
      and not exists(select 1 from boss_team_slots b where b.player_hero_id = ph.id)
    order by ph.fusion_level, ph.level
    limit required
    for update
  ) s;
  used := coalesce(array_length(ids,1), 0);
  if used < required then raise exception 'NOT_ENOUGH_DUPLICATES'; end if;
  if balance < cost then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;

  update game_players set forge_coins = forge_coins - cost, updated_at = now() where id = u returning forge_coins into after_balance;
  delete from hero_combat_state where hero_id = any(ids);
  delete from player_heroes where id = any(ids) and user_id = u;
  update player_heroes set fusion_level = fusion_level + 1, updated_at = now() where id = main.id returning * into after_row;

  insert into hero_fusion_history(user_id, hero_id, hero_key, from_stars, to_stars, materials_consumed, material_ids, cost_fc, atk_before, atk_after, hp_before, hp_after)
  values (u, main.id, main.hero_key, main.fusion_level, after_row.fusion_level, used, ids, cost, main.final_atk, after_row.final_atk, main.final_hp, after_row.final_hp);

  return jsonb_build_object(
    'heroId', main.id, 'name', after_row.name, 'fromStars', main.fusion_level, 'toStars', after_row.fusion_level,
    'atkBefore', round(main.final_atk), 'atkAfter', round(after_row.final_atk),
    'hpBefore', round(main.final_hp), 'hpAfter', round(after_row.final_hp),
    'bonusPercent', coalesce((cfg->'bonus_percent'->>after_row.fusion_level::text)::numeric, 0),
    'maxLevel', hero_max_level(after_row.fusion_level),
    'costFc', cost, 'consumed', used, 'balance', after_balance,
    'dashboard', get_hero_fusion_dashboard(p_telegram_id)
  );
end $$;

-- 6. admin configuration (no deploy needed)
create or replace function public.admin_set_fusion_config(p_admin_id bigint, p_patch jsonb, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare before jsonb; merged jsonb;
begin
  perform admin_assert(p_admin_id);
  before := hero_fusion_config();
  merged := before || coalesce(p_patch, '{}'::jsonb);
  if coalesce((merged->>'max_stars')::int, 5) not between 1 and 10 then raise exception 'INVALID_MAX_STARS'; end if;
  insert into game_settings(key, value, category, label, updated_by)
  values ('hero_fusion_config', merged, 'heroes', 'Fusão de heróis (estrelas)', p_admin_id)
  on conflict (key) do update set value = merged, updated_by = p_admin_id, updated_at = now();
  perform admin_bump_settings_version();
  perform admin_log(p_admin_id, 'fusion_config_update', 'setting', 'hero_fusion_config', before, merged, p_reason);
  -- stats are derived from fusion_level: refresh every fused hero with the new multipliers
  update player_heroes set updated_at = now() where fusion_level > 0;
  return merged;
end $$;

revoke all on function public.fuse_heroes(bigint, uuid, uuid[]) from anon, authenticated;
revoke all on function public.set_hero_lock(bigint, uuid, boolean) from anon, authenticated;
revoke all on function public.get_hero_fusion_dashboard(bigint) from anon, authenticated;
revoke all on function public.admin_set_fusion_config(bigint, jsonb, text) from anon, authenticated;