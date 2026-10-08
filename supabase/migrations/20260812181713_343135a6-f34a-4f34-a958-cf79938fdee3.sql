ALTER TABLE public.partner_channels
  ADD COLUMN IF NOT EXISTS validation_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS telegram_chat_id text;

-- ------------------------------------------------------------------ admin partners
CREATE OR REPLACE FUNCTION public.admin_partners(p_admin_id bigint, p_action text DEFAULT 'list', p_partner_id uuid DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE c public.partner_channels%rowtype; v_name text; v_url text; v_reward integer; v_sort integer;
        v_chat text; v_validate boolean;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  IF p_action = 'list' THEN
    RETURN jsonb_build_object('partners', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', c2.id, 'name', c2.name, 'rewardFc', c2.reward_fc, 'sortOrder', c2.sort_order,
        'enabled', c2.is_enabled,
        'validationEnabled', c2.validation_enabled,
        'chatId', c2.telegram_chat_id,
        'visits', (SELECT count(*) FROM public.partner_claims k WHERE k.partner_id = c2.id),
        'claims', (SELECT count(*) FROM public.partner_claims k WHERE k.partner_id = c2.id AND k.status = 'claimed')
      ) ORDER BY c2.sort_order, c2.created_at) FROM public.partner_channels c2
    ), '[]'::jsonb));
  END IF;

  IF p_action = 'create' THEN
    v_name := NULLIF(btrim(p_payload->>'name'), '');
    v_url := NULLIF(btrim(p_payload->>'url'), '');
    v_reward := GREATEST(0, COALESCE((p_payload->>'rewardFc')::integer, 500));
    v_validate := COALESCE((p_payload->>'validationEnabled')::boolean, false);
    v_chat := NULLIF(btrim(COALESCE(p_payload->>'chatId', '')), '');
    IF v_name IS NULL OR v_url IS NULL THEN RAISE EXCEPTION 'INVALID_PARTNER'; END IF;
    IF v_url !~* '^https?://' THEN RAISE EXCEPTION 'INVALID_URL'; END IF;
    -- Validation can never be stored without the chat used to verify membership.
    IF v_validate AND v_chat IS NULL THEN RAISE EXCEPTION 'MISSING_CHAT_ID'; END IF;
    SELECT COALESCE(max(sort_order), 0) + 1 INTO v_sort FROM public.partner_channels;
    INSERT INTO public.partner_channels (name, target_url, reward_fc, sort_order, validation_enabled, telegram_chat_id)
    VALUES (v_name, v_url, v_reward, COALESCE((p_payload->>'sortOrder')::integer, v_sort), v_validate, v_chat)
    RETURNING * INTO c;
    PERFORM public.admin_log(p_admin_id, 'partners.create', 'partner', c.id::text, NULL,
      jsonb_build_object('name', c.name, 'rewardFc', c.reward_fc, 'validationEnabled', c.validation_enabled), NULL, '{}'::jsonb);
    RETURN jsonb_build_object('partner', jsonb_build_object('id', c.id, 'name', c.name, 'rewardFc', c.reward_fc,
      'sortOrder', c.sort_order, 'enabled', c.is_enabled, 'validationEnabled', c.validation_enabled, 'chatId', c.telegram_chat_id));
  END IF;

  SELECT * INTO c FROM public.partner_channels WHERE id = p_partner_id;
  IF c.id IS NULL THEN RAISE EXCEPTION 'PARTNER_NOT_FOUND'; END IF;

  IF p_action = 'detail' OR p_action = 'stats' THEN
    RETURN jsonb_build_object('partner', jsonb_build_object(
      'id', c.id, 'name', c.name, 'rewardFc', c.reward_fc, 'sortOrder', c.sort_order,
      'enabled', c.is_enabled, 'linkConfigured', true,
      'validationEnabled', c.validation_enabled, 'chatId', c.telegram_chat_id,
      'urlHost', split_part(regexp_replace(c.target_url, '^https?://', ''), '/', 1),
      'url', c.target_url,
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
  ELSIF p_action = 'chat' THEN
    -- Chat id is only ever used for membership validation; it is never the GO link.
    v_chat := NULLIF(btrim(COALESCE(p_payload->>'chatId', '')), '');
    IF v_chat IS NULL THEN RAISE EXCEPTION 'MISSING_CHAT_ID'; END IF;
    UPDATE public.partner_channels
       SET telegram_chat_id = v_chat,
           validation_enabled = COALESCE((p_payload->>'validationEnabled')::boolean, c.validation_enabled)
     WHERE id = c.id;
    PERFORM public.admin_log(p_admin_id, 'partners.chat', 'partner', c.id::text,
      jsonb_build_object('chatId', c.telegram_chat_id), jsonb_build_object('chatId', v_chat), NULL, '{}'::jsonb);
  ELSIF p_action = 'validation' THEN
    v_validate := COALESCE((p_payload->>'validationEnabled')::boolean, NOT c.validation_enabled);
    IF v_validate AND NULLIF(btrim(COALESCE(c.telegram_chat_id, '')), '') IS NULL THEN RAISE EXCEPTION 'MISSING_CHAT_ID'; END IF;
    UPDATE public.partner_channels SET validation_enabled = v_validate WHERE id = c.id;
    PERFORM public.admin_log(p_admin_id, 'partners.validation', 'partner', c.id::text,
      jsonb_build_object('validationEnabled', c.validation_enabled), jsonb_build_object('validationEnabled', v_validate), NULL, '{}'::jsonb);
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
    UPDATE public.partner_channels SET is_enabled = false, name = c.name WHERE id = c.id;
    PERFORM public.admin_log(p_admin_id, 'partners.delete', 'partner', c.id::text,
      jsonb_build_object('name', c.name, 'enabled', c.is_enabled), jsonb_build_object('enabled', false), 'soft delete', '{}'::jsonb);
  ELSE
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  RETURN public.admin_partners(p_admin_id, 'detail', c.id, '{}'::jsonb);
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_partners(bigint, text, uuid, jsonb) FROM anon, authenticated;

-- ------------------------------------------------------------------ player facing list
CREATE OR REPLACE FUNCTION public.get_partner_channels(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
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
      -- The chat id itself is never exposed: only whether a membership check runs.
      'requiresValidation', c.validation_enabled,
      'rewardReceived', COALESCE(k.reward_fc, 0)
    ) ORDER BY c.sort_order, c.created_at)
    FROM public.partner_channels c
    LEFT JOIN public.partner_claims k ON k.partner_id = c.id AND k.user_id = v_user
    WHERE c.is_enabled
  ), '[]'::jsonb));
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_partner_channels(bigint) FROM anon, authenticated;

-- ------------------------------------------------------------------ claim with optional membership proof
CREATE OR REPLACE FUNCTION public.claim_partner_reward(p_telegram_id bigint, p_partner_id uuid, p_membership_verified boolean DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE u public.game_players%rowtype; c public.partner_channels%rowtype; k public.partner_claims%rowtype;
        v_before numeric; v_after numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('partner_reward:' || p_telegram_id::text || ':' || p_partner_id::text, 0));

  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  SELECT * INTO c FROM public.partner_channels WHERE id = p_partner_id AND is_enabled;
  IF c.id IS NULL THEN RAISE EXCEPTION 'PARTNER_NOT_AVAILABLE'; END IF;

  SELECT * INTO k FROM public.partner_claims WHERE partner_id = c.id AND user_id = u.id FOR UPDATE;
  IF k.id IS NULL THEN RAISE EXCEPTION 'PARTNER_NOT_VISITED'; END IF;

  IF k.status = 'claimed' THEN
    RETURN public.get_partner_channels(p_telegram_id)
      || jsonb_build_object('status','already_claimed','creditedFc',0,'balance',u.forge_coins);
  END IF;

  -- When validation is on, the edge function must prove membership before paying.
  IF c.validation_enabled AND COALESCE(p_membership_verified, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'PARTNER_NOT_JOINED';
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
$fn$;

REVOKE ALL ON FUNCTION public.claim_partner_reward(bigint, uuid, boolean) FROM anon, authenticated;

-- Server-only lookup of the validation target for a partner (chat id never reaches the client).
CREATE OR REPLACE FUNCTION public.partner_validation_target(p_partner_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT jsonb_build_object('validationEnabled', c.validation_enabled, 'chatId', c.telegram_chat_id)
  FROM public.partner_channels c WHERE c.id = p_partner_id AND c.is_enabled
$fn$;

REVOKE ALL ON FUNCTION public.partner_validation_target(uuid) FROM anon, authenticated;

-- ------------------------------------------------------------------ hot wallet control
CREATE OR REPLACE FUNCTION public.admin_wallet_config(p_admin_id bigint, p_action text DEFAULT 'get', p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE v_addr text; v_num numeric; v_old text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  IF p_action = 'set_hot_wallet' THEN
    v_addr := NULLIF(btrim(COALESCE(p_payload->>'address', '')), '');
    IF v_addr IS NULL OR length(v_addr) < 40 OR length(v_addr) > 80 OR v_addr !~ '^[A-Za-z0-9_:-]+$' THEN
      RAISE EXCEPTION 'INVALID_ADDRESS';
    END IF;
    SELECT value_text INTO v_old FROM public.wallet_settings WHERE key = 'ton_hot_wallet';
    INSERT INTO public.wallet_settings (key, value_text) VALUES ('ton_hot_wallet', v_addr)
    ON CONFLICT (key) DO UPDATE SET value_text = EXCLUDED.value_text, updated_at = now();
    PERFORM public.admin_log(p_admin_id, 'wallet.hot_wallet', 'wallet', 'ton_hot_wallet',
      jsonb_build_object('address', v_old), jsonb_build_object('address', v_addr), NULL, '{}'::jsonb);
  ELSIF p_action = 'set_min_withdraw' THEN
    v_num := (p_payload->>'value')::numeric;
    IF v_num IS NULL OR v_num < 0 OR v_num > 100000 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    INSERT INTO public.wallet_settings (key, value_numeric) VALUES ('min_withdraw_ton', v_num)
    ON CONFLICT (key) DO UPDATE SET value_numeric = EXCLUDED.value_numeric, updated_at = now();
    PERFORM public.admin_log(p_admin_id, 'wallet.min_withdraw', 'wallet', 'min_withdraw_ton', NULL,
      jsonb_build_object('value', v_num), NULL, '{}'::jsonb);
  ELSIF p_action <> 'get' THEN
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  RETURN jsonb_build_object(
    'hotWallet', (SELECT value_text FROM public.wallet_settings WHERE key = 'ton_hot_wallet'),
    'minWithdrawTon', (SELECT value_numeric FROM public.wallet_settings WHERE key = 'min_withdraw_ton'),
    'updatedAt', (SELECT max(updated_at) FROM public.wallet_settings WHERE key IN ('ton_hot_wallet','min_withdraw_ton')),
    'pendingWithdrawals', (SELECT count(*) FROM public.wallet_withdrawals WHERE status IN ('pending','locked')),
    'depositsToday', (SELECT count(*) FROM public.wallet_deposits WHERE created_at > now() - interval '24 hours')
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_wallet_config(bigint, text, jsonb) FROM anon, authenticated;