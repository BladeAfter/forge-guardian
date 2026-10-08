ALTER TABLE public.user_channel_rewards ADD COLUMN IF NOT EXISTS telegram_id bigint;

UPDATE public.user_channel_rewards r
   SET telegram_id = p.telegram_id
  FROM public.game_players p
 WHERE p.id = r.user_id AND r.telegram_id IS NULL;

DELETE FROM public.user_channel_rewards WHERE telegram_id IS NULL;
ALTER TABLE public.user_channel_rewards ALTER COLUMN telegram_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS user_channel_rewards_telegram_key
  ON public.user_channel_rewards (telegram_id, channel_key);

CREATE OR REPLACE FUNCTION public.claim_channel_reward(p_telegram_id bigint, p_channel_key text, p_membership_ok boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE u public.game_players%rowtype; c public.channel_reward_config%rowtype; r public.user_channel_rewards%rowtype; v_before numeric; v_after numeric;
BEGIN
  -- One-time reward keyed by Telegram ID only: no membership / chat_id verification at all.
  PERFORM pg_advisory_xact_lock(hashtextextended('channel_reward:' || p_telegram_id::text || ':' || coalesce(p_channel_key,''), 0));

  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  SELECT * INTO c FROM public.channel_reward_config WHERE channel_key = p_channel_key AND enabled;
  IF c.channel_key IS NULL THEN RAISE EXCEPTION 'CHANNEL_NOT_AVAILABLE'; END IF;

  INSERT INTO public.user_channel_rewards (user_id, telegram_id, channel_key)
  VALUES (u.id, p_telegram_id, c.channel_key)
  ON CONFLICT (telegram_id, channel_key) DO NOTHING;

  SELECT * INTO r FROM public.user_channel_rewards
   WHERE telegram_id = p_telegram_id AND channel_key = c.channel_key FOR UPDATE;

  IF r.reward_claimed THEN
    RETURN public.get_channel_rewards(p_telegram_id) || jsonb_build_object('status','already_claimed','creditedFc',0,'balance',u.forge_coins);
  END IF;

  v_before := u.forge_coins;
  v_after := v_before + c.reward_fc;
  UPDATE public.game_players SET forge_coins = v_after, updated_at = now() WHERE id = u.id;
  UPDATE public.user_channel_rewards
     SET user_id = u.id, joined_verified = true, verified_at = coalesce(verified_at, now()),
         reward_claimed = true, reward_amount = c.reward_fc, claimed_at = now(), updated_at = now()
   WHERE id = r.id;

  INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id)
  VALUES (u.id, 'channel_reward', c.reward_fc, v_before, v_after, p_telegram_id::text || ':' || c.channel_key)
  ON CONFLICT DO NOTHING;

  RETURN public.get_channel_rewards(p_telegram_id) || jsonb_build_object('status','claimed','creditedFc',c.reward_fc,'balance',v_after);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_channel_rewards(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN jsonb_build_object('channels', coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'key', c.channel_key, 'title', c.title, 'subtitle', c.subtitle, 'url', c.url,
      'rewardFc', c.reward_fc, 'enabled', c.enabled,
      'verifiable', true,
      'joined', coalesce(r.reward_claimed,false),
      'claimed', coalesce(r.reward_claimed,false),
      'rewardReceived', coalesce(r.reward_amount,0),
      'claimedAt', r.claimed_at
    ) ORDER BY c.sort_order)
    FROM public.channel_reward_config c
    LEFT JOIN public.user_channel_rewards r
      ON r.channel_key = c.channel_key AND r.telegram_id = p_telegram_id
    WHERE c.enabled
  ), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_player_channel_claims(p_admin_id bigint, p_player text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE u public.game_players%rowtype;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO u FROM public.game_players
   WHERE telegram_id::text = trim(p_player) OR lower(coalesce(username,'')) = lower(ltrim(trim(p_player),'@')) OR id::text = trim(p_player)
   LIMIT 1;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN jsonb_build_object(
    'playerId', u.id, 'telegramId', u.telegram_id, 'username', u.username, 'name', u.display_name,
    'channels', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'key', c.channel_key, 'title', c.title, 'rewardFc', c.reward_fc,
        'claimed', coalesce(r.reward_claimed,false),
        'claimedAt', r.claimed_at, 'rewardReceived', coalesce(r.reward_amount,0)
      ) ORDER BY c.sort_order)
      FROM public.channel_reward_config c
      LEFT JOIN public.user_channel_rewards r
        ON r.channel_key = c.channel_key AND r.telegram_id = u.telegram_id
    ), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reset_channel_claim(p_admin_id bigint, p_player text, p_channel_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE u public.game_players%rowtype; v_deleted integer;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO u FROM public.game_players
   WHERE telegram_id::text = trim(p_player) OR lower(coalesce(username,'')) = lower(ltrim(trim(p_player),'@')) OR id::text = trim(p_player)
   LIMIT 1;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  DELETE FROM public.user_channel_rewards
   WHERE telegram_id = u.telegram_id AND channel_key = p_channel_key;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  PERFORM public.admin_log(p_admin_id, 'channel_reward_reset', 'player', u.id::text,
    jsonb_build_object('telegramId', u.telegram_id, 'channelKey', p_channel_key, 'removed', v_deleted));

  RETURN public.admin_player_channel_claims(p_admin_id, u.telegram_id::text) || jsonb_build_object('removed', v_deleted);
END;
$$;