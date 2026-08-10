-- Central RNG helpers: plain random() is enough for loot rolls (no crypto needed).
create or replace function public.forge_random_seed(p_salt text default '')
returns text language sql volatile set search_path to 'public' as $$
  select md5(random()::text||clock_timestamp()::text||coalesce(p_salt,''))||md5(random()::text||coalesce(p_salt,'')||clock_timestamp()::text)
$$;

create or replace function public.roll_rarity_from_rates(p_rates jsonb, p_luck numeric default 0)
returns text language plpgsql volatile set search_path to 'public' as $$
declare roll numeric; cursor_v numeric:=0; k text; rate numeric; rar text; allowed text[]:=array[]::text[];
begin
  roll:=least(99.999,random()*100+greatest(0,coalesce(p_luck,0)));
  foreach k in array array['common','uncommon','rare','epic','legendary','ancestral'] loop
    rate:=coalesce((p_rates->>k)::numeric,0);
    if rate>0 then allowed:=allowed||k; cursor_v:=cursor_v+rate; if rar is null and roll<cursor_v then rar:=k; end if; end if;
  end loop;
  return coalesce(rar,allowed[array_length(allowed,1)],'common');
end $$;

create or replace function public.rates_allowed_rarities(p_rates jsonb)
returns text[] language sql immutable set search_path to 'public' as $$
  select coalesce(array_agg(k order by array_position(array['common','uncommon','rare','epic','legendary','ancestral'],k)),array[]::text[])
  from jsonb_each_text(coalesce(p_rates,'{}'::jsonb)) as e(k,v) where v::numeric>0
$$;

-- Picks one active hero of the rolled rarity, walking down the allowed rarities when a pool is empty.
create or replace function public.roll_hero_for_rarity(p_rarity text, p_allowed text[], out hero public.hero_catalog, out final_rarity text, out fallback_from text)
language plpgsql volatile set search_path to 'public' as $$
declare rar text:=p_rarity;
begin
  loop
    select * into hero from hero_catalog where enabled and rarity=rar order by random() limit 1;
    exit when hero.hero_key is not null;
    if array_position(p_allowed,rar) is null or array_position(p_allowed,rar)=1 then exit; end if;
    fallback_from:=coalesce(fallback_from,rar);
    rar:=p_allowed[array_position(p_allowed,rar)-1];
  end loop;
  if hero.hero_key is null then
    select * into hero from hero_catalog where enabled order by random() limit 1;
    if hero.hero_key is null then raise exception 'NO_ELIGIBLE_HERO'; end if;
    fallback_from:=coalesce(fallback_from,rar);
    rar:=hero.rarity;
  end if;
  final_rarity:=rar;
end $$;

create or replace function public.open_hero_chest(p_telegram_id bigint, p_inventory_item_id uuid, p_source text default 'calendar'::text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare u uuid; inv player_inventory%rowtype; cfg chest_reward_tables%rowtype; rates jsonb;
  seed text; rar text; allowed text[]; pick record;
  hero hero_catalog%rowtype; new_id uuid; basea numeric; baseh int; open_no int; key text; fallback_from text;
begin
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into inv from player_inventory where id=p_inventory_item_id and user_id=u and item_type='hero_chest' for update;
  if inv.id is null or inv.quantity<1 then raise exception 'CHEST_NOT_OWNED'; end if;
  select * into cfg from chest_reward_tables where chest_code=inv.item_code and enabled;
  if cfg.chest_code is null then raise exception 'CHEST_NOT_CONFIGURED'; end if;
  rates:=cfg.rarity_rates;

  seed:=forge_random_seed(inv.id::text);
  allowed:=rates_allowed_rarities(rates);
  rar:=roll_rarity_from_rates(rates,0);
  select * into pick from roll_hero_for_rarity(rar,allowed);
  hero:=pick.hero; rar:=pick.final_rarity; fallback_from:=pick.fallback_from;

  basea:=round((case rar when 'ancestral' then 3.05 when 'legendary' then 2.68 when 'epic' then 2.395 when 'rare' then 2.165 when 'uncommon' then 1.975 else 1.875 end)*(.95+(random()*100)::int/1000.0),3);
  baseh:=round((case rar when 'ancestral' then 340 when 'legendary' then 280 when 'epic' then 220 when 'rare' then 170 when 'uncommon' then 130 else 100 end)*(.95+(random()*100)::int/1000.0));

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
end $function$;

create or replace function public.hatch_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare u uuid; egg pet_eggs%rowtype; inv player_pet_inventory%rowtype; seed_text text;
  rar text; picked pets%rowtype; existing player_pets%rowtype;
  frags int:=0; history_id uuid; luck numeric:=0;
begin
  if length(trim(p_idempotency_key))<8 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if exists(select 1 from pet_hatch_history where idempotency_key=p_idempotency_key and user_id=u) then return get_pet_dashboard(p_telegram_id); end if;
  select * into egg from pet_eggs where id=p_egg_id and is_enabled;
  if egg.id is null then raise exception 'EGG_NOT_FOUND'; end if;
  select * into inv from player_pet_inventory where user_id=u and item_type='egg' and item_id=p_egg_id for update;
  if inv.id is null or inv.quantity<1 then raise exception 'EGG_NOT_OWNED'; end if;
  update player_pet_inventory set quantity=quantity-1, updated_at=now() where id=inv.id;

  seed_text:=forge_random_seed(p_idempotency_key);
  luck:=least(10,coalesce((get_pet_bonuses(u)->>'egg_luck_percent')::numeric,0));
  rar:=roll_rarity_from_rates(egg.rarity_rates,luck);

  select * into picked from pets p where p.is_enabled and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
    order by random() limit 1;
  if picked.id is null then raise exception 'NO_ELIGIBLE_PET'; end if;
  select * into existing from player_pets where user_id=u and pet_id=picked.id for update;
  if existing.id is not null then
    select coalesce((value->>rar)::int,10) into frags from pet_settings where key='duplicate_fragments';
    update player_pets set fragments=fragments+frags, updated_at=now() where id=existing.id;
  else
    insert into player_pets(user_id,pet_id,rarity) values(u,picked.id,rar);
  end if;
  insert into pet_hatch_history(user_id,egg_id,result_pet_id,result_rarity,duplicate_fragments,seed_hash,idempotency_key)
    values(u,egg.id,picked.id,rar,frags,seed_text,p_idempotency_key) returning id into history_id;
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name)
    values(u,p_telegram_id,'egg',egg.slug,'pet_egg',rar,picked.id,picked.name);
  return jsonb_build_object('result',jsonb_build_object('historyId',history_id,'petId',picked.id,'name',picked.name,'rarity',rar,'image',picked.image_baby_url,'duplicateFragments',frags),
    'dashboard',get_pet_dashboard(p_telegram_id));
end $function$;

-- pgcrypto lives in the "extensions" schema: the pool draw needs it on its search_path.
alter function public.distribute_community_pool(boolean) set search_path to 'public','extensions';

create or replace function public.admin_chest_diagnostics(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare result jsonb;
begin
  perform admin_assert(p_admin_id);
  select jsonb_build_object(
    'chests',coalesce((select jsonb_agg(x order by x->>'code') from (
        select jsonb_build_object('code',c.chest_code,'name',c.name,'enabled',c.enabled,'rates',c.rarity_rates,
          'missing',coalesce((select array_agg(r) from unnest(rates_allowed_rarities(c.rarity_rates)) r
             where not exists(select 1 from hero_catalog h where h.enabled and h.rarity=r)),array[]::text[])) x
        from chest_reward_tables c) s),'[]'::jsonb),
    'heroPools',coalesce((select jsonb_object_agg(r,cnt) from (
        select r, (select count(*) from hero_catalog h where h.enabled and h.rarity=r) cnt
        from unnest(array['common','uncommon','rare','epic','legendary','ancestral']) r) p),'{}'::jsonb)
  ) into result;
  return result;
end $$;