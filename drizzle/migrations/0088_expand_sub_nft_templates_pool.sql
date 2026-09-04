-- 1) New Sub-NFT pet templates (hidden from catalog)
insert into public.pets (name, slug, species, category, rarity, description, base_passives,
    image_baby_url, image_young_url, image_adult_url, image_ancestral_url,
    is_enabled, show_in_catalog, availability_type, egg_eligible, is_nft_exclusive,
    primary_attribute_key, primary_attribute_value)
values
 ('Terrling','sub-nft-earth','Sub-NFT','guardian','epic','Descendente de linhagem telúrica.','{"hp_bonus":6}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-earth.png','/assets/game/pets-sub-nft/sub-earth.png','/assets/game/pets-sub-nft/sub-earth.png',
   true,false,'SUB_NFT',false,false,'hp_bonus',6),
 ('Frostling','sub-nft-ice','Sub-NFT','spirit','epic','Descendente de linhagem glacial.','{"boss_damage":6}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-ice.png','/assets/game/pets-sub-nft/sub-ice.png','/assets/game/pets-sub-nft/sub-ice.png',
   true,false,'SUB_NFT',false,false,'boss_damage',6),
 ('Voltling','sub-nft-storm','Sub-NFT','beast','epic','Descendente de linhagem tempestuosa.','{"pvp_damage":6}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-storm.png','/assets/game/pets-sub-nft/sub-storm.png','/assets/game/pets-sub-nft/sub-storm.png',
   true,false,'SUB_NFT',false,false,'pvp_damage',6),
 ('Aqualing','sub-nft-water','Sub-NFT','spirit','epic','Descendente de linhagem abissal.','{"reward_bonus":6}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-water.png','/assets/game/pets-sub-nft/sub-water.png','/assets/game/pets-sub-nft/sub-water.png',
   true,false,'SUB_NFT',false,false,'reward_bonus',6),
 ('Ferrling','sub-nft-metal','Sub-NFT','guardian','epic','Descendente de linhagem forjada.','{"attack_bonus":6}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-metal.png','/assets/game/pets-sub-nft/sub-metal.png','/assets/game/pets-sub-nft/sub-metal.png',
   true,false,'SUB_NFT',false,false,'attack_bonus',6),
 ('Umbrling','sub-nft-void','Sub-NFT','spirit','epic','Descendente de linhagem do vazio.','{"attack_bonus":6}'::jsonb,
   '/assets/game/pets-sub-nft/sub-egg.png','/assets/game/pets-sub-nft/sub-void.png','/assets/game/pets-sub-nft/sub-void.png','/assets/game/pets-sub-nft/sub-void.png',
   true,false,'SUB_NFT',false,false,'attack_bonus',6)
on conflict (slug) do nothing;

insert into public.sub_nft_templates (code, name, element, secondary_element, appearance_family, image_url, description, pet_template_id)
select v.code, v.name, v.element, v.sec, v.element, v.img, v.descr, p.id
from (values
 ('sub_earth','Terrling','earth','nature','/assets/game/pets-sub-nft/sub-earth.png','Descendente de linhagem telúrica.','sub-nft-earth'),
 ('sub_ice','Frostling','ice','arcane','/assets/game/pets-sub-nft/sub-ice.png','Descendente de linhagem glacial.','sub-nft-ice'),
 ('sub_storm','Voltling','storm','cosmic','/assets/game/pets-sub-nft/sub-storm.png','Descendente de linhagem tempestuosa.','sub-nft-storm'),
 ('sub_water','Aqualing','water','nature','/assets/game/pets-sub-nft/sub-water.png','Descendente de linhagem abissal.','sub-nft-water'),
 ('sub_metal','Ferrling','metal','fire','/assets/game/pets-sub-nft/sub-metal.png','Descendente de linhagem forjada.','sub-nft-metal'),
 ('sub_void','Umbrling','void','shadow','/assets/game/pets-sub-nft/sub-void.png','Descendente de linhagem do vazio.','sub-nft-void')
) as v(code, name, element, sec, img, descr, slug)
join public.pets p on p.slug = v.slug
on conflict (code) do update set pet_template_id = excluded.pet_template_id,
  image_url = excluded.image_url, enabled = true;

-- 2) Mint never fails on duplicates anymore: always prefer an unowned template,
--    and when the whole pool is owned, keep the Sub-NFT and skip the duplicate pet row.
create or replace function public.sub_nft_mint(p_owner uuid, p_req public.nft_breeding_requests, p_cost numeric, p_side text)
returns uuid language plpgsql security definer set search_path = public as $$
declare s public.nft_breeding_settings; tpl public.sub_nft_templates; el_a text; el_b text;
        trait text; v_id uuid; v_pet uuid; v_serial bigint;
begin
  select * into s from public.nft_breeding_settings where id;
  select coalesce(element,'neutral') into el_a from public.nft_pets where id = p_req.nft_a_id;
  select coalesce(element,'neutral') into el_b from public.nft_pets where id = p_req.nft_b_id;

  select * into tpl from public.sub_nft_templates t
   where t.enabled and (t.element in (el_a, el_b) or coalesce(t.secondary_element,'') in (el_a, el_b))
     and not exists (select 1 from public.player_pets pp
                      where pp.user_id = p_owner and pp.pet_id = t.pet_template_id)
   order by random() limit 1;
  if tpl.id is null then
    select * into tpl from public.sub_nft_templates t
     where t.enabled and not exists (select 1 from public.player_pets pp
             where pp.user_id = p_owner and pp.pet_id = t.pet_template_id)
     order by random() limit 1;
  end if;
  if tpl.id is null then
    select * into tpl from public.sub_nft_templates t where t.enabled order by random() limit 1;
  end if;
  if tpl.id is null then raise exception 'NO_SUB_NFT_TEMPLATE'; end if;

  select code into trait from public.sub_nft_traits where enabled order by random() * (1.0 / greatest(weight,1)) limit 1;
  v_serial := nextval('public.sub_nft_serial_seq');

  insert into public.sub_nfts(serial, unique_instance_id, owner_user_id, template_id, breeding_id,
      parent_a_nft_id, parent_b_nft_id, generation, trait_code, birth_time, maturity_stage, matures_at,
      mining_rate_ton_day, mining_cap_ton)
  values (v_serial, 'SUB-NFT #' || lpad(v_serial::text, 6, '0'), p_owner, tpl.id, p_req.id,
      p_req.nft_a_id, p_req.nft_b_id, 1, trait, now(), 'EGG', now() + make_interval(hours => s.adult_hours),
      round(p_cost / 40.0, 9), round(p_cost, 9))
  returning id into v_id;

  if tpl.pet_template_id is not null then
    insert into public.player_pets (user_id, pet_id, rarity, level, xp, evolution_stage, fragments,
        is_active, tradable, market_locked, sub_nft_id, passives_override)
    values (p_owner, tpl.pet_template_id, 'nft_exclusive', 1, 0, 'baby', 0, false, false, false, v_id,
        public.sub_nft_passives(v_id))
    on conflict (user_id, pet_id) do nothing
    returning id into v_pet;
    if v_pet is not null then
      update public.sub_nfts set player_pet_id = v_pet where id = v_id;
    end if;
  end if;

  return v_id;
end $$;