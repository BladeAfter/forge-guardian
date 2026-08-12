-- ============================================================ NFT EXCLUSIVE PETS
alter table public.pets add column if not exists is_nft_exclusive boolean not null default false;
alter table public.pets add column if not exists egg_eligible boolean not null default true;

alter table public.pets drop constraint if exists pets_availability_type_check;
alter table public.pets add constraint pets_availability_type_check
  check (availability_type = any (array['NORMAL','LIMITED','EVENT','MYTHIC_EXCLUSIVE','ADMIN_ONLY','NFT_EXCLUSIVE']));

-- flags always coherent: an NFT pet can never be egg eligible / catalog obtainable
create or replace function public.pets_nft_flags()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.is_nft_exclusive then
    new.egg_eligible := false;
    new.availability_type := 'NFT_EXCLUSIVE';
    new.show_in_catalog := false;
  end if;
  return new;
end $$;
drop trigger if exists pets_nft_flags_trg on public.pets;
create trigger pets_nft_flags_trg before insert or update on public.pets
  for each row execute function public.pets_nft_flags();

insert into public.pets (slug, name, species, category, rarity, description, base_passives,
    image_baby_url, image_young_url, image_adult_url, image_ancestral_url,
    availability_type, is_nft_exclusive, egg_eligible, show_in_catalog, is_enabled, obtainable_from)
values
 ('nft-ignarion','Ignarion','black_fire_dragon','dragon','mythic','Dragão de Fogo Negro. Companheiro NFT exclusivo.',
   '{"boss_damage_percent":30,"critical_chance_percent":16,"team_hp_percent":18}'::jsonb,
   '/assets/game/pets-nft/ignarion.png','/assets/game/pets-nft/ignarion.png','/assets/game/pets-nft/ignarion.png','/assets/game/pets-nft/ignarion.png',
   'NFT_EXCLUSIVE', true, false, false, true, '[]'::jsonb),
 ('nft-astryx','Astryx','cosmic_fox','beast','mythic','Raposa Cósmica. Companheiro NFT exclusivo.',
   '{"reward_percent":26,"account_xp_percent":18,"hero_xp_percent":18}'::jsonb,
   '/assets/game/pets-nft/astryx.png','/assets/game/pets-nft/astryx.png','/assets/game/pets-nft/astryx.png','/assets/game/pets-nft/astryx.png',
   'NFT_EXCLUSIVE', true, false, false, true, '[]'::jsonb),
 ('nft-voltrix','Voltrix','storm_wolf','beast','mythic','Lobo da Tempestade. Companheiro NFT exclusivo.',
   '{"pvp_attack_percent":26,"pvp_speed_percent":20,"critical_chance_percent":16}'::jsonb,
   '/assets/game/pets-nft/voltrix.png','/assets/game/pets-nft/voltrix.png','/assets/game/pets-nft/voltrix.png','/assets/game/pets-nft/voltrix.png',
   'NFT_EXCLUSIVE', true, false, false, true, '[]'::jsonb),
 ('nft-cryon','Cryon','glacial_beast','beast','mythic','Fera Glacial. Companheiro NFT exclusivo.',
   '{"team_hp_percent":26,"boss_damage_percent":20,"pvp_attack_percent":14}'::jsonb,
   '/assets/game/pets-nft/cryon.png','/assets/game/pets-nft/cryon.png','/assets/game/pets-nft/cryon.png','/assets/game/pets-nft/cryon.png',
   'NFT_EXCLUSIVE', true, false, false, true, '[]'::jsonb),
 ('nft-nocthar','Nocthar','shadow_raven','spirit','mythic','Corvo Sombrio. Companheiro NFT exclusivo.',
   '{"critical_chance_percent":22,"pvp_speed_percent":22,"reward_percent":16}'::jsonb,
   '/assets/game/pets-nft/nocthar.png','/assets/game/pets-nft/nocthar.png','/assets/game/pets-nft/nocthar.png','/assets/game/pets-nft/nocthar.png',
   'NFT_EXCLUSIVE', true, false, false, true, '[]'::jsonb),
 ('nft-solarius','Solarius','solar_lion','beast','mythic','Leão Solar. Companheiro NFT exclusivo.',
   '{"boss_damage_percent":26,"team_hp_percent":20,"hero_xp_percent":16}'::jsonb,
   '/assets/game/pets-nft/solarius.png','/assets/game/pets-nft/solarius.png','/assets/game/pets-nft/solarius.png','/assets/game/pets-nft/solarius.png',
   'NFT_EXCLUSIVE', true, false, false, true, '[]'::jsonb),
 ('nft-zephyron','Zephyron','celestial_dragon','dragon','mythic','Dragão Celestial. Companheiro NFT exclusivo.',
   '{"team_hp_percent":24,"reward_percent":22,"account_xp_percent":16}'::jsonb,
   '/assets/game/pets-nft/zephyron.png','/assets/game/pets-nft/zephyron.png','/assets/game/pets-nft/zephyron.png','/assets/game/pets-nft/zephyron.png',
   'NFT_EXCLUSIVE', true, false, false, true, '[]'::jsonb),
 ('nft-sylvaris','Sylvaris','forest_spirit','spirit','mythic','Espírito da Floresta. Companheiro NFT exclusivo.',
   '{"account_xp_percent":24,"hero_xp_percent":22,"team_hp_percent":16}'::jsonb,
   '/assets/game/pets-nft/sylvaris.png','/assets/game/pets-nft/sylvaris.png','/assets/game/pets-nft/sylvaris.png','/assets/game/pets-nft/sylvaris.png',
   'NFT_EXCLUSIVE', true, false, false, true, '[]'::jsonb),
 ('nft-prismara','Prismara','crystal_spirit','spirit','mythic','Espírito de Cristal. Companheiro NFT exclusivo.',
   '{"reward_percent":24,"critical_chance_percent":18,"pvp_attack_percent":18}'::jsonb,
   '/assets/game/pets-nft/prismara.png','/assets/game/pets-nft/prismara.png','/assets/game/pets-nft/prismara.png','/assets/game/pets-nft/prismara.png',
   'NFT_EXCLUSIVE', true, false, false, true, '[]'::jsonb),
 ('nft-eternyx','Eternyx','ancient_guardian','guardian','ancestral','Guardião Ancestral. Companheiro NFT exclusivo.',
   '{"boss_damage_percent":34,"team_hp_percent":28,"reward_percent":28}'::jsonb,
   '/assets/game/pets-nft/eternyx.png','/assets/game/pets-nft/eternyx.png','/assets/game/pets-nft/eternyx.png','/assets/game/pets-nft/eternyx.png',
   'NFT_EXCLUSIVE', true, false, false, true, '[]'::jsonb)
on conflict (slug) do update set
  is_nft_exclusive = true, egg_eligible = false, availability_type = 'NFT_EXCLUSIVE',
  show_in_catalog = false, updated_at = now();

-- ------------------------------------------------------------ registry
create table if not exists public.nft_pets (
  id uuid primary key default gen_random_uuid(),
  pet_template_id uuid not null references public.pets(id) on delete restrict,
  nft_serial integer not null,
  unique_instance_id text not null unique,
  owner_user_id uuid references public.game_players(id) on delete set null,
  player_pet_id uuid,
  status text not null default 'AVAILABLE' check (status in ('AVAILABLE','OWNED','REVOKED','BURNED')),
  created_by_admin bigint,
  assigned_at timestamptz,
  revoked_at timestamptz,
  blockchain text,
  contract_address text,
  nft_address text,
  token_id text,
  minted boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (pet_template_id, nft_serial)
);
create unique index if not exists nft_pets_player_pet_uidx on public.nft_pets(player_pet_id) where player_pet_id is not null;
grant all on public.nft_pets to service_role;
alter table public.nft_pets enable row level security;

create table if not exists public.nft_pet_history (
  id uuid primary key default gen_random_uuid(),
  nft_pet_id uuid not null references public.nft_pets(id) on delete cascade,
  action text not null,
  admin_telegram_id bigint,
  from_user_id uuid,
  to_user_id uuid,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
grant all on public.nft_pet_history to service_role;
alter table public.nft_pet_history enable row level security;

drop trigger if exists nft_pets_updated_at on public.nft_pets;
create trigger nft_pets_updated_at before update on public.nft_pets
  for each row execute function public.update_updated_at_column();

alter table public.player_pets add column if not exists nft_pet_id uuid references public.nft_pets(id) on delete set null;
create unique index if not exists player_pets_nft_uidx on public.player_pets(nft_pet_id) where nft_pet_id is not null;
alter table public.nft_pets drop constraint if exists nft_pets_player_pet_fk;
alter table public.nft_pets add constraint nft_pets_player_pet_fk
  foreign key (player_pet_id) references public.player_pets(id) on delete set null;

-- ------------------------------------------------------------ hard guards
create or replace function public.player_pets_nft_guard()
returns trigger language plpgsql set search_path = public as $$
declare nft boolean;
begin
  if tg_op = 'INSERT' then
    select is_nft_exclusive into nft from public.pets where id = new.pet_id;
    if coalesce(nft,false) then
      if new.nft_pet_id is null then raise exception 'NFT_PET_ADMIN_ONLY'; end if;
      new.tradable := false; new.market_locked := true;
    end if;
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if old.nft_pet_id is not null then
      if new.nft_pet_id is distinct from old.nft_pet_id then raise exception 'NFT_PET_IMMUTABLE'; end if;
      if new.user_id is distinct from old.user_id then raise exception 'NFT_PET_NOT_TRANSFERABLE'; end if;
      new.tradable := false; new.market_locked := true;
    end if;
    return new;
  end if;
  if old.nft_pet_id is not null and coalesce(current_setting('mythreon.nft_revoke', true), '') <> '1' then
    raise exception 'NFT_PET_CANNOT_BE_DESTROYED';
  end if;
  return old;
end $$;
drop trigger if exists player_pets_nft_guard_trg on public.player_pets;
create trigger player_pets_nft_guard_trg before insert or update or delete on public.player_pets
  for each row execute function public.player_pets_nft_guard();

-- never let an NFT pet enter any reward / egg pool
create or replace function public.reward_pool_nft_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if exists (select 1 from public.pets where id = new.pet_id and is_nft_exclusive) then
    raise exception 'NFT_PET_NOT_DRAWABLE';
  end if;
  return new;
end $$;
drop trigger if exists reward_pet_pool_nft_guard_trg on public.reward_pet_pool;
create trigger reward_pet_pool_nft_guard_trg before insert or update on public.reward_pet_pool
  for each row execute function public.reward_pool_nft_guard();

-- never let an NFT pet be listed on the player market
create or replace function public.market_listing_nft_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.item_type = 'pet' and new.item_instance_id is not null
     and exists (select 1 from public.player_pets pp where pp.id = new.item_instance_id and pp.nft_pet_id is not null) then
    raise exception 'NFT_PET_NOT_SELLABLE';
  end if;
  return new;
end $$;
drop trigger if exists market_listings_nft_guard_trg on public.market_listings;
create trigger market_listings_nft_guard_trg before insert on public.market_listings
  for each row execute function public.market_listing_nft_guard();

-- ------------------------------------------------------------ admin api
create or replace function public.admin_nft_overview(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  perform public.admin_assert(p_admin_id);
  select jsonb_build_object(
    'templates', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', p.slug, 'name', p.name, 'rarity', p.rarity, 'species', p.species,
        'image', p.image_adult_url,
        'minted', (select count(*) from nft_pets n where n.pet_template_id = p.id),
        'available', (select count(*) from nft_pets n where n.pet_template_id = p.id and n.status = 'AVAILABLE'),
        'owned', (select count(*) from nft_pets n where n.pet_template_id = p.id and n.status = 'OWNED')
      ) order by p.name) from pets p where p.is_nft_exclusive), '[]'::jsonb),
    'totals', jsonb_build_object(
      'units', (select count(*) from nft_pets),
      'available', (select count(*) from nft_pets where status = 'AVAILABLE'),
      'owned', (select count(*) from nft_pets where status = 'OWNED'),
      'revoked', (select count(*) from nft_pets where status = 'REVOKED'))
  ) into res;
  return res;
end $$;

create or replace function public.admin_nft_create(p_admin_id bigint, p_slug text, p_quantity integer default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pt public.pets; qty int; i int; nxt int; created jsonb := '[]'::jsonb; row_id uuid; inst text;
begin
  perform public.admin_assert(p_admin_id);
  qty := greatest(1, least(50, coalesce(p_quantity, 1)));
  select * into pt from pets where (slug = p_slug or id::text = p_slug) and is_nft_exclusive;
  if pt.id is null then raise exception 'NFT_TEMPLATE_NOT_FOUND'; end if;
  select coalesce(max(nft_serial),0) into nxt from nft_pets where pet_template_id = pt.id;
  for i in 1..qty loop
    nxt := nxt + 1;
    inst := 'NFT-' || upper(regexp_replace(pt.name, '[^a-zA-Z0-9]', '', 'g')) || '-' || lpad(nxt::text, 4, '0');
    insert into nft_pets (pet_template_id, nft_serial, unique_instance_id, status, created_by_admin, minted)
    values (pt.id, nxt, inst, 'AVAILABLE', p_admin_id, false)
    returning id into row_id;
    insert into nft_pet_history (nft_pet_id, action, admin_telegram_id, metadata)
      values (row_id, 'CREATED', p_admin_id, jsonb_build_object('serial', nxt, 'instance', inst));
    created := created || jsonb_build_object('id', row_id, 'serial', nxt, 'instance', inst);
  end loop;
  perform public.admin_log(p_admin_id,'nft.create','pet',pt.slug,null,jsonb_build_object('quantity',qty),'NFT units created');
  return jsonb_build_object('pet', pt.name, 'slug', pt.slug, 'created', created);
end $$;

create or replace function public.admin_nft_available(p_admin_id bigint, p_slug text default null, p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  perform public.admin_assert(p_admin_id);
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', n.id, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
      'slug', p.slug, 'pet', p.name, 'rarity', p.rarity) order by p.name, n.nft_serial), '[]'::jsonb)
    into res
  from nft_pets n join pets p on p.id = n.pet_template_id
  where n.status = 'AVAILABLE' and (p_slug is null or p.slug = p_slug)
  limit greatest(1, least(60, coalesce(p_limit, 20)));
  return res;
end $$;

create or replace function public.admin_nft_registry(p_admin_id bigint, p_limit integer default 20, p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rows_json jsonb; total int;
begin
  perform public.admin_assert(p_admin_id);
  select count(*) into total from nft_pets;
  select coalesce(jsonb_agg(x order by (x->>'createdAt') desc), '[]'::jsonb) into rows_json from (
    select jsonb_build_object(
      'id', n.id, 'pet', p.name, 'slug', p.slug, 'rarity', p.rarity,
      'serial', n.nft_serial, 'instance', n.unique_instance_id, 'status', n.status,
      'minted', n.minted, 'createdAt', n.created_at, 'assignedAt', n.assigned_at,
      'owner', case when g.id is null then null else jsonb_build_object('name', g.name, 'telegramId', g.telegram_id, 'userId', g.id) end
    ) as x
    from nft_pets n
    join pets p on p.id = n.pet_template_id
    left join game_players g on g.id = n.owner_user_id
    order by n.created_at desc
    limit greatest(1, least(50, coalesce(p_limit,20))) offset greatest(0, coalesce(p_offset,0))
  ) t;
  return jsonb_build_object('total', total, 'units', rows_json);
end $$;

create or replace function public.admin_nft_search(p_admin_id bigint, p_query text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare q text; res jsonb;
begin
  perform public.admin_assert(p_admin_id);
  q := '%' || trim(coalesce(p_query,'')) || '%';
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', n.id, 'pet', p.name, 'slug', p.slug, 'serial', n.nft_serial,
      'instance', n.unique_instance_id, 'status', n.status,
      'owner', case when g.id is null then null else jsonb_build_object('name', g.name, 'telegramId', g.telegram_id) end
    ) order by n.created_at desc), '[]'::jsonb) into res
  from nft_pets n
  join pets p on p.id = n.pet_template_id
  left join game_players g on g.id = n.owner_user_id
  where n.unique_instance_id ilike q or p.name ilike q or p.slug ilike q
     or coalesce(g.name,'') ilike q or coalesce(g.telegram_id::text,'') ilike q
     or n.id::text = trim(coalesce(p_query,''));
  return res;
end $$;

create or replace function public.admin_nft_give(p_admin_id bigint, p_ref text, p_nft_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid; n public.nft_pets; pt public.pets; v_pp uuid; g record;
begin
  perform public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  select * into n from nft_pets where id = p_nft_id for update;
  if n.id is null then raise exception 'NFT_NOT_FOUND'; end if;
  if n.status = 'OWNED' or n.owner_user_id is not null then raise exception 'NFT_ALREADY_OWNED'; end if;
  if n.status = 'BURNED' then raise exception 'NFT_BURNED'; end if;
  select * into pt from pets where id = n.pet_template_id;

  insert into player_pets (user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active, tradable, market_locked, nft_pet_id)
  values (v_uid, pt.id, pt.rarity, 1, 0, 'baby', 0, false, false, true, n.id)
  returning id into v_pp;

  update nft_pets set owner_user_id = v_uid, player_pet_id = v_pp, status = 'OWNED',
      assigned_at = now(), revoked_at = null, updated_at = now()
   where id = n.id;
  insert into nft_pet_history (nft_pet_id, action, admin_telegram_id, to_user_id, reason)
    values (n.id, 'DELIVERED', p_admin_id, v_uid, p_reason);
  perform public.admin_log(p_admin_id,'nft.give','player',v_uid::text,null,
    jsonb_build_object('nft', n.unique_instance_id, 'pet', pt.slug, 'player_pet_id', v_pp), p_reason);

  select name, telegram_id into g from game_players where id = v_uid;
  return jsonb_build_object('pet', pt.name, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
    'playerName', g.name, 'telegramId', g.telegram_id, 'playerPetId', v_pp);
end $$;

create or replace function public.admin_nft_revoke(p_admin_id bigint, p_nft_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n public.nft_pets; pt public.pets; prev uuid;
begin
  perform public.admin_assert(p_admin_id);
  select * into n from nft_pets where id = p_nft_id for update;
  if n.id is null then raise exception 'NFT_NOT_FOUND'; end if;
  select * into pt from pets where id = n.pet_template_id;
  prev := n.owner_user_id;
  perform set_config('mythreon.nft_revoke','1', true);
  if n.player_pet_id is not null then
    delete from player_pets where id = n.player_pet_id;
  end if;
  perform set_config('mythreon.nft_revoke','0', true);
  update nft_pets set owner_user_id = null, player_pet_id = null, status = 'AVAILABLE',
      revoked_at = now(), assigned_at = null, updated_at = now()
   where id = n.id;
  insert into nft_pet_history (nft_pet_id, action, admin_telegram_id, from_user_id, reason)
    values (n.id, 'REVOKED', p_admin_id, prev, p_reason);
  perform public.admin_log(p_admin_id,'nft.revoke','pet',n.unique_instance_id,null,
    jsonb_build_object('from', prev), p_reason);
  return jsonb_build_object('instance', n.unique_instance_id, 'pet', pt.name, 'serial', n.nft_serial);
end $$;

create or replace function public.admin_nft_history(p_admin_id bigint, p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  perform public.admin_assert(p_admin_id);
  select coalesce(jsonb_agg(jsonb_build_object(
      'action', h.action, 'createdAt', h.created_at, 'reason', h.reason,
      'instance', n.unique_instance_id, 'pet', p.name,
      'to', (select name from game_players where id = h.to_user_id),
      'from', (select name from game_players where id = h.from_user_id)
    ) order by h.created_at desc), '[]'::jsonb) into res
  from (select * from nft_pet_history order by created_at desc limit greatest(1, least(50, coalesce(p_limit,20)))) h
  join nft_pets n on n.id = h.nft_pet_id
  join pets p on p.id = n.pet_template_id;
  return res;
end $$;

-- ------------------------------------------------------------ expose NFT info to the game
create or replace function public.player_pet_json(p_player_pet_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
DECLARE ppet record; nxt record; buffs jsonb; pkey text; pbase numeric; maxlvl int; totals numeric; nftj jsonb;
BEGIN
  SELECT ppet2.*, p.name, p.slug, p.species, p.category, p.base_passives, p.active_skill,
         p.image_baby_url, p.image_young_url, p.image_adult_url, p.image_ancestral_url,
         p.is_nft_exclusive
    INTO ppet FROM player_pets ppet2 JOIN pets p ON p.id = ppet2.pet_id WHERE ppet2.id = p_player_pet_id;
  IF NOT found THEN RETURN NULL; END IF;
  maxlvl := pet_max_level();
  buffs := player_pet_buffs(ppet.id);
  SELECT key, (value#>>'{}')::numeric INTO pkey, pbase
    FROM jsonb_each(coalesce(ppet.base_passives,'{}'::jsonb)) ORDER BY (value#>>'{}')::numeric DESC LIMIT 1;
  SELECT * INTO nxt FROM pet_evolution_tiers WHERE tier = ppet.evolution_tier + 1 AND enabled;
  SELECT coalesce(sum((value#>>'{}')::numeric),0) INTO totals FROM jsonb_each(buffs);
  SELECT jsonb_build_object('serial', n.nft_serial, 'instanceId', n.unique_instance_id,
      'status', n.status, 'minted', n.minted)
    INTO nftj FROM nft_pets n WHERE n.id = ppet.nft_pet_id;
  RETURN jsonb_build_object(
    'id', ppet.id, 'petId', ppet.pet_id, 'name', ppet.name, 'slug', ppet.slug, 'species', ppet.species,
    'category', ppet.category, 'rarity', ppet.rarity, 'level', ppet.level, 'maxLevel', maxlvl,
    'xp', ppet.xp, 'xpRequired', CASE WHEN ppet.level >= maxlvl THEN 0 ELSE pet_level_xp_required(ppet.level) END,
    'isMaxLevel', ppet.level >= maxlvl,
    'evolutionTier', ppet.evolution_tier,
    'evolutionLabel', coalesce((SELECT label FROM pet_evolution_tiers WHERE tier = ppet.evolution_tier), 'Forma Base'),
    'evolutionStage', ppet.evolution_stage,
    'fragments', ppet.fragments, 'isActive', ppet.is_active,
    'image', CASE ppet.evolution_stage
       WHEN 'ancestral' THEN ppet.image_ancestral_url WHEN 'adult' THEN ppet.image_adult_url
       WHEN 'young' THEN ppet.image_young_url ELSE ppet.image_baby_url END,
    'buffs', buffs,
    'primaryBuffKey', pkey,
    'primaryBuffValue', coalesce((buffs->>pkey)::numeric, 0),
    'secondaryBuffs', coalesce(ppet.secondary_buffs,'[]'::jsonb),
    'power', (CASE ppet.rarity WHEN 'legendary' THEN 8000 WHEN 'epic' THEN 4000 WHEN 'rare' THEN 2000
              WHEN 'uncommon' THEN 1000 ELSE 500 END) + ppet.level * 100 + round(totals * 250),
    'activeSkill', ppet.active_skill,
    'isNft', coalesce(ppet.is_nft_exclusive, false),
    'nft', nftj,
    'nextEvolution', CASE WHEN nxt.tier IS NULL THEN NULL ELSE jsonb_build_object(
        'tier', nxt.tier, 'label', nxt.label, 'requiredLevel', nxt.required_level,
        'fcCost', nxt.fc_cost, 'fragmentCost', nxt.fragment_cost,
        'newBuffChance', round(nxt.new_buff_chance * 100),
        'maxSecondaryBuffs', nxt.max_secondary_buffs,
        'primaryFrom', coalesce((buffs->>pkey)::numeric, 0),
        'primaryTo', round(coalesce(pbase,0) * pet_rarity_multiplier(ppet.rarity)
                     * (1 + (ppet.level - 1) * 0.02) * nxt.primary_multiplier, 2)
      ) END,
    'canEvolve', nxt.tier IS NOT NULL AND ppet.level >= nxt.required_level
  );
END $$;
