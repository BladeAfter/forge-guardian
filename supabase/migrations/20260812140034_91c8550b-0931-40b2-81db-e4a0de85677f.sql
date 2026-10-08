ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS pvp_tickets_reset_day date,
  ADD COLUMN IF NOT EXISTS pvp_tickets_reset_at timestamptz;

INSERT INTO public.game_settings (key, value)
VALUES ('pvp_ticket_free_daily', '5'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- Grants the free daily PvP tickets exactly once per game day (game_day_key uses the 21:00 calendar reset).
CREATE OR REPLACE FUNCTION public.pvp_apply_daily_tickets(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_day date := public.game_day_key();
  v_free int := greatest(0, public.setting_num('pvp_ticket_free_daily', 5)::int);
  v_row game_players%rowtype;
  v_granted boolean := false;
begin
  select * into v_row from public.game_players where telegram_id = p_telegram_id for update;
  if v_row.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  if v_row.pvp_tickets_reset_day is null or v_row.pvp_tickets_reset_day < v_day then
    update public.game_players
       set pvp_tickets = greatest(coalesce(pvp_tickets, 0), v_free),
           pvp_tickets_reset_day = v_day,
           pvp_tickets_reset_at = now()
     where id = v_row.id
     returning * into v_row;
    v_granted := true;
  end if;

  return jsonb_build_object(
    'granted', v_granted,
    'tickets', coalesce(v_row.pvp_tickets, 0),
    'freeDaily', v_free,
    'resetDay', v_day,
    'nextResetAt', public.game_day_start(v_day + 1)
  );
end $$;

REVOKE ALL ON FUNCTION public.pvp_apply_daily_tickets(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pvp_apply_daily_tickets(bigint) TO service_role;

-- Backend catch-up so offline players also receive the daily tickets at the 21:00 reset.
CREATE OR REPLACE FUNCTION public.pvp_reset_daily_tickets_all()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_day date := public.game_day_key();
  v_free int := greatest(0, public.setting_num('pvp_ticket_free_daily', 5)::int);
  v_count int;
begin
  with upd as (
    update public.game_players
       set pvp_tickets = greatest(coalesce(pvp_tickets, 0), v_free),
           pvp_tickets_reset_day = v_day,
           pvp_tickets_reset_at = now()
     where pvp_tickets_reset_day is null or pvp_tickets_reset_day < v_day
     returning 1
  )
  select count(*) into v_count from upd;
  return v_count;
end $$;

REVOKE ALL ON FUNCTION public.pvp_reset_daily_tickets_all() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pvp_reset_daily_tickets_all() TO service_role;