-- 1) Discovery table
CREATE TABLE IF NOT EXISTS public.pet_discoveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  pet_id uuid NOT NULL REFERENCES public.pets(id) ON DELETE CASCADE,
  discovered_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, pet_id)
);

GRANT SELECT ON public.pet_discoveries TO authenticated;
GRANT ALL ON public.pet_discoveries TO service_role;

ALTER TABLE public.pet_discoveries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Players read own pet discoveries"
ON public.pet_discoveries FOR SELECT TO authenticated
USING (user_id IN (SELECT id FROM public.game_players WHERE telegram_id = (auth.jwt() ->> 'telegram_id')::bigint));

CREATE TRIGGER update_pet_discoveries_updated_at
BEFORE UPDATE ON public.pet_discoveries
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE OR REPLACE FUNCTION public.record_pet_discovery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.pet_id IS NOT NULL THEN
    INSERT INTO public.pet_discoveries (user_id, pet_id)
    VALUES (NEW.user_id, NEW.pet_id)
    ON CONFLICT (user_id, pet_id) DO NOTHING;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_record_pet_discovery ON public.player_pets;
CREATE TRIGGER trg_record_pet_discovery
AFTER INSERT ON public.player_pets
FOR EACH ROW EXECUTE FUNCTION public.record_pet_discovery();

-- backfill existing owners
INSERT INTO public.pet_discoveries (user_id, pet_id, discovered_at)
SELECT pp.user_id, pp.pet_id, min(pp.created_at)
FROM public.player_pets pp
WHERE pp.pet_id IS NOT NULL
GROUP BY pp.user_id, pp.pet_id
ON CONFLICT (user_id, pet_id) DO NOTHING;

-- 2) 35 new catalog pets
INSERT INTO public.pets (name, slug, species, category, rarity, description, base_passives, image_baby_url, image_young_url, image_adult_url, image_ancestral_url, hide_name_until_discovered, show_in_catalog, is_enabled)
VALUES
-- COMMON
('Mossuk','mossuk','moss_sprite','magical','common','Guardião musgoso das ruínas.','{"team_hp_percent":4}','/__l5e/assets-v1/ccf7f7ec-236d-4999-9a93-9e59769f0f18/mossuk.png','/__l5e/assets-v1/ccf7f7ec-236d-4999-9a93-9e59769f0f18/mossuk.png','/__l5e/assets-v1/ccf7f7ec-236d-4999-9a93-9e59769f0f18/mossuk.png','/__l5e/assets-v1/ccf7f7ec-236d-4999-9a93-9e59769f0f18/mossuk.png',false,true,true),
('Cindra','cindra','ember_cub','beast','common','Filhote de brasas da forja.','{"pvp_attack_percent":3}','/__l5e/assets-v1/4a916331-5a30-49d3-b6e1-755e8a93fb4f/cindra.png','/__l5e/assets-v1/4a916331-5a30-49d3-b6e1-755e8a93fb4f/cindra.png','/__l5e/assets-v1/4a916331-5a30-49d3-b6e1-755e8a93fb4f/cindra.png','/__l5e/assets-v1/4a916331-5a30-49d3-b6e1-755e8a93fb4f/cindra.png',false,true,true),
('Wispet','wispet','wisp','magical','common','Chama-fátua curiosa.','{"farm_fc_percent":4}','/__l5e/assets-v1/5a277ac2-afc7-4be0-a099-40d20ea41950/wispet.png','/__l5e/assets-v1/5a277ac2-afc7-4be0-a099-40d20ea41950/wispet.png','/__l5e/assets-v1/5a277ac2-afc7-4be0-a099-40d20ea41950/wispet.png','/__l5e/assets-v1/5a277ac2-afc7-4be0-a099-40d20ea41950/wispet.png',false,true,true),
('Tarnyx','tarnyx','rock_pup','beast','common','Cão de pedra das minas.','{"defense_percent":4}','/__l5e/assets-v1/daad2fd0-8c75-4bfe-bb02-bcdafbf6fe0b/tarnyx.png','/__l5e/assets-v1/daad2fd0-8c75-4bfe-bb02-bcdafbf6fe0b/tarnyx.png','/__l5e/assets-v1/daad2fd0-8c75-4bfe-bb02-bcdafbf6fe0b/tarnyx.png','/__l5e/assets-v1/daad2fd0-8c75-4bfe-bb02-bcdafbf6fe0b/tarnyx.png',false,true,true),
('Fennrik','fennrik','field_fox','beast','common','Raposa dos campos da vila.','{"mission_reward_percent":4}','/__l5e/assets-v1/987dba6b-ea4a-48cc-b005-c7673255c4cb/fennrik.png','/__l5e/assets-v1/987dba6b-ea4a-48cc-b005-c7673255c4cb/fennrik.png','/__l5e/assets-v1/987dba6b-ea4a-48cc-b005-c7673255c4cb/fennrik.png','/__l5e/assets-v1/987dba6b-ea4a-48cc-b005-c7673255c4cb/fennrik.png',false,true,true),
-- UNCOMMON
('Brackwing','brackwing','marsh_bat','bird','uncommon','Asa do pântano sombrio.','{"pvp_speed_percent":5,"critical_chance_percent":3}','/__l5e/assets-v1/75910472-ee4e-4ec9-a8e7-f1fa0cc4f6f7/brackwing.png','/__l5e/assets-v1/75910472-ee4e-4ec9-a8e7-f1fa0cc4f6f7/brackwing.png','/__l5e/assets-v1/75910472-ee4e-4ec9-a8e7-f1fa0cc4f6f7/brackwing.png','/__l5e/assets-v1/75910472-ee4e-4ec9-a8e7-f1fa0cc4f6f7/brackwing.png',false,true,true),
('Quillow','quillow','quill_beast','beast','uncommon','Espinhos que protegem os aliados.','{"defense_percent":6,"team_hp_percent":4}','/__l5e/assets-v1/fc79c474-f7d1-45b1-b7e2-da02baeeaf03/quillow.png','/__l5e/assets-v1/fc79c474-f7d1-45b1-b7e2-da02baeeaf03/quillow.png','/__l5e/assets-v1/fc79c474-f7d1-45b1-b7e2-da02baeeaf03/quillow.png','/__l5e/assets-v1/fc79c474-f7d1-45b1-b7e2-da02baeeaf03/quillow.png',false,true,true),
('Sylphet','sylphet','breeze_fae','magical','uncommon','Fada da brisa élfica.','{"hero_xp_percent":6,"account_xp_percent":3}','/__l5e/assets-v1/66108b8d-2542-4d24-b12f-4dde97099299/sylphet.png','/__l5e/assets-v1/66108b8d-2542-4d24-b12f-4dde97099299/sylphet.png','/__l5e/assets-v1/66108b8d-2542-4d24-b12f-4dde97099299/sylphet.png','/__l5e/assets-v1/66108b8d-2542-4d24-b12f-4dde97099299/sylphet.png',false,true,true),
('Emberox','emberox','rune_ox','beast','uncommon','Touro rúnico das colinas de lava.','{"boss_damage_percent":7,"pvp_attack_percent":4}','/__l5e/assets-v1/fc49528e-a6ee-4616-95c0-aef497f48847/emberox.png','/__l5e/assets-v1/fc49528e-a6ee-4616-95c0-aef497f48847/emberox.png','/__l5e/assets-v1/fc49528e-a6ee-4616-95c0-aef497f48847/emberox.png','/__l5e/assets-v1/fc49528e-a6ee-4616-95c0-aef497f48847/emberox.png',false,true,true),
('Nimbry','nimbry','cloud_fox','magical','uncommon','Raposa de nuvem com cauda elétrica.','{"farm_fc_percent":6,"offline_production_percent":5}','/__l5e/assets-v1/bd01d687-351f-4b56-be57-b9326235fc8d/nimbry.png','/__l5e/assets-v1/bd01d687-351f-4b56-be57-b9326235fc8d/nimbry.png','/__l5e/assets-v1/bd01d687-351f-4b56-be57-b9326235fc8d/nimbry.png','/__l5e/assets-v1/bd01d687-351f-4b56-be57-b9326235fc8d/nimbry.png',false,true,true),
-- RARE
('Thornclaw','thornclaw','vine_cat','beast','rare','Felino de espinhos da floresta antiga.','{"pvp_attack_percent":7,"critical_chance_percent":5}','/__l5e/assets-v1/3a94c0b1-9268-4db7-bf79-b30992d5efb9/thornclaw.png','/__l5e/assets-v1/3a94c0b1-9268-4db7-bf79-b30992d5efb9/thornclaw.png','/__l5e/assets-v1/3a94c0b1-9268-4db7-bf79-b30992d5efb9/thornclaw.png','/__l5e/assets-v1/3a94c0b1-9268-4db7-bf79-b30992d5efb9/thornclaw.png',false,true,true),
('Glimmara','glimmara','crystal_moth','magical','rare','Mariposa de cristal prismático.','{"drop_chance_percent":7,"egg_luck_percent":5}','/__l5e/assets-v1/3b549734-2db2-429f-98a3-0abb1ca65504/glimmara.png','/__l5e/assets-v1/3b549734-2db2-429f-98a3-0abb1ca65504/glimmara.png','/__l5e/assets-v1/3b549734-2db2-429f-98a3-0abb1ca65504/glimmara.png','/__l5e/assets-v1/3b549734-2db2-429f-98a3-0abb1ca65504/glimmara.png',false,true,true),
('Corvane','corvane','storm_crow','bird','rare','Corvo das tempestades.','{"pvp_speed_percent":8,"pvp_attack_percent":5}','/__l5e/assets-v1/fc998f19-6837-4609-8732-8cca239494f8/corvane.png','/__l5e/assets-v1/fc998f19-6837-4609-8732-8cca239494f8/corvane.png','/__l5e/assets-v1/fc998f19-6837-4609-8732-8cca239494f8/corvane.png','/__l5e/assets-v1/fc998f19-6837-4609-8732-8cca239494f8/corvane.png',false,true,true),
('Marrowfang','marrowfang','bone_hound','beast','rare','Sabujo espectral de ossos encantados.','{"boss_damage_percent":10,"revive_speed_percent":10}','/__l5e/assets-v1/8fcf2798-9d82-418c-91ab-5fb52ff015a6/marrowfang.png','/__l5e/assets-v1/8fcf2798-9d82-418c-91ab-5fb52ff015a6/marrowfang.png','/__l5e/assets-v1/8fcf2798-9d82-418c-91ab-5fb52ff015a6/marrowfang.png','/__l5e/assets-v1/8fcf2798-9d82-418c-91ab-5fb52ff015a6/marrowfang.png',false,true,true),
('Aquilis','aquilis','sea_serpent','dragon','rare','Serpente marinha de pérolas.','{"team_hp_percent":8,"boss_damage_reduction_percent":6}','/__l5e/assets-v1/7f52450b-e3a8-46cb-8c93-7761a6853fca/aquilis.png','/__l5e/assets-v1/7f52450b-e3a8-46cb-8c93-7761a6853fca/aquilis.png','/__l5e/assets-v1/7f52450b-e3a8-46cb-8c93-7761a6853fca/aquilis.png','/__l5e/assets-v1/7f52450b-e3a8-46cb-8c93-7761a6853fca/aquilis.png',false,true,true),
-- EPIC
('Vulkaryn','vulkaryn','magma_drake','dragon','epic','Draco de magma da montanha negra.','{"boss_damage_percent":14,"pvp_attack_percent":8}','/__l5e/assets-v1/d61fe731-4b56-4aaa-abf0-ef29002b4fb8/vulkaryn.png','/__l5e/assets-v1/d61fe731-4b56-4aaa-abf0-ef29002b4fb8/vulkaryn.png','/__l5e/assets-v1/d61fe731-4b56-4aaa-abf0-ef29002b4fb8/vulkaryn.png','/__l5e/assets-v1/d61fe731-4b56-4aaa-abf0-ef29002b4fb8/vulkaryn.png',false,true,true),
('Selesta','selesta','astral_stag','beast','epic','Cervo astral das constelações.','{"reward_percent":10,"account_xp_percent":8}','/__l5e/assets-v1/da9fa19d-a810-4932-b302-8f1e0a0ca4bb/selesta.png','/__l5e/assets-v1/da9fa19d-a810-4932-b302-8f1e0a0ca4bb/selesta.png','/__l5e/assets-v1/da9fa19d-a810-4932-b302-8f1e0a0ca4bb/selesta.png','/__l5e/assets-v1/da9fa19d-a810-4932-b302-8f1e0a0ca4bb/selesta.png',false,true,true),
('Umbrathis','umbrathis','night_cat','magical','epic','Gato noturno de asas sombrias.','{"critical_chance_percent":10,"pvp_speed_percent":10}','/__l5e/assets-v1/e81e0acb-46df-4a6b-9bc3-ad5a260b2bc2/umbrathis.png','/__l5e/assets-v1/e81e0acb-46df-4a6b-9bc3-ad5a260b2bc2/umbrathis.png','/__l5e/assets-v1/e81e0acb-46df-4a6b-9bc3-ad5a260b2bc2/umbrathis.png','/__l5e/assets-v1/e81e0acb-46df-4a6b-9bc3-ad5a260b2bc2/umbrathis.png',false,true,true),
('Zephyrra','zephyrra','gale_falcon','bird','epic','Falcão da vendaval prateada.','{"pvp_speed_percent":12,"pvp_defense_percent":8}','/__l5e/assets-v1/67380f8d-cffe-40a6-b7c2-0e8d53405b55/zephyrra.png','/__l5e/assets-v1/67380f8d-cffe-40a6-b7c2-0e8d53405b55/zephyrra.png','/__l5e/assets-v1/67380f8d-cffe-40a6-b7c2-0e8d53405b55/zephyrra.png','/__l5e/assets-v1/67380f8d-cffe-40a6-b7c2-0e8d53405b55/zephyrra.png',false,true,true),
('Cryomir','cryomir','frost_wyrm','dragon','epic','Verme do gelo eterno.','{"team_hp_percent":12,"boss_damage_reduction_percent":10}','/__l5e/assets-v1/d311159e-ca5a-4db2-8deb-48e17c58bd68/cryomir.png','/__l5e/assets-v1/d311159e-ca5a-4db2-8deb-48e17c58bd68/cryomir.png','/__l5e/assets-v1/d311159e-ca5a-4db2-8deb-48e17c58bd68/cryomir.png','/__l5e/assets-v1/d311159e-ca5a-4db2-8deb-48e17c58bd68/cryomir.png',false,true,true),
-- LEGENDARY
('Solvarion','solvarion','solar_phoenix','bird','legendary','Fênix solar da aurora dourada.','{"revive_speed_percent":25,"team_hp_percent":14,"reward_percent":12}','/__l5e/assets-v1/1c5b7375-2391-4230-8c8b-9ac0a5fffe1c/solvarion.png','/__l5e/assets-v1/1c5b7375-2391-4230-8c8b-9ac0a5fffe1c/solvarion.png','/__l5e/assets-v1/1c5b7375-2391-4230-8c8b-9ac0a5fffe1c/solvarion.png','/__l5e/assets-v1/1c5b7375-2391-4230-8c8b-9ac0a5fffe1c/solvarion.png',false,true,true),
('Nyxareth','nyxareth','eclipse_dragon','dragon','legendary','Dragão do eclipse violeta.','{"boss_damage_percent":20,"critical_chance_percent":12}','/__l5e/assets-v1/828534db-b250-4d69-bcf3-198de8b0765b/nyxareth.png','/__l5e/assets-v1/828534db-b250-4d69-bcf3-198de8b0765b/nyxareth.png','/__l5e/assets-v1/828534db-b250-4d69-bcf3-198de8b0765b/nyxareth.png','/__l5e/assets-v1/828534db-b250-4d69-bcf3-198de8b0765b/nyxareth.png',false,true,true),
('Terravox','terravox','rune_golem','magical','legendary','Golem rúnico guardião das montanhas.','{"defense_percent":18,"team_hp_percent":16}','/__l5e/assets-v1/189e34c3-ea47-490d-aaa8-282a9188ec08/terravox.png','/__l5e/assets-v1/189e34c3-ea47-490d-aaa8-282a9188ec08/terravox.png','/__l5e/assets-v1/189e34c3-ea47-490d-aaa8-282a9188ec08/terravox.png','/__l5e/assets-v1/189e34c3-ea47-490d-aaa8-282a9188ec08/terravox.png',false,true,true),
('Aetheline','aetheline','aether_unicorn','magical','legendary','Unicórnio do éter iridescente.','{"drop_chance_percent":14,"egg_luck_percent":12,"random_reward_percent":8}','/__l5e/assets-v1/d28f1d7f-1d3c-452c-8116-1ebda3942610/aetheline.png','/__l5e/assets-v1/d28f1d7f-1d3c-452c-8116-1ebda3942610/aetheline.png','/__l5e/assets-v1/d28f1d7f-1d3c-452c-8116-1ebda3942610/aetheline.png','/__l5e/assets-v1/d28f1d7f-1d3c-452c-8116-1ebda3942610/aetheline.png',false,true,true),
('Fulgorax','fulgorax','thunder_griffin','bird','legendary','Grifo do trovão dourado.','{"pvp_attack_percent":16,"pvp_speed_percent":14}','/__l5e/assets-v1/67e1909a-f9c0-483e-a214-54f8662b51e2/fulgorax.png','/__l5e/assets-v1/67e1909a-f9c0-483e-a214-54f8662b51e2/fulgorax.png','/__l5e/assets-v1/67e1909a-f9c0-483e-a214-54f8662b51e2/fulgorax.png','/__l5e/assets-v1/67e1909a-f9c0-483e-a214-54f8662b51e2/fulgorax.png',false,true,true),
-- MYTHIC
('Draviel','draviel','crystal_dragon','dragon','mythic','Dragão de cristal vivo.','{"boss_damage_percent":26,"team_hp_percent":18,"critical_chance_percent":14}','/__l5e/assets-v1/1a4822e8-1820-48a2-b177-58ef0a63d712/draviel.png','/__l5e/assets-v1/1a4822e8-1820-48a2-b177-58ef0a63d712/draviel.png','/__l5e/assets-v1/1a4822e8-1820-48a2-b177-58ef0a63d712/draviel.png','/__l5e/assets-v1/1a4822e8-1820-48a2-b177-58ef0a63d712/draviel.png',false,true,true),
('Astharil','astharil','celestial_serpent','dragon','mythic','Serpente celestial dos anéis rúnicos.','{"reward_percent":22,"hero_xp_percent":18,"account_xp_percent":14}','/__l5e/assets-v1/01598633-7530-42ca-9ad6-ac18b8ea01a1/astharil.png','/__l5e/assets-v1/01598633-7530-42ca-9ad6-ac18b8ea01a1/astharil.png','/__l5e/assets-v1/01598633-7530-42ca-9ad6-ac18b8ea01a1/astharil.png','/__l5e/assets-v1/01598633-7530-42ca-9ad6-ac18b8ea01a1/astharil.png',false,true,true),
('Voltharis','voltharis','plasma_tiger','beast','mythic','Tigre de plasma das tempestades eternas.','{"pvp_attack_percent":22,"pvp_speed_percent":18,"critical_chance_percent":16}','/__l5e/assets-v1/bc0f0b0b-014e-4667-97de-4fc5ebb4d105/voltharis.png','/__l5e/assets-v1/bc0f0b0b-014e-4667-97de-4fc5ebb4d105/voltharis.png','/__l5e/assets-v1/bc0f0b0b-014e-4667-97de-4fc5ebb4d105/voltharis.png','/__l5e/assets-v1/bc0f0b0b-014e-4667-97de-4fc5ebb4d105/voltharis.png',false,true,true),
('Seraphyx','seraphyx','radiant_owl','bird','mythic','Coruja radiante de seis asas.','{"revive_speed_percent":35,"team_hp_percent":20,"defense_percent":16}','/__l5e/assets-v1/bfd7fffc-cb93-4ab9-a4fe-1dd828a08524/seraphyx.png','/__l5e/assets-v1/bfd7fffc-cb93-4ab9-a4fe-1dd828a08524/seraphyx.png','/__l5e/assets-v1/bfd7fffc-cb93-4ab9-a4fe-1dd828a08524/seraphyx.png','/__l5e/assets-v1/bfd7fffc-cb93-4ab9-a4fe-1dd828a08524/seraphyx.png',false,true,true),
('Obliviax','obliviax','void_whale','magical','mythic','Baleia do vazio estelar.','{"drop_chance_percent":20,"egg_luck_percent":18,"farm_fc_percent":16}','/__l5e/assets-v1/6a2b32aa-61e2-412a-bb3f-66ba51a57ae2/obliviax.png','/__l5e/assets-v1/6a2b32aa-61e2-412a-bb3f-66ba51a57ae2/obliviax.png','/__l5e/assets-v1/6a2b32aa-61e2-412a-bb3f-66ba51a57ae2/obliviax.png','/__l5e/assets-v1/6a2b32aa-61e2-412a-bb3f-66ba51a57ae2/obliviax.png',false,true,true),
-- ANCESTRAL
('Ouranyx','ouranyx','cosmic_dragon','dragon','ancestral','Dragão cósmico com núcleo solar.','{"boss_damage_percent":38,"pvp_attack_percent":26,"team_hp_percent":22}','/__l5e/assets-v1/3842e8c5-8362-4f90-9469-78f755b79294/ouranyx.png','/__l5e/assets-v1/3842e8c5-8362-4f90-9469-78f755b79294/ouranyx.png','/__l5e/assets-v1/3842e8c5-8362-4f90-9469-78f755b79294/ouranyx.png','/__l5e/assets-v1/3842e8c5-8362-4f90-9469-78f755b79294/ouranyx.png',false,true,true),
('Primordis','primordis','titan_turtle','magical','ancestral','Titã primordial de casco montanhoso.','{"team_hp_percent":30,"defense_percent":26,"boss_damage_reduction_percent":22}','/__l5e/assets-v1/81a59fb2-9bc0-4ea7-8d64-5adfa34a658f/primordis.png','/__l5e/assets-v1/81a59fb2-9bc0-4ea7-8d64-5adfa34a658f/primordis.png','/__l5e/assets-v1/81a59fb2-9bc0-4ea7-8d64-5adfa34a658f/primordis.png','/__l5e/assets-v1/81a59fb2-9bc0-4ea7-8d64-5adfa34a658f/primordis.png',false,true,true),
('Aethermyr','aethermyr','nine_tail_spirit','magical','ancestral','Espírito de nove caudas do éter.','{"drop_chance_percent":28,"egg_luck_percent":26,"reward_percent":24}','/__l5e/assets-v1/d3b1410d-d474-4b80-99b3-d9f7d5828908/aethermyr.png','/__l5e/assets-v1/d3b1410d-d474-4b80-99b3-d9f7d5828908/aethermyr.png','/__l5e/assets-v1/d3b1410d-d474-4b80-99b3-d9f7d5828908/aethermyr.png','/__l5e/assets-v1/d3b1410d-d474-4b80-99b3-d9f7d5828908/aethermyr.png',false,true,true),
('Kaelthos','kaelthos','warlion_guardian','beast','ancestral','Leão guardião de armadura obsidiana.','{"pvp_attack_percent":30,"pvp_defense_percent":26,"critical_chance_percent":20}','/__l5e/assets-v1/e686eb28-74e9-4020-a887-efe0fa4f493d/kaelthos.png','/__l5e/assets-v1/e686eb28-74e9-4020-a887-efe0fa4f493d/kaelthos.png','/__l5e/assets-v1/e686eb28-74e9-4020-a887-efe0fa4f493d/kaelthos.png','/__l5e/assets-v1/e686eb28-74e9-4020-a887-efe0fa4f493d/kaelthos.png',false,true,true),
('Eternyx','eternyx','eternal_phoenix','bird','ancestral','Fênix eterna das galáxias.','{"revive_speed_percent":45,"reward_percent":28,"hero_xp_percent":24}','/__l5e/assets-v1/485b7874-1fc3-4ad3-8e96-c7385efe9e11/eternyx.png','/__l5e/assets-v1/485b7874-1fc3-4ad3-8e96-c7385efe9e11/eternyx.png','/__l5e/assets-v1/485b7874-1fc3-4ad3-8e96-c7385efe9e11/eternyx.png','/__l5e/assets-v1/485b7874-1fc3-4ad3-8e96-c7385efe9e11/eternyx.png',false,true,true)
ON CONFLICT (slug) DO NOTHING;

-- 3) Dashboard: permanent discovery + hide stats until discovered
CREATE OR REPLACE FUNCTION public.get_pet_dashboard(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN jsonb_build_object(
    'activePet', (SELECT player_pet_json(id) FROM player_pets WHERE user_id = u AND is_active LIMIT 1),
    'playerPets', coalesce((SELECT jsonb_agg(player_pet_json(t.id))
        FROM (SELECT id FROM player_pets WHERE user_id = u ORDER BY is_active DESC, level DESC, created_at) t), '[]'::jsonb),
    'catalog', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'id', p.id, 'name', p.name, 'slug', p.slug,
          'species', CASE WHEN d.found THEN p.species ELSE '???' END,
          'category', p.category,
          'description', CASE WHEN d.found THEN coalesce(p.description,'') ELSE '' END,
          'basePassives', CASE WHEN d.found THEN p.base_passives ELSE '{}'::jsonb END,
          'activeSkill', CASE WHEN d.found THEN p.active_skill ELSE NULL END,
          'rarity', p.rarity, 'availabilityType', p.availability_type,
          'hideName', p.hide_name_until_discovered,
          'images', jsonb_build_object('baby',p.image_baby_url,'young',p.image_young_url,'adult',p.image_adult_url,'ancestral',p.image_ancestral_url),
          'discovered', d.found,
          'bestRarity', (SELECT pp.rarity FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id ORDER BY pet_rarity_order(pp.rarity) DESC LIMIT 1),
          'bestLevel', (SELECT max(pp.level) FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id),
          'sources', coalesce((SELECT jsonb_agg(DISTINCT e.name) FROM reward_pet_pool rp
                JOIN pet_eggs e ON e.id::text = rp.source_key
               WHERE rp.source_type='EGG' AND rp.pet_id = p.id AND rp.enabled AND e.is_enabled),
             coalesce((SELECT jsonb_agg(e.name ORDER BY e.name) FROM pet_eggs e
               WHERE e.is_enabled AND p.availability_type='NORMAL'
                 AND NOT EXISTS (SELECT 1 FROM reward_pet_pool rp2 WHERE rp2.source_type='EGG' AND rp2.source_key=e.id::text)
                 AND (e.allowed_pet_categories IS NULL OR e.allowed_pet_categories ? p.category)), '[]'::jsonb))
        ) ORDER BY p.name)
        FROM pets p
        CROSS JOIN LATERAL (SELECT (exists(SELECT 1 FROM pet_discoveries pd WHERE pd.user_id = u AND pd.pet_id = p.id)
              OR exists(SELECT 1 FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id)) AS found) d
        WHERE p.show_in_catalog AND (p.is_enabled OR d.found)), '[]'::jsonb),
    'foods', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'code', f.code, 'name', f.name, 'rarity', f.rarity, 'xpValue', f.xp_value, 'icon', f.icon, 'priceFc', f.price_fc,
          'quantity', coalesce((SELECT quantity FROM player_pet_food pf WHERE pf.user_id = u AND pf.food_code = f.code), 0)
        ) ORDER BY f.sort_order) FROM pet_food_items f WHERE f.enabled), '[]'::jsonb),
    'fragments', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'playerPetId', pp.id, 'petName', p.name, 'image', p.image_baby_url, 'rarity', pp.rarity, 'quantity', pp.fragments
        ) ORDER BY pp.fragments DESC) FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.user_id = u), '[]'::jsonb),
    'inventory', jsonb_build_object(
        'food', coalesce((SELECT sum(quantity) FROM player_pet_food WHERE user_id = u), 0),
        'universalFragments', coalesce((SELECT quantity FROM player_pet_inventory WHERE user_id = u AND item_type = 'universal_fragment' AND item_id IS NULL), 0)),
    'history', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'id', h.id, 'eggName', e.name, 'petName', p.name, 'rarity', h.result_rarity,
          'duplicateFragments', h.duplicate_fragments, 'createdAt', h.created_at
        ) ORDER BY h.created_at DESC) FROM pet_hatch_history h
        JOIN pet_eggs e ON e.id = h.egg_id LEFT JOIN pets p ON p.id = h.result_pet_id
        WHERE h.user_id = u), '[]'::jsonb),
    'evolutionTiers', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'tier', t.tier, 'label', t.label, 'requiredLevel', t.required_level, 'fcCost', t.fc_cost,
          'fragmentCost', t.fragment_cost, 'newBuffChance', round(t.new_buff_chance*100)
        ) ORDER BY t.tier) FROM pet_evolution_tiers t WHERE t.enabled), '[]'::jsonb),
    'rarities', coalesce((SELECT jsonb_agg(jsonb_build_object('rarity',c.rarity,'label',c.label,'order',c.sort_order,
          'primary',c.color_primary,'secondary',c.color_secondary,'glow',c.glow) ORDER BY c.sort_order)
        FROM pet_rarity_config c WHERE c.enabled), '[]'::jsonb),
    'bonuses', get_pet_bonuses(u),
    'balance', coalesce((SELECT forge_coins FROM game_players WHERE id = u), 0)
  );
END $function$;

REVOKE ALL ON FUNCTION public.get_pet_dashboard(bigint) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.record_pet_discovery() FROM anon, authenticated;