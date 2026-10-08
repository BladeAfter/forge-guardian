INSERT INTO public.global_boss_templates
  (boss_number, code, name, subtitle, theme, image_url, background_url, boss_level, max_hp, reward_fc, duration_seconds, enabled)
VALUES
  (11,'abyss_sovereign','Abyss Sovereign','Ruler of the sunken depths','abyss','/assets/game/global-boss/abyss-sovereign.png','/assets/game/global-boss/arena-abyss-sovereign.jpg',11,1800000,450000,86400,true),
  (12,'crimson_behemoth','Crimson Behemoth','Forged in endless war','crimson','/assets/game/global-boss/crimson-behemoth.png','/assets/game/global-boss/arena-crimson-behemoth.jpg',12,2100000,520000,86400,true),
  (13,'storm_devourer','Storm Devourer','It swallows the sky itself','storm','/assets/game/global-boss/storm-devourer.png','/assets/game/global-boss/arena-storm-devourer.jpg',13,2500000,600000,86400,true),
  (14,'infernal_colossus','Infernal Colossus','A walking furnace of ruin','infernal','/assets/game/global-boss/infernal-colossus.png','/assets/game/global-boss/arena-infernal-colossus.jpg',14,3000000,700000,86400,true),
  (15,'void_leviathan','Void Leviathan','Born where reality ends','void','/assets/game/global-boss/void-leviathan.png','/assets/game/global-boss/arena-void-leviathan.jpg',15,3600000,820000,86400,true),
  (16,'frostbound_tyrant','Frostbound Tyrant','Winter that never forgives','frost','/assets/game/global-boss/frostbound-tyrant.png','/assets/game/global-boss/arena-frostbound-tyrant.jpg',16,4300000,950000,86400,true),
  (17,'eclipse_warden','Eclipse Warden','Guardian of the dying light','eclipse','/assets/game/global-boss/eclipse-warden.png','/assets/game/global-boss/arena-eclipse-warden.jpg',17,5100000,1080000,86400,true),
  (18,'bone_emperor','Bone Emperor','Crowned upon the dead','bone','/assets/game/global-boss/bone-emperor.png','/assets/game/global-boss/arena-bone-emperor.jpg',18,6000000,1220000,86400,true),
  (19,'chaos_paragon','Chaos Paragon','Perfection born of madness','chaos','/assets/game/global-boss/chaos-paragon.png','/assets/game/global-boss/arena-chaos-paragon.jpg',19,7000000,1360000,86400,true),
  (20,'celestial_ruinbringer','Celestial Ruinbringer','The last judgement of the heavens','celestial','/assets/game/global-boss/celestial-ruinbringer.png','/assets/game/global-boss/arena-celestial-ruinbringer.jpg',20,8000000,1500000,86400,true)
ON CONFLICT (boss_number) DO UPDATE
  SET code=excluded.code, name=excluded.name, subtitle=excluded.subtitle, theme=excluded.theme,
      image_url=excluded.image_url, background_url=excluded.background_url, boss_level=excluded.boss_level,
      max_hp=excluded.max_hp, reward_fc=excluded.reward_fc, duration_seconds=excluded.duration_seconds,
      enabled=excluded.enabled, updated_at=now();

UPDATE public.global_boss_templates t
   SET background_url = '/assets/game/global-boss/arena-' || replace(t.code,'_','-') || '.jpg', updated_at = now()
 WHERE t.background_url IS NULL;

CREATE OR REPLACE FUNCTION public.admin_global_boss_roster(p_admin_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_active_number int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT boss_number INTO v_active_number FROM public.global_boss_cycles WHERE status='active' LIMIT 1;
  RETURN jsonb_build_object(
    'activeBossNumber', v_active_number,
    'bosses', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'bossNumber', t.boss_number, 'code', t.code, 'name', t.name, 'subtitle', t.subtitle,
        'theme', t.theme, 'maxHp', t.max_hp, 'rewardFc', t.reward_fc,
        'durationSeconds', t.duration_seconds, 'enabled', t.enabled,
        'image', t.image_url, 'background', t.background_url,
        'current', t.boss_number = v_active_number
      ) ORDER BY t.boss_number)
      FROM public.global_boss_templates t), '[]'::jsonb)
  );
END; $$;

CREATE OR REPLACE FUNCTION public.admin_global_boss_template_set(
  p_admin_id bigint, p_code text, p_field text,
  p_value numeric DEFAULT NULL, p_text text DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_field text := lower(coalesce(p_field,'')); t public.global_boss_templates;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO t FROM public.global_boss_templates WHERE code = p_code;
  IF t.id IS NULL THEN RAISE EXCEPTION 'boss_not_found'; END IF;

  IF v_field IN ('enable','enabled','on') THEN
    UPDATE public.global_boss_templates SET enabled=true, updated_at=now() WHERE id=t.id RETURNING * INTO t;
  ELSIF v_field IN ('disable','off') THEN
    UPDATE public.global_boss_templates SET enabled=false, updated_at=now() WHERE id=t.id RETURNING * INTO t;
  ELSIF v_field='toggle' THEN
    UPDATE public.global_boss_templates SET enabled=NOT enabled, updated_at=now() WHERE id=t.id RETURNING * INTO t;
  ELSIF v_field IN ('hp','max_hp') THEN
    IF COALESCE(p_value,0) < 1 THEN RAISE EXCEPTION 'invalid_value'; END IF;
    UPDATE public.global_boss_templates SET max_hp=p_value, updated_at=now() WHERE id=t.id RETURNING * INTO t;
    UPDATE public.global_boss_cycles SET max_hp=p_value, current_hp=LEAST(current_hp,p_value), updated_at=now()
      WHERE status='active' AND boss_number=t.boss_number;
  ELSIF v_field IN ('reward','reward_fc') THEN
    IF COALESCE(p_value,0) < 0 THEN RAISE EXCEPTION 'invalid_value'; END IF;
    UPDATE public.global_boss_templates SET reward_fc=p_value, updated_at=now() WHERE id=t.id RETURNING * INTO t;
    UPDATE public.global_boss_cycles SET reward_pool_fc=p_value, updated_at=now()
      WHERE status='active' AND boss_number=t.boss_number;
  ELSIF v_field IN ('duration','duration_seconds') THEN
    IF COALESCE(p_value,0) < 300 THEN RAISE EXCEPTION 'invalid_value'; END IF;
    UPDATE public.global_boss_templates SET duration_seconds=p_value::int, updated_at=now() WHERE id=t.id RETURNING * INTO t;
  ELSIF v_field='name' THEN
    IF coalesce(trim(p_text),'') = '' THEN RAISE EXCEPTION 'invalid_value'; END IF;
    UPDATE public.global_boss_templates SET name=trim(p_text), updated_at=now() WHERE id=t.id RETURNING * INTO t;
    UPDATE public.global_boss_cycles SET boss_name=trim(p_text), updated_at=now()
      WHERE status='active' AND boss_number=t.boss_number;
  ELSIF v_field IN ('subtitle','lore') THEN
    UPDATE public.global_boss_templates SET subtitle=NULLIF(trim(p_text),''), updated_at=now() WHERE id=t.id RETURNING * INTO t;
    UPDATE public.global_boss_cycles SET boss_subtitle=NULLIF(trim(p_text),''), updated_at=now()
      WHERE status='active' AND boss_number=t.boss_number;
  ELSE
    RAISE EXCEPTION 'invalid_field';
  END IF;

  PERFORM public.admin_log(p_admin_id,'global_boss.template.'||v_field,'global_boss_template',t.code,null,
    jsonb_build_object('value',p_value,'text',p_text),p_reason,jsonb_build_object('bossNumber',t.boss_number));

  RETURN jsonb_build_object('bossNumber',t.boss_number,'code',t.code,'name',t.name,'subtitle',t.subtitle,
    'maxHp',t.max_hp,'rewardFc',t.reward_fc,'durationSeconds',t.duration_seconds,'enabled',t.enabled);
END; $$;

REVOKE ALL ON FUNCTION public.admin_global_boss_roster(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_global_boss_template_set(bigint, text, text, numeric, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_global_boss_roster(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_global_boss_template_set(bigint, text, text, numeric, text, text) TO service_role;