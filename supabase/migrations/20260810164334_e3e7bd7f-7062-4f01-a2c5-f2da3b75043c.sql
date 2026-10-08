-- 1. Central chest configuration
create table if not exists public.chest_reward_tables(
  chest_code text primary key,
  name text not null,
  subtitle text not null default '',
  rarity_rates jsonb not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select on public.chest_reward_tables to authenticated;
grant all on public.chest_reward_tables to service_role;
alter table public.chest_reward_tables enable row level security;
create policy "chest tables are service managed" on public.chest_reward_tables for all to service_role using (true) with check (true);

insert into public.chest_reward_tables(chest_code,name,subtitle,rarity_rates) values
 ('common_chest','Baú Comum','Comum','{"common":100}'),
 ('uncommon_chest','Baú Incomum','Incomum','{"common":70,"uncommon":30}'),
 ('rare_chest','Baú Raro','Raro','{"common":50,"uncommon":35,"rare":15}'),
 ('epic_chest','Baú Épico','Épico','{"common":30,"uncommon":30,"rare":30,"epic":10}'),
 ('legendary_chest','Baú Lendário','Lendário','{"rare":45,"epic":40,"legendary":15}'),
 ('hero_chest_common','Baú Comum','Comum','{"common":100}'),
 ('hero_chest_improved','Baú Raro','Raro','{"common":50,"uncommon":35,"rare":15}'),
 ('hero_chest_special','Baú Épico','Épico','{"common":30,"uncommon":30,"rare":30,"epic":10}')
on conflict (chest_code) do update set rarity_rates=excluded.rarity_rates,name=excluded.name,subtitle=excluded.subtitle,updated_at=now();

-- 2. Audit log for every chest/egg opening
create table if not exists public.reward_open_logs(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  telegram_id bigint,
  source text not null default 'calendar',
  item_key text not null,
  item_type text not null,
  rolled_rarity text,
  reward_id uuid,
  reward_name text,
  fallback_from text,
  created_at timestamptz not null default now()
);
grant select on public.reward_open_logs to authenticated;
grant all on public.reward_open_logs to service_role;
alter table public.reward_open_logs enable row level security;
create policy "reward logs are service managed" on public.reward_open_logs for all to service_role using (true) with check (true);
create index if not exists reward_open_logs_user_idx on public.reward_open_logs(user_id, created_at desc);

-- 3. Ancestral rarity support
alter table public.calendar_chest_open_history drop constraint if exists calendar_chest_open_history_result_rarity_check;
alter table public.calendar_chest_open_history add constraint calendar_chest_open_history_result_rarity_check
  check (result_rarity = any(array['common','uncommon','rare','epic','legendary','ancestral']));
alter table public.player_pets drop constraint if exists player_pets_rarity_check;
alter table public.player_pets add constraint player_pets_rarity_check
  check (rarity = any(array['common','uncommon','rare','epic','legendary','ancestral']));

update public.pet_settings set value = value || '{"ancestral":300}'::jsonb where key='duplicate_fragments';

-- 4. Egg odds
update public.pet_eggs set rarity_rates='{"rare":49,"epic":49,"legendary":2}', updated_at=now() where slug='epic-egg';
update public.pet_eggs set rarity_rates='{"legendary":70,"ancestral":30}', updated_at=now() where slug='ancestral-egg';

-- 5. Calendar now points at the real chest codes
update public.calendar_reward_config set item_code='common_chest', title='Baú de Herói', subtitle='Comum',
  rarity_rates=(select rarity_rates from public.chest_reward_tables where chest_code='common_chest'), updated_at=now()
  where item_code='hero_chest_common';
update public.calendar_reward_config set item_code='rare_chest', title='Baú de Herói', subtitle='Raro',
  rarity_rates=(select rarity_rates from public.chest_reward_tables where chest_code='rare_chest'), updated_at=now()
  where item_code='hero_chest_improved';
update public.calendar_reward_config set item_code='epic_chest', title='Baú de Herói', subtitle='Épico',
  rarity_rates=(select rarity_rates from public.chest_reward_tables where chest_code='epic_chest'), updated_at=now()
  where item_code='hero_chest_special';

-- migrate chests already owned by players
update public.player_inventory set item_code=case item_code
    when 'hero_chest_common' then 'common_chest'
    when 'hero_chest_improved' then 'rare_chest'
    when 'hero_chest_special' then 'epic_chest' end, updated_at=now()
  where item_type='hero_chest' and item_code in ('hero_chest_common','hero_chest_improved','hero_chest_special');

-- 6. Generic, atomic chest opening with rarity roll + fallback + logging
create or replace function public.open_hero_chest(p_telegram_id bigint, p_inventory_item_id uuid, p_source text default 'calendar')
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid; inv player_inventory%rowtype; cfg chest_reward_tables%rowtype; rates jsonb;
  seed text; roll numeric; cursor_v numeric:=0; k text; rate numeric; rar text; allowed text[];
  hero hero_catalog%rowtype; new_id uuid; basea numeric; baseh int; open_no int; key text; fallback_from text;
begin
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into inv from player_inventory where id=p_inventory_item_id and user_id=u and item_type='hero_chest' for update;
  if inv.id is null or inv.quantity<1 then raise exception 'CHEST_NOT_OWNED'; end if;
  select * into cfg from chest_reward_tables where chest_code=inv.item_code and enabled;
  if cfg.chest_code is null then raise exception 'CHEST_NOT_CONFIGURED'; end if;
  rates:=cfg.rarity_rates;

  seed:=encode(digest(gen_random_bytes(32),'sha256'),'hex');
  roll:=(('x'||substr(seed,1,8))::bit(32)::bigint%1000000)/10000.0;
  allowed:=array[]::text[];
  foreach k in array array['common','uncommon','rare','epic','legendary','ancestral'] loop
    rate:=coalesce((rates->>k)::numeric,0);
    if rate>0 then allowed:=allowed||k; cursor_v:=cursor_v+rate; if rar is null and roll<cursor_v then rar:=k; end if; end if;
  end loop;
  if rar is null then rar:=allowed[array_length(allowed,1)]; end if;

  -- pick an active hero of that rarity, falling back to the next lower allowed rarity
  loop
    select * into hero from hero_catalog where enabled and rarity=rar order by hashtextextended(hero_key||seed,0) limit 1;
    exit when hero.hero_key is not null;
    if array_position(allowed,rar) is null or array_position(allowed,rar)=1 then exit; end if;
    fallback_from:=coalesce(fallback_from,rar);
    rar:=allowed[array_position(allowed,rar)-1];
  end loop;
  if hero.hero_key is null then
    select * into hero from hero_catalog where enabled order by hashtextextended(hero_key||seed,0) limit 1;
    if hero.hero_key is null then raise exception 'NO_ELIGIBLE_HERO'; end if;
    fallback_from:=coalesce(fallback_from,rar); rar:=hero.rarity;
  end if;

  basea:=round((case rar when 'ancestral' then 3.05 when 'legendary' then 2.68 when 'epic' then 2.395 when 'rare' then 2.165 when 'uncommon' then 1.975 else 1.875 end)*(.95+(('x'||substr(seed,9,4))::bit(16)::int%101)/1000.0),3);
  baseh:=round((case rar when 'ancestral' then 340 when 'legendary' then 280 when 'epic' then 220 when 'rare' then 170 when 'uncommon' then 130 else 100 end)*(.95+(('x'||substr(seed,13,4))::bit(16)::int%101)/1000.0));

  select count(*)+1 into open_no from calendar_chest_open_history where inventory_item_id=inv.id;
  key:='chest_open:'||inv.id||':'||open_no;

  update player_inventory set quantity=quantity-1, updated_at=now() where id=inv.id;
  insert into player_heroes(user_id,hero_key,name,rarity,level,image,base_atk,base_hp,attribute_seed)
    values(u,hero.hero_key,hero.name,rar,1,hero.image,basea,baseh,seed) returning id into new_id;
  insert into calendar_chest_open_history(user_id,inventory_item_id,result_hero_id,result_rarity,idempotency_key)
    values(u,inv.id,new_id,rar,key);
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name,fallback_from)
    values(u,p_telegram_id,coalesce(nullif(p_source,''),'calendar'),inv.item_code,'hero_chest',rar,new_id,hero.name,fallback_from);

  return jsonb_build_object('hero',jsonb_build_object('id',new_id,'name',hero.name,'image',hero.image,'rarity',rar,'level',1,'baseAtk',basea,'baseHp',baseh),
    'chest',jsonb_build_object('code',cfg.chest_code,'name',cfg.name,'subtitle',cfg.subtitle),
    'inventory',get_player_inventory(p_telegram_id));
end $$;

-- backwards compatible wrapper
create or replace function public.open_calendar_hero_chest(p_telegram_id bigint, p_inventory_item_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  select public.open_hero_chest(p_telegram_id,p_inventory_item_id,'calendar');
$$;

-- 7. Player inventory (chests + eggs) so stored items can always be opened
create or replace function public.get_player_inventory(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid;
begin
  select id into u from game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return jsonb_build_object(
    'chests',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'itemCode',i.item_code,'name',coalesce(c.name,i.item_code),'subtitle',coalesce(c.subtitle,''),'quantity',i.quantity,'rarityRates',coalesce(c.rarity_rates,'{}'::jsonb)) order by i.item_code)
      from player_inventory i left join chest_reward_tables c on c.chest_code=i.item_code
      where i.user_id=u and i.item_type='hero_chest' and i.quantity>0),'[]'::jsonb),
    'eggs',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'slug',e.slug,'name',e.name,'image',e.image_url,'quantity',pi.quantity,'rarityRates',e.rarity_rates) order by e.name)
      from player_pet_inventory pi join pet_eggs e on e.id=pi.item_id
      where pi.user_id=u and pi.item_type='egg' and pi.quantity>0),'[]'::jsonb));
end $$;

-- 8. Calendar claim: validate against the real chest/egg catalogs instead of hardcoded whitelists
create or replace function public.claim_calendar_day(p_telegram_id bigint, p_day integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u game_players%rowtype; d jsonb; cycle text; expected int; r calendar_reward_config%rowtype; key text; egg uuid; inv_id uuid;
begin
  select * into u from game_players where telegram_id=p_telegram_id for update;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  d:=get_calendar_dashboard(p_telegram_id); cycle:=d->>'cycle'; expected:=(d->>'currentDay')::int;
  if not (d->>'canClaim')::boolean then raise exception 'CALENDAR_ALREADY_CLAIMED_TODAY'; end if;
  if p_day<>expected then raise exception 'CALENDAR_DAY_LOCKED'; end if;
  select * into r from calendar_reward_config where day=p_day and enabled for share;
  if r.day is null then raise exception 'CALENDAR_REWARD_DISABLED'; end if;
  key:='calendar_claim:'||cycle||':'||u.id||':'||p_day;
  insert into daily_calendar_claims(user_id,calendar_cycle,day,reward_type,reward_code,amount_fc,idempotency_key)
    values(u.id,cycle,p_day,r.reward_type,r.item_code,r.amount_fc,key);
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
    values(u.id,p_day,r.reward_type,r.item_code,r.amount_fc,jsonb_build_object('inventoryItemId',inv_id),key);
  return jsonb_build_object('reward',jsonb_build_object('day',r.day,'type',r.reward_type,'amountFc',r.amount_fc,'itemCode',r.item_code,'title',r.title,'subtitle',r.subtitle),
    'balance',(select forge_coins from game_players where id=u.id),'inventoryItemId',inv_id,
    'inventory',get_player_inventory(p_telegram_id),'dashboard',get_calendar_dashboard(p_telegram_id));
end $$;
