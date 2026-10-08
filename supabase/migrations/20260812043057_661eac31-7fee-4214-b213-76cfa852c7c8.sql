-- ============================================================
-- MYTHREON :: PARTNER CHANNELS (name + reward + hidden link)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.partner_channels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  target_url text NOT NULL,
  reward_fc integer NOT NULL DEFAULT 500,
  sort_order integer NOT NULL DEFAULT 100,
  is_enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.partner_channels TO service_role;
ALTER TABLE public.partner_channels ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: the Mini App only reads through SECURITY DEFINER RPCs,
-- so the real target_url never leaves the backend.

CREATE TABLE IF NOT EXISTS public.partner_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES public.partner_channels(id),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  telegram_id bigint NOT NULL,
  status text NOT NULL DEFAULT 'visited',
  reward_fc integer NOT NULL DEFAULT 0,
  visited_at timestamptz NOT NULL DEFAULT now(),
  claimed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT partner_claims_unique UNIQUE (partner_id, user_id),
  CONSTRAINT partner_claims_status_check CHECK (status IN ('visited','claimed'))
);

GRANT ALL ON public.partner_claims TO service_role;
ALTER TABLE public.partner_claims ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS partner_claims_partner_idx ON public.partner_claims(partner_id);
CREATE INDEX IF NOT EXISTS partner_channels_order_idx ON public.partner_channels(is_enabled, sort_order);

DROP TRIGGER IF EXISTS partner_channels_touch ON public.partner_channels;
CREATE TRIGGER partner_channels_touch BEFORE UPDATE ON public.partner_channels
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS partner_claims_touch ON public.partner_claims;
CREATE TRIGGER partner_claims_touch BEFORE UPDATE ON public.partner_claims
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ------------------------------------------------------------ player: list (no url ever)
CREATE OR REPLACE FUNCTION public.get_partner_channels(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  RETURN jsonb_build_object('partners', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'rewardFc', c.reward_fc,
      'claimed', COALESCE(k.status = 'claimed', false),
      'visited', k.id IS NOT NULL,
      'rewardReceived', COALESCE(k.reward_fc, 0)
    ) ORDER BY c.sort_order, c.created_at)
    FROM public.partner_channels c
    LEFT JOIN public.partner_claims k ON k.partner_id = c.id AND k.user_id = v_user
    WHERE c.is_enabled
  ), '[]'::jsonb));
END;
$$;

-- ------------------------------------------------------------ player: GO (returns the official hidden link)
CREATE OR REPLACE FUNCTION public.partner_channel_visit(p_telegram_id bigint, p_partner_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; c public.partner_channels%rowtype;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  SELECT * INTO c FROM public.partner_channels WHERE id = p_partner_id AND is_enabled;
  IF c.id IS NULL THEN RAISE EXCEPTION 'PARTNER_NOT_AVAILABLE'; END IF;

  INSERT INTO public.partner_claims (partner_id, user_id, telegram_id, status)
  VALUES (c.id, v_user, p_telegram_id, 'visited')
  ON CONFLICT (partner_id, user_id) DO NOTHING;

  RETURN jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'url', c.target_url,
    'rewardFc', c.reward_fc,
    'claimed', EXISTS (SELECT 1 FROM public.partner_claims k WHERE k.partner_id = c.id AND k.user_id = v_user AND k.status = 'claimed')
  );
END;
$$;

-- ------------------------------------------------------------ player: claim (one time per user, backend reward)
CREATE OR REPLACE FUNCTION public.claim_partner_reward(p_telegram_id bigint, p_partner_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u public.game_players%rowtype; c public.partner_channels%rowtype; k public.partner_claims%rowtype;
        v_before numeric; v_after numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('partner_reward:' || p_telegram_id::text || ':' || p_partner_id::text, 0));

  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  SELECT * INTO c FROM public.partner_channels WHERE id = p_partner_id AND is_enabled;
  IF c.id IS NULL THEN RAISE EXCEPTION 'PARTNER_NOT_AVAILABLE'; END IF;

  SELECT * INTO k FROM public.partner_claims WHERE partner_id = c.id AND user_id = u.id FOR UPDATE;
  -- Verification available for external channels: the GO action must have been registered first.
  IF k.id IS NULL THEN RAISE EXCEPTION 'PARTNER_NOT_VISITED'; END IF;

  IF k.status = 'claimed' THEN
    RETURN public.get_partner_channels(p_telegram_id)
      || jsonb_build_object('status','already_claimed','creditedFc',0,'balance',u.forge_coins);
  END IF;

  v_before := u.forge_coins;
  v_after := v_before + c.reward_fc;
  UPDATE public.game_players SET forge_coins = v_after, updated_at = now() WHERE id = u.id;
  UPDATE public.partner_claims
     SET status = 'claimed', reward_fc = c.reward_fc, claimed_at = now(), updated_at = now()
   WHERE id = k.id;

  INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id)
  VALUES (u.id, 'partner_reward', c.reward_fc, v_before, v_after, p_telegram_id::text || ':' || c.id::text)
  ON CONFLICT DO NOTHING;

  RETURN public.get_partner_channels(p_telegram_id)
    || jsonb_build_object('status','claimed','creditedFc',c.reward_fc,'balance',v_after,'partnerName',c.name);
END;
$$;

-- ------------------------------------------------------------ admin bot module
CREATE OR REPLACE FUNCTION public.admin_partners(
  p_admin_id bigint, p_action text, p_partner_id uuid DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c public.partner_channels%rowtype; v_name text; v_url text; v_reward integer; v_sort integer;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  IF p_action = 'list' THEN
    RETURN jsonb_build_object('partners', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', c2.id, 'name', c2.name, 'rewardFc', c2.reward_fc, 'sortOrder', c2.sort_order,
        'enabled', c2.is_enabled,
        'visits', (SELECT count(*) FROM public.partner_claims k WHERE k.partner_id = c2.id),
        'claims', (SELECT count(*) FROM public.partner_claims k WHERE k.partner_id = c2.id AND k.status = 'claimed')
      ) ORDER BY c2.sort_order, c2.created_at) FROM public.partner_channels c2
    ), '[]'::jsonb));
  END IF;

  IF p_action = 'create' THEN
    v_name := NULLIF(btrim(p_payload->>'name'), '');
    v_url := NULLIF(btrim(p_payload->>'url'), '');
    v_reward := GREATEST(0, COALESCE((p_payload->>'rewardFc')::integer, 500));
    IF v_name IS NULL OR v_url IS NULL THEN RAISE EXCEPTION 'INVALID_PARTNER'; END IF;
    IF v_url !~* '^https?://' THEN RAISE EXCEPTION 'INVALID_URL'; END IF;
    SELECT COALESCE(max(sort_order), 0) + 1 INTO v_sort FROM public.partner_channels;
    INSERT INTO public.partner_channels (name, target_url, reward_fc, sort_order)
    VALUES (v_name, v_url, v_reward, COALESCE((p_payload->>'sortOrder')::integer, v_sort))
    RETURNING * INTO c;
    PERFORM public.admin_log(p_admin_id, 'partners.create', 'partner', c.id::text, NULL,
      jsonb_build_object('name', c.name, 'rewardFc', c.reward_fc), NULL, '{}'::jsonb);
    RETURN jsonb_build_object('partner', jsonb_build_object('id', c.id, 'name', c.name, 'rewardFc', c.reward_fc, 'sortOrder', c.sort_order, 'enabled', c.is_enabled));
  END IF;

  SELECT * INTO c FROM public.partner_channels WHERE id = p_partner_id;
  IF c.id IS NULL THEN RAISE EXCEPTION 'PARTNER_NOT_FOUND'; END IF;

  IF p_action = 'detail' OR p_action = 'stats' THEN
    RETURN jsonb_build_object('partner', jsonb_build_object(
      'id', c.id, 'name', c.name, 'rewardFc', c.reward_fc, 'sortOrder', c.sort_order,
      'enabled', c.is_enabled, 'linkConfigured', true,
      'urlHost', split_part(regexp_replace(c.target_url, '^https?://', ''), '/', 1),
      'visits', (SELECT count(*) FROM public.partner_claims k WHERE k.partner_id = c.id),
      'claims', (SELECT count(*) FROM public.partner_claims k WHERE k.partner_id = c.id AND k.status = 'claimed'),
      'distributedFc', (SELECT COALESCE(sum(k.reward_fc), 0) FROM public.partner_claims k WHERE k.partner_id = c.id AND k.status = 'claimed'),
      'lastClaimAt', (SELECT max(k.claimed_at) FROM public.partner_claims k WHERE k.partner_id = c.id),
      'createdAt', c.created_at
    ));
  END IF;

  IF p_action = 'rename' THEN
    v_name := NULLIF(btrim(p_payload->>'name'), '');
    IF v_name IS NULL THEN RAISE EXCEPTION 'INVALID_PARTNER'; END IF;
    UPDATE public.partner_channels SET name = v_name WHERE id = c.id;
    PERFORM public.admin_log(p_admin_id, 'partners.rename', 'partner', c.id::text,
      jsonb_build_object('name', c.name), jsonb_build_object('name', v_name), NULL, '{}'::jsonb);
  ELSIF p_action = 'link' THEN
    v_url := NULLIF(btrim(p_payload->>'url'), '');
    IF v_url IS NULL OR v_url !~* '^https?://' THEN RAISE EXCEPTION 'INVALID_URL'; END IF;
    UPDATE public.partner_channels SET target_url = v_url WHERE id = c.id;
    PERFORM public.admin_log(p_admin_id, 'partners.link', 'partner', c.id::text, NULL,
      jsonb_build_object('host', split_part(regexp_replace(v_url, '^https?://', ''), '/', 1)), NULL, '{}'::jsonb);
  ELSIF p_action = 'reward' THEN
    v_reward := (p_payload->>'rewardFc')::integer;
    IF v_reward IS NULL OR v_reward < 0 OR v_reward > 100000000 THEN RAISE EXCEPTION 'INVALID_REWARD'; END IF;
    UPDATE public.partner_channels SET reward_fc = v_reward WHERE id = c.id;
    PERFORM public.admin_log(p_admin_id, 'partners.reward', 'partner', c.id::text,
      jsonb_build_object('rewardFc', c.reward_fc), jsonb_build_object('rewardFc', v_reward), NULL, '{}'::jsonb);
  ELSIF p_action = 'sort' THEN
    v_sort := (p_payload->>'sortOrder')::integer;
    IF v_sort IS NULL OR v_sort < 1 OR v_sort > 999 THEN RAISE EXCEPTION 'INVALID_SORT'; END IF;
    UPDATE public.partner_channels SET sort_order = v_sort WHERE id = c.id;
    PERFORM public.admin_log(p_admin_id, 'partners.sort', 'partner', c.id::text,
      jsonb_build_object('sortOrder', c.sort_order), jsonb_build_object('sortOrder', v_sort), NULL, '{}'::jsonb);
  ELSIF p_action = 'toggle' THEN
    UPDATE public.partner_channels SET is_enabled = NOT c.is_enabled WHERE id = c.id;
    PERFORM public.admin_log(p_admin_id, 'partners.toggle', 'partner', c.id::text,
      jsonb_build_object('enabled', c.is_enabled), jsonb_build_object('enabled', NOT c.is_enabled), NULL, '{}'::jsonb);
  ELSIF p_action = 'delete' THEN
    -- Soft delete: the partner disappears from the Mini App but every claim stays on record.
    UPDATE public.partner_channels SET is_enabled = false, name = c.name WHERE id = c.id;
    PERFORM public.admin_log(p_admin_id, 'partners.delete', 'partner', c.id::text,
      jsonb_build_object('name', c.name, 'enabled', c.is_enabled), jsonb_build_object('enabled', false), 'soft delete', '{}'::jsonb);
  ELSE
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  RETURN public.admin_partners(p_admin_id, 'detail', c.id, '{}'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.get_partner_channels(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.partner_channel_visit(bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_partner_reward(bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_partners(bigint, text, uuid, jsonb) FROM PUBLIC, anon, authenticated;