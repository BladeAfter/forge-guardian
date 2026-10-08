ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS language text NOT NULL DEFAULT 'en',
  ADD COLUMN IF NOT EXISTS language_locked boolean NOT NULL DEFAULT false;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'game_players_language_check') THEN
    ALTER TABLE public.game_players
      ADD CONSTRAINT game_players_language_check CHECK (language IN ('pt','en','es','ru'));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.normalize_language_code(p_code text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_code IS NULL THEN 'en'
    WHEN lower(p_code) LIKE 'pt%' THEN 'pt'
    WHEN lower(p_code) LIKE 'es%' THEN 'es'
    WHEN lower(p_code) LIKE 'ru%' THEN 'ru'
    WHEN lower(p_code) LIKE 'en%' THEN 'en'
    ELSE 'en'
  END
$$;

CREATE OR REPLACE FUNCTION public.upsert_telegram_player_profile(p_telegram_id bigint, p_first_name text, p_last_name text DEFAULT NULL::text, p_username text DEFAULT NULL::text, p_photo_url text DEFAULT NULL::text, p_language_code text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare player game_players%rowtype; suggested text;
begin
  if p_telegram_id is null or nullif(trim(p_first_name),'') is null then raise exception 'INVALID_TELEGRAM_PROFILE';end if;
  suggested := normalize_language_code(p_language_code);
  insert into game_players(telegram_id,first_name,last_name,display_name,username,avatar_url,last_seen_at,language)
  values(p_telegram_id,trim(p_first_name),nullif(trim(p_last_name),''),trim(concat_ws(' ',p_first_name,p_last_name)),nullif(trim(p_username),''),nullif(trim(p_photo_url),''),now(),suggested)
  on conflict(telegram_id) do update set first_name=excluded.first_name,last_name=excluded.last_name,display_name=excluded.display_name,username=excluded.username,avatar_url=excluded.avatar_url,last_seen_at=now(),updated_at=now()
  returning * into player;
  return jsonb_build_object('telegramId',player.telegram_id::text,'firstName',player.first_name,'lastName',player.last_name,'username',player.username,'photoUrl',player.avatar_url,'language',player.language,'languageLocked',player.language_locked);
end $function$;

CREATE OR REPLACE FUNCTION public.set_player_language(p_telegram_id bigint, p_language text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare v_lang text; player game_players%rowtype;
begin
  v_lang := lower(coalesce(p_language,''));
  if v_lang not in ('pt','en','es','ru') then raise exception 'INVALID_LANGUAGE'; end if;
  update game_players set language = v_lang, language_locked = true, updated_at = now()
   where telegram_id = p_telegram_id returning * into player;
  if player.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return jsonb_build_object('language',player.language,'languageLocked',player.language_locked);
end $function$;
