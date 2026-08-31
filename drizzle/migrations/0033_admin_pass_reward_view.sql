CREATE OR REPLACE FUNCTION public.admin_pass_reward_view(p_admin_id bigint, p_reward_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r public.season_pass_rewards%rowtype; v_version uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO r FROM public.season_pass_rewards WHERE id = p_reward_id;
  IF r.id IS NULL THEN RAISE EXCEPTION 'REWARD_NOT_FOUND'; END IF;
  SELECT v.id INTO v_version FROM public.pass_versions v WHERE v.season_id = r.season_id AND v.pass_type = r.tier LIMIT 1;
  RETURN jsonb_build_object('id', r.id, 'versionId', v_version, 'seasonId', r.season_id, 'tier', r.tier,
    'level', r.level, 'slot', r.reward_slot, 'type', r.reward_type, 'code', r.reward_code,
    'amount', r.amount, 'title', r.title, 'asset', r.reward_asset, 'requiresAsset', r.requires_asset,
    'assetOk', public.pass_reward_asset_ok(r), 'highlight', r.is_highlight, 'enabled', r.enabled);
END $$;