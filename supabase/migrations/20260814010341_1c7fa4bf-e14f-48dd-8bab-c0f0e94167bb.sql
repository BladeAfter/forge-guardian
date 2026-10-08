
alter table public.sub_nft_templates add column if not exists pet_template_id uuid references public.pets(id);

alter table public.pets drop constraint if exists pets_availability_type_check;
alter table public.pets add constraint pets_availability_type_check
  check (availability_type = any (array['NORMAL','LIMITED','EVENT','MYTHIC_EXCLUSIVE','ADMIN_ONLY','NFT_EXCLUSIVE','SUB_NFT']));

-- Elements of the existing UNIQUE NFT parents (drives the offspring appearance pool)
update public.nft_pets n set element = m.el, appearance_family = m.el
from (values
  ('nft-sylvaris','nature'),('nft-verdrathil','nature'),
  ('nft-nocthar','shadow'),('nft-umbraveth','shadow'),
  ('nft-ignarion','fire'),('nft-solarius','fire'),
  ('nft-seraphiel','holy'),('nft-eternyx','holy'),
  ('nft-astryx','cosmic'),('nft-astranyx','cosmic'),('nft-zephyron','cosmic'),
  ('nft-prismara','arcane'),('nft-kryzalith','arcane'),('nft-cryon','arcane'),('nft-voltrix','arcane')
) as m(slug, el)
join public.pets p on p.slug = m.slug
where n.pet_template_id = p.id and n.element is null;
update public.nft_pets set element = coalesce(element, 'neutral') where element is null;

-- Pet templates backing each SUB-NFT appearance (hidden from the catalog)
insert into public.pets (name, slug, species, category, rarity, description, base_passives,
    image_baby_url, image_young_url, image_adult_url, image_ancestral_url,
    is_enabled, show_in_catalog, availability_type, egg_eligible, is_nft_exclusive, primary_attribute_key, primary_attribute_value)
values
 ('Verdling','sub-nft-nature','Sub-NFT','spirit','epic','Descendente de linhagem natural.','{"boss_damage":6}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-nature.png','/assets/game/pets-sub-nft/sub-nature.png','/assets/game/pets-sub-nft/sub-nature.png',
   true,false,'SUB_NFT',false,false,'boss_damage',6),
 ('Nyxling','sub-nft-shadow','Sub-NFT','spirit','epic','Descendente de linhagem sombria.','{"pvp_damage":6}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-shadow.png','/assets/game/pets-sub-nft/sub-shadow.png','/assets/game/pets-sub-nft/sub-shadow.png',
   true,false,'SUB_NFT',false,false,'pvp_damage',6),
 ('Seraling','sub-nft-holy','Sub-NFT','guardian','epic','Descendente de linhagem sagrada.','{"hp_bonus":6}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-holy.png','/assets/game/pets-sub-nft/sub-holy.png','/assets/game/pets-sub-nft/sub-holy.png',
   true,false,'SUB_NFT',false,false,'hp_bonus',6),
 ('Runeling','sub-nft-arcane','Sub-NFT','spirit','epic','Descendente de linhagem arcana.','{"reward_bonus":6}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-arcane.png','/assets/game/pets-sub-nft/sub-arcane.png','/assets/game/pets-sub-nft/sub-arcane.png',
   true,false,'SUB_NFT',false,false,'reward_bonus',6),
 ('Emberling','sub-nft-fire','Sub-NFT','beast','epic','Descendente de linhagem flamejante.','{"attack_bonus":6}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-fire.png','/assets/game/pets-sub-nft/sub-fire.png','/assets/game/pets-sub-nft/sub-fire.png',
   true,false,'SUB_NFT',false,false,'attack_bonus',6),
 ('Astrling','sub-nft-cosmic','Sub-NFT','beast','epic','Descendente de linhagem cósmica.','{"reward_bonus":8}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-cosmic.png','/assets/game/pets-sub-nft/sub-cosmic.png','/assets/game/pets-sub-nft/sub-cosmic.png',
   true,false,'SUB_NFT',false,false,'reward_bonus',8)
on conflict (slug) do nothing;

insert into public.sub_nft_templates (code, name, element, secondary_element, appearance_family, image_url, description, pet_template_id)
select v.code, v.name, v.element, v.sec, v.element, v.img, v.descr, p.id
from (values
 ('sub_nature','Verdling','nature','holy','/assets/game/pets-sub-nft/sub-nature.png','Descendente de linhagem natural.','sub-nft-nature'),
 ('sub_shadow','Nyxling','shadow','arcane','/assets/game/pets-sub-nft/sub-shadow.png','Descendente de linhagem sombria.','sub-nft-shadow'),
 ('sub_holy','Seraling','holy','cosmic','/assets/game/pets-sub-nft/sub-holy.png','Descendente de linhagem sagrada.','sub-nft-holy'),
 ('sub_arcane','Runeling','arcane','nature','/assets/game/pets-sub-nft/sub-arcane.png','Descendente de linhagem arcana.','sub-nft-arcane'),
 ('sub_fire','Emberling','fire','shadow','/assets/game/pets-sub-nft/sub-fire.png','Descendente de linhagem flamejante.','sub-nft-fire'),
 ('sub_cosmic','Astrling','cosmic','arcane','/assets/game/pets-sub-nft/sub-cosmic.png','Descendente de linhagem cósmica.','sub-nft-cosmic')
) as v(code, name, element, sec, img, descr, slug)
join public.pets p on p.slug = v.slug
on conflict (code) do update set pet_template_id = excluded.pet_template_id, image_url = excluded.image_url;

-- Mint now also creates the collection pet so the Sub-NFT can be fed, evolved and sent on expeditions
create or replace function public.sub_nft_mint(p_owner uuid, p_req public.nft_breeding_requests, p_cost numeric, p_side text)
returns uuid language plpgsql security definer set search_path = public as $$
declare s public.nft_breeding_settings; tpl public.sub_nft_templates; el_a text; el_b text;
        trait text; v_id uuid; v_pet uuid; v_serial bigint;
begin
  select * into s from public.nft_breeding_settings where id;
  select coalesce(element,'neutral') into el_a from public.nft_pets where id = p_req.nft_a_id;
  select coalesce(element,'neutral') into el_b from public.nft_pets where id = p_req.nft_b_id;

  select * into tpl from public.sub_nft_templates
   where enabled and (element in (el_a, el_b) or coalesce(secondary_element,'') in (el_a, el_b))
   order by random() limit 1;
  if tpl.id is null then
    select * into tpl from public.sub_nft_templates where enabled order by random() limit 1;
  end if;
  if tpl.id is null then raise exception 'NO_SUB_NFT_TEMPLATE'; end if;

  select code into trait from public.sub_nft_traits where enabled order by random() * (1.0 / greatest(weight,1)) limit 1;
  v_serial := nextval('public.sub_nft_serial_seq');

  insert into public.sub_nfts(serial, unique_instance_id, owner_user_id, template_id, breeding_id,
      parent_a_nft_id, parent_b_nft_id, generation, trait_code, birth_time, maturity_stage, matures_at,
      mining_rate_ton_day, mining_cap_ton)
  values (v_serial, 'SUB-NFT #' || lpad(v_serial::text, 6, '0'), p_owner, tpl.id, p_req.id,
      p_req.nft_a_id, p_req.nft_b_id, 1, trait, now(), 'EGG', now() + make_interval(hours => s.adult_hours),
      round(p_cost * s.sub_rate_per_ton, 9), round(p_cost, 9))
  returning id into v_id;

  if tpl.pet_template_id is not null then
    insert into public.player_pets (user_id, pet_id, rarity, level, xp, evolution_stage, fragments,
        is_active, tradable, market_locked, sub_nft_id)
    values (p_owner, tpl.pet_template_id, 'epic', 1, 0, 'baby', 0, false, false, true, v_id)
    returning id into v_pet;
    update public.sub_nfts set player_pet_id = v_pet where id = v_id;
  end if;

  return v_id;
end $$;

revoke all on function public.sub_nft_mint(uuid, public.nft_breeding_requests, numeric, text) from public, anon, authenticated;
grant execute on function public.sub_nft_mint(uuid, public.nft_breeding_requests, numeric, text) to service_role;
