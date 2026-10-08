create or replace function public.premium_offers_state(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare u public.game_players; fc public.founder_pack_config; vc public.veteran_vault_v2_config;
        f jsonb; v jsonb; v_day date := public.premium_offer_day_key();
        v_queue text[] := array[]::text[]; v_f_seen boolean; v_v_seen boolean; v_v_window boolean;
begin
  select * into u from public.game_players where telegram_id = p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  fc := public.founder_pack_settings();
  select * into vc from public.veteran_vault_v2_config where id;

  f := public.founder_pack_state(p_telegram_id);
  v := public.veteran_v2_state(p_telegram_id);

  v_v_window := coalesce(vc.enabled,false)
                and now() >= coalesce(vc.start_at, now())
                and (vc.ends_at is null or now() < vc.ends_at);

  select exists (select 1 from public.premium_offer_popup_views
                  where user_id = u.id and offer_type = 'FOUNDER_PACK' and day_key = v_day) into v_f_seen;
  select exists (select 1 from public.premium_offer_popup_views
                  where user_id = u.id and offer_type = 'VETERAN_VAULT' and day_key = v_day) into v_v_seen;

  if coalesce(fc.popup_enabled,false) and fc.popup_frequency <> 'DISABLED'
     and coalesce((f->>'eligible')::boolean,false) and not v_f_seen then
    v_queue := array_append(v_queue, 'FOUNDER_PACK');
  end if;
  if coalesce(vc.popup_enabled,false) and vc.popup_frequency <> 'DISABLED' and v_v_window
     and coalesce((v->>'eligible')::boolean,false) and not v_v_seen then
    v_queue := array_append(v_queue, 'VETERAN_VAULT');
  end if;

  return jsonb_build_object(
    'dayKey', v_day,
    'timezone', public.premium_offer_timezone(),
    'queue', to_jsonb(v_queue),
    'founder', f || jsonb_build_object('popupSeenToday', v_f_seen, 'popupFrequency', fc.popup_frequency),
    'veteran', v || jsonb_build_object('popupSeenToday', v_v_seen, 'popupFrequency', vc.popup_frequency,
                                       'startAt', vc.start_at, 'endsAt', vc.ends_at,
                                       'windowOpen', v_v_window));
end $$;

revoke execute on function public.premium_offers_state(bigint) from public, anon, authenticated;
grant execute on function public.premium_offers_state(bigint) to service_role;