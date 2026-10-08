-- expose per-side cooldowns in the reconnect payload
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
    'matchId', m.id, 'status', m.status, 'turn', m.turn, 'side', v_side, 'practice', m.is_practice,
    'units', m.state->'units',
    'deck', COALESCE(m.state->'decks'->v_side, '[]'::jsonb),
    'cooldowns', COALESCE(m.state->'cds'->v_side, '{}'::jsonb),
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

/** Finishes a match: Elo-style rating, record and audit trail. */
CREATE OR REPLACE FUNCTION public.tactical_finish(p_match uuid, p_winner_side text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE m public.tactical_matches; v_k int := COALESCE((public.tactical_config()->>'ratingK')::int,32);
        ra int; rb int; ea numeric; da int; db int; v_winner uuid;
BEGIN
  SELECT * INTO m FROM public.tactical_matches WHERE id = p_match FOR UPDATE;
  IF m.status <> 'active' THEN RETURN; END IF;
  v_winner := CASE WHEN p_winner_side = 'a' THEN m.player_a WHEN p_winner_side = 'b' THEN m.player_b ELSE NULL END;
  IF m.is_practice OR m.player_b IS NULL THEN
    UPDATE public.tactical_matches SET status='finished', winner_id=v_winner, finished_at=now(),
      rating_a_delta=0, rating_b_delta=0 WHERE id = p_match;
    RETURN;
  END IF;
  SELECT rating INTO ra FROM public.tactical_ratings WHERE user_id = m.player_a;
  SELECT rating INTO rb FROM public.tactical_ratings WHERE user_id = m.player_b;
  ea := 1.0 / (1.0 + power(10.0, (rb - ra)::numeric / 400.0));
  da := round(v_k * ((CASE WHEN p_winner_side='a' THEN 1 ELSE 0 END) - ea));
  db := -da;
  UPDATE public.tactical_ratings SET rating = GREATEST(100, rating + da), best_rating = GREATEST(best_rating, GREATEST(100, rating + da)),
    wins = wins + (CASE WHEN p_winner_side='a' THEN 1 ELSE 0 END), losses = losses + (CASE WHEN p_winner_side='a' THEN 0 ELSE 1 END),
    matches = matches + 1, last_match_at = now(), updated_at = now() WHERE user_id = m.player_a;
  UPDATE public.tactical_ratings SET rating = GREATEST(100, rating + db), best_rating = GREATEST(best_rating, GREATEST(100, rating + db)),
    wins = wins + (CASE WHEN p_winner_side='b' THEN 1 ELSE 0 END), losses = losses + (CASE WHEN p_winner_side='b' THEN 0 ELSE 1 END),
    matches = matches + 1, last_match_at = now(), updated_at = now() WHERE user_id = m.player_b;
  UPDATE public.tactical_matches SET status='finished', winner_id=v_winner, finished_at=now(),
    rating_a_delta=da, rating_b_delta=db WHERE id = p_match;
END $$;

/**
 * Server-authoritative turn resolution. Runs only when both actions exist, or when the
 * 15s timer expired (missing side falls back to BASIC ATTACK, which also covers a
 * disconnected player and the AI training opponent).
 */
CREATE OR REPLACE FUNCTION public.tactical_resolve_turn(p_match uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE m public.tactical_matches; v_cfg jsonb := public.tactical_config();
        v_expired boolean; v_units jsonb; v_cds jsonb; v_log jsonb := '[]'::jsonb;
        v_acts jsonb := '{}'::jsonb; s text; v_side_act jsonb; v_order text[]; v_speeds numeric[];
        v_uid text; v_caster jsonb; v_skill public.tactical_skills; v_targets text[]; tgt text;
        v_dmg int; v_heal int; v_val numeric; v_rand numeric; v_crit boolean; v_before int;
        v_hp_sum int; v_prev_sum int; v_alive_a int; v_alive_b int; v_enemy text; v_scale numeric;
        v_key text; v_i int;
BEGIN
  SELECT * INTO m FROM public.tactical_matches WHERE id = p_match FOR UPDATE;
  IF m.id IS NULL OR m.status <> 'active' THEN RETURN false; END IF;
  v_expired := now() >= m.turn_started_at + make_interval(secs => COALESCE((v_cfg->>'turnTimerSeconds')::int,15));

  -- collect submitted actions; fill missing ones only when allowed
  FOREACH s IN ARRAY ARRAY['a','b'] LOOP
    SELECT jsonb_build_object('skill', a.skill_key, 'target', a.target_uid, 'auto', a.auto)
      INTO v_side_act FROM public.tactical_actions a
     WHERE a.match_id = p_match AND a.turn = m.turn AND a.side = s;
    IF v_side_act IS NULL THEN
      IF s = 'b' AND (m.is_practice OR m.player_b IS NULL) THEN
        v_side_act := jsonb_build_object('skill','basic_attack','target',NULL,'auto',true);
      ELSIF v_expired THEN
        v_side_act := jsonb_build_object('skill','basic_attack','target',NULL,'auto',true);
      ELSE
        RETURN false; -- still waiting for this player
      END IF;
      INSERT INTO public.tactical_actions (match_id, turn, side, user_id, skill_key, target_uid, auto)
      VALUES (p_match, m.turn, s, CASE WHEN s='a' THEN m.player_a ELSE m.player_b END, 'basic_attack', NULL, true)
      ON CONFLICT DO NOTHING;
    END IF;
    v_acts := v_acts || jsonb_build_object(s, v_side_act);
  END LOOP;

  v_units := m.state->'units';
  v_cds := COALESCE(m.state->'cds', jsonb_build_object('a','{}'::jsonb,'b','{}'::jsonb));
  v_scale := COALESCE(m.damage_scale, 1);
  SELECT COALESCE(SUM((u.value->>'hp')::int),0) INTO v_prev_sum FROM jsonb_each(v_units) u;

  -- turn order: caster speed desc, deterministic tie-break from the battle seed
  v_order := ARRAY[]::text[];
  DECLARE spd_a numeric := -1; spd_b numeric := -1; cast_a text; cast_b text;
  BEGIN
    FOREACH s IN ARRAY ARRAY['a','b'] LOOP
      SELECT s2.* INTO v_skill FROM public.tactical_skills s2 WHERE s2.skill_key = (v_acts->s->>'skill');
      SELECT u.key INTO v_uid FROM jsonb_each(v_units) u
       WHERE u.value->>'side' = s AND (u.value->>'alive')::boolean
         AND (v_skill.hero_class = 'any' OR u.value->>'class' = v_skill.hero_class)
       ORDER BY (u.value->>'speed')::numeric DESC, u.key LIMIT 1;
      IF v_uid IS NULL THEN
        SELECT u.key INTO v_uid FROM jsonb_each(v_units) u
         WHERE u.value->>'side' = s AND (u.value->>'alive')::boolean
         ORDER BY (u.value->>'speed')::numeric DESC, u.key LIMIT 1;
        v_acts := jsonb_set(v_acts, ARRAY[s,'skill'], '"basic_attack"'::jsonb);
      END IF;
      IF s='a' THEN cast_a := v_uid; spd_a := COALESCE((v_units->v_uid->>'speed')::numeric,0);
      ELSE cast_b := v_uid; spd_b := COALESCE((v_units->v_uid->>'speed')::numeric,0); END IF;
    END LOOP;
    IF cast_a IS NULL AND cast_b IS NULL THEN RETURN false; END IF;
    IF spd_a > spd_b THEN v_order := ARRAY['a','b'];
    ELSIF spd_b > spd_a THEN v_order := ARRAY['b','a'];
    ELSIF public.tactical_rand(m.seed || ':' || m.turn::text) >= 0.5 THEN v_order := ARRAY['a','b'];
    ELSE v_order := ARRAY['b','a']; END IF;
    v_acts := v_acts || jsonb_build_object('casters', jsonb_build_object('a', cast_a, 'b', cast_b));
  END;

  -- apply both actions
  FOREACH s IN ARRAY v_order LOOP
    v_uid := v_acts->'casters'->>s;
    IF v_uid IS NULL THEN CONTINUE; END IF;
    v_caster := v_units->v_uid;
    IF v_caster IS NULL OR NOT (v_caster->>'alive')::boolean THEN CONTINUE; END IF;
    IF public.tactical_has_status(v_caster, 'stun') THEN
      v_log := v_log || jsonb_build_object('side', s, 'caster', v_uid, 'skill', 'stunned', 'entries', '[]'::jsonb);
      CONTINUE;
    END IF;
    v_key := v_acts->s->>'skill';
    -- silence forces the basic attack; cooldown abuse is blocked here too
    IF v_key <> 'basic_attack' AND (public.tactical_has_status(v_caster,'silence')
        OR COALESCE((v_cds->s->>v_key)::int,0) > 0) THEN v_key := 'basic_attack'; END IF;
    SELECT * INTO v_skill FROM public.tactical_skills WHERE skill_key = v_key AND enabled;
    IF v_skill.skill_key IS NULL THEN SELECT * INTO v_skill FROM public.tactical_skills WHERE skill_key='basic_attack'; END IF;
    v_enemy := CASE WHEN s='a' THEN 'b' ELSE 'a' END;

    -- resolve targets
    v_targets := ARRAY[]::text[];
    IF v_skill.target_type = 'SELF' THEN v_targets := ARRAY[v_uid];
    ELSIF v_skill.target_type = 'ALL_ENEMIES' THEN
      SELECT ARRAY(SELECT u.key FROM jsonb_each(v_units) u WHERE u.value->>'side'=v_enemy AND (u.value->>'alive')::boolean ORDER BY u.key) INTO v_targets;
    ELSIF v_skill.target_type = 'ALL_ALLIES' THEN
      SELECT ARRAY(SELECT u.key FROM jsonb_each(v_units) u WHERE u.value->>'side'=s AND (u.value->>'alive')::boolean ORDER BY u.key) INTO v_targets;
    ELSE
      tgt := v_acts->s->>'target';
      IF tgt IS NOT NULL AND v_units ? tgt AND (v_units->tgt->>'alive')::boolean
         AND ((v_skill.target_type='SINGLE_ENEMY' AND v_units->tgt->>'side'=v_enemy)
           OR (v_skill.target_type='SINGLE_ALLY' AND v_units->tgt->>'side'=s))
      THEN v_targets := ARRAY[tgt];
      ELSE
        SELECT ARRAY(SELECT u.key FROM jsonb_each(v_units) u
          WHERE u.value->>'side' = (CASE WHEN v_skill.target_type='SINGLE_ALLY' THEN s ELSE v_enemy END)
            AND (u.value->>'alive')::boolean
          ORDER BY (u.value->>'hp')::int ASC, u.key LIMIT 1) INTO v_targets;
      END IF;
    END IF;

    v_i := 0;
    FOREACH tgt IN ARRAY COALESCE(v_targets, ARRAY[]::text[]) LOOP
      v_i := v_i + 1;
      IF NOT (v_units->tgt->>'alive')::boolean THEN CONTINUE; END IF;
      v_rand := public.tactical_rand(m.seed || ':' || m.turn::text || ':' || v_uid || ':' || tgt || ':' || v_i::text);
      IF v_skill.skill_type IN ('DAMAGE','STUN') THEN
        v_val := public.tactical_eff_atk(v_units->v_uid) * v_skill.power_multiplier * v_scale;
        v_val := v_val * (1 - public.tactical_eff_def(v_units->tgt) / (public.tactical_eff_def(v_units->tgt) + 800));
        v_crit := v_rand * 100 < (COALESCE((v_units->v_uid->>'crit')::numeric,5) + public.tactical_status_sum(v_units->v_uid, ARRAY['crit_up']));
        IF v_crit THEN v_val := v_val * COALESCE((v_units->v_uid->>'critMult')::numeric,1.5); END IF;
        IF (v_skill.effect_config ? 'bonusVsLowHp') AND (v_units->tgt->>'hp')::numeric < (v_units->tgt->>'maxHp')::numeric * 0.35 THEN
          v_val := v_val * (1 + (v_skill.effect_config->>'bonusVsLowHp')::numeric / 100);
        END IF;
        v_dmg := GREATEST(1, round(v_val))::int;
        v_before := (v_units->tgt->>'hp')::int;
        v_units := public.tactical_hit(v_units, tgt, v_dmg);
        IF v_skill.skill_type = 'STUN' AND (v_units->tgt->>'alive')::boolean
           AND NOT public.tactical_has_status(v_units->tgt, 'cc_immune') THEN
          -- stun lasts at most 1 turn and always grants CC immunity right after
          v_units := jsonb_set(v_units, ARRAY[tgt,'statuses'],
            COALESCE(v_units->tgt->'statuses','[]'::jsonb)
            || jsonb_build_object('t','stun','v',0,'turns',1)
            || jsonb_build_object('t','cc_immune','v',0,'turns',2));
        END IF;
        v_log := v_log || jsonb_build_object('side',s,'caster',v_uid,'skill',v_skill.skill_key,'target',tgt,
          'damage',v_dmg,'crit',v_crit,'hpBefore',v_before,'hpAfter',(v_units->tgt->>'hp')::int,
          'killed', NOT (v_units->tgt->>'alive')::boolean);
      ELSIF v_skill.skill_type = 'HEAL' THEN
        v_heal := GREATEST(1, round(public.tactical_eff_atk(v_units->v_uid) * v_skill.power_multiplier))::int;
        v_before := (v_units->tgt->>'hp')::int;
        v_units := jsonb_set(v_units, ARRAY[tgt,'hp'],
          to_jsonb(LEAST((v_units->tgt->>'maxHp')::int, v_before + v_heal)));
        v_log := v_log || jsonb_build_object('side',s,'caster',v_uid,'skill',v_skill.skill_key,'target',tgt,
          'heal',(v_units->tgt->>'hp')::int - v_before,'hpAfter',(v_units->tgt->>'hp')::int);
      ELSIF v_skill.skill_type = 'SHIELD' THEN
        v_val := round(public.tactical_eff_atk(v_units->v_uid) * v_skill.power_multiplier);
        v_units := jsonb_set(v_units, ARRAY[tgt,'shield'], to_jsonb(COALESCE((v_units->tgt->>'shield')::int,0) + v_val::int));
        v_units := jsonb_set(v_units, ARRAY[tgt,'statuses'], COALESCE(v_units->tgt->'statuses','[]'::jsonb)
          || jsonb_build_object('t','shield','v',v_val,'turns',GREATEST(1, v_skill.duration)));
        v_log := v_log || jsonb_build_object('side',s,'caster',v_uid,'skill',v_skill.skill_key,'target',tgt,'shield',v_val::int);
      ELSIF v_skill.skill_type IN ('BUFF','DEBUFF') THEN
        v_units := jsonb_set(v_units, ARRAY[tgt,'statuses'], COALESCE(v_units->tgt->'statuses','[]'::jsonb)
          || (CASE
              WHEN v_skill.effect_config ? 'atkPercent' THEN jsonb_build_array(jsonb_build_object('t', CASE WHEN (v_skill.effect_config->>'atkPercent')::numeric >= 0 THEN 'atk_up' ELSE 'atk_down' END,'v',(v_skill.effect_config->>'atkPercent')::numeric,'turns',GREATEST(1,v_skill.duration)))
              WHEN v_skill.effect_config ? 'defPercent' THEN jsonb_build_array(jsonb_build_object('t','def_up','v',(v_skill.effect_config->>'defPercent')::numeric,'turns',GREATEST(1,v_skill.duration)))
              WHEN v_skill.effect_config ? 'critPercent' THEN jsonb_build_array(jsonb_build_object('t','crit_up','v',(v_skill.effect_config->>'critPercent')::numeric,'turns',GREATEST(1,v_skill.duration)))
              WHEN v_skill.effect_config ? 'silence' THEN jsonb_build_array(jsonb_build_object('t','silence','v',0,'turns',GREATEST(1,v_skill.duration)))
              ELSE '[]'::jsonb END));
        v_log := v_log || jsonb_build_object('side',s,'caster',v_uid,'skill',v_skill.skill_key,'target',tgt,'status',v_skill.effect_config);
      ELSIF v_skill.skill_type = 'DOT' THEN
        v_val := round(public.tactical_eff_atk(v_units->v_uid) * v_skill.power_multiplier);
        v_units := jsonb_set(v_units, ARRAY[tgt,'statuses'], COALESCE(v_units->tgt->'statuses','[]'::jsonb)
          || jsonb_build_object('t','bleed','v',v_val,'turns',GREATEST(1,v_skill.duration)));
        v_log := v_log || jsonb_build_object('side',s,'caster',v_uid,'skill',v_skill.skill_key,'target',tgt,'dot',v_val::int);
      ELSIF v_skill.skill_type = 'CLEANSE' THEN
        v_units := jsonb_set(v_units, ARRAY[tgt,'statuses'], COALESCE((
          SELECT jsonb_agg(x) FROM jsonb_array_elements(COALESCE(v_units->tgt->'statuses','[]'::jsonb)) x
           WHERE x->>'t' NOT IN ('bleed','stun','silence','atk_down')), '[]'::jsonb));
        v_log := v_log || jsonb_build_object('side',s,'caster',v_uid,'skill',v_skill.skill_key,'target',tgt,'cleanse',true);
      END IF;
    END LOOP;

    IF v_skill.cooldown > 0 THEN
      v_cds := jsonb_set(v_cds, ARRAY[s, v_skill.skill_key], to_jsonb(v_skill.cooldown + 1));
    END IF;
  END LOOP;

  -- end of turn: DOT ticks, status/shield/cooldown decay
  FOR v_uid IN SELECT u.key FROM jsonb_each(v_units) u LOOP
    IF (v_units->v_uid->>'alive')::boolean THEN
      v_val := public.tactical_status_sum(v_units->v_uid, ARRAY['bleed']);
      IF v_val > 0 THEN
        v_units := public.tactical_hit(v_units, v_uid, GREATEST(1, round(v_val))::int);
        v_log := v_log || jsonb_build_object('side', v_units->v_uid->>'side', 'target', v_uid, 'skill','bleed_tick',
          'damage', GREATEST(1, round(v_val))::int, 'hpAfter', (v_units->v_uid->>'hp')::int);
      END IF;
    END IF;
    v_units := jsonb_set(v_units, ARRAY[v_uid,'statuses'], COALESCE((
      SELECT jsonb_agg(x || jsonb_build_object('turns', (x->>'turns')::int - 1))
        FROM jsonb_array_elements(COALESCE(v_units->v_uid->'statuses','[]'::jsonb)) x
       WHERE (x->>'turns')::int - 1 > 0), '[]'::jsonb));
    IF NOT public.tactical_has_status(v_units->v_uid, 'shield') THEN
      v_units := jsonb_set(v_units, ARRAY[v_uid,'shield'], '0'::jsonb);
    END IF;
  END LOOP;

  FOREACH s IN ARRAY ARRAY['a','b'] LOOP
    v_cds := jsonb_set(v_cds, ARRAY[s], COALESCE((
      SELECT jsonb_object_agg(c.key, GREATEST(0, (c.value)::text::int - 1))
        FROM jsonb_each(COALESCE(v_cds->s,'{}'::jsonb)) c
       WHERE (c.value)::text::int - 1 > 0), '{}'::jsonb));
  END LOOP;

  -- anti-stalemate: pure damage escalation, never an automatic defeat
  SELECT COALESCE(SUM((u.value->>'hp')::int),0) INTO v_hp_sum FROM jsonb_each(v_units) u;
  IF v_hp_sum = v_prev_sum THEN
    m.stagnant_turns := m.stagnant_turns + 1;
    IF m.stagnant_turns >= COALESCE((v_cfg->>'stalemateTurns')::int,5) THEN
      v_scale := v_scale + COALESCE((v_cfg->>'stalemateEscalation')::numeric, 0.10);
    END IF;
  ELSE
    m.stagnant_turns := 0;
  END IF;

  INSERT INTO public.tactical_battle_log (match_id, turn, entries) VALUES (p_match, m.turn, v_log);

  UPDATE public.tactical_matches
     SET state = m.state || jsonb_build_object('units', v_units, 'cds', v_cds),
         turn = m.turn + 1, turn_started_at = now(),
         stagnant_turns = m.stagnant_turns, damage_scale = v_scale
   WHERE id = p_match;

  SELECT count(*) INTO v_alive_a FROM jsonb_each(v_units) u WHERE u.value->>'side'='a' AND (u.value->>'alive')::boolean;
  SELECT count(*) INTO v_alive_b FROM jsonb_each(v_units) u WHERE u.value->>'side'='b' AND (u.value->>'alive')::boolean;
  IF v_alive_a = 0 OR v_alive_b = 0 THEN
    PERFORM public.tactical_finish(p_match, CASE WHEN v_alive_b = 0 AND v_alive_a > 0 THEN 'a'
                                                 WHEN v_alive_a = 0 AND v_alive_b > 0 THEN 'b' ELSE NULL END);
  END IF;
  RETURN true;
END $$;

/** The client only sends skill + target + match. Everything else is decided here. */
CREATE OR REPLACE FUNCTION public.tactical_submit_action(p_telegram_id bigint, p_match_id uuid, p_skill_key text, p_target_uid text, p_client_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := public.tactical_user_id(p_telegram_id); m public.tactical_matches; v_side text; v_key text;
BEGIN
  SELECT * INTO m FROM public.tactical_matches WHERE id = p_match_id FOR UPDATE;
  IF m.id IS NULL THEN RAISE EXCEPTION 'TACTICAL_MATCH_NOT_FOUND'; END IF;
  IF v_user NOT IN (COALESCE(m.player_a,'00000000-0000-0000-0000-000000000000'::uuid), COALESCE(m.player_b,'00000000-0000-0000-0000-000000000000'::uuid))
    THEN RAISE EXCEPTION 'TACTICAL_MATCH_FORBIDDEN'; END IF;
  IF m.status <> 'active' THEN RETURN public.tactical_match_json(p_match_id, v_user); END IF;
  v_side := CASE WHEN m.player_a = v_user THEN 'a' ELSE 'b' END;
  v_key := COALESCE(NULLIF(btrim(p_skill_key), ''), 'basic_attack');
  IF v_key <> 'basic_attack' THEN
    IF NOT EXISTS (SELECT 1 FROM public.tactical_decks d JOIN public.tactical_skills s ON s.skill_key=d.skill_key AND s.enabled
                    WHERE d.user_id = v_user AND d.skill_key = v_key)
      THEN RAISE EXCEPTION 'SKILL_NOT_IN_DECK'; END IF;
    IF COALESCE((m.state->'cds'->v_side->>v_key)::int, 0) > 0 THEN RAISE EXCEPTION 'SKILL_ON_COOLDOWN'; END IF;
  END IF;
  -- duplicated submissions of the same turn are ignored (unique per match/turn/side)
  INSERT INTO public.tactical_actions (match_id, turn, side, user_id, skill_key, target_uid, client_key)
  VALUES (p_match_id, m.turn, v_side, v_user, v_key, NULLIF(btrim(COALESCE(p_target_uid,'')),''), p_client_key)
  ON CONFLICT (match_id, turn, side) DO NOTHING;
  PERFORM public.tactical_resolve_turn(p_match_id);
  RETURN public.tactical_match_json(p_match_id, v_user);
END $$;

/** Polled by the arena screen: pushes the timer forward (auto basic attack) and returns state. */
CREATE OR REPLACE FUNCTION public.tactical_match_tick(p_telegram_id bigint, p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := public.tactical_user_id(p_telegram_id);
BEGIN
  PERFORM public.tactical_resolve_turn(p_match_id);
  RETURN public.tactical_match_json(p_match_id, v_user);
END $$;

-- ===================== history / ranking =====================
CREATE OR REPLACE FUNCTION public.tactical_history(p_telegram_id bigint, p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := public.tactical_user_id(p_telegram_id);
BEGIN
  RETURN COALESCE((SELECT jsonb_agg(x ORDER BY x->>'createdAt' DESC) FROM (
    SELECT jsonb_build_object(
      'matchId', m.id,
      'opponent', COALESCE(m.state->'names'->>(CASE WHEN m.player_a = v_user THEN 'b' ELSE 'a' END), 'AI'),
      'practice', m.is_practice,
      'result', CASE WHEN m.winner_id IS NULL THEN 'draw' WHEN m.winner_id = v_user THEN 'win' ELSE 'loss' END,
      'ratingChange', CASE WHEN m.player_a = v_user THEN COALESCE(m.rating_a_delta,0) ELSE COALESCE(m.rating_b_delta,0) END,
      'turns', m.turn, 'createdAt', m.created_at
    ) x FROM public.tactical_matches m
     WHERE m.status = 'finished' AND (m.player_a = v_user OR m.player_b = v_user)
     ORDER BY m.created_at DESC LIMIT GREATEST(1, LEAST(50, p_limit))) t), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.tactical_ranking(p_telegram_id bigint, p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := public.tactical_user_id(p_telegram_id);
BEGIN
  RETURN jsonb_build_object(
    'top', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'position', r.pos, 'userId', r.user_id, 'name', COALESCE(g.display_name, g.username, 'Player'),
        'username', g.username, 'avatarUrl', g.avatar_url, 'rating', r.rating,
        'league', public.tactical_league(r.rating), 'wins', r.wins, 'losses', r.losses) ORDER BY r.pos)
      FROM (SELECT t.*, row_number() OVER (ORDER BY t.rating DESC, t.wins DESC) pos
              FROM public.tactical_ratings t WHERE t.matches > 0) r
      JOIN public.game_players g ON g.id = r.user_id
     WHERE r.pos <= GREATEST(3, LEAST(100, p_limit))), '[]'::jsonb),
    'you', (SELECT jsonb_build_object('position', r.pos, 'rating', r.rating, 'league', public.tactical_league(r.rating))
              FROM (SELECT t.*, row_number() OVER (ORDER BY t.rating DESC, t.wins DESC) pos
                      FROM public.tactical_ratings t WHERE t.matches > 0) r WHERE r.user_id = v_user)
  );
END $$;

-- ===================== admin =====================
CREATE OR REPLACE FUNCTION public.admin_tactical_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object(
    'config', public.tactical_config(),
    'queue', (SELECT count(*) FROM public.tactical_queue WHERE status='searching'),
    'activeMatches', (SELECT count(*) FROM public.tactical_matches WHERE status='active'),
    'finishedMatches', (SELECT count(*) FROM public.tactical_matches WHERE status='finished'),
    'players', (SELECT count(*) FROM public.tactical_ratings WHERE matches > 0),
    'teams', (SELECT count(DISTINCT user_id) FROM public.tactical_teams),
    'skills', COALESCE((SELECT jsonb_agg(jsonb_build_object('key',s.skill_key,'class',s.hero_class,'type',s.skill_type,
        'mult',s.power_multiplier,'cd',s.cooldown,'dur',s.duration,'target',s.target_type,'enabled',s.enabled)
      ORDER BY s.sort_order) FROM public.tactical_skills s), '[]'::jsonb)
  );
END $$;

CREATE OR REPLACE FUNCTION public.admin_tactical_set(p_admin_id bigint, p_key text, p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_old jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_key NOT IN ('enabled','turnTimerSeconds','ticketCost','reconnectSeconds','stalemateTurns',
                   'stalemateEscalation','tournamentEnabled','eventMode','ratingK','deckSize')
    THEN RAISE EXCEPTION 'INVALID_CONFIG_KEY'; END IF;
  SELECT value INTO v_old FROM public.game_settings WHERE key='tactical_pvp';
  UPDATE public.game_settings SET value = COALESCE(value,'{}'::jsonb) || jsonb_build_object(p_key, p_value),
         updated_at = now(), updated_by = p_admin_id
   WHERE key = 'tactical_pvp';
  PERFORM public.admin_log(p_admin_id, 'tactical_config_set', 'tactical', p_key, v_old,
    jsonb_build_object(p_key, p_value), NULL, '{}'::jsonb);
  RETURN public.admin_tactical_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_tactical_skill_set(p_admin_id bigint, p_skill_key text, p_field text, p_value numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_old jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(s) INTO v_old FROM public.tactical_skills s WHERE s.skill_key = p_skill_key;
  IF v_old IS NULL THEN RAISE EXCEPTION 'SKILL_NOT_FOUND'; END IF;
  IF p_field = 'enabled' THEN UPDATE public.tactical_skills SET enabled = p_value >= 1, updated_at=now() WHERE skill_key=p_skill_key;
  ELSIF p_field = 'cooldown' THEN UPDATE public.tactical_skills SET cooldown = GREATEST(0, LEAST(10, p_value::int)), updated_at=now() WHERE skill_key=p_skill_key;
  ELSIF p_field = 'multiplier' THEN UPDATE public.tactical_skills SET power_multiplier = GREATEST(0, LEAST(5, p_value)), updated_at=now() WHERE skill_key=p_skill_key;
  ELSIF p_field = 'duration' THEN UPDATE public.tactical_skills SET duration = GREATEST(0, LEAST(5, p_value::int)), updated_at=now() WHERE skill_key=p_skill_key;
  ELSE RAISE EXCEPTION 'INVALID_SKILL_FIELD'; END IF;
  PERFORM public.admin_log(p_admin_id, 'tactical_skill_set', 'tactical_skill', p_skill_key, v_old,
    jsonb_build_object(p_field, p_value), NULL, '{}'::jsonb);
  RETURN public.admin_tactical_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_tactical_matches(p_admin_id bigint, p_limit integer DEFAULT 15)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'matchId', m.id, 'status', m.status, 'turn', m.turn, 'practice', m.is_practice,
      'a', COALESCE(m.state->'names'->>'a','?'), 'b', COALESCE(m.state->'names'->>'b','AI'),
      'winner', CASE WHEN m.winner_id IS NULL THEN NULL WHEN m.winner_id = m.player_a THEN 'A' ELSE 'B' END,
      'createdAt', m.created_at) ORDER BY m.created_at DESC)
    FROM (SELECT * FROM public.tactical_matches ORDER BY created_at DESC LIMIT GREATEST(1, LEAST(50, p_limit))) m), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.admin_tactical_ranking(p_admin_id bigint, p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'name', COALESCE(g.display_name, g.username, 'Player'), 'telegramId', g.telegram_id,
      'rating', t.rating, 'league', public.tactical_league(t.rating), 'wins', t.wins, 'losses', t.losses)
      ORDER BY t.rating DESC)
    FROM public.tactical_ratings t JOIN public.game_players g ON g.id = t.user_id
    WHERE t.matches > 0 ORDER BY t.rating DESC LIMIT GREATEST(1, LEAST(50, p_limit))), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.admin_tactical_reset(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_start int := COALESCE((public.tactical_config()->>'ratingStart')::int, 1000);
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  UPDATE public.tactical_matches SET status='abandoned', finished_at=now() WHERE status='active';
  DELETE FROM public.tactical_queue;
  UPDATE public.tactical_ratings SET rating=v_start, best_rating=v_start, wins=0, losses=0, matches=0, updated_at=now();
  PERFORM public.admin_log(p_admin_id, 'tactical_reset', 'tactical', 'ratings', NULL, NULL, NULL, '{}'::jsonb);
  RETURN public.admin_tactical_overview(p_admin_id);
END $$;

-- Public roles must never call these directly: the Edge Function uses the service role.
REVOKE EXECUTE ON FUNCTION public.tactical_dashboard(bigint), public.tactical_save_team(bigint,integer,uuid),
  public.tactical_remove_team(bigint,integer), public.tactical_save_deck(bigint,text[]),
  public.tactical_queue_join(bigint,boolean), public.tactical_queue_cancel(bigint), public.tactical_queue_status(bigint),
  public.tactical_match_json(uuid,uuid), public.tactical_match_tick(bigint,uuid),
  public.tactical_submit_action(bigint,uuid,text,text,text), public.tactical_resolve_turn(uuid),
  public.tactical_finish(uuid,text), public.tactical_start_match(uuid,uuid,boolean),
  public.tactical_build_units(uuid,text), public.tactical_validate_entry(uuid,boolean),
  public.tactical_history(bigint,integer), public.tactical_ranking(bigint,integer),
  public.admin_tactical_overview(bigint), public.admin_tactical_set(bigint,text,jsonb),
  public.admin_tactical_skill_set(bigint,text,text,numeric), public.admin_tactical_matches(bigint,integer),
  public.admin_tactical_ranking(bigint,integer), public.admin_tactical_reset(bigint)
FROM anon, authenticated;
