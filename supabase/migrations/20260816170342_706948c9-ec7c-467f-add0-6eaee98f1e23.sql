insert into public.equipment_templates (code, name, slot, kind, hero_class, rarity, tier, image_url,
  bonus_attack, bonus_defense, bonus_hp, power, description, is_active, is_nft)
values
  ('nfteq_weapon_029', 'Solaris Fang', 'weapon', 'sword', 'warrior', 'nft_exclusive', 5,
   '/assets/game/equipment/nft/solaris-fang.png', 352, 58, 240, 995,
   'Lamina solar 1/1 com nucleo de plasma dourado.', true, true)
on conflict (code) do nothing;

insert into public.nft_equipment (template_id, nft_serial, unique_instance_id, status, for_sale, price_ton, metadata)
select t.id, (select coalesce(max(nft_serial),0) from public.nft_equipment) + 1,
       'NFT-WEAPON-SOLARISFANG-0030', 'RESERVE', false, 2,
       jsonb_build_object('reserve_batch','reserve_2026_08','supply','1/1')
from public.equipment_templates t
where t.code = 'nfteq_weapon_029'
  and not exists (select 1 from public.nft_equipment n where n.template_id = t.id);