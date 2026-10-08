
-- ============================================================
-- MISSION: ADD #MYTHREON TO YOUR TELEGRAM NAME
-- Reward is paid only when the server itself proves the current
-- Telegram display name contains the exact hashtag token.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.name_mission_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  telegram_id bigint NOT NULL,
  mission_code text NOT NULL DEFAULT 'mythreon_name',
  hashtag text NOT NULL,
  verified_display_name text NOT NULL,
  verified_source text NOT NULL DEFAULT 'init_data',
  verified_at timestamptz NOT NULL DEFAULT now(),
  telegram_auth_date bigint,
  reward_type text NOT NULL DEFAULT 'fc',
  reward_amount numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT name_mission_claims_user_unique UNIQUE (user_id, mission_code),
  CONSTRAINT name_mission_claims_telegram_unique UNIQUE (telegram_id, mission_code)
);

GRANT ALL ON public.name_mission_claims TO service_role;
ALTER TABLE public.name_mission_claims ENABLE ROW LEVEL SECURITY;

INSERT INTO public.game_settings (key, value, category, label) VALUES
  ('name_mission_enabled', 'true'::jsonb, 'missions', 'Missão #Mythreon no nome ativa'),
  ('name_mission_hashtag', '"#Mythreon"'::jsonb, 'missions', 'Hashtag exigida no nome do Telegram'),
  ('name_mission_reward_fc', '50000'::jsonb, 'missions', 'Recompensa da missão #Mythreon (FC)')
ON CONFLICT (key) DO NOTHING;

-- Exact hashtag token match (case-insensitive). "#MythreonFake" or "Mythreon" never match.
CREATE OR REPLACE FUNCTION public.name_mission_matches(p_display_name text, p_hashtag text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE v_tag text; v_name text;
BEGIN
  v_tag := lower(regexp_replace(coalesce(p_hashtag, '#Mythreon'), '^#+', ''));
  IF v_tag = '' THEN RETURN false; END IF;
  v_name := lower(coalesce(p_display_name, ''));
  RETURN v_name ~ ('(^|[^[:alnum:]_])#' || v_tag || '([^[:alnum:]_]|$)');
END;
$$;

CREATE OR REPLACE FUNCTION public.name_mission_config()
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'enabled', COALESCE((SELECT value FROM public.game_settings WHERE key = 'name_mission_enabled')::text = 'true', true),
    'hashtag', COALESCE((SELECT value #>> '{}' FROM public.game_settings WHERE key = 'name_mission_hashtag'), '#Mythreon'),
    'rewardFc', COALESCE((SELECT (value #>> '{}')::numeric FROM public.game_settings WHERE key = 'name_mission_reward_fc'), 50000)
  );
$$;

CREATE OR REPLACE FUNCTION public.get_name_mission_state(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE cfg jsonb; k public.name_mission_claims%rowtype; u public.game_players%rowtype;
BEGIN
  cfg := public.name_mission_config();
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NOT NULL THEN
    SELECT * INTO k FROM public.name_mission_claims WHERE user_id = u.id AND mission_code = 'mythreon_name';
  END IF;
  RETURN cfg || jsonb_build_object(
    'claimed', k.id IS NOT NULL,
    'claimedAt', k.verified_at,
    'verifiedName', k.verified_display_name,
    'rewardReceived', COALESCE(k.reward_amount, 0)
  );
END;
$$;

/**
 * Atomic VERIFY & CLAIM. The display name is derived by the edge function from
 * authenticated Telegram data only, and it is re-validated here before paying.
 */
CREATE OR REPLACE FUNCTION public.claim_name_mission(
  p_telegram_id bigint,
  p_display_name text,
  p_source text DEFAULT 'init_data',
  p_auth_date bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE cfg jsonb; u public.game_players%rowtype; k public.name_mission_claims%rowtype;
        v_tag text; v_reward numeric; v_before numeric; v_after numeric;
BEGIN
  cfg := public.name_mission_config();
  IF COALESCE((cfg->>'enabled')::boolean, false) IS NOT TRUE THEN RAISE EXCEPTION 'NAME_MISSION_DISABLED'; END IF;
  v_tag := cfg->>'hashtag';
  v_reward := GREATEST(0, COALESCE((cfg->>'rewardFc')::numeric, 0));

  PERFORM pg_advisory_xact_lock(hashtextextended('name_mission:' || p_telegram_id::text, 0));

  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  SELECT * INTO k FROM public.name_mission_claims WHERE user_id = u.id AND mission_code = 'mythreon_name' FOR UPDATE;
  IF k.id IS NOT NULL THEN
    RETURN public.get_name_mission_state(p_telegram_id) || jsonb_build_object('status', 'already_claimed', 'creditedFc', 0, 'balance', u.forge_coins);
  END IF;

  -- Server-side re-validation: the flag from the caller is never enough.
  IF NOT public.name_mission_matches(p_display_name, v_tag) THEN RAISE EXCEPTION 'NAME_MISSION_HASHTAG_MISSING'; END IF;

  v_before := u.forge_coins;
  v_after := v_before + v_reward;
  UPDATE public.game_players SET forge_coins = v_after, updated_at = now() WHERE id = u.id;

  INSERT INTO public.name_mission_claims
    (user_id, telegram_id, mission_code, hashtag, verified_display_name, verified_source, telegram_auth_date, reward_type, reward_amount)
  VALUES (u.id, p_telegram_id, 'mythreon_name', v_tag, left(p_display_name, 160), COALESCE(p_source, 'init_data'), p_auth_date, 'fc', v_reward);

  INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id)
  VALUES (u.id, 'name_mission_reward', v_reward, v_before, v_after, 'name_mission:' || p_telegram_id::text)
  ON CONFLICT DO NOTHING;

  RETURN public.get_name_mission_state(p_telegram_id)
    || jsonb_build_object('status', 'claimed', 'creditedFc', v_reward, 'balance', v_after);
END;
$$;

-- ---------------------------------------------------------------- admin
CREATE OR REPLACE FUNCTION public.admin_name_mission(
  p_admin_id bigint,
  p_action text DEFAULT 'overview',
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE cfg jsonb; v_claims jsonb; v_total bigint; v_paid numeric; v_ref text; u public.game_players%rowtype; k public.name_mission_claims%rowtype;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  IF p_action = 'enable' OR p_action = 'disable' THEN
    INSERT INTO public.game_settings (key, value, category, label, updated_at, updated_by)
    VALUES ('name_mission_enabled', to_jsonb(p_action = 'enable'), 'missions', 'Missão #Mythreon no nome ativa', now(), p_admin_id)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;
    PERFORM public.admin_log(p_admin_id, 'name_mission_' || p_action, 'setting', 'name_mission_enabled');
  ELSIF p_action = 'set_reward' THEN
    INSERT INTO public.game_settings (key, value, category, label, updated_at, updated_by)
    VALUES ('name_mission_reward_fc', to_jsonb(GREATEST(0, COALESCE((p_payload->>'rewardFc')::numeric, 0))), 'missions', 'Recompensa da missão #Mythreon (FC)', now(), p_admin_id)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;
    PERFORM public.admin_log(p_admin_id, 'name_mission_set_reward', 'setting', 'name_mission_reward_fc', NULL, p_payload);
  ELSIF p_action = 'set_hashtag' THEN
    INSERT INTO public.game_settings (key, value, category, label, updated_at, updated_by)
    VALUES ('name_mission_hashtag', to_jsonb('#' || regexp_replace(COALESCE(p_payload->>'hashtag', '#Mythreon'), '^#+', '')), 'missions', 'Hashtag exigida no nome do Telegram', now(), p_admin_id)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;
    PERFORM public.admin_log(p_admin_id, 'name_mission_set_hashtag', 'setting', 'name_mission_hashtag', NULL, p_payload);
  ELSIF p_action = 'lookup' THEN
    v_ref := trim(COALESCE(p_payload->>'ref', ''));
    SELECT * INTO u FROM public.game_players
     WHERE (v_ref ~ '^[0-9]+$' AND telegram_id = v_ref::bigint)
        OR lower(COALESCE(username, '')) = lower(regexp_replace(v_ref, '^@', ''))
        OR lower(COALESCE(display_name, '')) = lower(v_ref)
     ORDER BY created_at LIMIT 1;
    IF u.id IS NOT NULL THEN
      SELECT * INTO k FROM public.name_mission_claims WHERE user_id = u.id AND mission_code = 'mythreon_name';
    END IF;
    RETURN public.name_mission_config() || jsonb_build_object(
      'found', u.id IS NOT NULL,
      'telegramId', u.telegram_id,
      'playerName', u.display_name,
      'username', u.username,
      'claimed', k.id IS NOT NULL,
      'claimedAt', k.verified_at,
      'verifiedName', k.verified_display_name,
      'rewardAmount', COALESCE(k.reward_amount, 0)
    );
  END IF;

  cfg := public.name_mission_config();
  SELECT count(*), COALESCE(sum(reward_amount), 0) INTO v_total, v_paid FROM public.name_mission_claims WHERE mission_code = 'mythreon_name';
  SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) INTO v_claims FROM (
    SELECT jsonb_build_object(
      'telegramId', c.telegram_id,
      'name', c.verified_display_name,
      'source', c.verified_source,
      'rewardAmount', c.reward_amount,
      'verifiedAt', c.verified_at
    ) AS row
    FROM public.name_mission_claims c
    WHERE c.mission_code = 'mythreon_name'
    ORDER BY c.verified_at DESC
    LIMIT 15
  ) t;

  RETURN cfg || jsonb_build_object('totalClaims', v_total, 'totalPaidFc', v_paid, 'claims', v_claims);
END;
$$;

REVOKE ALL ON FUNCTION public.claim_name_mission(bigint, text, text, bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_name_mission(bigint, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_name_mission_state(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_name_mission(bigint, text, text, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_name_mission(bigint, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_name_mission_state(bigint) TO service_role;
