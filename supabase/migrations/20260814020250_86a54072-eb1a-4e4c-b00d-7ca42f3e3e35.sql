-- Central per-instance usage status (single source of truth for locks)
CREATE OR REPLACE FUNCTION public.hero_usage_status(p_hero_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'manuallyLocked', s.manual,
    'pvpAttack', s.atk,
    'pvpDefense', s.def,
    'globalBoss', s.boss,
    'clanBoss', false,
    'tower', s.tower,
    'marketplace', s.market,
    'isNft', s.nft,
    'canFuse', NOT (s.manual OR s.atk OR s.def OR s.boss OR s.tower OR s.market OR s.nft),
    'reason', CASE
      WHEN s.manual THEN 'MANUAL'
      WHEN s.atk THEN 'PVP_ATTACK'
      WHEN s.def THEN 'PVP_DEFENSE'
      WHEN s.boss THEN 'BOSS'
      WHEN s.tower THEN 'TOWER'
      WHEN s.market THEN 'MARKET'
      WHEN s.nft THEN 'NFT'
      ELSE NULL END
  )
  FROM (
    SELECT
      coalesce(ph.locked, false) AS manual,
      coalesce(ph.is_nft_exclusive, false) AS nft,
      EXISTS(SELECT 1 FROM public.pvp_team_slots t
              WHERE t.hero_id = ph.id AND t.user_id = ph.user_id AND t.team_type = 'attack') AS atk,
      EXISTS(SELECT 1 FROM public.pvp_team_slots t
              WHERE t.hero_id = ph.id AND t.user_id = ph.user_id AND t.team_type = 'defense') AS def,
      EXISTS(SELECT 1 FROM public.boss_team_slots b
              WHERE b.player_hero_id = ph.id AND b.user_id = ph.user_id) AS boss,
      EXISTS(SELECT 1 FROM public.tower_team_slots w
              WHERE w.hero_id = ph.id AND w.user_id = ph.user_id) AS tower,
      EXISTS(SELECT 1 FROM public.market_listings m
              WHERE m.item_instance_id = ph.id AND m.status = 'active') AS market
    FROM public.player_heroes ph
    WHERE ph.id = p_hero_id
  ) s;
$$;

REVOKE ALL ON FUNCTION public.hero_usage_status(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hero_usage_status(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_usage_status(uuid) TO service_role;

-- Material availability now derives from the same single source of truth
CREATE OR REPLACE FUNCTION public.hero_fusion_material_available(p_hero_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT coalesce((public.hero_usage_status(p_hero_id)->>'canFuse')::boolean, false);
$$;

REVOKE ALL ON FUNCTION public.hero_fusion_material_available(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hero_fusion_material_available(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_fusion_material_available(uuid) TO service_role;

-- Star fusion dashboard: expose per-instance usage + reason
CREATE OR REPLACE FUNCTION public.get_hero_fusion_dashboard(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare u uuid; cfg jsonb := hero_fusion_config(); balance numeric := 0; heroes jsonb;
begin
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id;
  if u is null then return jsonb_build_object('config', cfg, 'balance', 0, 'heroes', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(h order by h->>'name'), '[]'::jsonb) into heroes from (
    select jsonb_build_object(
      'heroId', ph.id, 'heroKey', ph.hero_key, 'name', ph.name, 'rarity', ph.rarity, 'level', ph.level,
      'imageUrl', ph.image, 'archetype', ph.archetype, 'stars', ph.fusion_level, 'locked', ph.locked,
      'isNft', ph.is_nft_exclusive, 'nftSerial', ph.nft_serial, 'nftInstance', ph.nft_instance_id,
      'finalAtk', round(ph.final_atk), 'finalHp', round(ph.final_hp),
      'power', round(ph.final_atk * 2 + ph.final_hp),
      'maxLevel', hero_max_level(ph.fusion_level),
      'usage', usage,
      'lockReason', usage->>'reason',
      'inTeam', coalesce((usage->>'pvpAttack')::boolean,false)
              or coalesce((usage->>'pvpDefense')::boolean,false)
              or coalesce((usage->>'globalBoss')::boolean,false)
              or coalesce((usage->>'tower')::boolean,false)
              or coalesce((usage->>'marketplace')::boolean,false),
      'duplicates', (
        select count(*) from player_heroes d
        where d.user_id = ph.user_id and d.hero_key = ph.hero_key and d.id <> ph.id
          and public.hero_fusion_material_available(d.id)
      ),
      'next', case when ph.is_nft_exclusive or ph.fusion_level >= coalesce((cfg->>'max_stars')::int,5) then null else jsonb_build_object(
        'stars', ph.fusion_level + 1,
        'costFc', coalesce((cfg->'cost_fc'->>(ph.fusion_level+1)::text)::numeric, 0),
        'duplicatesRequired', public.hero_fusion_required_copies(ph.fusion_level),
        'bonusPercent', coalesce((cfg->'bonus_percent'->>(ph.fusion_level+1)::text)::numeric, 0),
        'maxLevel', hero_max_level(ph.fusion_level + 1),
        'finalAtk', greatest(1, round((ph.base_atk + coalesce(ph.bonus_atk,0)) * power(1+ph.attack_growth, ph.level-1) * hero_fusion_multiplier(ph.fusion_level+1))),
        'finalHp', greatest(1, round((ph.base_hp + coalesce(ph.bonus_hp,0)) * power(1+ph.hp_growth, ph.level-1) * hero_fusion_multiplier(ph.fusion_level+1)))
      ) end
    ) as h
    from player_heroes ph
    cross join lateral (select public.hero_usage_status(ph.id) as usage) us
    where ph.user_id = u
  ) s;
  return jsonb_build_object('config', cfg, 'balance', balance, 'heroes', heroes);
end $function$;

-- Rarity fusion dashboard: same source of truth (adds tower + marketplace)
CREATE OR REPLACE FUNCTION public.get_rarity_fusion_dashboard(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_user uuid; v_bal numeric := 0; cfg jsonb := public.hero_rarity_fusion_config(); v_heroes jsonb; v_counts jsonb;
BEGIN
  SELECT id, forge_coins INTO v_user, v_bal FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('config', cfg, 'balance', 0, 'heroes', '[]'::jsonb, 'counts', '{}'::jsonb);
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'heroId', ph.id, 'heroKey', ph.hero_key, 'name', ph.name, 'rarity', ph.rarity,
      'level', ph.level, 'imageUrl', ph.image, 'stars', ph.fusion_level,
      'finalAtk', round(ph.final_atk), 'finalHp', round(ph.final_hp),
      'power', round(ph.final_atk * 2 + ph.final_hp),
      'locked', ph.locked,
      'equipped', NOT coalesce((us.usage->>'canFuse')::boolean, false) AND NOT coalesce(ph.locked,false),
      'usage', us.usage,
      'lockReason', us.usage->>'reason',
      'exclusive', ph.is_season_exclusive
    ) ORDER BY ph.created_at DESC), '[]'::jsonb) INTO v_heroes
  FROM public.player_heroes ph
  CROSS JOIN LATERAL (SELECT public.hero_usage_status(ph.id) AS usage) us
  WHERE ph.user_id = v_user AND NOT ph.is_nft_exclusive;
  SELECT coalesce(jsonb_object_agg(rarity, n), '{}'::jsonb) INTO v_counts FROM (
    SELECT rarity, count(*) AS n FROM public.player_heroes WHERE user_id = v_user AND NOT is_nft_exclusive GROUP BY rarity
  ) s;
  RETURN jsonb_build_object(
    'config', cfg, 'balance', v_bal, 'heroes', v_heroes, 'counts', v_counts,
    'fragments', coalesce((SELECT quantity FROM public.player_inventory WHERE user_id = v_user AND item_type='fragments' AND item_code='fragments'), 0),
    'history', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', h.id, 'sourceRarity', h.source_rarity, 'targetRarity', h.target_rarity,
        'success', h.success, 'costFc', h.fusion_cost_fc, 'chance', h.success_chance,
        'rewardHero', h.reward_hero_name, 'fragments', h.fragment_reward, 'createdAt', h.created_at
      ) ORDER BY h.created_at DESC) FROM (
        SELECT * FROM public.hero_rarity_fusion_history WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10
      ) h), '[]'::jsonb)
  );
END; $function$;

-- Clean stale market escrow flags (no active listing => hero is free again)
UPDATE public.player_heroes ph
SET market_locked = false, updated_at = now()
WHERE coalesce(ph.market_locked, false)
  AND NOT EXISTS (SELECT 1 FROM public.market_listings m
                  WHERE m.item_instance_id = ph.id AND m.status = 'active');