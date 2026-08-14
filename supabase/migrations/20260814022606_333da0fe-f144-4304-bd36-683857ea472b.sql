CREATE OR REPLACE FUNCTION public.admin_hero_mining_toggle(p_admin_id bigint, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_enabled boolean := COALESCE(p_enabled, true);
BEGIN
  PERFORM admin_assert(p_admin_id);

  -- Settle / flush mining cursors BEFORE flipping the flag so the paused
  -- window never accrues TON and never pays retroactively on resume.
  UPDATE player_heroes
     SET mining_last_at = now()
   WHERE user_id IS NOT NULL;

  -- Single global row (id is the singleton boolean primary key).
  INSERT INTO hero_mining_settings (id, enabled, updated_at)
  VALUES (true, v_enabled, now())
  ON CONFLICT (id) DO UPDATE
    SET enabled = EXCLUDED.enabled, updated_at = now();

  PERFORM admin_log(p_admin_id, 'hero_mining_toggle', 'hero_mining', 'settings', NULL,
    jsonb_build_object('enabled', v_enabled), 'mineração de TON alternada pelo painel admin', '{}'::jsonb);
  RETURN admin_hero_mining_overview(p_admin_id);
END $function$;