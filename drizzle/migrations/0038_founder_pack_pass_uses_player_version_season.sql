-- 1) Founder Pack agora entrega o passe na temporada/versão que o jogador realmente vê.
CREATE OR REPLACE FUNCTION public.founder_pack_pass_season(p_user_id uuid, p_snapshot jsonb)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_season uuid;
BEGIN
  v_season := public.pass_user_season_id(p_user_id);
  IF v_season IS NOT NULL THEN RETURN v_season; END IF;
  v_season := nullif(p_snapshot->>'seasonId','')::uuid;
  IF v_season IS NOT NULL THEN RETURN v_season; END IF;
  SELECT id INTO v_season FROM public.season_pass_seasons WHERE active ORDER BY created_at DESC LIMIT 1;
  RETURN v_season;
END $$;

REVOKE ALL ON FUNCTION public.founder_pack_pass_season(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.founder_pack_pass_season(uuid, jsonb) TO service_role;

-- 2) Corrige o jogador @SFO_BAYAREA_MINER: passe do Founder Pack entregue na temporada errada.
DO $$
DECLARE v_user uuid := '61727fe2-2cae-4dea-8e47-cd3cfe09a505';
        v_season uuid;
BEGIN
  v_season := public.pass_user_season_id(v_user);
  IF v_season IS NOT NULL THEN
    PERFORM public.season_pass_apply_entitlement(v_user, v_season, 'legendary');
    UPDATE public.founder_pack_purchases
       SET delivery = delivery || jsonb_build_object('pass', jsonb_build_object('seasonId', v_season, 'tier', 'legendary', 'repaired', true))
     WHERE user_id = v_user;
  END IF;
END $$;
