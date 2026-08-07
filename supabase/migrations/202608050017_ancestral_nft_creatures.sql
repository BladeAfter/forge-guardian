alter table public.pets
  add column if not exists is_nft boolean not null default false,
  add column if not exists nft_collection text,
  add column if not exists nft_badge text;

create table if not exists public.ancestral_nft_pool(
  pet_id uuid primary key references public.pets(id) on delete cascade,
  weight integer not null default 20 check(weight > 0),
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.ancestral_nft_pool enable row level security;
revoke all on public.ancestral_nft_pool from anon,authenticated;

insert into public.pets(name,slug,species,category,description,base_passives,active_skill,image_baby_url,image_young_url,image_adult_url,image_ancestral_url,is_season_exclusive,exclusive_badge,exclusive_passive,is_nft,nft_collection,nft_badge,is_enabled) values
('Solkaris','ancestral-nft-solkaris','solar_qilin_dragon','ancestral_nft','Qilin-dragão solar exclusivo da coleção do Ovo Ancestral.','{"boss_damage_percent":9,"farm_fc_percent":7}','{"name":"Coroa do Sol","pvp_turns":4,"average_team_atk_percent":80}','/assets/game/pets/ancestral-nft/solkaris.png','/assets/game/pets/ancestral-nft/solkaris.png','/assets/game/pets/ancestral-nft/solkaris.png','/assets/game/pets/ancestral-nft/solkaris.png',true,'NFT','{"collection":"Ancestral Genesis"}',true,'ancestral_genesis','NFT',false),
('Umbrael','ancestral-nft-umbrael','cosmic_panther','ancestral_nft','Pantera cósmica exclusiva da coleção do Ovo Ancestral.','{"critical_chance_percent":8,"pvp_speed_percent":7}','{"name":"Eclipse Violeta","pvp_turns":4,"average_team_atk_percent":82}','/assets/game/pets/ancestral-nft/umbrael.png','/assets/game/pets/ancestral-nft/umbrael.png','/assets/game/pets/ancestral-nft/umbrael.png','/assets/game/pets/ancestral-nft/umbrael.png',true,'NFT','{"collection":"Ancestral Genesis"}',true,'ancestral_genesis','NFT',false),
('Thalassor','ancestral-nft-thalassor','citadel_leviathan','ancestral_nft','Leviatã-cidadela exclusivo da coleção do Ovo Ancestral.','{"team_hp_percent":9,"pvp_defense_percent":7}','{"name":"Fortaleza Abissal","pvp_turns":5,"team_max_hp_shield_percent":10}','/assets/game/pets/ancestral-nft/thalassor.png','/assets/game/pets/ancestral-nft/thalassor.png','/assets/game/pets/ancestral-nft/thalassor.png','/assets/game/pets/ancestral-nft/thalassor.png',true,'NFT','{"collection":"Ancestral Genesis"}',true,'ancestral_genesis','NFT',false),
('Verdantia','ancestral-nft-verdantia','crystal_fox_stag','ancestral_nft','Espírito raposa-cervo exclusivo da coleção do Ovo Ancestral.','{"mission_reward_percent":8,"drop_chance_percent":7}','{"name":"Florescer Eterno","pvp_turns":5,"team_max_hp_shield_percent":7}','/assets/game/pets/ancestral-nft/verdantia.png','/assets/game/pets/ancestral-nft/verdantia.png','/assets/game/pets/ancestral-nft/verdantia.png','/assets/game/pets/ancestral-nft/verdantia.png',true,'NFT','{"collection":"Ancestral Genesis"}',true,'ancestral_genesis','NFT',false),
('Ignivar','ancestral-nft-ignivar','volcanic_ram_phoenix','ancestral_nft','Carneiro-fênix vulcânico exclusivo da coleção do Ovo Ancestral.','{"boss_damage_percent":8,"revive_speed_percent":9}','{"name":"Erupção Imortal","pvp_turns":4,"average_team_atk_percent":85}','/assets/game/pets/ancestral-nft/ignivar.png','/assets/game/pets/ancestral-nft/ignivar.png','/assets/game/pets/ancestral-nft/ignivar.png','/assets/game/pets/ancestral-nft/ignivar.png',true,'NFT','{"collection":"Ancestral Genesis"}',true,'ancestral_genesis','NFT',false)
on conflict(slug) do update set name=excluded.name,species=excluded.species,category='ancestral_nft',description=excluded.description,base_passives=excluded.base_passives,active_skill=excluded.active_skill,image_baby_url=excluded.image_baby_url,image_young_url=excluded.image_young_url,image_adult_url=excluded.image_adult_url,image_ancestral_url=excluded.image_ancestral_url,is_season_exclusive=true,exclusive_badge='NFT',exclusive_passive=excluded.exclusive_passive,is_nft=true,nft_collection='ancestral_genesis',nft_badge='NFT',is_enabled=false;

insert into public.ancestral_nft_pool(pet_id,weight)
select id,20 from public.pets where slug in('ancestral-nft-solkaris','ancestral-nft-umbrael','ancestral-nft-thalassor','ancestral-nft-verdantia','ancestral-nft-ignivar')
on conflict(pet_id) do update set weight=excluded.weight,enabled=true;

create or replace function public.hatch_pet_egg(p_telegram_id bigint,p_egg_id uuid,p_idempotency_key text) returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid;egg pet_eggs%rowtype;inv player_pet_inventory%rowtype;seed bytea;seed_text text;roll numeric;cursor numeric:=0;k text;rate numeric;rar text:='common';picked pets%rowtype;existing player_pets%rowtype;frags int:=0;history_id uuid;luck numeric:=0;
begin
 if length(trim(p_idempotency_key))<8 then raise exception 'INVALID_IDEMPOTENCY_KEY';end if;
 select id into u from game_players where telegram_id=p_telegram_id for update;
 if exists(select 1 from pet_hatch_history where idempotency_key=p_idempotency_key and user_id=u) then return get_pet_dashboard(p_telegram_id);end if;
 select * into egg from pet_eggs where id=p_egg_id and is_enabled;
 if egg.id is null then raise exception 'EGG_NOT_FOUND';end if;
 select * into inv from player_pet_inventory where user_id=u and item_type='egg' and item_id=p_egg_id for update;
 if inv.id is null or inv.quantity<1 then raise exception 'EGG_NOT_OWNED';end if;
 update player_pet_inventory set quantity=quantity-1,updated_at=now() where id=inv.id;
 seed:=gen_random_bytes(32);seed_text:=encode(digest(seed,'sha256'),'hex');luck:=least(10,coalesce((get_pet_bonuses(u)->>'egg_luck_percent')::numeric,0));
 roll:=least(99.999,(('x'||substr(seed_text,1,8))::bit(32)::bigint%1000000)/10000.0+luck);
 foreach k in array array['common','uncommon','rare','epic','legendary'] loop rate:=coalesce((egg.rarity_rates->>k)::numeric,0);cursor:=cursor+rate;if roll<cursor then rar:=k;exit;end if;end loop;
 if egg.slug='ancestral' then
   select p.* into picked from ancestral_nft_pool ap join pets p on p.id=ap.pet_id where ap.enabled and p.is_nft and p.nft_collection='ancestral_genesis' order by hashtextextended(p.id::text||seed_text,0) limit 1;
 else
   select * into picked from pets p where p.is_enabled and not coalesce(p.is_nft,false) and not coalesce(p.is_mythic,false) and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category) order by hashtextextended(p.id::text||seed_text,0) limit 1;
 end if;
 if picked.id is null then raise exception 'NO_ELIGIBLE_PET';end if;
 select * into existing from player_pets where user_id=u and pet_id=picked.id for update;
 if existing.id is not null then select coalesce((value->>rar)::int,10) into frags from pet_settings where key='duplicate_fragments';update player_pets set fragments=fragments+frags,updated_at=now() where id=existing.id;
 else insert into player_pets(user_id,pet_id,rarity) values(u,picked.id,rar);end if;
 insert into pet_hatch_history(user_id,egg_id,result_pet_id,result_rarity,duplicate_fragments,seed_hash,idempotency_key) values(u,egg.id,picked.id,rar,frags,seed_text,p_idempotency_key) returning id into history_id;
 return jsonb_build_object('result',jsonb_build_object('historyId',history_id,'petId',picked.id,'name',picked.name,'rarity',rar,'image',picked.image_baby_url,'duplicateFragments',frags,'isNft',coalesce(picked.is_nft,false),'badge',picked.nft_badge),'dashboard',get_pet_dashboard(p_telegram_id));
end$$;

revoke all on function public.hatch_pet_egg(bigint,uuid,text) from public,anon,authenticated;
grant execute on function public.hatch_pet_egg(bigint,uuid,text) to service_role;
