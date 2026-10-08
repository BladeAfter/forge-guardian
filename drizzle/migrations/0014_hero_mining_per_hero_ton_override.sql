ALTER TABLE public.player_heroes
  ADD COLUMN IF NOT EXISTS mining_ton_override numeric;

CREATE OR REPLACE FUNCTION public.hero_mining_row_rate(p_override numeric, p_rarity text, p_nft_hero_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_override IS NOT NULL THEN GREATEST(p_override, 0)
    ELSE public.hero_mining_hero_rate(p_rarity, p_nft_hero_id)
  END;
$$;

DO $patch$
DECLARE r record; v_def text;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('hero_mining_accrue','claim_hero_mining','hero_mining_settle_all','get_hero_mining_state')
       AND p.prosrc LIKE '%hero_mining_hero_rate(h.rarity, h.nft_hero_id)%'
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_def := replace(v_def,
      'hero_mining_hero_rate(h.rarity, h.nft_hero_id)',
      'hero_mining_row_rate(h.mining_ton_override, h.rarity, h.nft_hero_id)');
    EXECUTE v_def;
  END LOOP;
END
$patch$;
