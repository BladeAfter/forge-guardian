CREATE OR REPLACE FUNCTION public.get_pet_bonuses(p_user uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare r record; result jsonb := '{}'; k text; base numeric; cap numeric; final numeric; evo numeric; stage int;
begin
  select pp.rarity, pp.level, p.base_passives
    into r
    from player_pets pp join pets p on p.id = pp.pet_id
   where pp.user_id = p_user and pp.is_active;
  if not found then return result; end if;
  stage := greatest(0, coalesce(public.pet_visual_index(coalesce(r.level, 1)), 0));
  evo := 1 + 0.15 * stage;
  for k, base in select key, value::text::numeric from jsonb_each(r.base_passives) loop
    select (value->>k)::numeric into cap from pet_settings where key = 'bonus_caps';
    final := round(base * pet_rarity_multiplier(r.rarity) * (1 + (coalesce(r.level,1) - 1) * .02) * evo, 2);
    if cap is not null then final := least(final, cap); end if;
    result := result || jsonb_build_object(k, final);
  end loop;
  return result;
end$function$;

REVOKE ALL ON FUNCTION public.get_pet_bonuses(uuid) FROM anon, authenticated, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_pet_bonuses(uuid) TO service_role;