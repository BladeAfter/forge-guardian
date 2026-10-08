-- 1) Flag para heróis NFT exclusivos da Roleta Global
ALTER TABLE public.hero_catalog
  ADD COLUMN IF NOT EXISTS roulette_exclusive boolean NOT NULL DEFAULT false;

-- 2) Novos heróis NFT exclusivos da roleta (não obtíveis por loja, recrutamento, drop, fusão ou pool)
INSERT INTO public.hero_catalog (
  hero_key, name, rarity, hero_class, nft_class_label, image, enabled, description,
  base_atk, base_hp, base_def, base_speed, crit_rate, skill_power,
  start_level, max_level, is_nft_exclusive, roulette_exclusive,
  recruit_enabled, recruit_eligible, shop_eligible, in_shop, reward_pool_eligible,
  random_drop_eligible, fusion_pool_enabled, featured, sort_order, nft_passive
) VALUES
 ('nft-rl-arkhanor','Arkhanor, Sentinela do Vazio','nft_exclusive','tank','Tank','/assets/game/heroes-nft/rl-arkhanor.jpg',true,'Exclusivo da Roleta Global de Mistério.',
  1060,13900,1520,90,14,1560,1,120,true,true,false,false,false,false,false,false,false,false,101,'{"key":"void_bulwark","reflect_percent":18}'::jsonb),
 ('nft-rl-astraea','Astraea, Oráculo Celestial','nft_exclusive','mage','Mago/Suporte','/assets/game/heroes-nft/rl-selvyra.jpg',true,'Exclusivo da Roleta Global de Mistério.',
  1330,9700,1020,102,25,1950,1,120,true,true,false,false,false,false,false,false,false,false,102,'{"key":"stellar_prophecy","ally_crit_bonus":18}'::jsonb),
 ('nft-rl-vorgrim','Vorgrim, Fúria Dracônica','nft_exclusive','warrior','Guerreiro','/assets/game/heroes-nft/rl-drakvorn.jpg',true,'Exclusivo da Roleta Global de Mistério.',
  1390,10600,1160,100,28,1620,1,120,true,true,false,false,false,false,false,false,false,false,103,'{"key":"draconic_fury","lifesteal":18}'::jsonb),
 ('nft-rl-lyssandriel','Lyssandriel, Lâmina Aurora','nft_exclusive','assassin','Assassina','/assets/game/heroes-nft/rl-lyssandriel.jpg',true,'Exclusivo da Roleta Global de Mistério.',
  1320,9300,1000,116,36,1660,1,120,true,true,false,false,false,false,false,false,false,false,104,'{"key":"aurora_strike","crit_bonus":26}'::jsonb),
 ('nft-rl-thornvael','Thornvael, Arqueiro Espectral','nft_exclusive','archer','Arqueiro','/assets/game/heroes-nft/rl-thornvael.jpg',true,'Exclusivo da Roleta Global de Mistério.',
  1300,9800,1040,112,31,1640,1,120,true,true,false,false,false,false,false,false,false,false,105,'{"key":"spectral_volley","def_pierce":26}'::jsonb),
 ('nft-rl-thalassa','Thalassa, Guardiã Abissal','nft_exclusive','support','Curandeira','/assets/game/heroes-nft/rl-veymora.jpg',true,'Exclusivo da Roleta Global de Mistério.',
  1040,12200,1250,94,17,1880,1,120,true,true,false,false,false,false,false,false,false,false,106,'{"key":"abyssal_blessing","team_heal_percent":14}'::jsonb)
ON CONFLICT (hero_key) DO NOTHING;

-- 3) Entrega da roleta: apenas templates exclusivos da roleta + mineração TON configurável (default 0.20/dia)
CREATE OR REPLACE FUNCTION public.roulette_grant_premium(p_user uuid, p_cycle uuid, p_spin uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cyc public.global_roulette_cycles; c public.hero_catalog; v_hero uuid; ph public.player_heroes;
        v_nft uuid; v_res jsonb; v_out jsonb; v_mining numeric;
BEGIN
  SELECT * INTO cyc FROM public.global_roulette_cycles WHERE id = p_cycle;
  IF cyc.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO c FROM public.hero_catalog WHERE hero_key = cyc.target_reward_id;

  IF cyc.target_reward_type = 'NFT_HERO' THEN
    IF c.hero_key IS NULL THEN RAISE EXCEPTION 'REWARD_TEMPLATE_NOT_FOUND:%', cyc.target_reward_id; END IF;
    IF coalesce(c.roulette_exclusive, false) = false THEN
      RAISE EXCEPTION 'REWARD_NOT_ROULETTE_EXCLUSIVE:%', cyc.target_reward_id;
    END IF;

    SELECT coalesce((rc.metadata->>'mining_daily_ton')::numeric, 0.20) INTO v_mining
      FROM public.roulette_reward_config rc
     WHERE rc.reward_class = 'NFT_HERO' AND rc.reward_key = cyc.target_reward_id
     LIMIT 1;
    v_mining := coalesce(v_mining, 0.20);

    SELECT n.id INTO v_nft FROM public.nft_heroes n
     WHERE n.hero_template_id = cyc.target_reward_id AND n.owner_user_id IS NULL AND n.status='AVAILABLE'
     ORDER BY n.nft_serial LIMIT 1 FOR UPDATE SKIP LOCKED;
    IF v_nft IS NULL THEN
      v_nft := public.roulette_mint_nft_unit(cyc.target_reward_id, 'GLOBAL_ROULETTE');
    END IF;
    IF v_nft IS NULL THEN RAISE EXCEPTION 'REWARD_TEMPLATE_NOT_FOUND:%', cyc.target_reward_id; END IF;

    UPDATE public.nft_heroes
       SET mining_daily_ton = v_mining, mining_daily_myth = 0, mining_dual = false,
           metadata = coalesce(metadata,'{}'::jsonb)
             || jsonb_build_object('mining_enabled', v_mining > 0, 'source','GLOBAL_ROULETTE')
     WHERE id = v_nft;

    v_res := public.nft_hero_assign_unit(v_nft, p_user, 'GLOBAL_ROULETTE_NFT_HERO');
    UPDATE public.player_heroes SET mining_daily_myth = 0, premium_source = 'GLOBAL_ROULETTE_NFT_HERO'
     WHERE id = (v_res->>'playerHeroId')::uuid;
    v_out := jsonb_build_object('class','NFT_HERO','heroKey', cyc.target_reward_id, 'name', coalesce(v_res->>'heroName', c.name),
      'serial', v_res->>'serial', 'image', c.image, 'mining', v_mining > 0, 'miningDailyTon', v_mining,
      'atk', v_res->>'atk', 'hp', v_res->>'hp', 'power', c.power, 'playerHeroId', v_res->>'playerHeroId');
  ELSE
    IF c.hero_key IS NULL THEN RAISE EXCEPTION 'REWARD_TEMPLATE_NOT_FOUND:%', cyc.target_reward_id; END IF;
    IF cyc.target_reward_type = 'CELESTIAL_HERO' AND public.roulette_user_has_celestial(p_user) THEN RETURN NULL; END IF;
    INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image, archetype, premium_source)
    VALUES (p_user, c.hero_key, c.name, public.normalize_hero_rarity(c.rarity), greatest(1, c.start_level), c.image,
            c.hero_class, 'GLOBAL_ROULETTE_' || cyc.target_reward_type)
    RETURNING id INTO v_hero;
    SELECT * INTO ph FROM public.player_heroes WHERE id = v_hero;
    IF cyc.target_reward_type = 'CELESTIAL_HERO' THEN
      INSERT INTO public.roulette_celestial_awards(user_id, hero_key, player_hero_id, cycle_id, spin_id)
      VALUES (p_user, c.hero_key, v_hero, p_cycle, p_spin);
    END IF;
    v_out := jsonb_build_object('class', cyc.target_reward_type, 'heroKey', c.hero_key, 'name', c.name,
      'rarity', public.normalize_hero_rarity(c.rarity), 'image', c.image, 'power', c.power,
      'atk', round(coalesce(ph.final_atk,0)), 'hp', round(coalesce(ph.final_hp,0)), 'playerHeroId', v_hero);
  END IF;

  INSERT INTO public.global_roulette_awards(spin_id, cycle_id, user_id, reward_class, reward_key, source_type, amount, payload)
  VALUES (p_spin, p_cycle, p_user, cyc.target_reward_type, cyc.target_reward_id,
          'GLOBAL_ROULETTE_' || cyc.target_reward_type, 1, v_out);
  RETURN v_out;
END $function$;