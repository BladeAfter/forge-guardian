CREATE OR REPLACE FUNCTION public.player_owns_any_nft(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.nft_heroes WHERE owner_user_id = p_user_id AND COALESCE(status,'active') <> 'revoked')
      OR EXISTS (SELECT 1 FROM public.nft_pets WHERE owner_user_id = p_user_id AND COALESCE(status,'active') <> 'revoked')
      OR EXISTS (SELECT 1 FROM public.nft_equipment WHERE owner_user_id = p_user_id AND COALESCE(status,'active') <> 'revoked');
$function$;

CREATE OR REPLACE FUNCTION public.player_ton_withdraw_locked(p_user_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN public.ton_mining_has_paid_v2_pass(p_user_id) OR public.player_owns_any_nft(p_user_id) THEN 0
    ELSE round(GREATEST(0, LEAST(
      GREATEST(public.withdraw_min_deposit_ton(), 0),
      public.player_ton_deposit_total(p_user_id),
      COALESCE((SELECT ton_balance FROM game_players WHERE id = p_user_id), 0)
    )), 6)
  END;
$function$;