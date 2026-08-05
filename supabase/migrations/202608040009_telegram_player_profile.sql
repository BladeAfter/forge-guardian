alter table public.game_players add column if not exists first_name text;
alter table public.game_players add column if not exists last_name text;

create or replace function public.upsert_telegram_player_profile(
  p_telegram_id bigint,p_first_name text,p_last_name text default null,p_username text default null,p_photo_url text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare player game_players%rowtype;
begin
  if p_telegram_id is null or nullif(trim(p_first_name),'') is null then raise exception 'INVALID_TELEGRAM_PROFILE';end if;
  insert into game_players(telegram_id,first_name,last_name,display_name,username,avatar_url,last_seen_at)
  values(p_telegram_id,trim(p_first_name),nullif(trim(p_last_name),''),trim(concat_ws(' ',p_first_name,p_last_name)),nullif(trim(p_username),''),nullif(trim(p_photo_url),''),now())
  on conflict(telegram_id) do update set first_name=excluded.first_name,last_name=excluded.last_name,display_name=excluded.display_name,username=excluded.username,avatar_url=excluded.avatar_url,last_seen_at=now(),updated_at=now()
  returning * into player;
  return jsonb_build_object('telegramId',player.telegram_id::text,'firstName',player.first_name,'lastName',player.last_name,'username',player.username,'photoUrl',player.avatar_url);
end $$;

revoke all on function public.upsert_telegram_player_profile(bigint,text,text,text,text) from public,anon,authenticated;
grant execute on function public.upsert_telegram_player_profile(bigint,text,text,text,text) to service_role;
