-- Soma todas as variações do buff de vida vindas dos pets.
CREATE OR REPLACE FUNCTION public.pet_hp_bonus_percent(p_buffs jsonb)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT GREATEST(0,
    COALESCE((p_buffs->>'team_hp_percent')::numeric, 0)
  + COALESCE((p_buffs->>'hp_percent')::numeric, 0)
  + COALESCE((p_buffs->>'hp_bonus')::numeric, 0))
$$;

-- Bônus de pet: raridade + nível + estágio de evolução (+15% por evolução).
CREATE OR REPLACE FUNCTION public.get_pet_bonuses(p_user uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare r record; result jsonb := '{}'; k text; base numeric; cap numeric; final numeric; evo numeric;
begin
  select pp.rarity, pp.level, coalesce(pp.evolution_stage,1) as evolution_stage, p.base_passives
    into r
    from player_pets pp join pets p on p.id = pp.pet_id
   where pp.user_id = p_user and pp.is_active;
  if not found then return result; end if;
  evo := 1 + 0.15 * greatest(0, coalesce(r.evolution_stage,1) - 1);
  for k, base in select key, value::text::numeric from jsonb_each(r.base_passives) loop
    select (value->>k)::numeric into cap from pet_settings where key = 'bonus_caps';
    final := round(base * pet_rarity_multiplier(r.rarity) * (1 + (r.level - 1) * .02) * evo, 2);
    if cap is not null then final := least(final, cap); end if;
    result := result || jsonb_build_object(k, final);
  end loop;
  return result;
end$function$;

-- Boss global: vida dos heróis usa a soma completa do buff.
CREATE OR REPLACE FUNCTION public.apply_pet_hp_on_combat_hero()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare u uuid; bonus numeric := 0; factor numeric;
begin
  select user_id into u from boss_combats where id = new.combat_id;
  bonus := public.pet_hp_bonus_percent(public.get_pet_bonuses(u));
  factor := 1 + bonus / 100;
  new.max_hp := round(new.max_hp * factor);
  new.current_hp := least(new.max_hp, round(new.current_hp * factor));
  return new;
end$function$;

-- PvP (arena clássica e torre): a vida da equipe passa a receber o buff.
CREATE OR REPLACE FUNCTION public.pvp_apply_pet_modifiers(p_team jsonb, p_buffs jsonb)
 RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x || jsonb_build_object(
    'finalAtk', greatest(1, round((x->>'finalAtk')::numeric * (1 + coalesce((p_buffs->>'pvp_attack_percent')::numeric,0)/100)))::int,
    'finalHp', greatest(1, round(coalesce((x->>'finalHp')::numeric,1) * (1 + public.pet_hp_bonus_percent(p_buffs)/100)))::int,
    'maxHp', greatest(1, round(coalesce((x->>'maxHp')::numeric, (x->>'finalHp')::numeric, 1) * (1 + public.pet_hp_bonus_percent(p_buffs)/100)))::int,
    'defense', round(coalesce((x->>'defense')::numeric,0) * (1 + coalesce((p_buffs->>'pvp_defense_percent')::numeric,0)/100))::int,
    'speed', greatest(1, round(coalesce((x->>'speed')::numeric,1) * (1 + coalesce((p_buffs->>'pvp_speed_percent')::numeric,0)/100)))::int,
    'critChance', greatest(0, coalesce((p_buffs->>'critical_chance_percent')::numeric,0)),
    'critMultiplier', 1.5 + coalesce((p_buffs->>'critical_damage_percent')::numeric,0)/100
  ) order by coalesce((x->>'slot')::int, 0)), '[]'::jsonb)
  from jsonb_array_elements(coalesce(p_team,'[]'::jsonb)) x
$function$;