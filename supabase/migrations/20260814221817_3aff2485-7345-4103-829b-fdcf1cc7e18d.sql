ALTER TABLE public.game_players DROP CONSTRAINT IF EXISTS game_players_language_check;
ALTER TABLE public.game_players ADD CONSTRAINT game_players_language_check CHECK (language IN ('pt','en','es','ru','tr'));

CREATE OR REPLACE FUNCTION public.normalize_language_code(p_code text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE
    WHEN p_code IS NULL THEN 'en'
    WHEN lower(p_code) LIKE 'pt%' THEN 'pt'
    WHEN lower(p_code) LIKE 'es%' THEN 'es'
    WHEN lower(p_code) LIKE 'ru%' THEN 'ru'
    WHEN lower(p_code) LIKE 'tr%' THEN 'tr'
    WHEN lower(p_code) LIKE 'en%' THEN 'en'
    ELSE 'en'
  END
$$;

CREATE OR REPLACE FUNCTION public.set_player_language(p_telegram_id bigint, p_language text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare v_lang text; player game_players%rowtype;
begin
  v_lang := lower(coalesce(p_language,''));
  if v_lang not in ('pt','en','es','ru','tr') then raise exception 'INVALID_LANGUAGE'; end if;
  update game_players set language = v_lang, language_locked = true, updated_at = now()
   where telegram_id = p_telegram_id returning * into player;
  if player.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return jsonb_build_object('language',player.language,'languageLocked',player.language_locked);
end $function$;

REVOKE ALL ON FUNCTION public.set_player_language(bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_player_language(bigint, text) TO service_role;