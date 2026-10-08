-- Common/Uncommon are no longer allowed to mine TON.
UPDATE public.hero_mining_rates SET ton_per_day = 0, updated_at = now()
 WHERE rarity IN ('common', 'uncommon');

-- Hard eligibility gate: rarity must be RARE or higher, regardless of the rate table.
CREATE OR REPLACE FUNCTION public.hero_mining_rarity_eligible(p_rarity text)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT lower(btrim(COALESCE(p_rarity, ''))) IN ('rare', 'epic', 'legendary', 'mythic', 'ancestral');
$$;

CREATE OR REPLACE FUNCTION public.hero_mining_rate(p_rarity text)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN hero_mining_rarity_eligible(p_rarity)
      THEN COALESCE((SELECT ton_per_day FROM hero_mining_rates WHERE rarity = lower(btrim(COALESCE(p_rarity, '')))), 0)
    ELSE 0
  END;
$$;

REVOKE ALL ON FUNCTION public.hero_mining_rarity_eligible(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_mining_rarity_eligible(text) TO service_role;
REVOKE ALL ON FUNCTION public.hero_mining_rate(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_mining_rate(text) TO service_role;