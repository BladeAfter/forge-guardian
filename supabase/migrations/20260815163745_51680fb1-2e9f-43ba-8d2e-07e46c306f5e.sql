-- ============================================================
-- PVP LEAGUE ARENA (event slot that can replace the Community Pool display)
-- Created as DRAFT: nothing starts until the admin activates it.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.pvp_league_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL DEFAULT 'PVP LEAGUE ARENA',
  status text NOT NULL DEFAULT 'draft',
  started_at timestamptz,
  ends_at timestamptz,
  prize_pool_ton numeric(20,9) NOT NULL DEFAULT 40,
  top_limit integer NOT NULL DEFAULT 50,
  duration_days integer NOT NULL DEFAULT 7,
  enabled boolean NOT NULL DEFAULT true,
  min_matches integer NOT NULL DEFAULT 1,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pvp_league_events_status_check CHECK (status IN ('draft','active','finished','cancelled')),
  CONSTRAINT pvp_league_events_top_check CHECK (top_limit BETWEEN 3 AND 500),
  CONSTRAINT pvp_league_events_duration_check CHECK (duration_days BETWEEN 1 AND 90),
  CONSTRAINT pvp_league_events_pool_check CHECK (prize_pool_ton > 0)
);
GRANT ALL ON public.pvp_league_events TO service_role;
ALTER TABLE public.pvp_league_events ENABLE ROW LEVEL SECURITY;

-- Only one active event at a time (single main event slot).
CREATE UNIQUE INDEX IF NOT EXISTS pvp_league_events_single_active
  ON public.pvp_league_events ((status)) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS public.pvp_league_scores (
  event_id uuid NOT NULL REFERENCES public.pvp_league_events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  score integer NOT NULL DEFAULT 0,
  matches integer NOT NULL DEFAULT 0,
  wins integer NOT NULL DEFAULT 0,
  losses integer NOT NULL DEFAULT 0,
  best_score integer NOT NULL DEFAULT 0,
  best_score_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, user_id)
);
GRANT ALL ON public.pvp_league_scores TO service_role;
ALTER TABLE public.pvp_league_scores ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS pvp_league_scores_rank_idx
  ON public.pvp_league_scores (event_id, score DESC, wins DESC, best_score_at ASC);

CREATE TABLE IF NOT EXISTS public.pvp_league_score_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.pvp_league_events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  match_id uuid NOT NULL,
  role text NOT NULL DEFAULT 'attacker',
  score_delta integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pvp_league_score_events_unique UNIQUE (event_id, user_id, match_id)
);
GRANT ALL ON public.pvp_league_score_events TO service_role;
ALTER TABLE public.pvp_league_score_events ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.pvp_league_rewards (
  event_id uuid NOT NULL REFERENCES public.pvp_league_events(id) ON DELETE CASCADE,
  rank integer NOT NULL,
  reward_ton numeric(20,9) NOT NULL,
  PRIMARY KEY (event_id, rank)
);
GRANT ALL ON public.pvp_league_rewards TO service_role;
ALTER TABLE public.pvp_league_rewards ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.pvp_league_payouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.pvp_league_events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  rank integer NOT NULL,
  score integer NOT NULL DEFAULT 0,
  reward_ton numeric(20,9) NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pvp_league_payouts_unique UNIQUE (event_id, user_id)
);
GRANT ALL ON public.pvp_league_payouts TO service_role;
ALTER TABLE public.pvp_league_payouts ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.pvp_league_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS pvp_league_events_touch ON public.pvp_league_events;
CREATE TRIGGER pvp_league_events_touch BEFORE UPDATE ON public.pvp_league_events
FOR EACH ROW EXECUTE FUNCTION public.pvp_league_touch();

-- ------------------------------------------------------------
-- Reward table: exact NUMERIC split, total == prize_pool_ton
-- Base blueprint (40 TON / TOP 50): 16 TON top3, 12 TON #4-#10, 12 TON #11-#50.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pvp_league_build_rewards(p_event_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  ev public.pvp_league_events;
  f numeric; total numeric := 0; dust numeric;
  seg3 numeric; segmid numeric; segtail numeric;
  base_mid numeric[] := ARRAY[2.2,2.0,1.8,1.7,1.6,1.4,1.3];
  mid_end int; w numeric; wsum numeric := 0; r int; val numeric;
BEGIN
  SELECT * INTO ev FROM public.pvp_league_events WHERE id = p_event_id;
  IF ev.id IS NULL THEN RAISE EXCEPTION 'EVENT_NOT_FOUND'; END IF;

  DELETE FROM public.pvp_league_rewards WHERE event_id = p_event_id;
  f := ev.prize_pool_ton / 40.0;                    -- scales the blueprint to any pool
  seg3 := 16 * f; segmid := 12 * f; segtail := 12 * f;
  mid_end := LEAST(ev.top_limit, 10);

  -- #1-#3
  INSERT INTO public.pvp_league_rewards(event_id, rank, reward_ton) VALUES
    (p_event_id, 1, round(7 * f, 6)), (p_event_id, 2, round(5 * f, 6)), (p_event_id, 3, round(4 * f, 6));

  -- #4-#10 (fixed decreasing blueprint)
  IF ev.top_limit >= 4 THEN
    FOR r IN 4..mid_end LOOP
      INSERT INTO public.pvp_league_rewards(event_id, rank, reward_ton)
      VALUES (p_event_id, r, round(base_mid[r - 3] * f, 6));
    END LOOP;
  END IF;

  -- #11..top_limit: linear decreasing, exact sum
  IF ev.top_limit >= 11 THEN
    FOR r IN 11..ev.top_limit LOOP wsum := wsum + (ev.top_limit - r + 1); END LOOP;
    FOR r IN 11..ev.top_limit LOOP
      w := ev.top_limit - r + 1;
      val := round(segtail * w / wsum, 6);
      INSERT INTO public.pvp_league_rewards(event_id, rank, reward_ton) VALUES (p_event_id, r, val);
    END LOOP;
  END IF;

  SELECT COALESCE(sum(reward_ton), 0) INTO total FROM public.pvp_league_rewards WHERE event_id = p_event_id;
  dust := round(ev.prize_pool_ton - total, 9);
  IF dust <> 0 THEN
    UPDATE public.pvp_league_rewards SET reward_ton = round(reward_ton + dust, 9)
     WHERE event_id = p_event_id AND rank = 1;
  END IF;
  SELECT COALESCE(sum(reward_ton), 0) INTO total FROM public.pvp_league_rewards WHERE event_id = p_event_id;
  RETURN total;
END $$;
REVOKE ALL ON FUNCTION public.pvp_league_build_rewards(uuid) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- Scoring hook: observes finished PvP battles only, never changes PvP rules.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pvp_league_apply_delta(p_event uuid, p_user uuid, p_match uuid, p_role text, p_delta int, p_win boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_score int;
BEGIN
  INSERT INTO public.pvp_league_score_events(event_id, user_id, match_id, role, score_delta)
  VALUES (p_event, p_user, p_match, p_role, p_delta)
  ON CONFLICT (event_id, user_id, match_id) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN RETURN; END IF;   -- idempotent: one match scores once per player

  INSERT INTO public.pvp_league_scores(event_id, user_id, score, matches, wins, losses, best_score, best_score_at)
  VALUES (p_event, p_user, GREATEST(0, p_delta), 1, CASE WHEN p_win THEN 1 ELSE 0 END,
          CASE WHEN p_win THEN 0 ELSE 1 END, GREATEST(0, p_delta), now())
  ON CONFLICT (event_id, user_id) DO UPDATE
    SET score = GREATEST(0, public.pvp_league_scores.score + p_delta),
        matches = public.pvp_league_scores.matches + 1,
        wins = public.pvp_league_scores.wins + CASE WHEN p_win THEN 1 ELSE 0 END,
        losses = public.pvp_league_scores.losses + CASE WHEN p_win THEN 0 ELSE 1 END,
        updated_at = now()
  RETURNING score INTO v_score;

  UPDATE public.pvp_league_scores
     SET best_score = v_score, best_score_at = now()
   WHERE event_id = p_event AND user_id = p_user AND v_score > best_score;
END $$;
REVOKE ALL ON FUNCTION public.pvp_league_apply_delta(uuid,uuid,uuid,text,int,boolean) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.pvp_league_record_battle()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE ev public.pvp_league_events; v_win int; v_loss int; v_def_delta int;
BEGIN
  SELECT * INTO ev FROM public.pvp_league_events WHERE status = 'active' LIMIT 1;
  IF ev.id IS NULL THEN RETURN NEW; END IF;
  IF ev.started_at IS NULL OR NEW.created_at < ev.started_at THEN RETURN NEW; END IF;
  IF ev.ends_at IS NOT NULL AND NEW.created_at >= ev.ends_at THEN RETURN NEW; END IF;
  IF NEW.result IS NULL THEN RETURN NEW; END IF;

  v_win := public.setting_num('pvp_trophy_win', 30)::int;
  v_loss := abs(public.setting_num('pvp_trophy_loss', -20)::int);

  PERFORM public.pvp_league_apply_delta(ev.id, NEW.attacker_id, NEW.id, 'attacker',
    COALESCE(NEW.trophy_change, 0), NEW.result = 'attacker_win');

  IF NEW.defender_id IS NOT NULL AND NOT COALESCE(NEW.is_bot_battle, false) THEN
    v_def_delta := CASE WHEN NEW.result = 'attacker_win' THEN -v_loss ELSE v_win END;
    PERFORM public.pvp_league_apply_delta(ev.id, NEW.defender_id, NEW.id, 'defender',
      v_def_delta, NEW.result <> 'attacker_win');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pvp_league_battle_score ON public.pvp_battles;
CREATE TRIGGER pvp_league_battle_score AFTER INSERT ON public.pvp_battles
FOR EACH ROW EXECUTE FUNCTION public.pvp_league_record_battle();

-- ------------------------------------------------------------
-- Finalization: freeze ranking, deterministic tie-break, credit withdrawable TON.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pvp_league_finalize(p_event_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE ev public.pvp_league_events; row_r record; v_total numeric := 0; v_paid int := 0; v_lang text;
BEGIN
  SELECT * INTO ev FROM public.pvp_league_events WHERE id = p_event_id FOR UPDATE;
  IF ev.id IS NULL THEN RAISE EXCEPTION 'EVENT_NOT_FOUND'; END IF;
  IF ev.status <> 'active' THEN RETURN jsonb_build_object('ok', false, 'status', ev.status); END IF;

  UPDATE public.pvp_league_events SET status = 'finished', finished_at = now() WHERE id = p_event_id;

  FOR row_r IN
    SELECT s.user_id, s.score, s.wins, s.matches,
           row_number() OVER (ORDER BY s.score DESC, s.wins DESC,
             (s.wins::numeric / GREATEST(1, s.matches)) DESC, s.best_score_at ASC NULLS LAST, s.user_id) AS rank
      FROM public.pvp_league_scores s
     WHERE s.event_id = p_event_id AND s.score > 0 AND s.matches >= GREATEST(1, ev.min_matches)
     ORDER BY rank
     LIMIT ev.top_limit
  LOOP
    INSERT INTO public.pvp_league_payouts(event_id, user_id, rank, score, reward_ton, status)
    SELECT p_event_id, row_r.user_id, row_r.rank::int, row_r.score, r.reward_ton, 'pending'
      FROM public.pvp_league_rewards r WHERE r.event_id = p_event_id AND r.rank = row_r.rank::int
    ON CONFLICT (event_id, user_id) DO NOTHING;

    UPDATE public.pvp_league_payouts p SET status = 'paid', paid_at = now()
     WHERE p.event_id = p_event_id AND p.user_id = row_r.user_id AND p.status = 'pending'
     RETURNING p.reward_ton INTO v_total;

    IF v_total IS NOT NULL AND v_total > 0 THEN
      PERFORM public.credit_ton_reward(row_r.user_id, v_total, 'pvp_league_reward',
        p_event_id::text || ':' || row_r.user_id::text,
        'PVP LEAGUE ARENA #' || row_r.rank::text);
      v_paid := v_paid + 1;
      SELECT COALESCE(language, 'en') INTO v_lang FROM public.game_players WHERE id = row_r.user_id;
      INSERT INTO public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
      VALUES (row_r.user_id, 'pvp_league_reward',
        CASE v_lang WHEN 'pt' THEN '🏆 RESULTADO — PVP LEAGUE ARENA'
                    WHEN 'es' THEN '🏆 RESULTADOS — PVP LEAGUE ARENA'
                    WHEN 'ru' THEN '🏆 ИТОГИ — PVP LEAGUE ARENA'
                    WHEN 'tr' THEN '🏆 SONUÇLAR — PVP LEAGUE ARENA'
                    ELSE '🏆 PVP LEAGUE ARENA RESULTS' END,
        CASE v_lang
          WHEN 'pt' THEN 'Sua posição: #' || row_r.rank || E'\nPrêmio: ' || trim(to_char(v_total, 'FM999990.000')) || E' TON\nCreditado no seu saldo TON sacável.'
          WHEN 'es' THEN 'Tu posición: #' || row_r.rank || E'\nPremio: ' || trim(to_char(v_total, 'FM999990.000')) || E' TON\nAcreditado en tu saldo TON retirable.'
          WHEN 'ru' THEN 'Ваше место: #' || row_r.rank || E'\nНаграда: ' || trim(to_char(v_total, 'FM999990.000')) || E' TON\nЗачислено на выводимый баланс TON.'
          WHEN 'tr' THEN 'Sıralaman: #' || row_r.rank || E'\nÖdül: ' || trim(to_char(v_total, 'FM999990.000')) || E' TON\nÇekilebilir TON bakiyene eklendi.'
          ELSE 'Your rank: #' || row_r.rank || E'\nReward: ' || trim(to_char(v_total, 'FM999990.000')) || E' TON\nCredited to your withdrawable TON balance.' END,
        jsonb_build_object('eventId', p_event_id, 'rank', row_r.rank, 'rewardTon', v_total),
        'pvp_league:' || p_event_id::text || ':' || row_r.user_id::text);
    END IF;
    v_total := NULL;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'eventId', p_event_id, 'winners', v_paid,
    'distributedTon', COALESCE((SELECT sum(reward_ton) FROM public.pvp_league_payouts WHERE event_id = p_event_id AND status = 'paid'), 0));
END $$;
REVOKE ALL ON FUNCTION public.pvp_league_finalize(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.pvp_league_maybe_finalize()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM public.pvp_league_events
   WHERE status = 'active' AND ends_at IS NOT NULL AND now() >= ends_at LIMIT 1;
  IF v_id IS NOT NULL THEN PERFORM public.pvp_league_finalize(v_id); END IF;
END $$;
REVOKE ALL ON FUNCTION public.pvp_league_maybe_finalize() FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- Player dashboard (read-only). status='draft' => the client keeps the Community Pool.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pvp_league_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE ev public.pvp_league_events; me public.game_players; v_rank int; v_score int; v_matches int; v_wins int;
        v_reward numeric := 0; v_league text; v_participants int := 0; v_ranking jsonb;
BEGIN
  PERFORM public.pvp_league_maybe_finalize();
  SELECT * INTO ev FROM public.pvp_league_events WHERE status = 'active' LIMIT 1;
  IF ev.id IS NULL THEN
    SELECT * INTO ev FROM public.pvp_league_events ORDER BY created_at DESC LIMIT 1;
    RETURN jsonb_build_object('status', COALESCE(ev.status, 'draft'), 'active', false);
  END IF;

  SELECT * INTO me FROM public.game_players WHERE telegram_id = p_telegram_id;
  SELECT count(*) INTO v_participants FROM public.pvp_league_scores WHERE event_id = ev.id AND matches > 0;

  WITH ranked AS (
    SELECT s.user_id, s.score, s.wins, s.matches,
           row_number() OVER (ORDER BY s.score DESC, s.wins DESC,
             (s.wins::numeric / GREATEST(1, s.matches)) DESC, s.best_score_at ASC NULLS LAST, s.user_id) AS position
      FROM public.pvp_league_scores s
     WHERE s.event_id = ev.id AND s.score > 0 AND s.matches >= GREATEST(1, ev.min_matches)
  )
  SELECT jsonb_agg(jsonb_build_object(
           'position', position, 'userId', user_id, 'name', COALESCE(NULLIF(g.display_name,''), NULLIF(g.first_name,''), NULLIF(g.username,''), 'Player'),
           'username', g.username, 'avatarUrl', g.avatar_url, 'score', score, 'wins', wins, 'matches', matches,
           'rewardTon', COALESCE(r.reward_ton, 0), 'isYou', user_id = me.id) ORDER BY position)
    INTO v_ranking
    FROM ranked
    JOIN public.game_players g ON g.id = ranked.user_id
    LEFT JOIN public.pvp_league_rewards r ON r.event_id = ev.id AND r.rank = ranked.position::int
   WHERE position <= ev.top_limit;

  IF me.id IS NOT NULL THEN
    WITH ranked AS (
      SELECT s.user_id, s.score, s.wins, s.matches,
             row_number() OVER (ORDER BY s.score DESC, s.wins DESC,
               (s.wins::numeric / GREATEST(1, s.matches)) DESC, s.best_score_at ASC NULLS LAST, s.user_id) AS position
        FROM public.pvp_league_scores s
       WHERE s.event_id = ev.id AND s.score > 0 AND s.matches >= GREATEST(1, ev.min_matches)
    )
    SELECT position::int, score, matches, wins INTO v_rank, v_score, v_matches, v_wins FROM ranked WHERE user_id = me.id;
    IF v_rank IS NOT NULL AND v_rank <= ev.top_limit THEN
      SELECT COALESCE(reward_ton, 0) INTO v_reward FROM public.pvp_league_rewards WHERE event_id = ev.id AND rank = v_rank;
    END IF;
    SELECT l.name INTO v_league FROM public.pvp_leagues l
     WHERE COALESCE(me.pvp_trophies,0) >= l.min_trophies AND COALESCE(me.pvp_trophies,0) <= COALESCE(l.max_trophies, 2147483647)
     ORDER BY l.sort_order LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'status', ev.status, 'active', true,
    'event', jsonb_build_object('id', ev.id, 'name', ev.name, 'prizePoolTon', ev.prize_pool_ton,
      'topLimit', ev.top_limit, 'startedAt', ev.started_at, 'endsAt', ev.ends_at, 'durationDays', ev.duration_days),
    'participants', v_participants,
    'player', jsonb_build_object('score', COALESCE(v_score, 0), 'position', v_rank, 'matches', COALESCE(v_matches, 0),
      'wins', COALESCE(v_wins, 0), 'estimatedRewardTon', COALESCE(v_reward, 0), 'league', v_league,
      'trophies', COALESCE(me.pvp_trophies, 0), 'inTop', v_rank IS NOT NULL AND v_rank <= ev.top_limit),
    'tiers', jsonb_build_array(
      jsonb_build_object('label', 'TOP 1-3', 'ton', COALESCE((SELECT sum(reward_ton) FROM public.pvp_league_rewards WHERE event_id = ev.id AND rank <= 3), 0)),
      jsonb_build_object('label', 'TOP 4-10', 'ton', COALESCE((SELECT sum(reward_ton) FROM public.pvp_league_rewards WHERE event_id = ev.id AND rank BETWEEN 4 AND 10), 0)),
      jsonb_build_object('label', 'TOP 11-' || ev.top_limit, 'ton', COALESCE((SELECT sum(reward_ton) FROM public.pvp_league_rewards WHERE event_id = ev.id AND rank >= 11), 0))),
    'ranking', COALESCE(v_ranking, '[]'::jsonb),
    'serverTime', now());
END $$;
REVOKE ALL ON FUNCTION public.pvp_league_dashboard(bigint) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- Admin panel (Telegram bot)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_pvp_league_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE ev public.pvp_league_events;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM public.pvp_league_maybe_finalize();
  SELECT * INTO ev FROM public.pvp_league_events WHERE status = 'active' LIMIT 1;
  IF ev.id IS NULL THEN
    SELECT * INTO ev FROM public.pvp_league_events WHERE status = 'draft' ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF ev.id IS NULL THEN SELECT * INTO ev FROM public.pvp_league_events ORDER BY created_at DESC LIMIT 1; END IF;
  RETURN jsonb_build_object('event', to_jsonb(ev),
    'participants', COALESCE((SELECT count(*) FROM public.pvp_league_scores WHERE event_id = ev.id AND matches > 0), 0),
    'matches', COALESCE((SELECT count(*) FROM public.pvp_league_score_events WHERE event_id = ev.id), 0),
    'rewardTotal', COALESCE((SELECT sum(reward_ton) FROM public.pvp_league_rewards WHERE event_id = ev.id), 0),
    'paidTotal', COALESCE((SELECT sum(reward_ton) FROM public.pvp_league_payouts WHERE event_id = ev.id AND status = 'paid'), 0),
    'rewards', COALESCE((SELECT jsonb_agg(jsonb_build_object('rank', rank, 'ton', reward_ton) ORDER BY rank)
                           FROM public.pvp_league_rewards WHERE event_id = ev.id), '[]'::jsonb),
    'poolStatus', (SELECT status FROM public.pool_balance ORDER BY starts_at DESC LIMIT 1),
    'history', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'name', name, 'status', status,
        'prizePoolTon', prize_pool_ton, 'startedAt', started_at, 'endsAt', ends_at) ORDER BY created_at DESC)
        FROM (SELECT * FROM public.pvp_league_events ORDER BY created_at DESC LIMIT 6) h), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.admin_pvp_league_overview(bigint) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_pvp_league_configure(p_admin_id bigint, p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE ev public.pvp_league_events;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO ev FROM public.pvp_league_events WHERE status = 'draft' ORDER BY created_at DESC LIMIT 1;
  IF ev.id IS NULL THEN
    INSERT INTO public.pvp_league_events(name) VALUES ('PVP LEAGUE ARENA') RETURNING * INTO ev;
  END IF;
  UPDATE public.pvp_league_events SET
    name = COALESCE(NULLIF(btrim(p_patch->>'name'), ''), name),
    prize_pool_ton = COALESCE((p_patch->>'prize_pool_ton')::numeric, prize_pool_ton),
    duration_days = COALESCE((p_patch->>'duration_days')::int, duration_days),
    top_limit = COALESCE((p_patch->>'top_limit')::int, top_limit),
    min_matches = COALESCE((p_patch->>'min_matches')::int, min_matches),
    enabled = COALESCE((p_patch->>'enabled')::boolean, enabled)
   WHERE id = ev.id RETURNING * INTO ev;
  PERFORM public.admin_log(p_admin_id, 'pvp_league.configure', 'pvp_league', ev.id::text, NULL, p_patch, 'painel admin', '{}'::jsonb);
  RETURN to_jsonb(ev);
END $$;
REVOKE ALL ON FUNCTION public.admin_pvp_league_configure(bigint, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_pvp_league_activate(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE ev public.pvp_league_events; v_total numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF EXISTS (SELECT 1 FROM public.pvp_league_events WHERE status = 'active') THEN RAISE EXCEPTION 'EVENT_ALREADY_ACTIVE'; END IF;
  SELECT * INTO ev FROM public.pvp_league_events WHERE status = 'draft' ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  IF ev.id IS NULL THEN RAISE EXCEPTION 'NO_DRAFT_EVENT'; END IF;

  UPDATE public.pvp_league_events
     SET status = 'active', started_at = now(), ends_at = now() + make_interval(days => ev.duration_days)
   WHERE id = ev.id RETURNING * INTO ev;
  v_total := public.pvp_league_build_rewards(ev.id);
  -- The Community Pool keeps every cycle, payout and history intact; only the UI slot switches.
  PERFORM public.admin_log(p_admin_id, 'pvp_league.activate', 'pvp_league', ev.id::text, NULL,
    jsonb_build_object('startedAt', ev.started_at, 'endsAt', ev.ends_at, 'prizePoolTon', ev.prize_pool_ton, 'rewardTotal', v_total),
    'troca de evento principal', jsonb_build_object('financial', true));
  RETURN jsonb_build_object('event', to_jsonb(ev), 'rewardTotal', v_total);
END $$;
REVOKE ALL ON FUNCTION public.admin_pvp_league_activate(bigint) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_pvp_league_end(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE ev public.pvp_league_events; res jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO ev FROM public.pvp_league_events WHERE status = 'active' LIMIT 1;
  IF ev.id IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_EVENT'; END IF;
  res := public.pvp_league_finalize(ev.id);
  PERFORM public.admin_log(p_admin_id, 'pvp_league.end', 'pvp_league', ev.id::text, NULL, res, 'painel admin', jsonb_build_object('financial', true));
  RETURN res;
END $$;
REVOKE ALL ON FUNCTION public.admin_pvp_league_end(bigint) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_pvp_league_cancel(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE ev public.pvp_league_events;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO ev FROM public.pvp_league_events WHERE status IN ('active','draft') ORDER BY status, created_at DESC LIMIT 1;
  IF ev.id IS NULL THEN RAISE EXCEPTION 'NO_EVENT'; END IF;
  UPDATE public.pvp_league_events SET status = 'cancelled', finished_at = now() WHERE id = ev.id;
  INSERT INTO public.pvp_league_events(name, prize_pool_ton, top_limit, duration_days, min_matches)
  VALUES (ev.name, ev.prize_pool_ton, ev.top_limit, ev.duration_days, ev.min_matches);
  PERFORM public.admin_log(p_admin_id, 'pvp_league.cancel', 'pvp_league', ev.id::text, to_jsonb(ev), NULL, 'painel admin', '{}'::jsonb);
  RETURN jsonb_build_object('ok', true, 'cancelled', ev.id);
END $$;
REVOKE ALL ON FUNCTION public.admin_pvp_league_cancel(bigint) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_pvp_league_ranking(p_admin_id bigint, p_limit int DEFAULT 20, p_query text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE ev public.pvp_league_events; v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO ev FROM public.pvp_league_events WHERE status IN ('active','finished') ORDER BY status, created_at DESC LIMIT 1;
  IF ev.id IS NULL THEN RETURN jsonb_build_object('rows', '[]'::jsonb); END IF;
  WITH ranked AS (
    SELECT s.user_id, s.score, s.wins, s.matches,
           row_number() OVER (ORDER BY s.score DESC, s.wins DESC,
             (s.wins::numeric / GREATEST(1, s.matches)) DESC, s.best_score_at ASC NULLS LAST, s.user_id) AS position
      FROM public.pvp_league_scores s WHERE s.event_id = ev.id AND s.score > 0
  )
  SELECT jsonb_agg(jsonb_build_object('position', position, 'telegramId', g.telegram_id,
           'name', COALESCE(NULLIF(g.display_name,''), NULLIF(g.username,''), 'Player'),
           'score', score, 'wins', wins, 'matches', matches, 'rewardTon', COALESCE(r.reward_ton, 0)) ORDER BY position)
    INTO v FROM ranked
    JOIN public.game_players g ON g.id = ranked.user_id
    LEFT JOIN public.pvp_league_rewards r ON r.event_id = ev.id AND r.rank = ranked.position::int
   WHERE (p_query IS NULL OR g.telegram_id::text = btrim(p_query) OR g.username ILIKE '%' || btrim(p_query) || '%'
          OR g.display_name ILIKE '%' || btrim(p_query) || '%')
     AND (p_query IS NOT NULL OR position <= GREATEST(1, p_limit));
  RETURN jsonb_build_object('event', to_jsonb(ev), 'rows', COALESCE(v, '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.admin_pvp_league_ranking(bigint, int, text) FROM PUBLIC, anon, authenticated;

-- Seed the DRAFT event (40 TON / TOP 50 / 7 days). Nothing starts until activation.
INSERT INTO public.pvp_league_events(name, status, prize_pool_ton, top_limit, duration_days, min_matches)
SELECT 'PVP LEAGUE ARENA', 'draft', 40, 50, 7, 1
WHERE NOT EXISTS (SELECT 1 FROM public.pvp_league_events);