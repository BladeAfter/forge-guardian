alter table public.nft_heroes drop constraint if exists nft_heroes_status_chk;
alter table public.nft_heroes add constraint nft_heroes_status_chk
  check (status = any (array['RESERVE','AVAILABLE','RESERVED','OWNED','REVOKED','BURNED','DISABLED']));

alter table public.nft_pets drop constraint if exists nft_pets_status_check;
alter table public.nft_pets add constraint nft_pets_status_check
  check (status = any (array['RESERVE','AVAILABLE','RESERVED','OWNED','REVOKED','BURNED','DISABLED']));

alter table public.nft_equipment drop constraint if exists nft_equipment_status_check;
alter table public.nft_equipment add constraint nft_equipment_status_check
  check (status = any (array['RESERVE','AVAILABLE','RESERVED','OWNED','BURNED','DISABLED']));

insert into public.hero_catalog (hero_key, name, rarity, image, enabled, description, hero_class,
  base_atk, base_hp, base_def, base_speed, crit_rate, skill_power, growth_multiplier,
  start_level, max_level, is_nft_exclusive, in_shop, shop_eligible, recruit_eligible, recruit_enabled,
  reward_pool_eligible, random_drop_eligible, fusion_pool_enabled, nft_class_label, nft_passive, skills, buffs, sort_order)
values
  ('nft-aurenvyx', 'Aurenvyx, Soberano Solar', 'nft_exclusive', '/assets/game/heroes-nft/aurenvyx.jpg', true,
   'Paladino NFT exclusivo: julgamento solar, escudo radiante e cura em area.', 'tank',
   1180, 11200, 1180, 96, 24, 1720, 1.15, 1, 60, true, false, false, false, false, false, false, false,
   'Paladino', '{"key":"solar_reckoning","bonus_max":45}'::jsonb,
   '[{"name":"Julgamento Solar","type":"attack","desc":"Golpe flamejante em um alvo."},
     {"name":"Aegis Radiante","type":"special","desc":"Escudo solar para toda a equipe."},
     {"name":"Solar Reckoning","type":"passive","desc":"Converte dano recebido em ate 45% de dano solar."}]'::jsonb,
   '[]'::jsonb, 16),
  ('nft-kaerith', 'Kaerith, Juramento Congelado', 'nft_exclusive', '/assets/game/heroes-nft/kaerith.jpg', true,
   'Cavaleira NFT exclusiva: controle glacial, lentidao e execucao perfurante.', 'warrior',
   1265, 10100, 1010, 104, 29, 1690, 1.15, 1, 60, true, false, false, false, false, false, false, false,
   'Cavaleira', '{"key":"frozen_oath","bonus_max":40}'::jsonb,
   '[{"name":"Lamina Glacial","type":"attack","desc":"Corte congelante em um alvo."},
     {"name":"Juramento Congelado","type":"special","desc":"Congela a linha inimiga reduzindo velocidade."},
     {"name":"Frozen Oath","type":"passive","desc":"Aumenta o dano em ate 40% contra alvos lentos."}]'::jsonb,
   '[]'::jsonb, 17)
on conflict (hero_key) do nothing;

insert into public.pets (slug, name, species, category, rarity, description, base_passives,
  availability_type, is_enabled, is_nft_exclusive, egg_eligible, show_in_catalog,
  image_base_url, image_baby_url, image_young_url, image_adult_url, image_ancestral_url,
  image_evo1_url, image_evo2_url, image_evo3_url, image_evo4_url, image_final_url)
values
  ('nft-zoryphel', 'Zoryphel', 'storm_griffin', 'nft_exclusive', 'nft_exclusive',
   'Grifo celeste da tempestade. Companheiro NFT exclusivo.',
   '{"account_xp_percent":17,"hero_xp_percent":19,"reward_percent":25}'::jsonb,
   'NFT_EXCLUSIVE', true, true, false, false,
   '/assets/game/pets-nft/zoryphel.png','/assets/game/pets-nft/zoryphel.png','/assets/game/pets-nft/zoryphel.png',
   '/assets/game/pets-nft/zoryphel.png','/assets/game/pets-nft/zoryphel.png','/assets/game/pets-nft/zoryphel.png',
   '/assets/game/pets-nft/zoryphel.png','/assets/game/pets-nft/zoryphel.png','/assets/game/pets-nft/zoryphel.png',
   '/assets/game/pets-nft/zoryphel.png'),
  ('nft-mordralyx', 'Mordralyx', 'abyssal_wyrm', 'nft_exclusive', 'nft_exclusive',
   'Wyrm abissal de obsidiana. Companheiro NFT exclusivo.',
   '{"account_xp_percent":15,"hero_xp_percent":20,"reward_percent":23}'::jsonb,
   'NFT_EXCLUSIVE', true, true, false, false,
   '/assets/game/pets-nft/mordralyx.png','/assets/game/pets-nft/mordralyx.png','/assets/game/pets-nft/mordralyx.png',
   '/assets/game/pets-nft/mordralyx.png','/assets/game/pets-nft/mordralyx.png','/assets/game/pets-nft/mordralyx.png',
   '/assets/game/pets-nft/mordralyx.png','/assets/game/pets-nft/mordralyx.png','/assets/game/pets-nft/mordralyx.png',
   '/assets/game/pets-nft/mordralyx.png')
on conflict (slug) do nothing;

insert into public.equipment_templates (code, name, slot, kind, hero_class, rarity, tier, image_url,
  bonus_attack, bonus_defense, bonus_hp, power, description, is_active, is_nft)
values
  ('nfteq_weapon_027', 'Solaris Fang', 'weapon', 'sword', 'warrior', 'nft_exclusive', 5,
   '/assets/game/equipment/nft/solaris-fang.png', 352, 58, 240, 995,
   'Lamina solar 1/1 com nucleo de plasma dourado.', true, true),
  ('nfteq_weapon_028', 'Voidwhisper Scythe', 'weapon', 'axe', 'assassin', 'nft_exclusive', 5,
   '/assets/game/equipment/nft/voidwhisper-scythe.png', 366, 34, 190, 1010,
   'Foice do vazio 1/1 forjada em sussurros abissais.', true, true)
on conflict (code) do nothing;

insert into public.nft_heroes (hero_template_id, nft_serial, unique_instance_id, status, minted,
  price_ton, tier_ton, mining_daily_ton, for_sale, generation, level, stars, metadata)
select v.hero_key,
       (select coalesce(max(nft_serial),0) from public.nft_heroes) + v.ord,
       v.instance, 'RESERVE', false, v.price, v.price, v.yield_ton, false, 1, 1, 5,
       jsonb_build_object('tier_ton', v.price, 'mint_daily_yield_ton', v.yield_ton,
                          'reserve_batch', 'reserve_2026_08', 'supply', '1/1')
from (values
  ('nft-aurenvyx', 1, 'NFT-HERO-AURENVYX-0016', 50::numeric, 1.25::numeric),
  ('nft-kaerith',  2, 'NFT-HERO-KAERITH-0017',  30::numeric, 0.75::numeric)
) as v(hero_key, ord, instance, price, yield_ton)
where not exists (select 1 from public.nft_heroes n where n.hero_template_id = v.hero_key);

insert into public.nft_pets (pet_template_id, nft_serial, unique_instance_id, status, minted,
  price_ton, tier_ton, daily_yield_ton, for_sale, generation, element, appearance_family, metadata)
select p.id,
       (select coalesce(max(nft_serial),0) from public.nft_pets) + v.ord,
       v.instance, 'RESERVE', false, v.price, v.price, v.yield_ton, false, 1, v.element, v.element,
       jsonb_build_object('tier_ton', v.price, 'mint_daily_yield_ton', v.yield_ton,
                          'reserve_batch', 'reserve_2026_08', 'supply', '1/1')
from (values
  ('nft-zoryphel',  1, 'NFT-PET-ZORYPHEL-0019',  30::numeric, 0.6::numeric,  'storm'),
  ('nft-mordralyx', 2, 'NFT-PET-MORDRALYX-0020', 20::numeric, 0.35::numeric, 'dark')
) as v(slug, ord, instance, price, yield_ton, element)
join public.pets p on p.slug = v.slug
where not exists (select 1 from public.nft_pets n where n.pet_template_id = p.id);

insert into public.nft_equipment (template_id, nft_serial, unique_instance_id, status, for_sale,
  price_ton, metadata)
select t.id,
       (select coalesce(max(nft_serial),0) from public.nft_equipment) + v.ord,
       v.instance, 'RESERVE', false, v.price,
       jsonb_build_object('reserve_batch', 'reserve_2026_08', 'supply', '1/1')
from (values
  ('nfteq_weapon_027', 1, 'NFT-WEAPON-SOLARISFANG-0028', 2::numeric),
  ('nfteq_weapon_028', 2, 'NFT-WEAPON-VOIDWHISPERSCYTHE-0029', 2::numeric)
) as v(code, ord, instance, price)
join public.equipment_templates t on t.code = v.code
where not exists (select 1 from public.nft_equipment n where n.template_id = t.id);

create or replace function public.nft_reserve_stock_json()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'hero', jsonb_build_object(
      'available', (select count(*) from public.nft_heroes where status='AVAILABLE' and for_sale and owner_user_id is null and rotation_retired_at is null),
      'reserve',   (select count(*) from public.nft_heroes where status='RESERVE'),
      'sold',      (select count(*) from public.nft_heroes where owner_user_id is not null)),
    'pet', jsonb_build_object(
      'available', (select count(*) from public.nft_pets where status='AVAILABLE' and for_sale and owner_user_id is null and rotation_retired_at is null),
      'reserve',   (select count(*) from public.nft_pets where status='RESERVE'),
      'sold',      (select count(*) from public.nft_pets where owner_user_id is not null)),
    'weapon', jsonb_build_object(
      'available', (select count(*) from public.nft_equipment e join public.equipment_templates t on t.id=e.template_id
                     where e.status='AVAILABLE' and e.for_sale and e.owner_user_id is null and t.slot='weapon'),
      'reserve',   (select count(*) from public.nft_equipment e join public.equipment_templates t on t.id=e.template_id
                     where e.status='RESERVE' and t.slot='weapon'),
      'sold',      (select count(*) from public.nft_equipment e join public.equipment_templates t on t.id=e.template_id
                     where e.owner_user_id is not null and t.slot='weapon'))
  );
$$;

create or replace function public.nft_reserve_publish(p_kind text, p_admin_id bigint default null, p_limit int default 2)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  k text := lower(coalesce(p_kind,''));
  lim int := greatest(1, coalesce(p_limit, 2));
  before_avail int; after_avail int;
  published jsonb := '[]'::jsonb; ids uuid[] := '{}';
  r record;
begin
  if k not in ('hero','pet','weapon') then raise exception 'NFT_KIND_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nft_reserve_publish:'||k, 0));

  before_avail := ((public.nft_reserve_stock_json() -> k) ->> 'available')::int;

  if k = 'hero' then
    for r in
      select n.id, n.nft_serial, n.unique_instance_id, n.price_ton, n.mining_daily_ton as yield_ton, c.name
        from public.nft_heroes n join public.hero_catalog c on c.hero_key = n.hero_template_id
       where n.status = 'RESERVE' and n.owner_user_id is null
       order by n.nft_serial
       for update of n skip locked
       limit lim
    loop
      update public.nft_heroes set status='AVAILABLE', for_sale=true, updated_at=now() where id = r.id;
      insert into public.nft_hero_history (nft_hero_id, action, admin_telegram_id, reason)
      values (r.id, 'CREATED', p_admin_id, 'reserve_refill');
      ids := ids || r.id;
      published := published || jsonb_build_object('id', r.id, 'kind', k, 'name', r.name,
        'serial', r.nft_serial, 'instance', r.unique_instance_id,
        'priceTon', round(coalesce(r.price_ton,0),9), 'dailyYieldTon', round(coalesce(r.yield_ton,0),9));
    end loop;
  elsif k = 'pet' then
    for r in
      select n.id, n.nft_serial, n.unique_instance_id, n.price_ton, n.daily_yield_ton as yield_ton, p.name
        from public.nft_pets n join public.pets p on p.id = n.pet_template_id
       where n.status = 'RESERVE' and n.owner_user_id is null
       order by n.nft_serial
       for update of n skip locked
       limit lim
    loop
      update public.nft_pets set status='AVAILABLE', for_sale=true, updated_at=now() where id = r.id;
      insert into public.nft_pet_history (nft_pet_id, action, admin_telegram_id, reason, metadata)
      values (r.id, 'CREATED', p_admin_id, 'reserve_refill',
              jsonb_build_object('serial', r.nft_serial, 'instance', r.unique_instance_id));
      ids := ids || r.id;
      published := published || jsonb_build_object('id', r.id, 'kind', k, 'name', r.name,
        'serial', r.nft_serial, 'instance', r.unique_instance_id,
        'priceTon', round(coalesce(r.price_ton,0),9), 'dailyYieldTon', round(coalesce(r.yield_ton,0),9));
    end loop;
  else
    for r in
      select n.id, n.nft_serial, n.unique_instance_id, n.price_ton, t.name
        from public.nft_equipment n join public.equipment_templates t on t.id = n.template_id
       where n.status = 'RESERVE' and n.owner_user_id is null and t.slot = 'weapon'
       order by n.nft_serial
       for update of n skip locked
       limit lim
    loop
      update public.nft_equipment set status='AVAILABLE', for_sale=true, updated_at=now() where id = r.id;
      ids := ids || r.id;
      published := published || jsonb_build_object('id', r.id, 'kind', k, 'name', r.name,
        'serial', r.nft_serial, 'instance', r.unique_instance_id,
        'priceTon', round(coalesce(r.price_ton,0),9), 'dailyYieldTon', 0);
    end loop;
  end if;

  after_avail := ((public.nft_reserve_stock_json() -> k) ->> 'available')::int;

  if p_admin_id is not null then
    perform public.admin_log(p_admin_id, 'nft.refill.' || k, 'nft_reserve', null, null,
      jsonb_build_object('category', k, 'count', jsonb_array_length(published),
                         'publishedInstanceIds', to_jsonb(ids),
                         'beforeAvailable', before_avail, 'afterAvailable', after_avail,
                         'published', published),
      'NFT reserve refill', null);
  end if;

  return jsonb_build_object('kind', k, 'published', published,
    'count', jsonb_array_length(published),
    'beforeAvailable', before_avail, 'afterAvailable', after_avail,
    'reserveLeft', ((public.nft_reserve_stock_json() -> k) ->> 'reserve')::int,
    'stock', public.nft_reserve_stock_json());
end $$;

create or replace function public.admin_nft_reserve_overview(p_admin_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public.admin_assert(p_admin_id);
  return public.nft_reserve_stock_json();
end $$;

create or replace function public.admin_nft_reserve_refill(p_admin_id bigint, p_kind text, p_limit int default 2)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare res jsonb; k text := lower(coalesce(p_kind,''));
begin
  perform public.admin_assert(p_admin_id);
  if k = 'all' then
    res := jsonb_build_object(
      'hero',   public.nft_reserve_publish('hero',   p_admin_id, p_limit),
      'pet',    public.nft_reserve_publish('pet',    p_admin_id, p_limit),
      'weapon', public.nft_reserve_publish('weapon', p_admin_id, p_limit));
    perform public.admin_log(p_admin_id, 'nft.refill.all', 'nft_reserve', null, null, res, 'NFT reserve refill all', null);
    return jsonb_build_object('kind','all','results',res,'stock', public.nft_reserve_stock_json());
  end if;
  return public.nft_reserve_publish(k, p_admin_id, p_limit);
end $$;

revoke all on function public.nft_reserve_publish(text, bigint, int) from anon, authenticated;
revoke all on function public.admin_nft_reserve_overview(bigint) from anon, authenticated;
revoke all on function public.admin_nft_reserve_refill(bigint, text, int) from anon, authenticated;
grant execute on function public.nft_reserve_stock_json() to service_role;
grant execute on function public.nft_reserve_publish(text, bigint, int) to service_role;
grant execute on function public.admin_nft_reserve_overview(bigint) to service_role;
grant execute on function public.admin_nft_reserve_refill(bigint, text, int) to service_role;