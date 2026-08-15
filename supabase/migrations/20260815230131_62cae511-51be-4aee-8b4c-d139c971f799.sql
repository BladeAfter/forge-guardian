-- ===================== helpers =====================
CREATE OR REPLACE FUNCTION public.tactical_user_id(p_telegram_id bigint)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v uuid;
BEGIN
  SELECT id INTO v FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.tactical_status_sum(u jsonb, p_types text[])
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT COALESCE(SUM((s->>'v')::numeric), 0)
  FROM jsonb_array_elements(COALESCE(u->'statuses','[]'::jsonb)) s
  WHERE s->>'t' = ANY(p_types)
$$;

CREATE OR REPLACE FUNCTION public.tactical_has_status(u jsonb, p_type text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(u->'statuses','[]'::jsonb)) s
    WHERE s->>'t' = p_type AND COALESCE((s->>'turns')::int,0) > 0
  )
$$;

CREATE OR REPLACE FUNCTION public.tactical_eff_atk(u jsonb)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT GREATEST(1, (u->>'atk')::numeric * (1 + public.tactical_status_sum(u, ARRAY['atk_up','atk_down'])/100))
$$;

CREATE OR REPLACE FUNCTION public.tactical_eff_def(u jsonb)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT GREATEST(0, COALESCE((u->>'def')::numeric,0) * (1 + public.tactical_status_sum(u, ARRAY['def_up'])/100))
$$;

/** Applies raw damage to one unit: shield absorbs first, then HP. */
CREATE OR REPLACE FUNCTION public.tactical_hit(p_units jsonb, p_uid text, p_dmg integer)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $$
DECLARE u jsonb; v_shield int; v_hp int; v_left int := GREATEST(0, p_dmg);
BEGIN
  u := p_units -> p_uid;
  IF u IS NULL OR NOT (u->>'alive')::boolean THEN RETURN p_units; END IF;
  v_shield := COALESCE((u->>'shield')::int, 0);
  v_hp := COALESCE((u->>'hp')::int, 0);
  IF v_shield > 0 THEN
    IF v_shield >= v_left THEN v_shield := v_shield - v_left; v_left := 0;
    ELSE v_left := v_left - v_shield; v_shield := 0; END IF;
  END IF;
  v_hp := GREATEST(0, v_hp - v_left);
  u := u || jsonb_build_object('shield', v_shield, 'hp', v_hp, 'alive', v_hp > 0);
  RETURN jsonb_set(p_units, ARRAY[p_uid], u);
END $$;

-- ===================== team / deck =====================
CREATE OR REPLACE FUNCTION public.tactical_team_json(p_user uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(jsonb_agg(
    public.pvp_hero_json(h) || jsonb_build_object('slot', t.slot, 'class', lower(COALESCE(h.archetype,'warrior')))
    ORDER BY t.slot), '[]'::jsonb)
  FROM public.tactical_teams t
  JOIN public.player_heroes h ON h.id = t.player_hero_id AND h.user_id = p_user
  WHERE t.user_id = p_user
$$;

CREATE OR REPLACE FUNCTION public.tactical_deck_json(p_user uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'position', d.position, 'skillKey', s.skill_key, 'nameKey', s.name_key, 'class', s.hero_class,
    'type', s.skill_type, 'multiplier', s.power_multiplier, 'cooldown', s.cooldown,
    'target', s.target_type, 'duration', s.duration, 'config', s.effect_config
  ) ORDER BY d.position), '[]'::jsonb)
  FROM public.tactical_decks d
  JOIN public.tactical_skills s ON s.skill_key = d.skill_key AND s.enabled
  WHERE d.user_id = p_user
$$;

CREATE OR REPLACE FUNCTION public.tactical_save_team(p_telegram_id bigint, p_slot integer, p_hero_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := public.tactical_user_id(p_telegram_id); h public.player_heroes; v_tpl text;
BEGIN
  IF p_slot < 1 OR p_slot > 3 THEN RAISE EXCEPTION 'INVALID_SLOT'; END IF;
  SELECT * INTO h FROM public.player_heroes WHERE id = p_hero_id AND user_id = v_user;
  IF h.id IS NULL THEN RAISE EXCEPTION 'HERO_NOT_OWNED'; END IF;
  IF public.pvp_hero_block_reason(h) IN ('MARKET','LOCKED') THEN RAISE EXCEPTION 'HERO_UNAVAILABLE'; END IF;
  v_tpl := public.pvp_hero_template_key(h);
  -- one instance per hero template inside the tactical team
  IF EXISTS (
    SELECT 1 FROM public.tactical_teams t
    JOIN public.player_heroes o ON o.id = t.player_hero_id
    WHERE t.user_id = v_user AND t.slot <> p_slot AND public.pvp_hero_template_key(o) = v_tpl
  ) THEN RAISE EXCEPTION 'DUPLICATED_HERO_TEMPLATE'; END IF;
  -- moving a hero already used in another tactical slot frees that slot
  DELETE FROM public.tactical_teams WHERE user_id = v_user AND player_hero_id = p_hero_id;
  INSERT INTO public.tactical_teams (user_id, slot, player_hero_id) VALUES (v_user, p_slot, p_hero_id)
  ON CONFLICT (user_id, slot) DO UPDATE SET player_hero_id = EXCLUDED.player_hero_id, updated_at = now();
  -- deck entries whose class disappeared from the team are dropped
  DELETE FROM public.tactical_decks d WHERE d.user_id = v_user AND d.skill_key <> 'basic_attack'
    AND NOT EXISTS (
      SELECT 1 FROM public.tactical_skills s
      JOIN public.tactical_teams t2 ON t2.user_id = v_user
      JOIN public.player_heroes h2 ON h2.id = t2.player_hero_id
      WHERE s.skill_key = d.skill_key AND (s.hero_class = 'any' OR s.hero_class = lower(COALESCE(h2.archetype,'')))
    );
  RETURN public.tactical_dashboard(p_telegram_id);
END $$;

CREATE OR REPLACE FUNCTION public.tactical_remove_team(p_telegram_id bigint, p_slot integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := public.tactical_user_id(p_telegram_id);
BEGIN
  DELETE FROM public.tactical_teams WHERE user_id = v_user AND slot = p_slot;
  RETURN public.tactical_dashboard(p_telegram_id);
END $$;

CREATE OR REPLACE FUNCTION public.tactical_save_deck(p_telegram_id bigint, p_skill_keys text[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := public.tactical_user_id(p_telegram_id);
        v_cfg jsonb := public.tactical_config();
        v_size int := COALESCE((v_cfg->>'deckSize')::int, 6);
        v_keys text[]; k text; i int := 0; v_classes text[];
BEGIN
  SELECT ARRAY(SELECT DISTINCT x FROM unnest(COALESCE(p_skill_keys, '{}')) x WHERE x <> 'basic_attack') INTO v_keys;
  IF array_length(v_keys, 1) IS DISTINCT FROM v_size THEN RAISE EXCEPTION 'DECK_MUST_HAVE_% SKILLS', v_size; END IF;
  SELECT ARRAY(SELECT DISTINCT lower(COALESCE(h.archetype,'')) FROM public.tactical_teams t
               JOIN public.player_heroes h ON h.id = t.player_hero_id WHERE t.user_id = v_user)
    INTO v_classes;
  IF COALESCE(array_length(v_classes,1),0) = 0 THEN RAISE EXCEPTION 'TACTICAL_TEAM_INCOMPLETE'; END IF;
  FOREACH k IN ARRAY v_keys LOOP
    IF NOT EXISTS (SELECT 1 FROM public.tactical_skills s WHERE s.skill_key = k AND s.enabled
                    AND (s.hero_class = 'any' OR s.hero_class = ANY(v_classes)))
    THEN RAISE EXCEPTION 'SKILL_CLASS_NOT_IN_TEAM'; END IF;
  END LOOP;
  DELETE FROM public.tactical_decks WHERE user_id = v_user;
  FOREACH k IN ARRAY v_keys LOOP
    i := i + 1;
    INSERT INTO public.tactical_decks (user_id, position, skill_key) VALUES (v_user, i, k);
  END LOOP;
  RETURN public.tactical_dashboard(p_telegram_id);
END $$;

-- ===================== dashboard =====================
CREATE OR REPLACE FUNCTION public.tactical_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := public.tactical_user_id(p_telegram_id);
        v_cfg jsonb := public.tactical_config();
        v_admin boolean := public.tactical_is_admin(p_telegram_id);
        r public.tactical_ratings; v_match uuid; v_queue jsonb; v_classes text[]; v_tickets int;
BEGIN
  INSERT INTO public.tactical_ratings (user_id, rating, best_rating)
  VALUES (v_user, COALESCE((v_cfg->>'ratingStart')::int,1000), COALESCE((v_cfg->>'ratingStart')::int,1000))
  ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO r FROM public.tactical_ratings WHERE user_id = v_user;
  SELECT pvp_tickets INTO v_tickets FROM public.game_players WHERE id = v_user;
  SELECT id INTO v_match FROM public.tactical_matches
    WHERE status = 'active' AND (player_a = v_user OR player_b = v_user) ORDER BY created_at DESC LIMIT 1;
  SELECT ARRAY(SELECT DISTINCT lower(COALESCE(h.archetype,'')) FROM public.tactical_teams t
               JOIN public.player_heroes h ON h.id = t.player_hero_id WHERE t.user_id = v_user) INTO v_classes;
  SELECT to_jsonb(q) - 'user_id' INTO v_queue FROM public.tactical_queue q WHERE q.user_id = v_user AND q.status = 'searching';
  RETURN jsonb_build_object(
    'userId', v_user,
    'config', v_cfg,
    'available', COALESCE((v_cfg->>'enabled')::boolean, false) OR v_admin,
    'testMode', v_admin AND NOT COALESCE((v_cfg->>'enabled')::boolean, false),
    'isAdmin', v_admin,
    'rating', r.rating, 'bestRating', r.best_rating, 'league', public.tactical_league(r.rating),
    'wins', r.wins, 'losses', r.losses, 'matches', r.matches,
    'tickets', COALESCE(v_tickets, 0),
    'team', public.tactical_team_json(v_user),
    'deck', public.tactical_deck_json(v_user),
    'teamClasses', to_jsonb(COALESCE(v_classes, '{}')),
    'skills', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'skillKey', s.skill_key, 'nameKey', s.name_key, 'class', s.hero_class, 'type', s.skill_type,
        'multiplier', s.power_multiplier, 'cooldown', s.cooldown, 'target', s.target_type,
        'duration', s.duration, 'config', s.effect_config,
        'unlocked', (s.hero_class = 'any' OR s.hero_class = ANY(COALESCE(v_classes,'{}')))
      ) ORDER BY s.sort_order) FROM public.tactical_skills s WHERE s.enabled AND s.skill_key <> 'basic_attack'), '[]'::jsonb),
    'activeMatchId', v_match,
    'queue', v_queue,
    'ownedHeroes', COALESCE((SELECT jsonb_agg(public.pvp_hero_json(h) || jsonb_build_object('class', lower(COALESCE(h.archetype,'warrior'))) ORDER BY h.created_at DESC)
       FROM public.player_heroes h WHERE h.user_id = v_user AND COALESCE(h.market_locked,false) = false), '[]'::jsonb),
    'petBonuses', COALESCE(public.get_pet_bonuses(v_user), '{}'::jsonb)
  );
END $$;

-- ===================== entry validation =====================
CREATE OR REPLACE FUNCTION public.tactical_validate_entry(p_user uuid, p_require_ticket boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cfg jsonb := public.tactical_config(); v_team int; v_deck int; v_dupes int; v_tickets int;
BEGIN
  SELECT count(*) INTO v_team FROM public.tactical_teams t
    JOIN public.player_heroes h ON h.id = t.player_hero_id AND h.user_id = p_user
   WHERE t.user_id = p_user AND public.pvp_hero_block_reason(h) IS DISTINCT FROM 'MARKET';
  IF v_team <> COALESCE((v_cfg->>'teamSize')::int,3) THEN RAISE EXCEPTION 'TACTICAL_TEAM_INCOMPLETE'; END IF;
  SELECT count(*) - count(DISTINCT public.pvp_hero_template_key(h)) INTO v_dupes
    FROM public.tactical_teams t JOIN public.player_heroes h ON h.id = t.player_hero_id WHERE t.user_id = p_user;
  IF COALESCE(v_dupes,0) > 0 THEN RAISE EXCEPTION 'DUPLICATED_HERO_TEMPLATE'; END IF;
  SELECT count(*) INTO v_deck FROM public.tactical_decks d
    JOIN public.tactical_skills s ON s.skill_key = d.skill_key AND s.enabled WHERE d.user_id = p_user;
  IF v_deck <> COALESCE((v_cfg->>'deckSize')::int,6) THEN RAISE EXCEPTION 'TACTICAL_DECK_INCOMPLETE'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.tactical_decks d JOIN public.tactical_skills s ON s.skill_key = d.skill_key
     WHERE d.user_id = p_user AND s.hero_class <> 'any' AND s.hero_class NOT IN (
       SELECT lower(COALESCE(h.archetype,'')) FROM public.tactical_teams t
       JOIN public.player_heroes h ON h.id = t.player_hero_id WHERE t.user_id = p_user)
  ) THEN RAISE EXCEPTION 'SKILL_CLASS_NOT_IN_TEAM'; END IF;
  IF p_require_ticket THEN
    SELECT pvp_tickets INTO v_tickets FROM public.game_players WHERE id = p_user;
    IF COALESCE(v_tickets,0) < COALESCE((v_cfg->>'ticketCost')::int,1) THEN RAISE EXCEPTION 'NO_PVP_TICKETS'; END IF;
  END IF;
END $$;

-- ===================== unit building =====================
CREATE OR REPLACE FUNCTION public.tactical_build_units(p_user uuid, p_side text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_buffs jsonb := COALESCE(public.get_pet_bonuses(p_user), '{}'::jsonb);
        v_units jsonb := '{}'::jsonb; rec record; v_uid text; v_atk numeric; v_hp numeric; v_def numeric; v_spd numeric;
BEGIN
  FOR rec IN
    SELECT t.slot, h.* FROM public.tactical_teams t
    JOIN public.player_heroes h ON h.id = t.player_hero_id
    WHERE t.user_id = p_user ORDER BY t.slot
  LOOP
    v_uid := p_side || rec.slot::text;
    -- Official hero stats. Arena pet buffs apply once, exactly like the Classic Arena mapping.
    v_atk := GREATEST(1, round(COALESCE(rec.final_atk,1) * (1 + COALESCE((v_buffs->>'pvp_attack_percent')::numeric,0)/100)));
    v_hp  := GREATEST(1, round(COALESCE(rec.final_hp,1) * (1 + COALESCE((v_buffs->>'pvp_hp_percent')::numeric,0)/100)));
    v_def := round(COALESCE(rec.final_hp,0) * 0.09 * (1 + COALESCE((v_buffs->>'pvp_defense_percent')::numeric,0)/100));
    v_spd := GREATEST(1, round((90 + COALESCE(rec.level,1)) * (1 + COALESCE((v_buffs->>'pvp_speed_percent')::numeric,0)/100)));
    v_units := v_units || jsonb_build_object(v_uid, jsonb_build_object(
      'uid', v_uid, 'side', p_side, 'slot', rec.slot, 'heroId', rec.id,
      'name', rec.name, 'image', rec.image, 'rarity', public.normalize_hero_rarity(rec.rarity),
      'level', rec.level, 'class', lower(COALESCE(rec.archetype,'warrior')),
      'atk', v_atk, 'hp', v_hp, 'maxHp', v_hp, 'def', v_def, 'speed', v_spd,
      'crit', GREATEST(5, COALESCE((v_buffs->>'critical_chance_percent')::numeric,0) + 5),
      'critMult', 1.5 + COALESCE((v_buffs->>'critical_damage_percent')::numeric,0)/100,
      'shield', 0, 'alive', true, 'statuses', '[]'::jsonb, 'cds', '{}'::jsonb,
      'isNft', COALESCE(rec.is_nft_exclusive,false)
    ));
  END LOOP;
  RETURN v_units;
END $$;

-- ===================== match creation =====================
CREATE OR REPLACE FUNCTION public.tactical_start_match(p_a uuid, p_b uuid, p_practice boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cfg jsonb := public.tactical_config(); v_cost int := COALESCE((v_cfg->>'ticketCost')::int,1);
        v_match uuid; v_units jsonb; v_b_units jsonb; v_deck_a jsonb; v_deck_b jsonb; v_seed text;
        v_rating_a int; v_rating_b int;
BEGIN
  PERFORM public.tactical_validate_entry(p_a, NOT p_practice);
  IF NOT p_practice THEN PERFORM public.tactical_validate_entry(p_b, true); END IF;

  v_seed := encode(digest(p_a::text || COALESCE(p_b::text,'ai') || clock_timestamp()::text, 'sha256'), 'hex');
  v_units := public.tactical_build_units(p_a, 'a');
  IF p_practice THEN
    -- Practice/test mirror: same official stats, AI controlled, no rating and no ticket.
    v_b_units := (SELECT jsonb_object_agg(replace(key,'a','b'),
        value || jsonb_build_object('uid', replace(key,'a','b'), 'side','b'))
      FROM jsonb_each(v_units));
    v_deck_b := public.tactical_deck_json(p_a);
  ELSE
    v_b_units := public.tactical_build_units(p_b, 'b');
    v_deck_b := public.tactical_deck_json(p_b);
  END IF;
  v_deck_a := public.tactical_deck_json(p_a);

  SELECT rating INTO v_rating_a FROM public.tactical_ratings WHERE user_id = p_a;
  IF NOT p_practice THEN SELECT rating INTO v_rating_b FROM public.tactical_ratings WHERE user_id = p_b; END IF;

  INSERT INTO public.tactical_matches (player_a, player_b, is_practice, seed, state, rating_a, rating_b)
  VALUES (p_a, CASE WHEN p_practice THEN NULL ELSE p_b END, p_practice, v_seed,
    jsonb_build_object(
      'units', v_units || v_b_units,
      'decks', jsonb_build_object('a', v_deck_a, 'b', v_deck_b),
      'names', jsonb_build_object(
        'a', (SELECT COALESCE(display_name, username, 'Player') FROM public.game_players WHERE id = p_a),
        'b', CASE WHEN p_practice THEN 'AI TRAINING'
             ELSE (SELECT COALESCE(display_name, username, 'Player') FROM public.game_players WHERE id = p_b) END),
      'avatars', jsonb_build_object(
        'a', (SELECT avatar_url FROM public.game_players WHERE id = p_a),
        'b', CASE WHEN p_practice THEN NULL ELSE (SELECT avatar_url FROM public.game_players WHERE id = p_b) END)
    ), v_rating_a, v_rating_b)
  RETURNING id INTO v_match;

  -- Tickets are charged ONLY here: match found + battle initialized.
  IF NOT p_practice THEN
    UPDATE public.game_players SET pvp_tickets = pvp_tickets - v_cost WHERE id IN (p_a, p_b);
  END IF;
  RETURN v_match;
END $$;

-- ===================== queue =====================
CREATE OR REPLACE FUNCTION public.tactical_queue_join(p_telegram_id bigint, p_practice boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := public.tactical_user_id(p_telegram_id);
        v_cfg jsonb := public.tactical_config(); v_rating int; v_match uuid;
BEGIN
  IF NOT COALESCE((v_cfg->>'enabled')::boolean,false) AND NOT public.tactical_is_admin(p_telegram_id)
    THEN RAISE EXCEPTION 'TACTICAL_DISABLED'; END IF;
  IF p_practice AND NOT public.tactical_is_admin(p_telegram_id) THEN RAISE EXCEPTION 'TACTICAL_PRACTICE_FORBIDDEN'; END IF;
  IF EXISTS (SELECT 1 FROM public.tactical_matches WHERE status='active' AND (player_a=v_user OR player_b=v_user))
    THEN RAISE EXCEPTION 'TACTICAL_MATCH_IN_PROGRESS'; END IF;
  PERFORM public.tactical_validate_entry(v_user, NOT p_practice);
  IF p_practice THEN
    v_match := public.tactical_start_match(v_user, NULL, true);
    DELETE FROM public.tactical_queue WHERE user_id = v_user;
    RETURN jsonb_build_object('status','matched','matchId',v_match,'practice',true);
  END IF;
  SELECT rating INTO v_rating FROM public.tactical_ratings WHERE user_id = v_user;
  INSERT INTO public.tactical_queue (user_id, rating, status, match_id)
  VALUES (v_user, COALESCE(v_rating,1000), 'searching', NULL)
  ON CONFLICT (user_id) DO UPDATE SET status='searching', match_id=NULL, rating=EXCLUDED.rating,
    enqueued_at=now(), updated_at=now();
  RETURN public.tactical_queue_status(p_telegram_id);
END $$;

CREATE OR REPLACE FUNCTION public.tactical_queue_cancel(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := public.tactical_user_id(p_telegram_id); v_match uuid;
BEGIN
  SELECT match_id INTO v_match FROM public.tactical_queue WHERE user_id = v_user AND status='matched';
  IF v_match IS NOT NULL THEN RETURN jsonb_build_object('status','matched','matchId',v_match); END IF;
  DELETE FROM public.tactical_queue WHERE user_id = v_user; -- no ticket was ever charged in queue
  RETURN jsonb_build_object('status','idle');
END $$;

/** Polled by the client while searching. Pairs the two closest ratings and creates the match. */
CREATE OR REPLACE FUNCTION public.tactical_queue_status(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := public.tactical_user_id(p_telegram_id); q public.tactical_queue;
        v_opponent uuid; v_match uuid; v_window int;
BEGIN
  SELECT id INTO v_match FROM public.tactical_matches
   WHERE status='active' AND (player_a=v_user OR player_b=v_user) ORDER BY created_at DESC LIMIT 1;
  IF v_match IS NOT NULL THEN
    DELETE FROM public.tactical_queue WHERE user_id = v_user;
    RETURN jsonb_build_object('status','matched','matchId',v_match);
  END IF;
  SELECT * INTO q FROM public.tactical_queue WHERE user_id = v_user FOR UPDATE;
  IF q.user_id IS NULL OR q.status = 'cancelled' THEN RETURN jsonb_build_object('status','idle'); END IF;
  -- rating window widens with the waiting time so nobody waits forever
  v_window := 100 + LEAST(1500, GREATEST(0, EXTRACT(EPOCH FROM (now() - q.enqueued_at))::int) * 25);
  SELECT o.user_id INTO v_opponent FROM public.tactical_queue o
   WHERE o.user_id <> v_user AND o.status='searching' AND abs(o.rating - q.rating) <= v_window
     AND o.updated_at > now() - interval '90 seconds'
   ORDER BY abs(o.rating - q.rating), o.enqueued_at LIMIT 1;
  IF v_opponent IS NULL THEN
    UPDATE public.tactical_queue SET updated_at = now() WHERE user_id = v_user;
    RETURN jsonb_build_object('status','searching','waitedSeconds', EXTRACT(EPOCH FROM (now()-q.enqueued_at))::int);
  END IF;
  BEGIN
    v_match := public.tactical_start_match(v_user, v_opponent, false);
  EXCEPTION WHEN OTHERS THEN
    DELETE FROM public.tactical_queue WHERE user_id = v_opponent; -- opponent became invalid
    RETURN jsonb_build_object('status','searching','waitedSeconds', EXTRACT(EPOCH FROM (now()-q.enqueued_at))::int);
  END;
  DELETE FROM public.tactical_queue WHERE user_id IN (v_user, v_opponent);
  RETURN jsonb_build_object('status','matched','matchId',v_match);
END $$;

-- ===================== match state (reconnect-safe) =====================
CREATE OR REPLACE FUNCTION public.tactical_match_json(p_match uuid, p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE m public.tactical_matches; v_side text; v_cfg jsonb := public.tactical_config();
        v_deadline timestamptz; v_submitted boolean;
BEGIN
  SELECT * INTO m FROM public.tactical_matches WHERE id = p_match;
  IF m.id IS NULL THEN RAISE EXCEPTION 'TACTICAL_MATCH_NOT_FOUND'; END IF;
  IF p_user NOT IN (COALESCE(m.player_a,'00000000-0000-0000-0000-000000000000'::uuid), COALESCE(m.player_b,'00000000-0000-0000-0000-000000000000'::uuid))
    THEN RAISE EXCEPTION 'TACTICAL_MATCH_FORBIDDEN'; END IF;
  v_side := CASE WHEN m.player_a = p_user THEN 'a' ELSE 'b' END;
  UPDATE public.tactical_matches SET a_seen_at = CASE WHEN v_side='a' THEN now() ELSE a_seen_at END,
                                     b_seen_at = CASE WHEN v_side='b' THEN now() ELSE b_seen_at END
   WHERE id = p_match;
  v_deadline := m.turn_started_at + make_interval(secs => COALESCE((v_cfg->>'turnTimerSeconds')::int,15));
  SELECT EXISTS(SELECT 1 FROM public.tactical_actions WHERE match_id=p_match AND turn=m.turn AND side=v_side) INTO v_submitted;
  RETURN jsonb_build_object(
    'matchId', m.id, 'status', m.status, 'turn', m.turn, 'side', v_side,
    'practice', m.is_practice,
    'units', m.state->'units',
    'deck', COALESCE(m.state->'decks'->v_side, '[]'::jsonb),
    'you', COALESCE(m.state->'names'->>v_side, 'You'),
    'opponent', COALESCE(m.state->'names'->>(CASE WHEN v_side='a' THEN 'b' ELSE 'a' END), 'Opponent'),
    'opponentAvatar', m.state->'avatars'->>(CASE WHEN v_side='a' THEN 'b' ELSE 'a' END),
    'yourAvatar', m.state->'avatars'->>v_side,
    'submitted', v_submitted,
    'deadline', v_deadline, 'secondsLeft', GREATEST(0, EXTRACT(EPOCH FROM (v_deadline - now()))::int),
    'turnTimerSeconds', COALESCE((v_cfg->>'turnTimerSeconds')::int,15),
    'damageScale', m.damage_scale,
    'winner', CASE WHEN m.status='finished' THEN (CASE WHEN m.winner_id = p_user THEN 'you' WHEN m.winner_id IS NULL THEN 'draw' ELSE 'opponent' END) ELSE NULL END,
    'ratingDelta', CASE WHEN v_side='a' THEN m.rating_a_delta ELSE m.rating_b_delta END,
    'rating', (SELECT rating FROM public.tactical_ratings WHERE user_id = p_user),
    'log', COALESCE((SELECT jsonb_agg(jsonb_build_object('turn', l.turn, 'entries', l.entries) ORDER BY l.turn)
                     FROM public.tactical_battle_log l WHERE l.match_id = p_match AND l.turn >= GREATEST(1, m.turn - 3)), '[]'::jsonb)
  );
END $$;
