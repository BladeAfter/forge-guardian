create extension if not exists pgcrypto;

create table if not exists public.pets(
 id uuid primary key default gen_random_uuid(),name text not null,slug text unique not null,species text not null,category text not null,description text,
 base_passives jsonb not null default '{}',active_skill jsonb,image_baby_url text,image_young_url text,image_adult_url text,image_ancestral_url text,
 is_enabled boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.player_pets(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references game_players(id) on delete cascade,pet_id uuid not null references pets(id),
 rarity text not null check(rarity in('common','uncommon','rare','epic','legendary')),level integer not null default 1 check(level between 1 and 30),xp integer not null default 0 check(xp>=0),
 evolution_stage text not null default 'baby' check(evolution_stage in('baby','young','adult','ancestral')),fragments integer not null default 0 check(fragments>=0),is_active boolean not null default false,
 obtained_at timestamptz not null default now(),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(user_id,pet_id)
);
create unique index if not exists player_pets_one_active on player_pets(user_id) where is_active;
create index if not exists player_pets_user_idx on player_pets(user_id);
create table if not exists public.pet_eggs(
 id uuid primary key default gen_random_uuid(),name text not null,slug text unique not null,image_url text,rarity_rates jsonb not null,allowed_pet_categories jsonb,
 price_fc numeric check(price_fc is null or price_fc>=0),price_ton numeric check(price_ton is null or price_ton>=0),is_enabled boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.player_pet_inventory(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references game_players(id) on delete cascade,item_type text not null check(item_type in('egg','food','universal_fragment')),
 item_id uuid references pet_eggs(id),quantity integer not null default 0 check(quantity>=0),updated_at timestamptz not null default now()
);
create unique index if not exists player_pet_inventory_unique on player_pet_inventory(user_id,item_type,coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid));
create table if not exists public.pet_hatch_history(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references game_players(id),egg_id uuid not null references pet_eggs(id),result_pet_id uuid references pets(id),result_rarity text check(result_rarity in('common','uncommon','rare','epic','legendary')),
 duplicate_fragments integer not null default 0,seed_hash text not null,idempotency_key text unique not null,created_at timestamptz not null default now()
);
create table if not exists public.pet_upgrade_history(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references game_players(id),player_pet_id uuid not null references player_pets(id),old_level integer,new_level integer,
 fc_spent numeric not null default 0,food_spent integer not null default 0,fragments_spent integer not null default 0,created_at timestamptz not null default now()
);
create table if not exists public.pet_settings(key text primary key,value jsonb not null,updated_at timestamptz not null default now());
insert into pet_settings(key,value) values
 ('bonus_caps','{"boss_damage_percent":20,"farm_fc_percent":15,"critical_chance_percent":10,"pvp_speed_percent":10,"team_hp_percent":20,"pvp_defense_percent":20,"defense_percent":20,"reward_percent":10,"drop_chance_percent":10,"egg_luck_percent":10,"hero_xp_percent":15,"account_xp_percent":15}'),
 ('duplicate_fragments','{"common":10,"uncommon":20,"rare":40,"epic":80,"legendary":150}'),('max_level','30'),('food_xp','100') on conflict(key) do nothing;

insert into pets(name,slug,species,category,description,base_passives,active_skill,image_baby_url,image_young_url,image_adult_url,image_ancestral_url) values
 ('Pyron','pyron','fire_dragon','dragon','Companheiro de dano contra chefes','{"boss_damage_percent":5,"pvp_attack_percent":2}','{"name":"Chama Ancestral","cooldown_seconds":60,"boss_team_cycles":3,"pvp_turns":5,"pvp_attack_percent":70}','/assets/game/pets/pyron.webp','/assets/game/pets/pyron.webp','/assets/game/pets/pyron.webp','/assets/game/pets/pyron.webp'),
 ('Glacius','glacius','ice_dragon','dragon','Guardião de gelo e defesa','{"team_hp_percent":5,"pvp_defense_percent":4,"boss_damage_reduction_percent":5}','{"name":"Barreira Congelada","pvp_turns":5,"shield_team_hp_percent":8}','/assets/game/pets/glacius.webp','/assets/game/pets/glacius.webp','/assets/game/pets/glacius.webp','/assets/game/pets/glacius.webp'),
 ('Noctis','noctis','shadow_wolf','beast','Caçador crítico e veloz','{"critical_chance_percent":4,"pvp_speed_percent":3}','{"name":"Caçada Sombria","target":"lowest_hp","average_team_atk_percent":80}','/assets/game/pets/noctis.webp','/assets/game/pets/noctis.webp','/assets/game/pets/noctis.webp','/assets/game/pets/noctis.webp'),
 ('Ignara','ignara','phoenix','bird','Fênix de renascimento e prosperidade','{"reward_percent":3,"team_hp_percent":3,"revive_speed_percent":15}','{"name":"Renascimento","once_per_battle":true,"revive_hp_percent":20}','/assets/game/pets/ignara.webp','/assets/game/pets/ignara.webp','/assets/game/pets/ignara.webp','/assets/game/pets/ignara.webp'),
 ('Bastion','bastion','iron_golem','magical','Muralha viva de ferro','{"defense_percent":8,"team_hp_percent":4}','{"name":"Muralha de Ferro","shield_individual_hp_percent":5}','/assets/game/pets/bastion.webp','/assets/game/pets/bastion.webp','/assets/game/pets/bastion.webp','/assets/game/pets/bastion.webp'),
 ('Aureon','aureon','golden_griffin','bird','Companheiro de farm e produção','{"farm_fc_percent":5,"offline_production_percent":5,"mission_reward_percent":2}','{"name":"Prosperidade"}','/assets/game/pets/aureon.webp','/assets/game/pets/aureon.webp','/assets/game/pets/aureon.webp','/assets/game/pets/aureon.webp'),
 ('Lumia','lumia','mystic_fox','magical','Raposa de sorte mística','{"drop_chance_percent":5,"egg_luck_percent":3,"random_reward_percent":2}','{"name":"Fortuna Mística"}','/assets/game/pets/lumia.webp','/assets/game/pets/lumia.webp','/assets/game/pets/lumia.webp','/assets/game/pets/lumia.webp'),
 ('Astra','astra','arcane_owl','bird','Sábia companheira de experiência','{"hero_xp_percent":5,"account_xp_percent":3,"mission_progress_percent":2}','{"name":"Sabedoria Arcana"}','/assets/game/pets/astra.webp','/assets/game/pets/astra.webp','/assets/game/pets/astra.webp','/assets/game/pets/astra.webp') on conflict(slug) do update set base_passives=excluded.base_passives,active_skill=excluded.active_skill,updated_at=now();
insert into pet_eggs(name,slug,image_url,rarity_rates,allowed_pet_categories,price_fc) values
 ('Ovo Comum','common-egg','/assets/game/pet-eggs/common-egg.webp','{"common":75,"uncommon":20,"rare":5}',null,10000),
 ('Ovo Raro','rare-egg','/assets/game/pet-eggs/rare-egg.webp','{"common":35,"uncommon":40,"rare":20,"epic":5}',null,30000),
 ('Ovo Épico','epic-egg','/assets/game/pet-eggs/epic-egg.webp','{"uncommon":25,"rare":45,"epic":25,"legendary":5}',null,75000),
 ('Ovo Ancestral','ancestral-egg','/assets/game/pet-eggs/ancestral-egg.webp','{"rare":50,"epic":40,"legendary":10}',null,150000),
 ('Ovo de Dragão','dragon-egg','/assets/game/pet-eggs/dragon-egg.webp','{"common":35,"uncommon":35,"rare":20,"epic":8,"legendary":2}','["dragon"]',100000) on conflict(slug) do update set rarity_rates=excluded.rarity_rates,allowed_pet_categories=excluded.allowed_pet_categories,updated_at=now();

alter table pets enable row level security;alter table player_pets enable row level security;alter table pet_eggs enable row level security;alter table player_pet_inventory enable row level security;alter table pet_hatch_history enable row level security;alter table pet_upgrade_history enable row level security;alter table pet_settings enable row level security;
revoke all on pets,player_pets,pet_eggs,player_pet_inventory,pet_hatch_history,pet_upgrade_history,pet_settings from anon,authenticated;
grant all on pets,player_pets,pet_eggs,player_pet_inventory,pet_hatch_history,pet_upgrade_history,pet_settings to service_role;