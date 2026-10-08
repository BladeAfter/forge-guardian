-- Tactical Arena: replace pgcrypto digest() (not installed) with native md5 for the match seed.
CREATE OR REPLACE FUNCTION public.tactical_start_match(p_a uuid, p_b uuid, p_practice boolean DEFAULT false)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_seed text;
  v_match uuid;
  v_state jsonb;
  v_cfg jsonb := public.tactical_config();
BEGIN
  v_seed := md5(p_a::text || COALESCE(p_b::text, 'ai') || clock_timestamp()::text || random()::text);
  v_state := public.tactical_build_state(p_a, p_b, v_seed);

  INSERT INTO public.tactical_matches (
    player_a_id, player_b_id, practice, status, turn, seed, state,
    turn_deadline, created_at, updated_at
  ) VALUES (
    p_a, p_b, COALESCE(p_practice, false), 'active', 1, v_seed, v_state,
    now() + make_interval(secs => COALESCE((v_cfg->>'turnTimerSeconds')::numeric, 15)),
    now(), now()
  ) RETURNING id INTO v_match;

  DELETE FROM public.tactical_queue WHERE player_id = p_a OR (p_b IS NOT NULL AND player_id = p_b);
  RETURN v_match;
END;
$fn$;

REVOKE ALL ON FUNCTION public.tactical_start_match(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tactical_start_match(uuid, uuid, boolean) TO service_role;