-- Official single implementation of chest rarity roll (explicit numeric params)
create or replace function public.roll_chest_rarity(
  p_common numeric default 0,
  p_uncommon numeric default 0,
  p_rare numeric default 0,
  p_epic numeric default 0,
  p_legendary numeric default 0,
  p_ancestral numeric default 0
) returns table(rarity text, allowed text[])
language plpgsql
stable
set search_path = public
as $$
declare
  keys text[] := array['common','uncommon','rare','epic','legendary','ancestral'];
  vals numeric[] := array[coalesce(p_common,0),coalesce(p_uncommon,0),coalesce(p_rare,0),coalesce(p_epic,0),coalesce(p_legendary,0),coalesce(p_ancestral,0)];
  total numeric := 0;
  cursor_v numeric := 0;
  roll numeric;
  i int;
  picked text;
  allow text[] := array[]::text[];
begin
  for i in 1..6 loop
    if vals[i] < 0 then raise exception 'CHEST_RATES_INVALID'; end if;
    total := total + vals[i];
  end loop;
  if abs(total - 100) > 0.01 then raise exception 'CHEST_RATES_SUM_INVALID'; end if;

  roll := random() * total;
  for i in 1..6 loop
    if vals[i] > 0 then
      allow := allow || keys[i];
      cursor_v := cursor_v + vals[i];
      if picked is null and roll < cursor_v then picked := keys[i]; end if;
    end if;
  end loop;

  rarity := coalesce(picked, allow[array_length(allow,1)], 'common');
  allowed := allow;
  return next;
end;
$$;

grant execute on function public.roll_chest_rarity(numeric,numeric,numeric,numeric,numeric,numeric) to service_role;

-- Fix the caller: pass explicit numeric rates instead of the whole chest_reward_tables record
create or replace function public.open_hero_chest(p_telegram_id bigint, p_inventory_item_id uuid, p_source text default 'calendar')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid; inv player_inventory%rowtype; cfg chest_reward_tables%rowtype;
  rar text; allowed text[]; hero record; pick record; roll record;
  basea numeric; baseh int; seed int; new_id uuid; open_no int; key text; fallback_from text;
begin
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('hero_chest:'||u::text,0));

  select * into inv from player_inventory where id=p_inventory_item_id and user_id=u for update;
  if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_FOUND'; end if;

  select * into cfg from chest_reward_tables where chest_code=inv.item_code and enabled;
  if cfg.chest_code is null then raise exception 'CHEST_NOT_CONFIGURED'; end if;

  seed:=(random()*1000000)::int;
  select r.rarity, r.allowed into rar, allowed from roll_chest_rarity(
    coalesce((cfg.rarity_rates->>'common')::numeric,0),
    coalesce((cfg.rarity_rates->>'uncommon')::numeric,0),
    coalesce((cfg.rarity_rates->>'rare')::numeric,0),
    coalesce((cfg.rarity_rates->>'epic')::numeric,0),
    coalesce((cfg.rarity_rates->>'legendary')::numeric,0),
    coalesce((cfg.rarity_rates->>'ancestral')::numeric,0)
  ) r;

  select * into pick from roll_hero_for_rarity(rar,allowed);
  hero:=pick.hero; rar:=pick.final_rarity; fallback_from:=pick.fallback_from;

  basea:=round((case rar when 'ancestral' then 3.05 when 'legendary' then 2.68 when 'epic' then 2.395 when 'rare' then 2.165 when 'uncommon' then 1.975 else 1.875 end)*(.95+(random()*100)::int/1000.0),3);
  baseh:=round((case rar when 'ancestral' then 340 when 'legendary' then 280 when 'epic' then 220 when 'rare' then 170 when 'uncommon' then 130 else 100 end)*(.95+(random()*100)::int/1000.0));

  select count(*)+1 into open_no from calendar_chest_open_history where inventory_item_id=inv.id;
  key:='chest_open:'||inv.id||':'||open_no;

  update player_inventory set quantity=quantity-1, updated_at=now() where id=inv.id;
  insert into player_heroes(user_id,hero_key,name,rarity,level,image,base_atk,base_hp,attribute_seed)
    values(u,hero.hero_key,hero.name,rar,1,hero.image,basea,baseh,seed) returning id into new_id;
  insert into calendar_chest_open_history(user_id,inventory_item_id,result_hero_id,result_rarity,idempotency_key,result_hero_key,result_hero_name,result_hero_image)
    values(u,inv.id,new_id,rar,key,hero.hero_key,hero.name,hero.image);
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name,fallback_from)
    values(u,p_telegram_id,coalesce(nullif(p_source,''),'calendar'),inv.item_code,'hero_chest',rar,new_id,hero.name,fallback_from);

  return jsonb_build_object('hero',jsonb_build_object('id',new_id,'name',hero.name,'image',hero.image,'rarity',rar,'level',1,'baseAtk',basea,'baseHp',baseh),
    'chest',jsonb_build_object('code',cfg.chest_code,'name',cfg.name,'subtitle',cfg.subtitle),
    'inventory',get_player_inventory(p_telegram_id));
end;
$$;

-- Guard: chest rate tables must always sum to 100
create or replace function public.chest_rates_sum_ok(p_rates jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select abs(coalesce((select sum(v::numeric) from jsonb_each_text(p_rates) as t(k,v)),0) - 100) <= 0.01
$$;

alter table public.chest_reward_tables
  drop constraint if exists chest_reward_tables_rates_sum_check;
alter table public.chest_reward_tables
  add constraint chest_reward_tables_rates_sum_check check (public.chest_rates_sum_ok(rarity_rates));