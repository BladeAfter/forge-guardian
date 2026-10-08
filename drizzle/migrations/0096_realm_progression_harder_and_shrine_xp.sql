-- 1) Progressão de construções muito mais lenta e caras a cada nível
UPDATE public.realm_building_types SET base_seconds = 5400, base_fc_cost = 60000,
  cost_materials = '{"iron_ore":14,"magic_wood":14}'::jsonb WHERE id='castle';
UPDATE public.realm_building_types SET base_seconds = 3600, base_fc_cost = 35000,
  cost_materials = '{"iron_ore":16,"rune_dust":6}'::jsonb WHERE id='forge';
UPDATE public.realm_building_types SET base_seconds = 3000, base_fc_cost = 32000,
  cost_materials = '{"iron_ore":8,"magic_wood":16}'::jsonb WHERE id='training_ground';
UPDATE public.realm_building_types SET base_seconds = 3300, base_fc_cost = 42000,
  cost_materials = '{"iron_ore":10,"rune_dust":10}'::jsonb WHERE id='watchtower';
UPDATE public.realm_building_types SET base_seconds = 3300, base_fc_cost = 38000,
  cost_materials = '{"magic_wood":14,"rune_dust":8}'::jsonb,
  description = 'Cada um dos 5 primeiros níveis concede +4% de XP do Reino (até +20%). Também melhora o rendimento de coleta dos pets.'
 WHERE id='pet_sanctuary';

CREATE OR REPLACE FUNCTION public.realm_building_upgrade(p_user uuid, p_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare bt record; b record; v_next int; v_fc numeric; v_secs int; v_castle int; m record; v_qty numeric;
begin
  perform realm_ensure_profile(p_user);
  select * into bt from realm_building_types where id=p_type and enabled;
  if bt is null then raise exception 'REALM_BUILDING_UNKNOWN'; end if;
  select * into b from realm_buildings where user_id=p_user and building_type=p_type for update;
  if b.status <> 'idle' then raise exception 'REALM_BUILDING_BUSY'; end if;

  v_next := b.level + 1;
  if v_next > bt.max_level then raise exception 'REALM_BUILDING_MAX'; end if;

  v_castle := realm_building_level(p_user,'castle');
  if p_type <> 'castle' and v_next > v_castle then raise exception 'REALM_CASTLE_TOO_LOW'; end if;

  v_fc := round(bt.base_fc_cost * power(2.0, b.level));
  v_secs := ceil(bt.base_seconds * power(2.1, b.level));

  update game_players set forge_coins = forge_coins - v_fc
   where id=p_user and forge_coins >= v_fc;
  if not found then raise exception 'REALM_NOT_ENOUGH_FC'; end if;

  for m in select key, value::text::numeric as qty from jsonb_each_text(bt.cost_materials) t(key,value) loop
    v_qty := ceil(m.qty * power(1.7, b.level));
    perform realm_material_add(p_user, m.key, -v_qty, 'building_upgrade', p_type);
  end loop;

  update realm_buildings
     set status='upgrading', upgrade_started_at=now(),
         upgrade_finishes_at=now() + make_interval(secs => v_secs), updated_at=now()
   where user_id=p_user and building_type=p_type;

  return realm_state(p_user);
end $function$;

-- 2) Santuário de Pets: 5 primeiros níveis dão % de XP do Reino
CREATE OR REPLACE FUNCTION public.realm_shrine_xp_mult(p_user uuid)
RETURNS numeric
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  select 1 + least(realm_building_level(p_user,'pet_sanctuary'), 5) * 0.04
$function$;

CREATE OR REPLACE FUNCTION public.realm_apply_shrine_xp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare v_delta numeric; v_mult numeric;
begin
  if NEW.realm_xp > OLD.realm_xp then
    v_delta := NEW.realm_xp - OLD.realm_xp;
    v_mult := realm_shrine_xp_mult(NEW.user_id);
    NEW.realm_xp := OLD.realm_xp + ceil(v_delta * v_mult);
  end if;
  return NEW;
end $function$;

DROP TRIGGER IF EXISTS trg_realm_apply_shrine_xp ON public.realm_profiles;
CREATE TRIGGER trg_realm_apply_shrine_xp
BEFORE UPDATE OF realm_xp ON public.realm_profiles
FOR EACH ROW EXECUTE FUNCTION public.realm_apply_shrine_xp();