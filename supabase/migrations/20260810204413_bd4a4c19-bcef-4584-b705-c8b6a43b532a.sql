CREATE OR REPLACE FUNCTION public.admin_channels_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object('channels', coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'key', c.channel_key, 'title', c.title, 'subtitle', c.subtitle, 'url', c.url,
      'chatRef', c.chat_ref, 'rewardFc', c.reward_fc, 'enabled', c.enabled,
      'claims', (SELECT count(*) FROM public.user_channel_rewards r WHERE r.channel_key = c.channel_key AND r.reward_claimed),
      'paidFc', (SELECT coalesce(sum(r.reward_amount),0) FROM public.user_channel_rewards r WHERE r.channel_key = c.channel_key AND r.reward_claimed)
    ) ORDER BY c.sort_order)
    FROM public.channel_reward_config c
  ), '[]'::jsonb));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_channel(p_admin_id bigint, p_channel_key text, p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.channel_reward_config%rowtype;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO c FROM public.channel_reward_config WHERE channel_key = p_channel_key FOR UPDATE;
  IF c.channel_key IS NULL THEN RAISE EXCEPTION 'CHANNEL_NOT_FOUND'; END IF;
  UPDATE public.channel_reward_config SET
    url = coalesce(nullif(p_patch->>'url',''), url),
    chat_ref = CASE WHEN p_patch ? 'chat_ref' THEN nullif(p_patch->>'chat_ref','') ELSE chat_ref END,
    reward_fc = coalesce((p_patch->>'reward_fc')::numeric, reward_fc),
    enabled = coalesce((p_patch->>'enabled')::boolean, enabled),
    updated_at = now()
  WHERE channel_key = p_channel_key
  RETURNING * INTO c;
  PERFORM public.admin_log(p_admin_id, 'channel_update', 'channel', p_channel_key, p_patch, 'painel admin');
  RETURN jsonb_build_object('key', c.channel_key, 'title', c.title, 'url', c.url, 'chatRef', c.chat_ref, 'rewardFc', c.reward_fc, 'enabled', c.enabled);
END; $$;

REVOKE EXECUTE ON FUNCTION public.admin_channels_overview(bigint) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_update_channel(bigint, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_channels_overview(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_update_channel(bigint, text, jsonb) TO service_role;