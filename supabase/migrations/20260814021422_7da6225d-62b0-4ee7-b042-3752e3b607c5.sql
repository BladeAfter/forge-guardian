-- 1. Config helpers -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fragment_summon_config()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT coalesce((SELECT value FROM game_settings WHERE key = 'fragment_summon_config'),
    jsonb_build_object('fragments_per_hero', 5,
      'rates', jsonb_build_object('common', 70, 'uncommon', 30)));
$$;

CREATE OR REPLACE FUNCTION public.universal_fusion_fragment_cost()
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT greatest(1, coalesce((SELECT (value)::text::int FROM game_settings WHERE key = 'universal_fusion_fragment_cost'), 25));
$$;

REVOKE ALL ON FUNCTION public.fragment_summon_config() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.universal_fusion_fragment_cost() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fragment_summon_config() TO service_role;
GRANT EXECUTE ON FUNCTION public.universal_fusion_fragment_cost() TO service_role;

-- 2. Summon history / idempotency ----------------------------------------
CREATE TABLE IF NOT EXISTS public.fragment_summon_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  idempotency_key text UNIQUE,
  fragments_spent integer NOT NULL,
  rolled_rarity text NOT NULL,
  hero_id uuid,
  hero_key text,
  hero_name text,
  result jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.fragment_summon_history TO service_role;
ALTER TABLE public.fragment_summon_history ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS fragment_summon_history_user_idx ON public.fragment_summon_history(user_id, created_at DESC);

-- 3. Fragment summon: 5 fragments -> 1 random common/uncommon hero -------
CREATE OR REPLACE FUNCTION public.summon_hero_with_fragments(p_telegram_id bigint, p_idempotency_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  u uuid; cfg jsonb := public.fragment_summon_config(); v_cost int; v_have int;
  v_common numeric; v_uncommon numeric; v_roll numeric; v_rarity text;
  picked public.hero_catalog%rowtype; v_new public.player_heroes%rowtype; v_left int; v_result jsonb; v_existing jsonb;
BEGIN
  IF p_idempotency_key IS NOT NULL AND length(p_idempotency_key) > 0 THEN
    SELECT result INTO v_existing FROM public.fragment_summon_history WHERE idempotency_key = p_idempotency_key;
    IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;
  END IF;

  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('fragment_summon:' || u::text, 0));

  v_cost := greatest(1, coalesce((cfg->>'fragments_per_hero')::int, 5));
  SELECT quantity INTO v_have FROM public.player_inventory
   WHERE user_id = u AND item_type = 'fragments' AND item_code = 'fragments' FOR UPDATE;
  IF coalesce(v_have, 0) < v_cost THEN RAISE EXCEPTION 'NOT_ENOUGH_FRAGMENTS'; END IF;

  v_common := greatest(0, coalesce((cfg->'rates'->>'common')::numeric, 70));
  v_uncommon := greatest(0, coalesce((cfg->'rates'->>'uncommon')::numeric, 30));
  IF v_common + v_uncommon <= 0 THEN v_common := 1; v_uncommon := 0; END IF;
  v_roll := random() * (v_common + v_uncommon);
  v_rarity := CASE WHEN v_roll < v_common THEN 'common' ELSE 'uncommon' END;

  SELECT * INTO picked FROM public.hero_catalog
   WHERE enabled AND NOT is_nft_exclusive AND public.normalize_hero_rarity(rarity) = v_rarity
   ORDER BY random() LIMIT 1;
  IF picked.hero_key IS NULL THEN
    SELECT * INTO picked FROM public.hero_catalog
     WHERE enabled AND NOT is_nft_exclusive
       AND public.normalize_hero_rarity(rarity) IN ('common','uncommon')
     ORDER BY random() LIMIT 1;
    v_rarity := public.normalize_hero_rarity(picked.rarity);
  END IF;
  IF picked.hero_key IS NULL THEN RAISE EXCEPTION 'NO_ELIGIBLE_HERO'; END IF;

  UPDATE public.player_inventory SET quantity = quantity - v_cost, updated_at = now()
   WHERE user_id = u AND item_type = 'fragments' AND item_code = 'fragments'
   RETURNING quantity INTO v_left;

  INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image)
  VALUES (u, picked.hero_key, picked.name, public.normalize_hero_rarity(picked.rarity), 1, picked.image)
  RETURNING * INTO v_new;

  v_result := jsonb_build_object(
    'fragmentsSpent', v_cost,
    'fragmentsLeft', coalesce(v_left, 0),
    'rarity', v_rarity,
    'hero', jsonb_build_object('heroId', v_new.id, 'heroKey', v_new.hero_key, 'name', v_new.name,
      'rarity', v_new.rarity, 'level', v_new.level, 'imageUrl', v_new.image,
      'finalAtk', round(v_new.final_atk), 'finalHp', round(v_new.final_hp),
      'power', round(v_new.final_atk * 2 + v_new.final_hp)));

  INSERT INTO public.fragment_summon_history(user_id, idempotency_key, fragments_spent, rolled_rarity, hero_id, hero_key, hero_name, result)
  VALUES (u, nullif(p_idempotency_key, ''), v_cost, v_rarity, v_new.id, v_new.hero_key, v_new.name, v_result);

  RETURN v_result;
END $$;

REVOKE ALL ON FUNCTION public.summon_hero_with_fragments(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.summon_hero_with_fragments(bigint, text) TO service_role;

-- 4. Star fusion: allow 25 universal fragments instead of hero copies ----
DROP FUNCTION IF EXISTS public.fuse_heroes(bigint, uuid, uuid[]);

CREATE OR REPLACE FUNCTION public.fuse_heroes(
  p_telegram_id bigint,
  p_main_hero_id uuid,
  p_material_ids uuid[] DEFAULT '{}'::uuid[],
  p_use_fragments boolean DEFAULT false,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u uuid; balance numeric; cfg jsonb := hero_fusion_config(); main player_heroes%rowtype;
  required int; cost numeric; max_stars int; ids uuid[] := '{}'::uuid[]; used int := 0;
  after_row player_heroes%rowtype; after_balance numeric;
  frag_cost int := 0; frag_left int := null; v_key text;
begin
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('hero_fusion:' || u::text, 0));

  v_key := nullif(p_idempotency_key, '');
  if v_key is not null and exists (
    select 1 from hero_fusion_history where user_id = u and idempotency_key = v_key
  ) then
    raise exception 'DUPLICATE_REQUEST';
  end if;

  select * into main from player_heroes where id = p_main_hero_id and user_id = u for update;
  if main.id is null then raise exception 'HERO_NOT_OWNED'; end if;
  if main.is_nft_exclusive then raise exception 'NFT_HERO_UNIQUE'; end if;

  max_stars := coalesce((cfg->>'max_stars')::int, 5);
  if main.fusion_level >= max_stars then raise exception 'HERO_MAX_STARS'; end if;
  required := public.hero_fusion_required_copies(main.fusion_level);
  cost := coalesce((cfg->'cost_fc'->>(main.fusion_level+1)::text)::numeric, 0);
  if balance < cost then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;

  if p_use_fragments then
    -- Universal fragments fully replace the required copies for this single step.
    frag_cost := public.universal_fusion_fragment_cost();
    if public.universal_fragment_balance(u) < frag_cost then raise exception 'NOT_ENOUGH_UNIVERSAL_FRAGMENTS'; end if;
    update player_pet_inventory set quantity = quantity - frag_cost, updated_at = now()
      where user_id = u and item_type = 'universal_fragment' and item_id is null
      returning quantity into frag_left;
    if frag_left is null or frag_left < 0 then raise exception 'NOT_ENOUGH_UNIVERSAL_FRAGMENTS'; end if;
  else
    if exists(select 1 from player_heroes where id = any(coalesce(p_material_ids,'{}'::uuid[])) and is_nft_exclusive) then
      raise exception 'NFT_HERO_UNIQUE';
    end if;
    select coalesce(array_agg(id), '{}') into ids from (
      select ph.id from player_heroes ph
      where ph.user_id = u and ph.id <> main.id and ph.hero_key = main.hero_key
        and ph.id = any(coalesce(p_material_ids, '{}'::uuid[]))
        and public.hero_fusion_material_available(ph.id)
      order by ph.fusion_level, ph.level
      limit required
      for update
    ) s;
    used := coalesce(array_length(ids,1), 0);
    if used < required then raise exception 'NOT_ENOUGH_DUPLICATES'; end if;
  end if;

  update game_players set forge_coins = forge_coins - cost, updated_at = now() where id = u returning forge_coins into after_balance;

  if not p_use_fragments then
    delete from hero_combat_state where hero_id = any(ids);
    delete from player_heroes where id = any(ids) and user_id = u;
  end if;

  update player_heroes set fusion_level = fusion_level + 1, updated_at = now() where id = main.id returning * into after_row;

  insert into hero_fusion_history(user_id, hero_id, hero_key, from_stars, to_stars, materials_consumed, material_ids, cost_fc,
      atk_before, atk_after, hp_before, hp_after, universal_fragments_spent, idempotency_key)
  values (u, main.id, main.hero_key, main.fusion_level, after_row.fusion_level, used, ids, cost,
      main.final_atk, after_row.final_atk, main.final_hp, after_row.final_hp, frag_cost, v_key);

  return jsonb_build_object(
    'heroId', main.id, 'name', after_row.name, 'fromStars', main.fusion_level, 'toStars', after_row.fusion_level,
    'atkBefore', round(main.final_atk), 'atkAfter', round(after_row.final_atk),
    'hpBefore', round(main.final_hp), 'hpAfter', round(after_row.final_hp),
    'bonusPercent', coalesce((cfg->'bonus_percent'->>after_row.fusion_level::text)::numeric, 0),
    'maxLevel', hero_max_level(after_row.fusion_level),
    'costFc', cost, 'consumed', used, 'balance', after_balance,
    'usedFragments', p_use_fragments, 'fragmentsSpent', frag_cost,
    'universalFragments', public.universal_fragment_balance(u),
    'dashboard', get_hero_fusion_dashboard(p_telegram_id)
  );
end $function$;

ALTER TABLE public.hero_fusion_history
  ADD COLUMN IF NOT EXISTS universal_fragments_spent integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS idempotency_key text;

CREATE UNIQUE INDEX IF NOT EXISTS hero_fusion_history_idem_idx
  ON public.hero_fusion_history(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

REVOKE ALL ON FUNCTION public.fuse_heroes(bigint, uuid, uuid[], boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fuse_heroes(bigint, uuid, uuid[], boolean, text) TO service_role;

-- 5. Admin config setter -------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_fragment_utility(
  p_admin_id bigint,
  p_fragments_per_hero integer DEFAULT NULL,
  p_common_chance numeric DEFAULT NULL,
  p_uncommon_chance numeric DEFAULT NULL,
  p_fragments_per_fusion integer DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg jsonb := public.fragment_summon_config();
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_fragments_per_hero IS NOT NULL THEN
    cfg := jsonb_set(cfg, '{fragments_per_hero}', to_jsonb(greatest(1, p_fragments_per_hero)));
  END IF;
  IF p_common_chance IS NOT NULL THEN
    cfg := jsonb_set(cfg, '{rates,common}', to_jsonb(greatest(0, p_common_chance)));
  END IF;
  IF p_uncommon_chance IS NOT NULL THEN
    cfg := jsonb_set(cfg, '{rates,uncommon}', to_jsonb(greatest(0, p_uncommon_chance)));
  END IF;
  IF coalesce((cfg->'rates'->>'common')::numeric,0) + coalesce((cfg->'rates'->>'uncommon')::numeric,0) <= 0 THEN
    RAISE EXCEPTION 'INVALID_RATES';
  END IF;
  PERFORM public.admin_set_setting(p_admin_id, 'fragment_summon_config', cfg, 'fragment summon config');
  IF p_fragments_per_fusion IS NOT NULL THEN
    PERFORM public.admin_set_setting(p_admin_id, 'universal_fusion_fragment_cost',
      to_jsonb(greatest(1, p_fragments_per_fusion)), 'universal fragments per fusion step');
  END IF;
  RETURN jsonb_build_object('summon', public.fragment_summon_config(),
    'fragmentsPerFusion', public.universal_fusion_fragment_cost());
END $$;

REVOKE ALL ON FUNCTION public.admin_set_fragment_utility(bigint, integer, numeric, numeric, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_fragment_utility(bigint, integer, numeric, numeric, integer) TO service_role;