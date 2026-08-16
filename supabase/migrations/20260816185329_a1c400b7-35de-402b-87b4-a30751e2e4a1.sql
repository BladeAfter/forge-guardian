do $$
declare r record;
begin
  for r in (
    select * from (values
      ('astharil',      '/__l5e/assets-v1/ee866331-d064-4f0d-badc-a88ee225a27b/astharil-evo1.png',      '/__l5e/assets-v1/641bf475-01d5-4f59-a427-f88a7eba4d7b/astharil-evo2.png'),
      ('kaelthos',      '/__l5e/assets-v1/90ae3789-5331-4022-8682-87b8872d3e15/kaelthos-evo1.png',      '/__l5e/assets-v1/16da90ed-3807-46d6-8c67-0fa53e8d9012/kaelthos-evo2.png'),
      ('seraphyx',      '/__l5e/assets-v1/c10ca23e-3ebd-4831-bcf9-c238df700c97/seraphyx-evo1.png',      '/__l5e/assets-v1/05de3958-3452-4ab2-93f9-73691ac4d7bb/seraphyx-evo2.png'),
      ('nft-cryon',     '/__l5e/assets-v1/ecdac7ef-8acc-43a5-8d28-f5aa53c2b9a0/nft-cryon-evo1.png',     '/__l5e/assets-v1/395cae27-bce1-4ddd-b2ad-11964a400600/nft-cryon-evo2.png'),
      ('nft-eternyx',   '/__l5e/assets-v1/deb4dcf2-42a0-4d39-a8e7-2dc85e9c79b8/nft-eternyx-evo1.png',   '/__l5e/assets-v1/e74b70d1-21bb-4374-88b3-6093aa93227f/nft-eternyx-evo2.png'),
      ('nft-kryzalith', '/__l5e/assets-v1/8ec68bf7-d9c3-4b52-9c75-a52b0a45709e/nft-kryzalith-evo1.png', '/__l5e/assets-v1/083ffd97-86ec-4ff9-bcb1-81ba77fb0cf2/nft-kryzalith-evo2.png'),
      ('nft-seraphiel', '/__l5e/assets-v1/ad16d800-2a0c-4f65-9363-1d1ef51d5d5a/nft-seraphiel-evo1.png', '/__l5e/assets-v1/4efb3453-b621-497c-8862-40185c6850f7/nft-seraphiel-evo2.png'),
      ('nft-sylvaris',  '/__l5e/assets-v1/d0b38806-7953-40dd-91c7-81b46e224052/nft-sylvaris-evo1.png',  '/__l5e/assets-v1/92814398-15d4-4a3a-a8bc-81f02f84523c/nft-sylvaris-evo2.png'),
      ('nft-vaeloryn',  '/__l5e/assets-v1/f268290d-d7b8-4fff-8664-eb95ba264e3e/nft-vaeloryn-evo1.png',  '/__l5e/assets-v1/eb5a7fdd-27da-49ae-88ef-e925c53c99b9/nft-vaeloryn-evo2.png')
    ) as t(slug, evo1, evo2)
  ) loop
    update public.pets
       set image_evo1_url = r.evo1,
           image_evo2_url = r.evo2,
           image_evo3_url = r.evo2,
           image_evo4_url = r.evo2,
           image_final_url = r.evo2,
           updated_at = now()
     where slug = r.slug;
  end loop;
end $$;