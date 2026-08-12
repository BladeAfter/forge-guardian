-- 1) rarity normalization now understands mythic / ancestral (EN + PT)
CREATE OR REPLACE FUNCTION public.normalize_hero_rarity(value text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case lower(trim(coalesce(value,'common')))
    when 'common' then 'common' when 'comum' then 'common' when 'uncommon' then 'uncommon' when 'incomum' then 'uncommon'
    when 'rare' then 'rare' when 'raro' then 'rare' when 'rara' then 'rare' when 'epic' then 'epic' when 'épico' then 'epic'
    when 'epico' then 'epic' when 'épica' then 'epic' when 'epica' then 'epic' when 'legendary' then 'legendary'
    when 'lendário' then 'legendary' when 'lendario' then 'legendary' when 'lendária' then 'legendary' when 'lendaria' then 'legendary'
    when 'mythic' then 'mythic' when 'mítico' then 'mythic' when 'mitico' then 'mythic' when 'mítica' then 'mythic' when 'mitica' then 'mythic'
    when 'ancestral' then 'ancestral' when 'ancient' then 'ancestral'
    else 'common' end
$function$;

-- 2) PvP stat generation: mythic and ancestral ranges above legendary
CREATE OR REPLACE FUNCTION public.ensure_pvp_hero_stats()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r text;seed text;min_atk numeric;max_atk numeric;min_hp numeric;max_hp numeric;min_ag numeric;max_ag numeric;min_hg numeric;max_hg numeric;atk_mult numeric:=1;hp_mult numeric:=1;fuse numeric:=1;kinds text[]:=array['warrior','assassin','tank','mage','archer','support'];
begin
  r:=normalize_hero_rarity(new.rarity);new.hero_template_id:=coalesce(new.hero_template_id,new.hero_key,new.name);seed:=coalesce(new.stats_seed,new.id::text||':'||new.hero_template_id||':'||new.user_id::text||':'||new.created_at::text);new.stats_seed:=seed;new.archetype:=coalesce(new.archetype,kinds[1+(abs(hashtextextended(seed||':kind',0))%6)::int]);
  select s.min_atk,s.max_atk,s.min_hp,s.max_hp,s.min_ag,s.max_ag,s.min_hg,s.max_hg into min_atk,max_atk,min_hp,max_hp,min_ag,max_ag,min_hg,max_hg from(values
    ('common',80,110,800,1100,.025,.030,.040,.045),
    ('uncommon',105,140,1050,1400,.028,.033,.042,.048),
    ('rare',135,180,1350,1800,.031,.036,.045,.051),
    ('epic',175,235,1750,2350,.034,.039,.048,.054),
    ('legendary',230,310,2300,3100,.037,.042,.051,.057),
    ('mythic',310,415,3100,4150,.040,.045,.054,.060),
    ('ancestral',415,545,4150,5450,.043,.048,.057,.063)
  )s(rarity,min_atk,max_atk,min_hp,max_hp,min_ag,max_ag,min_hg,max_hg)where s.rarity=r;
  case new.archetype when 'warrior' then hp_mult:=1.15;when 'assassin' then atk_mult:=1.15;hp_mult:=.9;when 'tank' then atk_mult:=.85;hp_mult:=1.3;when 'mage' then atk_mult:=1.2;hp_mult:=.85;when 'archer' then atk_mult:=1.1;when 'support' then atk_mult:=.9;hp_mult:=1.1;else new.archetype:='warrior';hp_mult:=1.15;end case;
  if new.base_atk is null then new.base_atk:=greatest(1,round((min_atk+pvp_stat_unit(seed||':atk')*(max_atk-min_atk))*atk_mult));end if;
  if new.base_hp is null then new.base_hp:=greatest(1,round((min_hp+pvp_stat_unit(seed||':hp')*(max_hp-min_hp))*hp_mult));end if;
  if new.attack_growth is null then new.attack_growth:=round(min_ag+pvp_stat_unit(seed||':ag')*(max_ag-min_ag),5);end if;
  if new.hp_growth is null then new.hp_growth:=round(min_hg+pvp_stat_unit(seed||':hg')*(max_hg-min_hg),5);end if;
  new.level:=greatest(1,coalesce(new.level,1));
  new.fusion_level:=greatest(0,coalesce(new.fusion_level,0));
  fuse:=hero_fusion_multiplier(new.fusion_level);
  new.final_atk:=greatest(1,round((new.base_atk+coalesce(new.bonus_atk,0))*power(1+new.attack_growth,new.level-1)*fuse));
  new.final_hp:=greatest(1,round((new.base_hp+coalesce(new.bonus_hp,0))*power(1+new.hp_growth,new.level-1)*fuse));
  new.stats_generated_at:=coalesce(new.stats_generated_at,now());return new;
end
$function$;

-- 3) summon rates now cover all seven rarities
CREATE OR REPLACE FUNCTION public.admin_set_hero_summon_rates(p_admin_id bigint, p_rates jsonb, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_allowed text[] := ARRAY['common','uncommon','rare','epic','legendary','mythic','ancestral'];
  v_total numeric := 0; k text; v numeric; v_old jsonb; v_final jsonb := '{}'::jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  FOR k, v IN SELECT key, (value #>> '{}')::numeric FROM jsonb_each(p_rates) LOOP
    IF NOT (k = ANY(v_allowed)) THEN RAISE EXCEPTION 'invalid_rarity:%', k; END IF;
    IF v IS NULL OR v < 0 OR v > 100 THEN RAISE EXCEPTION 'invalid_rate:%', k; END IF;
    v_total := v_total + v;
    v_final := v_final || jsonb_build_object(k, round(v, 4));
  END LOOP;

  IF (SELECT count(*) FROM jsonb_object_keys(v_final)) <> array_length(v_allowed, 1) THEN
    RAISE EXCEPTION 'missing_rarities';
  END IF;
  IF abs(v_total - 100) > 0.001 THEN
    RAISE EXCEPTION 'rates_must_total_100:%', v_total;
  END IF;

  SELECT value INTO v_old FROM public.game_settings WHERE key = 'hero_summon_rates';
  INSERT INTO public.game_settings (key, value, category, label, updated_at, updated_by)
  VALUES ('hero_summon_rates', v_final, 'heroes', 'Chances de invocação por raridade (%)', now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;

  PERFORM public.admin_log(p_admin_id, 'hero.summon_rates', 'setting', 'hero_summon_rates',
                           v_old, v_final, p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN public.get_hero_shop_config();
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_reset_hero_shop(p_admin_id bigint, p_scope text DEFAULT 'prices'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_scope IN ('prices','all') THEN
    PERFORM public.admin_set_hero_recruit_price(p_admin_id, 1, 25000, 'reset_default');
    PERFORM public.admin_set_hero_recruit_price(p_admin_id, 5, 125000, 'reset_default');
    PERFORM public.admin_set_hero_recruit_price(p_admin_id, 10, 250000, 'reset_default');
  END IF;
  IF p_scope IN ('odds','all') THEN
    PERFORM public.admin_set_hero_summon_rates(
      p_admin_id,
      '{"common":55.9,"uncommon":30,"rare":10,"epic":2.7,"legendary":1.3,"mythic":0.08,"ancestral":0.02}'::jsonb,
      'reset_default');
  END IF;
  RETURN public.get_hero_shop_config();
END;
$function$;

-- 4) default summon rates fallback (used only when the setting is missing)
CREATE OR REPLACE FUNCTION public.hero_summon_rates()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT value FROM public.game_settings WHERE key = 'hero_summon_rates'),
    '{"common":55.9,"uncommon":30,"rare":10,"epic":2.7,"legendary":1.3,"mythic":0.08,"ancestral":0.02}'::jsonb
  );
$function$;

REVOKE ALL ON FUNCTION public.hero_summon_rates() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.normalize_hero_rarity(text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_hero_summon_rates(bigint, jsonb, text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_reset_hero_shop(bigint, text) FROM anon, authenticated;