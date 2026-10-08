-- rarity fusion: NFT heroes are never eligible material and never listed.
CREATE OR REPLACE FUNCTION public.fuse_heroes_by_rarity(p_telegram_id bigint, p_hero_ids uuid[], p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_user uuid; v_bal numeric; cfg jsonb := public.hero_rarity_fusion_config(); tier jsonb;
  ids uuid[]; v_required int; v_count int; v_src text; v_tgt text;
  v_cost numeric; v_chance numeric; v_frags int; v_roll numeric; v_success boolean;
  picked public.hero_catalog%rowtype; v_new_id uuid; v_after numeric; v_keys text[];
  v_existing jsonb; v_frag_total int := 0; v_result jsonb; v_new_row public.player_heroes%rowtype;
BEGIN
  IF p_idempotency_key IS NOT NULL AND length(p_idempotency_key) > 0 THEN
    SELECT result INTO v_existing FROM public.hero_rarity_fusion_idempotency WHERE key = p_idempotency_key;
    IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;
  END IF;

  IF coalesce((cfg->>'enabled')::boolean, true) IS NOT TRUE THEN RAISE EXCEPTION 'FUSION_DISABLED'; END IF;

  SELECT id, forge_coins INTO v_user, v_bal FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('hero_rarity_fusion:' || v_user::text, 0));

  v_required := coalesce((cfg->>'required_heroes')::int, 5);
  SELECT array_agg(DISTINCT x) INTO ids FROM unnest(coalesce(p_hero_ids, '{}'::uuid[])) x;
  IF coalesce(array_length(ids,1),0) <> v_required THEN RAISE EXCEPTION 'NEED_EXACT_HEROES'; END IF;

  PERFORM 1 FROM public.player_heroes WHERE id = ANY(ids) ORDER BY id FOR UPDATE;

  SELECT count(*), array_agg(hero_key) INTO v_count, v_keys FROM public.player_heroes WHERE id = ANY(ids) AND user_id = v_user;
  IF v_count <> v_required THEN RAISE EXCEPTION 'HERO_NOT_OWNED'; END IF;

  IF EXISTS(SELECT 1 FROM public.player_heroes WHERE id = ANY(ids) AND is_nft_exclusive) THEN RAISE EXCEPTION 'NFT_HERO_UNIQUE'; END IF;
  IF EXISTS(SELECT 1 FROM public.player_heroes WHERE id = ANY(ids) AND locked) THEN RAISE EXCEPTION 'HERO_LOCKED'; END IF;
  IF EXISTS(SELECT 1 FROM public.pvp_team_slots WHERE hero_id = ANY(ids)) THEN RAISE EXCEPTION 'HERO_EQUIPPED'; END IF;
  IF EXISTS(SELECT 1 FROM public.boss_team_slots WHERE player_hero_id = ANY(ids)) THEN RAISE EXCEPTION 'HERO_EQUIPPED'; END IF;

  SELECT count(DISTINCT rarity), min(rarity) INTO v_count, v_src FROM public.player_heroes WHERE id = ANY(ids);
  IF v_count <> 1 THEN RAISE EXCEPTION 'RARITY_MISMATCH'; END IF;

  tier := cfg->'tiers'->v_src;
  IF tier IS NULL THEN RAISE EXCEPTION 'MAX_FUSION_RARITY'; END IF;
  v_tgt := tier->>'target';
  v_cost := coalesce((tier->>'cost_fc')::numeric, 0);
  v_chance := least(100, greatest(0, coalesce((tier->>'chance')::numeric, 0)));
  v_frags := greatest(0, coalesce((tier->>'fragments')::int, 0));
  IF v_tgt IS NULL THEN RAISE EXCEPTION 'MAX_FUSION_RARITY'; END IF;
  IF v_tgt = 'nft_exclusive' THEN RAISE EXCEPTION 'MAX_FUSION_RARITY'; END IF;
  IF v_bal < v_cost THEN RAISE EXCEPTION 'NOT_ENOUGH_FC'; END IF;

  v_roll := random() * 100;
  v_success := v_roll < v_chance;

  IF v_success THEN
    SELECT * INTO picked FROM public.hero_catalog
      WHERE enabled AND fusion_pool_enabled AND NOT is_nft_exclusive AND rarity = v_tgt ORDER BY random() LIMIT 1;
    IF picked.hero_key IS NULL THEN RAISE EXCEPTION 'NO_ELIGIBLE_HERO'; END IF;
  END IF;

  UPDATE public.game_players SET forge_coins = forge_coins - v_cost, updated_at = now()
    WHERE id = v_user RETURNING forge_coins INTO v_after;

  DELETE FROM public.hero_combat_state WHERE hero_id = ANY(ids);
  DELETE FROM public.player_heroes WHERE id = ANY(ids) AND user_id = v_user;

  IF v_success THEN
    INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image)
      VALUES (v_user, picked.hero_key, picked.name, public.normalize_hero_rarity(picked.rarity), 1, picked.image)
      RETURNING id INTO v_new_id;
    SELECT * INTO v_new_row FROM public.player_heroes WHERE id = v_new_id;
  ELSE
    INSERT INTO public.player_inventory AS inv (user_id, item_type, item_code, quantity, updated_at)
      VALUES (v_user, 'fragments', 'fragments', v_frags, now())
      ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = inv.quantity + v_frags, updated_at = now()
      RETURNING inv.quantity INTO v_frag_total;
  END IF;

  INSERT INTO public.hero_rarity_fusion_history(user_id, source_rarity, target_rarity, selected_hero_ids, selected_hero_keys,
      fusion_cost_fc, success_chance, rng_roll, success, reward_hero_id, reward_hero_key, reward_hero_name, fragment_reward)
    VALUES (v_user, v_src, v_tgt, ids, coalesce(v_keys,'{}'), v_cost, v_chance, v_roll, v_success,
      v_new_id, picked.hero_key, picked.name, CASE WHEN v_success THEN 0 ELSE v_frags END);

  v_result := jsonb_build_object(
    'success', v_success, 'sourceRarity', v_src, 'targetRarity', v_tgt,
    'costFc', v_cost, 'chance', v_chance, 'balance', v_after,
    'consumed', v_required,
    'fragments', CASE WHEN v_success THEN 0 ELSE v_frags END,
    'fragmentsTotal', v_frag_total,
    'hero', CASE WHEN v_success THEN jsonb_build_object(
        'heroId', v_new_id, 'heroKey', v_new_row.hero_key, 'name', v_new_row.name, 'rarity', v_new_row.rarity,
        'level', v_new_row.level, 'imageUrl', v_new_row.image,
        'finalAtk', round(v_new_row.final_atk), 'finalHp', round(v_new_row.final_hp),
        'power', round(v_new_row.final_atk * 2 + v_new_row.final_hp)) ELSE NULL END
  );

  IF p_idempotency_key IS NOT NULL AND length(p_idempotency_key) > 0 THEN
    INSERT INTO public.hero_rarity_fusion_idempotency(key, user_id, result)
      VALUES (p_idempotency_key, v_user, v_result) ON CONFLICT (key) DO NOTHING;
  END IF;

  RETURN v_result || jsonb_build_object('dashboard', public.get_rarity_fusion_dashboard(p_telegram_id));
END; $fn$;

CREATE OR REPLACE FUNCTION public.get_rarity_fusion_dashboard(p_telegram_id bigint)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_user uuid; v_bal numeric := 0; cfg jsonb := public.hero_rarity_fusion_config(); v_heroes jsonb; v_counts jsonb;
BEGIN
  SELECT id, forge_coins INTO v_user, v_bal FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('config', cfg, 'balance', 0, 'heroes', '[]'::jsonb, 'counts', '{}'::jsonb);
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'heroId', ph.id, 'heroKey', ph.hero_key, 'name', ph.name, 'rarity', ph.rarity,
      'level', ph.level, 'imageUrl', ph.image, 'stars', ph.fusion_level,
      'finalAtk', round(ph.final_atk), 'finalHp', round(ph.final_hp),
      'power', round(ph.final_atk * 2 + ph.final_hp),
      'locked', ph.locked,
      'equipped', (EXISTS(SELECT 1 FROM public.pvp_team_slots t WHERE t.hero_id = ph.id)
                OR EXISTS(SELECT 1 FROM public.boss_team_slots b WHERE b.player_hero_id = ph.id)),
      'exclusive', ph.is_season_exclusive
    ) ORDER BY ph.created_at DESC), '[]'::jsonb) INTO v_heroes
  FROM public.player_heroes ph WHERE ph.user_id = v_user AND NOT ph.is_nft_exclusive;
  SELECT coalesce(jsonb_object_agg(rarity, n), '{}'::jsonb) INTO v_counts FROM (
    SELECT rarity, count(*) AS n FROM public.player_heroes WHERE user_id = v_user AND NOT is_nft_exclusive GROUP BY rarity
  ) s;
  RETURN jsonb_build_object(
    'config', cfg, 'balance', v_bal, 'heroes', v_heroes, 'counts', v_counts,
    'fragments', coalesce((SELECT quantity FROM public.player_inventory WHERE user_id = v_user AND item_type='fragments' AND item_code='fragments'), 0),
    'history', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', h.id, 'sourceRarity', h.source_rarity, 'targetRarity', h.target_rarity,
        'success', h.success, 'costFc', h.fusion_cost_fc, 'chance', h.success_chance,
        'rewardHero', h.reward_hero_name, 'fragments', h.fragment_reward, 'createdAt', h.created_at
      ) ORDER BY h.created_at DESC) FROM (
        SELECT * FROM public.hero_rarity_fusion_history WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10
      ) h), '[]'::jsonb)
  );
END; $fn$;

CREATE OR REPLACE FUNCTION public.get_hero_fusion_dashboard(p_telegram_id bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare u uuid; cfg jsonb := hero_fusion_config(); balance numeric := 0; heroes jsonb;
begin
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id;
  if u is null then return jsonb_build_object('config', cfg, 'balance', 0, 'heroes', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(h order by h->>'name'), '[]'::jsonb) into heroes from (
    select jsonb_build_object(
      'heroId', ph.id, 'heroKey', ph.hero_key, 'name', ph.name, 'rarity', ph.rarity, 'level', ph.level,
      'imageUrl', ph.image, 'archetype', ph.archetype, 'stars', ph.fusion_level, 'locked', ph.locked,
      'isNft', ph.is_nft_exclusive, 'nftSerial', ph.nft_serial, 'nftInstance', ph.nft_instance_id,
      'finalAtk', round(ph.final_atk), 'finalHp', round(ph.final_hp),
      'power', round(ph.final_atk * 2 + ph.final_hp),
      'maxLevel', hero_max_level(ph.fusion_level),
      'inTeam', exists(select 1 from pvp_team_slots t where t.hero_id = ph.id)
              or exists(select 1 from boss_team_slots b where b.player_hero_id = ph.id),
      'duplicates', (
        select count(*) from player_heroes d
        where d.user_id = ph.user_id and d.hero_key = ph.hero_key and d.id <> ph.id and not d.locked
          and not d.is_nft_exclusive
          and not exists(select 1 from pvp_team_slots t where t.hero_id = d.id)
          and not exists(select 1 from boss_team_slots b where b.player_hero_id = d.id)
      ),
      'next', case when ph.is_nft_exclusive or ph.fusion_level >= coalesce((cfg->>'max_stars')::int,5) then null else jsonb_build_object(
        'stars', ph.fusion_level + 1,
        'costFc', coalesce((cfg->'cost_fc'->>(ph.fusion_level+1)::text)::numeric, 0),
        'duplicatesRequired', coalesce((cfg->'duplicates'->>(ph.fusion_level+1)::text)::int, 1),
        'bonusPercent', coalesce((cfg->'bonus_percent'->>(ph.fusion_level+1)::text)::numeric, 0),
        'maxLevel', hero_max_level(ph.fusion_level + 1),
        'finalAtk', greatest(1, round((ph.base_atk + coalesce(ph.bonus_atk,0)) * power(1+ph.attack_growth, ph.level-1) * hero_fusion_multiplier(ph.fusion_level+1))),
        'finalHp', greatest(1, round((ph.base_hp + coalesce(ph.bonus_hp,0)) * power(1+ph.hp_growth, ph.level-1) * hero_fusion_multiplier(ph.fusion_level+1)))
      ) end
    ) as h
    from player_heroes ph where ph.user_id = u
  ) s;
  return jsonb_build_object('config', cfg, 'balance', balance, 'heroes', heroes);
end $fn$;

-- AI opponents never use NFT hero art/stats unless explicitly configured by the admin later.
CREATE OR REPLACE FUNCTION public.pvp_generate_bot(p_user uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare
  u game_players%rowtype; v_power int; v_slots int; v_league text; band jsonb;
  v_streak int:=0; rec record; v_target numeric; v_share numeric; v_team jsonb:='[]'::jsonb;
  v_i int; v_rar text; r record; h record; v_k numeric; v_atk numeric; v_hp numeric; v_lvl int;
  v_hero_power numeric; v_total numeric:=0; v_name text; v_color text; v_strategy text; bot_id uuid;
  first_names text[]:=array['Alex','Victor','Kai','Luna','Mika','Raven','Leo','Nova','Dmitri','Arthur','Iris','Sora','Elias','Nyx','Rex','Zara','Milo','Vera','Orion','Kira','Bruno','Talia','Enzo','Freya','Kenji','Lyra','Otto','Sasha','Tarek','Yuna','Caio','Dante','Elza','Gunnar','Hana','Ivan','Jade','Kaya','Lucca','Maya'];
  suffixes text[]:=array['','','','X','7','99','Prime','Zero','Storm','Wolf','Ash','Nyte','Vex','Rider','Blaze','Iron','Shade','Fang','Kron','Sol'];
  colors text[]:=array['#e17076','#7bc862','#65aadd','#a695e7','#ee7aae','#6ec9cb','#faa774','#d97ad9','#8f9ff0','#c9a227'];
begin
  select * into u from game_players where id=p_user;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  v_power:=pvp_team_power(u.id,'attack');
  if v_power<=0 then raise exception 'ATTACK_TEAM_EMPTY'; end if;
  v_slots:=greatest(1,least(5,(select count(*) from pvp_team_slots where user_id=u.id and team_type='attack')));
  v_league:=pvp_league(u.pvp_trophies);
  for rec in select (b.winner_id is not null and b.winner_id=b.attacker_id) w from pvp_battles b where b.attacker_id=u.id order by b.created_at desc limit 10 loop
    if rec.w then v_streak:=v_streak+1; else exit; end if;
  end loop;
  band:=pvp_bot_band(v_league,v_streak);
  v_target:=v_power*((band->>'lo')::numeric+random()*((band->>'hi')::numeric-(band->>'lo')::numeric));

  for v_i in 1..v_slots loop
    v_share:=(v_target/v_slots)*(0.9+random()*0.2);
    select s.rarity into v_rar from (
      select r2.rarity, abs(((r2.min_atk+r2.max_atk)/2*2.2+(r2.min_hp+r2.max_hp)/2*0.18+750)-v_share) gap
      from (values ('common'),('uncommon'),('rare'),('epic'),('legendary'),('mythic'),('ancestral')) rr(rarity)
      cross join lateral (select rr.rarity rarity,* from hero_stat_ranges(rr.rarity)) r2
      order by gap limit 1) s;
    v_rar:=coalesce(v_rar,'common');
    select * into r from hero_stat_ranges(v_rar);
    select hero_key,name,image,coalesce(battle_image,image) battle_image,hero_class,rarity into h
      from hero_catalog where enabled and not is_nft_exclusive and normalize_hero_rarity(rarity)=v_rar order by random() limit 1;
    if h.hero_key is null then
      select hero_key,name,image,coalesce(battle_image,image) battle_image,hero_class,rarity into h
        from hero_catalog where enabled and not is_nft_exclusive order by random() limit 1;
    end if;
    if h.hero_key is null then raise exception 'NO_HERO_CATALOG'; end if;
    v_lvl:=greatest(1,least(60,round(10+random()*40)::int));
    v_atk:=r.min_atk+random()*(r.max_atk-r.min_atk);
    v_hp:=r.min_hp+random()*(r.max_hp-r.min_hp);
    v_k:=greatest(0.5,least(6.0,(v_share-v_lvl*25)/greatest(1,(v_atk*2.2+v_hp*0.18))));
    v_atk:=round(v_atk*v_k); v_hp:=round(v_hp*v_k);
    v_hero_power:=round(v_atk*2.2+v_hp*0.18+v_lvl*25);
    v_total:=v_total+v_hero_power;
    v_team:=v_team||jsonb_build_array(jsonb_build_object(
      'heroId','bot-'||gen_random_uuid()::text,'name',h.name,'imageUrl',h.image,
      'rarity',normalize_hero_rarity(h.rarity),'level',v_lvl,'archetype',h.hero_class,
      'finalAtk',v_atk::int,'finalHp',v_hp::int,'defense',0,'speed',v_lvl,
      'power',v_hero_power::int,'slot',v_i,'isBot',true));
  end loop;

  loop
    v_name:=first_names[1+floor(random()*array_length(first_names,1))::int]||suffixes[1+floor(random()*array_length(suffixes,1))::int];
    exit when not exists(select 1 from pvp_bots where target_user_id=u.id and name=v_name and created_at>now()-interval '2 hours');
  end loop;
  v_color:=colors[1+floor(random()*array_length(colors,1))::int];
  v_strategy:=(array['aggressive','defensive','balanced','finisher','tactical'])[1+floor(random()*5)::int];

  insert into pvp_bots(target_user_id,name,avatar_letter,avatar_color,power,league,trophies,team,strategy)
  values(u.id,v_name,upper(left(v_name,1)),v_color,v_total::int,v_league,
    greatest(0,u.pvp_trophies+(floor(random()*80)::int-40)),v_team,v_strategy)
  returning id into bot_id;

  return jsonb_build_object('userId',bot_id,'name',v_name,'username',null,'avatarUrl',null,
    'avatarLetter',upper(left(v_name,1)),'avatarColor',v_color,'isBot',true,'strategy',v_strategy,
    'trophies',greatest(0,u.pvp_trophies),'league',v_league,'teamPower',v_total::int,
    'wins',greatest(0,floor(random()*80)::int),'defenseTeam',v_team);
end $fn$;
