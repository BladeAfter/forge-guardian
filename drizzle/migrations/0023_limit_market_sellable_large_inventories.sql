DO $migration$
DECLARE
  function_sql text;
BEGIN
  SELECT pg_get_functiondef(p.oid)
    INTO function_sql
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'market_get_sellable'
    AND pg_get_function_identity_arguments(p.oid) = 'p_telegram_id bigint';

  IF function_sql IS NULL THEN
    RAISE EXCEPTION 'market_get_sellable(bigint) not found';
  END IF;

  function_sql := replace(
    function_sql,
    'from player_heroes h where h.user_id = u',
    'from (
      select ph.*
      from player_heroes ph
      where ph.user_id = u
        and jsonb_array_length(market_hero_locks(ph.*)) = 0
      order by ph.created_at desc
      limit 150
    ) h'
  );

  IF position('limit 150' in lower(function_sql)) = 0 THEN
    RAISE EXCEPTION 'market_get_sellable source pattern changed; migration not applied';
  END IF;

  EXECUTE function_sql;
END
$migration$;