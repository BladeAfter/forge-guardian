CREATE OR REPLACE FUNCTION public.hero_xp_last_award(p_user_id uuid, p_activity text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
declare a text := NULLIF(upper(COALESCE(p_activity, '')), ''); v_ref text; v_act text;
        cfg jsonb := public.hero_progression_config(); v_max int;
begin
  if p_user_id is null then return NULL; end if;
  v_max := COALESCE((cfg->>'maxLevel')::int, 20);

  select e.activity_type, e.reference_id into v_act, v_ref
    from public.hero_xp_events e
   where e.user_id = p_user_id
     and (a is null or e.activity_type = a)
     and e.created_at > now() - interval '90 seconds'
   order by e.created_at desc limit 1;
  if v_ref is null then return NULL; end if;

  return jsonb_build_object(
    'activity', v_act,
    'xpEach', (select max(xp_awarded) from public.hero_xp_events
                where user_id = p_user_id and activity_type = v_act and reference_id = v_ref),
    'heroes', COALESCE((
      select jsonb_agg(jsonb_build_object(
        'heroId', e.player_hero_id, 'name', h.name, 'image', h.image,
        'xpAwarded', e.xp_awarded, 'levelBefore', e.level_before, 'level', e.level_after,
        'leveledUp', e.level_after > e.level_before,
        'xp', GREATEST(0, COALESCE(h.xp, 0)),
        'xpToNext', public.hero_xp_to_next(GREATEST(1, COALESCE(h.level, 1))),
        'maxLevel', v_max, 'maxed', COALESCE(h.level, 1) >= v_max,
        'finalAtk', round(COALESCE(h.final_atk, 0)), 'finalHp', round(COALESCE(h.final_hp, 0))
      ) order by e.created_at)
      from public.hero_xp_events e
      join public.player_heroes h on h.id = e.player_hero_id
     where e.user_id = p_user_id and e.activity_type = v_act and e.reference_id = v_ref), '[]'::jsonb)
  );
end $$;
REVOKE ALL ON FUNCTION public.hero_xp_last_award(uuid, text) FROM PUBLIC, anon, authenticated;