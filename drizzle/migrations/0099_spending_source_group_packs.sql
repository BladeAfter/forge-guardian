-- Premium packs (celestial, sovereign, vanguard, adventurer, mythic power) belong to the "packs" group.
CREATE OR REPLACE FUNCTION public.spending_source_group(p_source_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN lower(COALESCE(p_source_type,'')) LIKE '%pack%' OR lower(COALESCE(p_source_type,'')) LIKE 'veteran%'
      OR lower(COALESCE(p_source_type,'')) LIKE 'premium_egg%' THEN 'packs'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'ton_direct_deposit%' THEN 'ton_direct_deposit'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'ton_to_fc%' OR lower(COALESCE(p_source_type,'')) LIKE 'deposit_credit%' THEN 'ton_to_fc'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'myth%' THEN 'myth_sale'
    WHEN lower(COALESCE(p_source_type,'')) LIKE '%pass%' THEN 'season_pass'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'nft%' THEN 'nft_shop'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'market%' THEN 'marketplace'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'auction%' THEN 'auction'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'fc%' OR lower(COALESCE(p_source_type,'')) LIKE '%_fc_spend%' THEN 'fc_spend'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'other_ton%' THEN 'other_ton'
    ELSE 'fc_spend'
  END
$function$;