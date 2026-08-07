alter table public.pets
  add column if not exists is_mythic boolean not null default false;

create table if not exists public.mythic_pet_pool(
  pet_id uuid primary key references public.pets(id) on delete cascade,
  weight integer not null default 20 check(weight > 0),
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.mythic_egg_results(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  inventory_item_id uuid not null references public.player_inventory(id),
  pet_id uuid not null references public.pets(id),
  player_pet_id uuid references public.player_pets(id),
  seed_hash text not null,
  idempotency_key text not null unique,
  duplicate_fragments integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.mythic_pet_pool enable row level security;
alter table public.mythic_egg_results enable row level security;
revoke all on public.mythic_pet_pool,public.mythic_egg_results from anon,authenticated;

insert into public.pets(name,slug,species,category,description,base_passives,active_skill,image_baby_url,image_young_url,image_adult_url,image_ancestral_url,is_season_exclusive,exclusive_pass_tier,exclusive_badge,exclusive_passive,is_mythic,is_enabled) values
('Aetherion','mythic-aetherion','celestial_lion_dragon','mythic','Leão-dragão celestial exclusivo do Ovo Mítico.','{"boss_damage_percent":8,"team_hp_percent":5}','{"name":"Coroa Estelar","pvp_turns":5,"team_max_hp_shield_percent":6}','/assets/game/pets/mythic/aetherion.png','/assets/game/pets/mythic/aetherion.png','/assets/game/pets/mythic/aetherion.png','/assets/game/pets/mythic/aetherion.png',true,'legendary','CRIATURA MÍTICA','{"aura":"Fogo Estelar"}',true,false),
('Nymbrak','mythic-nymbrak','obsidian_rune_bear','mythic','Urso rúnico de obsidiana exclusivo do Ovo Mítico.','{"pvp_defense_percent":8,"boss_damage_reduction_percent":6}','{"name":"Muralha de Obsidiana","pvp_turns":5,"team_max_hp_shield_percent":8}','/assets/game/pets/mythic/nymbrak.png','/assets/game/pets/mythic/nymbrak.png','/assets/game/pets/mythic/nymbrak.png','/assets/game/pets/mythic/nymbrak.png',true,'legendary','CRIATURA MÍTICA','{"aura":"Runas do Abismo"}',true,false),
('Sylvaris','mythic-sylvaris','ancestral_serpent_stag','mythic','Serpe-cervo ancestral exclusiva do Ovo Mítico.','{"farm_fc_percent":8,"mission_reward_percent":6}','{"name":"Renascimento Verde","pvp_turns":5,"team_max_hp_shield_percent":5}','/assets/game/pets/mythic/sylvaris.png','/assets/game/pets/mythic/sylvaris.png','/assets/game/pets/mythic/sylvaris.png','/assets/game/pets/mythic/sylvaris.png',true,'legendary','CRIATURA MÍTICA','{"aura":"Coração da Floresta"}',true,false),
('Zephyrax','mythic-zephyrax','storm_gryphon','mythic','Grifo da tempestade exclusivo do Ovo Mítico.','{"pvp_speed_percent":8,"critical_chance_percent":6}','{"name":"Ruptura Trovejante","pvp_turns":4,"average_team_atk_percent":75}','/assets/game/pets/mythic/zephyrax.png','/assets/game/pets/mythic/zephyrax.png','/assets/game/pets/mythic/zephyrax.png','/assets/game/pets/mythic/zephyrax.png',true,'legendary','CRIATURA MÍTICA','{"aura":"Olho da Tempestade"}',true,false),
('Morvanna','mythic-morvanna','crimson_phoenix_wyrm','mythic','Fênix-serpe carmesim exclusiva do Ovo Mítico.','{"boss_damage_percent":7,"revive_speed_percent":8}','{"name":"Ascensão Carmesim","pvp_turns":5,"average_team_atk_percent":80}','/assets/game/pets/mythic/morvanna.png','/assets/game/pets/mythic/morvanna.png','/assets/game/pets/mythic/morvanna.png','/assets/game/pets/mythic/morvanna.png',true,'legendary','CRIATURA MÍTICA','{"aura":"Cinzas Eternas"}',true,false)
on conflict(slug) do update set name=excluded.name,species=excluded.species,category='mythic',description=excluded.description,base_passives=excluded.base_passives,active_skill=excluded.active_skill,image_baby_url=excluded.image_baby_url,image_young_url=excluded.image_young_url,image_adult_url=excluded.image_adult_url,image_ancestral_url=excluded.image_ancestral_url,is_season_exclusive=true,exclusive_pass_tier='legendary',exclusive_badge='CRIATURA MÍTICA',exclusive_passive=excluded.exclusive_passive,is_mythic=true,is_enabled=false;

insert into public.mythic_pet_pool(pet_id,weight)
select id,20 from public.pets where slug in('mythic-aetherion','mythic-nymbrak','mythic-sylvaris','mythic-zephyrax','mythic-morvanna')
on conflict(pet_id) do update set weight=excluded.weight,enabled=true;

insert into public.hero_catalog(hero_key,name,rarity,image) values
('common-6','Lâmina da Vila','common','/assets/game/heroes/shop/expanded/common-village-blade.png'),('common-7','Guardiã da Lança','common','/assets/game/heroes/shop/expanded/common-spear-warden.png'),('common-8','Brom Martelo-Firme','common','/assets/game/heroes/shop/expanded/common-dwarf-smith.png'),('common-9','Arqueira do Bosque','common','/assets/game/heroes/shop/expanded/common-wood-elf-archer.png'),('common-10','Escudo de Ferro','common','/assets/game/heroes/shop/expanded/common-shield-bearer.png'),
('uncommon-6','Batedora das Lâminas','uncommon','/assets/game/heroes/shop/expanded/uncommon-twinblade-scout.png'),('uncommon-7','Elandor Folha-Verde','uncommon','/assets/game/heroes/shop/expanded/uncommon-high-elf-ranger.png'),('uncommon-8','Dagna Engrenarruna','uncommon','/assets/game/heroes/shop/expanded/uncommon-dwarf-runesmith.png'),('uncommon-9','Caçador da Besta','uncommon','/assets/game/heroes/shop/expanded/uncommon-crossbow-hunter.png'),('uncommon-10','Sentinela Lunar','uncommon','/assets/game/heroes/shop/expanded/uncommon-moon-elf-warder.png'),
('rare-6','Thalion do Gelo','rare','/assets/game/heroes/shop/expanded/rare-frost-elf.png'),('rare-7','Cavaleira da Coroa','rare','/assets/game/heroes/shop/expanded/rare-royal-knight.png'),('rare-8','Dorrik Trovejante','rare','/assets/game/heroes/shop/expanded/rare-dwarf-thunder.png'),('rare-9','Arqueira Solar','rare','/assets/game/heroes/shop/expanded/rare-sun-elf.png'),('rare-10','Lanceiro Arcano','rare','/assets/game/heroes/shop/expanded/rare-arcane-lancer.png'),
('epic-6','Nyxara do Vazio','epic','/assets/game/heroes/shop/expanded/epic-void-elf.png'),('epic-7','Templário da Chama','epic','/assets/game/heroes/shop/expanded/epic-flame-templar.png'),('epic-8','Brynja Cristalina','epic','/assets/game/heroes/shop/expanded/epic-dwarf-crystal.png'),('epic-9','Duelista das Estrelas','epic','/assets/game/heroes/shop/expanded/epic-star-elf.png'),('epic-10','Lanceira Dracônica','epic','/assets/game/heroes/shop/expanded/epic-dragon-lancer.png'),
('legendary-6','Aurelius, Rei Celestial','legendary','/assets/game/heroes/shop/expanded/legendary-celestial-king.png'),('legendary-7','Seraphina, Rainha Fênix','legendary','/assets/game/heroes/shop/expanded/legendary-phoenix-queen.png'),('legendary-8','Thorgar, Alto Rei Anão','legendary','/assets/game/heroes/shop/expanded/legendary-dwarf-high-king.png'),('legendary-9','Astrid da Tempestade','legendary','/assets/game/heroes/shop/expanded/legendary-storm-valkyrie.png'),('legendary-10','Vaelor, Lâmina Sombria','legendary','/assets/game/heroes/shop/expanded/legendary-shadow-blademaster.png')
on conflict(hero_key) do update set name=excluded.name,rarity=excluded.rarity,image=excluded.image,enabled=true;

update public.season_exclusive_rewards
set display_name='Ovo Mítico',passive='{"containsPool":["Aetherion","Nymbrak","Sylvaris","Zephyrax","Morvanna"],"resultRarity":"legendary"}'::jsonb,target_pet_id=null,updated_at=now()
where reward_kind='mythic_egg';

drop function if exists public.open_season_mythic_egg(bigint,uuid);
create or replace function public.open_season_mythic_egg(p_telegram_id bigint,p_item_id uuid,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid;i player_inventory%rowtype;e season_exclusive_rewards%rowtype;seed_text text;p pets%rowtype;existing player_pets%rowtype;pp uuid;frags int:=0;prior mythic_egg_results%rowtype;
begin
 if length(trim(coalesce(p_idempotency_key,'')))<8 then raise exception 'INVALID_IDEMPOTENCY_KEY';end if;
 select id into u from game_players where telegram_id=p_telegram_id for update;
 if u is null then raise exception 'PLAYER_NOT_FOUND';end if;
 select * into prior from mythic_egg_results where idempotency_key=p_idempotency_key and user_id=u;
 if prior.id is not null then select * into p from pets where id=prior.pet_id;return jsonb_build_object('playerPetId',prior.player_pet_id,'petId',p.id,'name',p.name,'rarity','legendary','eggTier','mythic','level',1,'xp',0,'evolutionStage','baby','badge','CRIATURA MÍTICA','image',p.image_baby_url,'duplicateFragments',prior.duplicate_fragments);end if;
 select * into i from player_inventory where id=p_item_id and user_id=u and is_exclusive and item_type='pet_egg' and quantity>0 for update;
 if i.id is null then raise exception 'MYTHIC_EGG_NOT_OWNED';end if;
 select * into e from season_exclusive_rewards where season_id=i.season_id and reward_code=i.exclusive_reward_code and reward_kind='mythic_egg' and enabled;
 if e.id is null then raise exception 'MYTHIC_EGG_INVALID';end if;
 seed_text:=encode(digest(gen_random_bytes(32),'sha256'),'hex');
 select p0.* into p from mythic_pet_pool mp join pets p0 on p0.id=mp.pet_id where mp.enabled and p0.is_mythic order by hashtextextended(p0.id::text||seed_text,0) limit 1;
 if p.id is null then raise exception 'MYTHIC_POOL_EMPTY';end if;
 update player_inventory set quantity=quantity-1 where id=i.id;
 select * into existing from player_pets where user_id=u and pet_id=p.id for update;
 if existing.id is not null then frags:=300;update player_pets set fragments=fragments+frags,updated_at=now() where id=existing.id returning id into pp;
 else insert into player_pets(user_id,pet_id,rarity,level,xp,evolution_stage,is_season_exclusive,exclusive_season_id,exclusive_badge,tradable) values(u,p.id,'legendary',1,0,'baby',true,e.season_id,'CRIATURA MÍTICA',false) returning id into pp;end if;
 insert into mythic_egg_results(user_id,inventory_item_id,pet_id,player_pet_id,seed_hash,idempotency_key,duplicate_fragments) values(u,i.id,p.id,pp,seed_text,p_idempotency_key,frags);
 return jsonb_build_object('playerPetId',pp,'petId',p.id,'name',p.name,'rarity','legendary','eggTier','mythic','level',1,'xp',0,'evolutionStage','baby','badge','CRIATURA MÍTICA','image',p.image_baby_url,'duplicateFragments',frags);
end$$;

revoke all on function public.open_season_mythic_egg(bigint,uuid,text) from public,anon,authenticated;
grant execute on function public.open_season_mythic_egg(bigint,uuid,text) to service_role;
