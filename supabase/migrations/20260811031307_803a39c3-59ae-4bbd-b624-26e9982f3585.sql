-- public read of hero images (bucket is private; policy allows anon/authenticated reads)
CREATE POLICY "Hero images are publicly readable"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (bucket_id = 'hero-images');

CREATE OR REPLACE FUNCTION public.admin_next_hero_key(p_admin_id bigint, p_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_base text; v_key text; v_i int := 2;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_base := lower(btrim(coalesce(p_name, '')));
  v_base := translate(v_base,
    'áàâãäéèêëíìîïóòôõöúùûüçñ',
    'aaaaaeeeeiiiiooooouuuucn');
  v_base := regexp_replace(v_base, '[^a-z0-9]+', '_', 'g');
  v_base := btrim(regexp_replace(v_base, '_+', '_', 'g'), '_');
  IF v_base = '' THEN v_base := 'hero'; END IF;
  v_base := left(v_base, 48);
  v_key := v_base;
  WHILE EXISTS (SELECT 1 FROM public.hero_catalog WHERE hero_key = v_key) LOOP
    v_key := v_base || '_' || v_i;
    v_i := v_i + 1;
  END LOOP;
  RETURN v_key;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_search_heroes(p_admin_id bigint, p_query text DEFAULT NULL, p_limit int DEFAULT 12)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v jsonb; v_q text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_q := '%' || lower(btrim(coalesce(p_query, ''))) || '%';
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.sort_order, t.name), '[]'::jsonb) INTO v FROM (
    SELECT hero_key, name, rarity, hero_class, enabled, in_shop, price_fc, base_atk, base_hp, image, sort_order
    FROM public.hero_catalog
    WHERE p_query IS NULL OR btrim(p_query) = '' OR lower(name) LIKE v_q OR lower(hero_key) LIKE v_q
    ORDER BY sort_order, name
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 12), 40))
  ) t;
  RETURN jsonb_build_object('heroes', v);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_catalog_hero(p_admin_id bigint, p_hero_key text, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_old jsonb; v_owned int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(c) INTO v_old FROM public.hero_catalog c WHERE c.hero_key = p_hero_key;
  IF v_old IS NULL THEN RAISE EXCEPTION 'hero_not_found'; END IF;
  SELECT count(*) INTO v_owned FROM public.player_heroes WHERE hero_key = p_hero_key;
  IF v_owned > 0 THEN
    UPDATE public.hero_catalog SET enabled = false, in_shop = false, updated_at = now() WHERE hero_key = p_hero_key;
    PERFORM public.admin_log(p_admin_id, 'hero.disable', 'hero', p_hero_key, v_old, NULL, p_reason);
    PERFORM public.admin_bump_settings_version();
    RETURN jsonb_build_object('mode', 'disabled', 'owned', v_owned, 'name', v_old->>'name');
  END IF;
  DELETE FROM public.hero_catalog WHERE hero_key = p_hero_key;
  PERFORM public.admin_log(p_admin_id, 'hero.delete', 'hero', p_hero_key, v_old, NULL, p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN jsonb_build_object('mode', 'deleted', 'owned', 0, 'name', v_old->>'name');
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_next_hero_key(bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_search_heroes(bigint, text, int) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_catalog_hero(bigint, text, text) TO service_role;