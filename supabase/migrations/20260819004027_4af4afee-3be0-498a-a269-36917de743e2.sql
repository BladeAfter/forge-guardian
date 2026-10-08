do $$
declare t timestamptz := clock_timestamp(); n int; c int; begin
  select count(*) into c from player_heroes ph join game_players g on g.id=ph.user_id where g.telegram_id=1310583958;
  select jsonb_array_length(public.get_hero_fusion_dashboard(1310583958)->'heroes') into n;
  raise notice 'heroes=% json=% ms=%', c, n, extract(milliseconds from clock_timestamp()-t);
end $$;