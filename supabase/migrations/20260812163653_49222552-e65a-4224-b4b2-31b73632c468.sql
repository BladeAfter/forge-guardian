-- 1) Official single-signature audit logger (old/new values now optional)
CREATE OR REPLACE FUNCTION public.admin_log(
  p_admin_id bigint,
  p_action text,
  p_target_type text,
  p_target_id text,
  p_old jsonb DEFAULT NULL,
  p_new jsonb DEFAULT NULL,
  p_reason text DEFAULT NULL,
  p_context jsonb DEFAULT '{}'::jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.admin_audit_logs (admin_id, action, target_type, target_id, old_value, new_value, reason, context)
  VALUES (p_admin_id, COALESCE(p_action,'unknown'), COALESCE(p_target_type,'system'), p_target_id, p_old, p_new, p_reason, COALESCE(p_context,'{}'::jsonb))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- 2) Hero shop rarity toggle: config + audit in the same transaction, canonical admin_log call
CREATE OR REPLACE FUNCTION public.admin_set_hero_rarity_enabled(p_admin_id bigint, p_rarity text, p_enabled boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_rarity text := lower(trim(coalesce(p_rarity, ''))); v_flags jsonb; v_old jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_rarity NOT IN ('common','uncommon','rare','epic','legendary','mythic') THEN
    RAISE EXCEPTION 'RARITY_NOT_TOGGLEABLE:%', v_rarity;
  END IF;
  v_old := public.hero_recruit_rarity_flags();
  v_flags := v_old || jsonb_build_object(v_rarity, coalesce(p_enabled, true));

  -- at least one rarity with an actual hero pool must stay open
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_each(v_flags) f
     WHERE (f.value)::text::boolean
       AND COALESCE((public.hero_summon_rates() #>> ARRAY[f.key])::numeric, 0) > 0
       AND EXISTS (SELECT 1 FROM public.hero_catalog c WHERE c.rarity = f.key AND c.enabled AND c.recruit_enabled)
  ) THEN RAISE EXCEPTION 'LAST_ACTIVE_RARITY'; END IF;

  INSERT INTO public.game_settings(key, value) VALUES ('hero_recruit_rarity_enabled', v_flags)
    ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now();
  PERFORM public.admin_bump_settings_version();
  PERFORM public.admin_log(
    p_admin_id,
    'hero_rarity_toggle',
    'game_settings',
    v_rarity,
    jsonb_build_object('enabled', COALESCE((v_old #>> ARRAY[v_rarity])::boolean, true)),
    jsonb_build_object('enabled', coalesce(p_enabled, true)),
    'painel admin',
    '{}'::jsonb
  );
  RETURN public.admin_hero_rarity_flags(p_admin_id);
END; $function$;

-- 3) Patch remaining non-canonical admin_log calls (clan boss + daily quest repair)
DO $do$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'admin_clan_boss';
  IF v_def IS NOT NULL THEN
    v_def := replace(v_def,
      'public.admin_log(p_admin_id, ''clan_boss_config'', p_ref, p_payload)',
      'public.admin_log(p_admin_id, ''clan_boss_config'', ''clan_boss'', p_ref, NULL::jsonb, p_payload, ''painel admin'', ''{}''::jsonb)');
    v_def := replace(v_def,
      'public.admin_log(p_admin_id, ''clan_boss_force_start'', p_ref, jsonb_build_object(''cycle'', b.cycle, ''maxHp'', b.max_hp))',
      'public.admin_log(p_admin_id, ''clan_boss_force_start'', ''clan_boss'', p_ref, NULL::jsonb, jsonb_build_object(''cycle'', b.cycle, ''maxHp'', b.max_hp), ''painel admin'', ''{}''::jsonb)');
    v_def := replace(v_def,
      'public.admin_log(p_admin_id, ''clan_boss_end_cycle'', p_ref, p_payload)',
      'public.admin_log(p_admin_id, ''clan_boss_end_cycle'', ''clan_boss'', p_ref, NULL::jsonb, p_payload, ''painel admin'', ''{}''::jsonb)');
    EXECUTE v_def;
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'admin_repair_daily_quests';
  IF v_def IS NOT NULL THEN
    v_def := replace(v_def,
      'public.admin_log(p_admin_id, NULL, ''quests_repair'', jsonb_build_object(''activeDailyCount'', v_total))',
      'public.admin_log(p_admin_id, ''quests_repair'', ''quests'', NULL, NULL::jsonb, jsonb_build_object(''activeDailyCount'', v_total), ''painel admin'', ''{}''::jsonb)');
    EXECUTE v_def;
  END IF;
END $do$;

-- 4) Player Market: qualify/rename locals that collided with game_players.ton_balance
CREATE OR REPLACE FUNCTION public.market_browse(p_telegram_id bigint, p_item_type text DEFAULT 'all'::text, p_rarity text DEFAULT 'all'::text, p_sort text DEFAULT 'newest'::text, p_limit integer DEFAULT 60, p_offset integer DEFAULT 0, p_currency text DEFAULT 'all'::text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare u uuid; v_balance_fc numeric := 0; v_pending_fc numeric := 0; v_ton_balance numeric := 0; v_pending_ton numeric := 0;
        rows_json jsonb; lim integer := least(greatest(coalesce(p_limit,60),1),100);
        cur text := upper(coalesce(p_currency,'all'));
begin
  if not market_can_access(p_telegram_id) then
    return jsonb_build_object('listings', '[]'::jsonb, 'balanceFc', 0, 'pendingFc', 0, 'balanceTon', 0, 'pendingTon', 0,
      'settings', market_settings_json(), 'eligibility', null, 'activeCount', 0,
      'status', market_status(p_telegram_id));
  end if;

  select g.id, g.forge_coins, g.market_pending_fc, coalesce(g.ton_balance,0), coalesce(g.market_pending_ton,0)
    into u, v_balance_fc, v_pending_fc, v_ton_balance, v_pending_ton
    from game_players g where g.telegram_id = p_telegram_id;

  update market_listings
     set status = 'active', reserved_for = null, reserved_until = null, updated_at = now()
   where status = 'reserved' and coalesce(reserved_until, now()) <= now();

  select coalesce(jsonb_agg(item), '[]'::jsonb) into rows_json from (
    select jsonb_build_object(
      'id', l.id, 'itemType', l.item_type, 'priceFc', l.price_fc, 'priceTon', l.price_ton,
      'currency', coalesce(l.currency,'FC'), 'quantity', l.quantity,
      'createdAt', l.created_at, 'mine', (l.seller_user_id = u),
      'reserved', l.status = 'reserved',
      'seller', coalesce(l.snapshot->>'seller', market_seller_label(l.seller_user_id)),
      'name', coalesce(l.snapshot->>'name','Item'),
      'rarity', lower(coalesce(l.snapshot->>'rarity','common')),
      'level', coalesce((l.snapshot->>'level')::integer, 1),
      'image', l.snapshot->>'image',
      'atk', coalesce((l.snapshot->>'atk')::numeric, 0),
      'hp', coalesce((l.snapshot->>'hp')::numeric, 0),
      'stars', coalesce((l.snapshot->>'stars')::integer, 0)
    ) as item
    from market_listings l
    where l.status in ('active','reserved')
      and (l.risk_level <> 'high' or l.seller_user_id = u)
      and (coalesce(p_item_type,'all') = 'all' or l.item_type = p_item_type)
      and (cur = 'ALL' or coalesce(l.currency,'FC') = cur)
      and (coalesce(p_rarity,'all') = 'all' or lower(coalesce(l.snapshot->>'rarity','common')) = lower(p_rarity))
    order by
      case when p_sort = 'price_low' then coalesce(l.price_fc, l.price_ton * 100000) end asc nulls last,
      case when p_sort = 'price_high' then coalesce(l.price_fc, l.price_ton * 100000) end desc nulls last,
      l.created_at desc
    limit lim offset greatest(coalesce(p_offset,0),0)
  ) q;

  return jsonb_build_object('listings', rows_json, 'balanceFc', coalesce(v_balance_fc,0),
    'pendingFc', coalesce(v_pending_fc,0), 'balanceTon', coalesce(v_ton_balance,0), 'pendingTon', coalesce(v_pending_ton,0),
    'settings', market_settings_json(),
    'eligibility', case when u is null then null else market_sell_eligibility(u) end,
    'status', market_status(p_telegram_id),
    'activeCount', (select count(*) from market_listings ml where ml.seller_user_id = u and ml.status in ('active','reserved')));
end $function$;

REVOKE ALL ON FUNCTION public.admin_log(bigint, text, text, text, jsonb, jsonb, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_hero_rarity_enabled(bigint, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.market_browse(bigint, text, text, text, integer, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_log(bigint, text, text, text, jsonb, jsonb, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_hero_rarity_enabled(bigint, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.market_browse(bigint, text, text, text, integer, integer, text) TO service_role;