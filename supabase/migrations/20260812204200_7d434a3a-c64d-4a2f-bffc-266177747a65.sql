CREATE TABLE IF NOT EXISTS public.clan_boss_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  cycle_number integer NOT NULL UNIQUE,
  boss_key text NOT NULL UNIQUE,
  name text NOT NULL,
  subtitle text NOT NULL DEFAULT '',
  theme text NOT NULL DEFAULT 'abyss',
  image_url text,
  background_url text,
  max_hp numeric NOT NULL,
  base_damage numeric NOT NULL DEFAULT 100,
  reward_fc numeric NOT NULL DEFAULT 0,
  reward_clan_xp integer NOT NULL DEFAULT 0,
  enabled boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.clan_boss_templates TO authenticated;
GRANT ALL ON public.clan_boss_templates TO service_role;
ALTER TABLE public.clan_boss_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Clan boss templates are readable by members"
  ON public.clan_boss_templates FOR SELECT TO authenticated USING (true);

DROP TRIGGER IF EXISTS update_clan_boss_templates_updated_at ON public.clan_boss_templates;
CREATE TRIGGER update_clan_boss_templates_updated_at
  BEFORE UPDATE ON public.clan_boss_templates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.clan_boss_templates
  (cycle_number, boss_key, name, subtitle, theme, max_hp, base_damage, reward_fc, reward_clan_xp, sort_order)
VALUES
  (1,'abyssal_warlord','Abyssal Warlord','Lord of the Bleeding Abyss','abyss',1500000,100,20000,500,1),
  (2,'frost_tyrant','Frost Tyrant','Sovereign of the Endless Winter','frost',2200000,140,30000,700,2),
  (3,'shadow_devourer','Shadow Devourer','Eater of Forgotten Souls','shadow',3000000,180,45000,900,3),
  (4,'molten_colossus','Molten Colossus','Titan of the Burning Deep','molten',4200000,240,60000,1200,4),
  (5,'plague_monarch','Plague Monarch','Crowned in Rot and Ruin','plague',5800000,320,80000,1500,5),
  (6,'storm_reaper','Storm Reaper','Herald of the Black Tempest','storm',7500000,400,110000,2000,6),
  (7,'void_executioner','Void Executioner','Blade of the Hollow Cosmos','void',9500000,520,145000,2500,7),
  (8,'crimson_behemoth','Crimson Behemoth','Butcher of the Blood Legion','crimson',12000000,650,185000,3000,8),
  (9,'soulbreaker_king','Soulbreaker King','Warden of Shattered Spirits','soul',15500000,800,240000,4000,9),
  (10,'eternal_overlord','Eternal Overlord','The Last Throne of Mythreon','eternal',20000000,1000,320000,5000,10)
ON CONFLICT (cycle_number) DO NOTHING;

-- Resolves the template for a given clan cycle. Clamps to the last enabled boss.
CREATE OR REPLACE FUNCTION public.clan_boss_template_for_cycle(p_cycle integer)
RETURNS public.clan_boss_templates
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT t.* FROM public.clan_boss_templates t
  WHERE t.enabled
    AND t.cycle_number <= GREATEST(1, COALESCE(p_cycle, 1))
  ORDER BY t.cycle_number DESC
  LIMIT 1
$$;

REVOKE ALL ON FUNCTION public.clan_boss_template_for_cycle(integer) FROM anon, authenticated;

-- Instance creation now takes HP / rewards / identity from the cycle template.
-- Attack, cooldown and damage logic are untouched.
CREATE OR REPLACE FUNCTION public.clan_boss_ensure(p_clan_id uuid)
RETURNS public.clan_boss_instances
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_boss_config; b public.clan_boss_instances; tpl public.clan_boss_templates;
        v_cycle integer; v_hp numeric; v_level integer; v_rewards jsonb;
BEGIN
  cfg := public.clan_boss_cfg();
  SELECT * INTO b FROM public.clan_boss_instances WHERE clan_id = p_clan_id AND status = 'active' LIMIT 1;
  IF b.id IS NOT NULL AND b.ends_at <= now() THEN
    PERFORM public.clan_boss_settle(b.id, 'expired');
    b := NULL;
  END IF;
  IF b.id IS NULL THEN
    SELECT COALESCE(MAX(cycle), 0) + 1 INTO v_cycle FROM public.clan_boss_instances WHERE clan_id = p_clan_id;
    SELECT GREATEST(1, level) INTO v_level FROM public.clans WHERE id = p_clan_id;
    tpl := public.clan_boss_template_for_cycle(v_cycle);
    IF tpl.id IS NULL THEN
      v_hp := public.clan_boss_scaled_hp(p_clan_id, v_cycle);
      v_rewards := cfg.rewards;
      INSERT INTO public.clan_boss_instances(clan_id, boss_key, boss_name, cycle, level, max_hp, current_hp,
        min_damage_required, rewards_snapshot, starts_at, ends_at)
      VALUES (p_clan_id, cfg.boss_key, cfg.boss_name, v_cycle, COALESCE(v_level,1), v_hp, v_hp,
        round(v_hp * cfg.min_damage_pct / 100.0), v_rewards, now(),
        now() + make_interval(hours => GREATEST(1, cfg.duration_hours)))
      RETURNING * INTO b;
    ELSE
      v_hp := GREATEST(1, tpl.max_hp);
      v_rewards := COALESCE(cfg.rewards, '{}'::jsonb)
        || jsonb_build_object('fcPool', tpl.reward_fc, 'clanXp', tpl.reward_clan_xp,
                              'bossKey', tpl.boss_key, 'theme', tpl.theme, 'baseDamage', tpl.base_damage);
      INSERT INTO public.clan_boss_instances(clan_id, boss_key, boss_name, cycle, level, max_hp, current_hp,
        min_damage_required, rewards_snapshot, starts_at, ends_at)
      VALUES (p_clan_id, tpl.boss_key, tpl.name, v_cycle, COALESCE(v_level,1), v_hp, v_hp,
        round(v_hp * cfg.min_damage_pct / 100.0), v_rewards, now(),
        now() + make_interval(hours => GREATEST(1, cfg.duration_hours)))
      RETURNING * INTO b;
    END IF;
  END IF;
  RETURN b;
END $function$;

-- Settlement uses the cycle snapshot (per-boss FC pool and clan XP) when present.
CREATE OR REPLACE FUNCTION public.clan_boss_settle(p_instance_id uuid, p_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_boss_config; b public.clan_boss_instances; r record; snap jsonb;
        v_min numeric; v_pool numeric; v_share numeric; v_reward jsonb; v_top uuid; v_xp integer;
BEGIN
  cfg := public.clan_boss_cfg();
  SELECT * INTO b FROM public.clan_boss_instances WHERE id = p_instance_id FOR UPDATE;
  IF b.id IS NULL OR b.status <> 'active' THEN RETURN; END IF;
  snap := COALESCE(b.rewards_snapshot, cfg.rewards, '{}'::jsonb);

  SELECT user_id INTO v_top FROM public.clan_boss_damage WHERE instance_id = b.id ORDER BY damage DESC LIMIT 1;
  v_min := GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0));
  v_pool := CASE WHEN p_status = 'defeated' THEN COALESCE((snap->>'fcPool')::numeric, 0) ELSE 0 END;
  v_xp := CASE WHEN p_status = 'defeated'
            THEN GREATEST(0, COALESCE((snap->>'clanXp')::integer, cfg.clan_xp_reward)) ELSE 0 END;

  UPDATE public.clan_boss_instances
     SET status = p_status, finished_at = now(), top_user_id = v_top,
         min_damage_required = v_min, clan_xp_awarded = v_xp,
         rewards_snapshot = snap,
         total_damage = COALESCE((SELECT SUM(damage) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
         participants = COALESCE((SELECT count(*) FROM public.clan_boss_damage WHERE instance_id = b.id), 0)
   WHERE id = b.id;

  IF p_status = 'defeated' THEN
    FOR r IN SELECT user_id, damage FROM public.clan_boss_damage WHERE instance_id = b.id AND damage >= v_min LOOP
      v_share := CASE WHEN b.max_hp > 0 THEN r.damage / b.max_hp ELSE 0 END;
      v_reward := jsonb_build_object(
        'fc', floor(COALESCE((snap->'participant'->>'fc')::numeric, 0) + v_pool * v_share),
        'fragments', COALESCE((snap->'participant'->>'fragments')::int, 0),
        'petFood', COALESCE((snap->'participant'->>'petFood')::int, 0),
        'chests', COALESCE((snap->'participant'->>'chests')::int, 0),
        'pvpTickets', COALESCE((snap->'participant'->>'pvpTickets')::int, 0)
      );
      IF r.user_id = v_top THEN
        v_reward := jsonb_build_object(
          'fc', COALESCE((v_reward->>'fc')::numeric,0) + COALESCE((snap->'topDamage'->>'fc')::numeric, 0),
          'fragments', COALESCE((v_reward->>'fragments')::int,0) + COALESCE((snap->'topDamage'->>'fragments')::int, 0),
          'petFood', COALESCE((v_reward->>'petFood')::int,0) + COALESCE((snap->'topDamage'->>'petFood')::int, 0),
          'chests', COALESCE((v_reward->>'chests')::int,0) + COALESCE((snap->'topDamage'->>'chests')::int, 0),
          'pvpTickets', COALESCE((v_reward->>'pvpTickets')::int,0) + COALESCE((snap->'topDamage'->>'pvpTickets')::int, 0)
        );
      END IF;
      INSERT INTO public.clan_boss_claims(instance_id, clan_id, user_id, damage, payload)
      VALUES (b.id, b.clan_id, r.user_id, r.damage, v_reward)
      ON CONFLICT (instance_id, user_id) DO NOTHING;
      IF found THEN
        PERFORM public.clan_boss_deliver(r.user_id, v_reward);
        IF v_xp > 0 THEN PERFORM public.grant_clan_xp(r.user_id, 'clan_boss_cycle', v_xp); END IF;
      END IF;
    END LOOP;
  END IF;
END $function$;

-- State payload gains the visual/progression fields. Ranking, cooldown and damage
-- semantics are unchanged.
CREATE OR REPLACE FUNCTION public.get_clan_boss(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_boss_config; v_uid uuid; v_clan uuid; c public.clans%rowtype;
        b public.clan_boss_instances; d public.clan_boss_damage; v_rank integer; v_next timestamptz;
        tpl public.clan_boss_templates; v_total integer; v_last integer;
BEGIN
  cfg := public.clan_boss_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  SELECT count(*)::int, COALESCE(MAX(cycle_number),0) INTO v_total, v_last
    FROM public.clan_boss_templates WHERE enabled;
  IF v_clan IS NULL THEN
    RETURN jsonb_build_object('inClan', false, 'bossName', cfg.boss_name, 'bossKey', cfg.boss_key,
      'totalBosses', v_total, 'serverTime', now());
  END IF;
  SELECT * INTO c FROM public.clans WHERE id = v_clan;
  b := public.clan_boss_ensure(v_clan);
  tpl := public.clan_boss_template_for_cycle(b.cycle);
  SELECT * INTO d FROM public.clan_boss_damage WHERE instance_id = b.id AND user_id = v_uid;
  SELECT count(*) + 1 INTO v_rank FROM public.clan_boss_damage
   WHERE instance_id = b.id AND damage > COALESCE(d.damage, 0);
  v_next := COALESCE(d.last_attack_at, to_timestamp(0)) + make_interval(secs => GREATEST(1, cfg.cooldown_seconds));

  RETURN jsonb_build_object(
    'inClan', true,
    'totalBosses', v_total,
    'clan', jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'level', c.level, 'emblem', c.emblem_config),
    'boss', jsonb_build_object(
      'id', b.id, 'key', b.boss_key, 'name', b.boss_name, 'cycle', b.cycle, 'level', b.level,
      'maxHp', b.max_hp, 'currentHp', b.current_hp, 'status', b.status,
      'startsAt', b.starts_at, 'endsAt', b.ends_at,
      'subtitle', COALESCE(tpl.subtitle, ''),
      'theme', COALESCE(tpl.theme, 'abyss'),
      'imageUrl', tpl.image_url,
      'backgroundUrl', tpl.background_url,
      'baseDamage', COALESCE(tpl.base_damage, 0),
      'rewardFc', COALESCE(tpl.reward_fc, 0),
      'bossNumber', COALESCE(tpl.cycle_number, b.cycle),
      'isFinal', COALESCE(tpl.cycle_number, 0) >= v_last,
      'clanDamage', COALESCE((SELECT SUM(damage) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'attacks', COALESCE((SELECT SUM(attacks) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'participants', COALESCE((SELECT count(*) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'minDamageForRewards', GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0)),
      'clanXpReward', COALESCE((b.rewards_snapshot->>'clanXp')::integer, cfg.clan_xp_reward),
      'cooldownSeconds', cfg.cooldown_seconds
    ),
    'me', jsonb_build_object(
      'damage', COALESCE(d.damage, 0), 'attacks', COALESCE(d.attacks, 0),
      'rank', CASE WHEN COALESCE(d.damage,0) > 0 THEN v_rank ELSE NULL END,
      'nextAttackAt', CASE WHEN d.last_attack_at IS NULL THEN NULL ELSE v_next END,
      'canAttack', b.status = 'active' AND b.current_hp > 0 AND (d.last_attack_at IS NULL OR v_next <= now()),
      'eligibleForRewards', COALESCE(d.damage,0) >= GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0)),
      'power', public.clan_player_power(v_uid)
    ),
    'ranking', COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'damage')::numeric DESC) FROM (
        SELECT jsonb_build_object('userId', dd.user_id,
          'name', COALESCE(g.display_name, g.first_name, g.username, 'Player'),
          'username', g.username, 'avatar', g.avatar_url,
          'damage', dd.damage, 'attacks', dd.attacks, 'isMe', dd.user_id = v_uid) x
        FROM public.clan_boss_damage dd JOIN public.game_players g ON g.id = dd.user_id
        WHERE dd.instance_id = b.id ORDER BY dd.damage DESC LIMIT 50) s), '[]'::jsonb),
    'rewards', COALESCE(b.rewards_snapshot, cfg.rewards),
    'history', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'cycle', h.cycle, 'status', h.status, 'maxHp', h.max_hp, 'totalDamage', h.total_damage,
        'bossName', h.boss_name, 'bossKey', h.boss_key,
        'clanXp', h.clan_xp_awarded, 'finishedAt', h.finished_at,
        'topName', COALESCE(tg.display_name, tg.username, NULL),
        'topDamage', (SELECT MAX(damage) FROM public.clan_boss_damage cd WHERE cd.instance_id = h.id)) ORDER BY h.cycle DESC)
      FROM public.clan_boss_instances h LEFT JOIN public.game_players tg ON tg.id = h.top_user_id
      WHERE h.clan_id = v_clan AND h.status <> 'active'), '[]'::jsonb),
    'serverTime', now()
  );
END $function$;
