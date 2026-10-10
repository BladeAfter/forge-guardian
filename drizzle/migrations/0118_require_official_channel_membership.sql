CREATE OR REPLACE FUNCTION public.claim_channel_reward(p_telegram_id bigint, p_channel_key text, p_membership_ok boolean DEFAULT false)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE u public.game_players%rowtype; c public.channel_reward_config%rowtype; r public.user_channel_rewards%rowtype; v_before numeric; v_after numeric;
BEGIN
  IF p_membership_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'CHANNEL_MEMBERSHIP_REQUIRED'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('channel_reward:' || p_telegram_id::text || ':' || coalesce(p_channel_key,''), 0));
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO c FROM public.channel_reward_config WHERE channel_key = p_channel_key AND enabled AND chat_ref IS NOT NULL;
  IF c.channel_key IS NULL THEN RAISE EXCEPTION 'CHANNEL_NOT_AVAILABLE'; END IF;
  INSERT INTO public.user_channel_rewards (user_id, telegram_id, channel_key) VALUES (u.id, p_telegram_id, c.channel_key) ON CONFLICT (telegram_id, channel_key) DO NOTHING;
  SELECT * INTO r FROM public.user_channel_rewards WHERE telegram_id = p_telegram_id AND channel_key = c.channel_key FOR UPDATE;
  IF r.reward_claimed THEN RETURN public.get_channel_rewards(p_telegram_id) || jsonb_build_object('status','already_claimed','creditedFc',0,'balance',u.forge_coins); END IF;
  v_before := u.forge_coins; v_after := v_before + c.reward_fc;
  UPDATE public.game_players SET forge_coins = v_after, updated_at = now() WHERE id = u.id;
  UPDATE public.user_channel_rewards SET user_id = u.id, joined_verified = true, verified_at = coalesce(verified_at, now()), reward_claimed = true, reward_amount = c.reward_fc, claimed_at = now(), updated_at = now() WHERE id = r.id;
  INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id) VALUES (u.id, 'channel_reward', c.reward_fc, v_before, v_after, p_telegram_id::text || ':' || c.channel_key) ON CONFLICT DO NOTHING;
  RETURN public.get_channel_rewards(p_telegram_id) || jsonb_build_object('status','claimed','creditedFc',c.reward_fc,'balance',v_after);
END;
$function$;
REVOKE ALL ON FUNCTION public.claim_channel_reward(bigint,text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_channel_reward(bigint,text,boolean) TO service_role;