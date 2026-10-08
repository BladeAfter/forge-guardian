-- 1) Auto ATK preference (single source of truth for the benefit toggle)
CREATE TABLE IF NOT EXISTS public.global_boss_auto_attack (
  user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT true,
  last_auto_attack_at timestamptz,
  next_auto_attack_at timestamptz NOT NULL DEFAULT now(),
  attacks_total bigint NOT NULL DEFAULT 0,
  paused_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.global_boss_auto_attack TO service_role;
ALTER TABLE public.global_boss_auto_attack ENABLE ROW LEVEL SECURITY;

-- 2) Attack audit log (manual + auto)
CREATE TABLE IF NOT EXISTS public.global_boss_attack_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  telegram_id bigint,
  boss_id uuid,
  cycle_id uuid,
  attack_type text NOT NULL CHECK (attack_type IN ('manual','season_pass_auto')),
  damage numeric NOT NULL DEFAULT 0,
  team_power numeric NOT NULL DEFAULT 0,
  pass_type text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.global_boss_attack_log TO service_role;
ALTER TABLE public.global_boss_attack_log ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_gb_attack_log_user ON public.global_boss_attack_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gb_attack_log_cycle ON public.global_boss_attack_log(cycle_id, created_at DESC);

-- 3) Active pass tier granting the Auto ATK benefit (adventurer OR legendary = one benefit)
CREATE OR REPLACE FUNCTION public.global_boss_auto_pass_tier(p_user uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.tier FROM public.player_season_pass p
  JOIN public.season_pass_seasons s ON s.id = p.season_id
  WHERE p.user_id = p_user AND s.active AND now() BETWEEN s.start_at AND s.end_at
    AND p.tier IN ('adventurer','legendary')
  ORDER BY CASE p.tier WHEN 'legendary' THEN 0 ELSE 1 END
  LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.global_boss_auto_pass_tier(uuid) FROM PUBLIC, anon, authenticated;

-- 4) State json (auto-creates the row so a fresh pass purchase is instantly ON)
CREATE OR REPLACE FUNCTION public.global_boss_auto_attack_state_json(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a public.global_boss_auto_attack%rowtype; v_tier text; v_team boolean; v_reason text;
BEGIN
  IF p_user IS NULL THEN RETURN jsonb_build_object('eligible',false,'enabled',false,'active',false,'reason','no_pass'); END IF;
  INSERT INTO public.global_boss_auto_attack(user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO a FROM public.global_boss_auto_attack WHERE user_id = p_user;
  v_tier := public.global_boss_auto_pass_tier(p_user);
  v_team := EXISTS (SELECT 1 FROM public.boss_team_slots WHERE user_id = p_user);
  v_reason := CASE WHEN v_tier IS NULL THEN 'no_pass' WHEN NOT a.enabled THEN 'disabled'
                   WHEN NOT v_team THEN 'no_team' ELSE NULL END;
  RETURN jsonb_build_object(
    'eligible', v_tier IS NOT NULL, 'passTier', v_tier, 'enabled', a.enabled,
    'hasTeam', v_team, 'active', v_tier IS NOT NULL AND a.enabled AND v_team,
    'intervalSeconds', 300, 'lastAttackAt', a.last_auto_attack_at,
    'nextAttackAt', a.next_auto_attack_at, 'attacksTotal', a.attacks_total, 'reason', v_reason);
END $$;
REVOKE ALL ON FUNCTION public.global_boss_auto_attack_state_json(uuid) FROM PUBLIC, anon, authenticated;

-- 5) Toggle RPC (persisted preference, works across devices)
CREATE OR REPLACE FUNCTION public.set_global_boss_auto_attack(p_telegram_id bigint, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF public.global_boss_auto_pass_tier(u) IS NULL THEN RAISE EXCEPTION 'SEASON_PASS_REQUIRED'; END IF;
  INSERT INTO public.global_boss_auto_attack(user_id, enabled, next_auto_attack_at)
    VALUES (u, coalesce(p_enabled,true), now())
  ON CONFLICT (user_id) DO UPDATE SET enabled = coalesce(p_enabled,true),
    next_auto_attack_at = CASE WHEN coalesce(p_enabled,true) THEN LEAST(public.global_boss_auto_attack.next_auto_attack_at, now()) ELSE public.global_boss_auto_attack.next_auto_attack_at END,
    updated_at = now();
  RETURN public.global_boss_auto_attack_state_json(u);
END $$;
REVOKE ALL ON FUNCTION public.set_global_boss_auto_attack(bigint, boolean) FROM PUBLIC, anon, authenticated;

-- 6) Manual attack: same cooldown source of truth + audit log
CREATE OR REPLACE FUNCTION public.attack_boss(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b public.boss_templates; v_result jsonb; u uuid; cyc uuid; v_before numeric; v_after numeric; v_power numeric;
BEGIN
  b := public.active_boss_template();
  IF b.code IS NULL THEN RAISE EXCEPTION 'BOSS_NOT_ACTIVE'; END IF;
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF NOT EXISTS (SELECT 1 FROM public.boss_team_slots ts WHERE ts.user_id = u) THEN
    RAISE EXCEPTION 'BOSS_TEAM_EMPTY';
  END IF;
  SELECT id INTO cyc FROM public.global_boss_cycles WHERE status = 'active' ORDER BY created_at DESC LIMIT 1;
  SELECT coalesce(damage_total,0) INTO v_before FROM public.global_boss_participants
    WHERE boss_cycle_id = cyc AND user_id = u;
  v_result := public.process_boss_combat(p_telegram_id);
  SELECT coalesce(damage_total,0) INTO v_after FROM public.global_boss_participants
    WHERE boss_cycle_id = cyc AND user_id = u;
  SELECT coalesce(sum(s.final_atk),0) INTO v_power FROM public.hero_combat_state s
    JOIN public.boss_combats bc ON bc.id = s.combat_id
    WHERE bc.user_id = u AND s.slot IS NOT NULL;
  INSERT INTO public.global_boss_attack_log(user_id, telegram_id, boss_id, cycle_id, attack_type, damage, team_power, pass_type)
    VALUES (u, p_telegram_id, b.id, cyc, 'manual', greatest(0, coalesce(v_after,0) - coalesce(v_before,0)),
            coalesce(v_power,0), public.global_boss_auto_pass_tier(u));
  -- shared cooldown: a manual attack pushes the next automatic tick forward
  UPDATE public.global_boss_auto_attack SET last_auto_attack_at = now(),
    next_auto_attack_at = now() + interval '300 seconds', updated_at = now() WHERE user_id = u;
  PERFORM public.record_quest_event_for_telegram(p_telegram_id, 'boss_attack', 1);
  RETURN v_result;
END $$;

-- 7) Backend scheduler routine: offline Auto ATK for pass holders
CREATE OR REPLACE FUNCTION public.process_global_boss_auto_attacks(p_limit int DEFAULT 500)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_boss_cycles; r record; v_before numeric; v_after numeric;
        v_power numeric; v_tier text; v_count int := 0; v_dmg numeric := 0;
BEGIN
  -- one worker at a time (protects against overlapping cron runs / retries)
  IF NOT pg_try_advisory_xact_lock(hashtext('global_boss_auto_attacks')) THEN
    RETURN jsonb_build_object('processed', 0, 'skipped', 'locked');
  END IF;
  cyc := public.ensure_global_boss_cycle();
  IF cyc.id IS NULL OR cyc.status <> 'active' OR cyc.current_hp <= 0 THEN
    RETURN jsonb_build_object('processed', 0, 'skipped', 'boss_inactive');
  END IF;
  FOR r IN
    SELECT a.user_id, g.telegram_id
    FROM public.global_boss_auto_attack a
    JOIN public.game_players g ON g.id = a.user_id
    WHERE a.enabled
      AND a.next_auto_attack_at <= now()
      AND public.global_boss_auto_pass_tier(a.user_id) IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.boss_team_slots ts WHERE ts.user_id = a.user_id)
    ORDER BY a.next_auto_attack_at
    LIMIT GREATEST(1, LEAST(coalesce(p_limit, 500), 2000))
    FOR UPDATE OF a SKIP LOCKED
  LOOP
    SELECT * INTO cyc FROM public.global_boss_cycles WHERE id = cyc.id;
    EXIT WHEN cyc.status <> 'active' OR cyc.current_hp <= 0;
    v_tier := public.global_boss_auto_pass_tier(r.user_id);
    CONTINUE WHEN v_tier IS NULL;
    SELECT coalesce(damage_total,0) INTO v_before FROM public.global_boss_participants
      WHERE boss_cycle_id = cyc.id AND user_id = r.user_id;
    BEGIN
      PERFORM public.process_boss_combat(r.telegram_id);
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.global_boss_auto_attack SET next_auto_attack_at = now() + interval '300 seconds',
        paused_reason = left(SQLERRM, 200), updated_at = now() WHERE user_id = r.user_id;
      CONTINUE;
    END;
    SELECT coalesce(damage_total,0) INTO v_after FROM public.global_boss_participants
      WHERE boss_cycle_id = cyc.id AND user_id = r.user_id;
    SELECT coalesce(sum(s.final_atk),0) INTO v_power FROM public.hero_combat_state s
      JOIN public.boss_combats bc ON bc.id = s.combat_id
      WHERE bc.user_id = r.user_id AND s.slot IS NOT NULL;
    v_dmg := greatest(0, coalesce(v_after,0) - coalesce(v_before,0));
    INSERT INTO public.global_boss_attack_log(user_id, telegram_id, boss_id, cycle_id, attack_type, damage, team_power, pass_type)
      VALUES (r.user_id, r.telegram_id, cyc.boss_template_id, cyc.id, 'season_pass_auto', v_dmg, coalesce(v_power,0), v_tier);
    UPDATE public.global_boss_auto_attack SET last_auto_attack_at = now(),
      next_auto_attack_at = now() + interval '300 seconds', attacks_total = attacks_total + 1,
      paused_reason = NULL, updated_at = now() WHERE user_id = r.user_id;
    v_count := v_count + 1;
  END LOOP;
  RETURN jsonb_build_object('processed', v_count, 'cycleId', cyc.id);
END $$;
REVOKE ALL ON FUNCTION public.process_global_boss_auto_attacks(int) FROM PUBLIC, anon, authenticated;

-- 8) Expose auto attack state in the boss payload
CREATE OR REPLACE FUNCTION public.get_boss_combat(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare c public.boss_combats%rowtype; defeats_count int; v_user uuid; b public.boss_templates; v_active boolean; v_base jsonb;
begin
  insert into public.game_players(telegram_id) values(p_telegram_id)
  on conflict(telegram_id) do update set updated_at=now() returning id into v_user;
  b:=public.active_boss_template();
  v_active:=b.code is not null;
  select * into c from public.boss_combats where user_id=v_user and status in ('active','defeated')
  order by case status when 'defeated' then 0 else 1 end, created_at desc limit 1;
  if c.id is null and v_active then
    perform public.ensure_boss_combat(p_telegram_id);
    select * into c from public.boss_combats where user_id=v_user and status in ('active','defeated')
    order by case status when 'defeated' then 0 else 1 end, created_at desc limit 1;
  end if;
  select boss_defeats into defeats_count from public.game_players where id=v_user;
  if c.id is null then
    v_base:=jsonb_build_object('id',null,'bossId',b.id,'bossName',coalesce(b.name,'Nenhum chefe ativo'),
      'bossLevel',coalesce(b.level,1),'bossMaxHp',coalesce(b.max_hp,0),'bossCurrentHp',coalesce(b.max_hp,0),
      'bossAttack',coalesce(b.attack,0),'bossAttackIntervalSeconds',coalesce(b.attack_interval_seconds,60),
      'rewardAmount',coalesce(b.reward_amount,0),'status','inactive','bossActive',v_active,
      'bossStartsAt',b.starts_at,'bossEndsAt',b.ends_at,
      'totalDamageDealt',0,'defeats',coalesce(defeats_count,0),'startedAt',now(),'lastProcessedAt',now(),
      'nextHeroAttackAt',null,'bossLastAttackAt',null,'bossNextAttackAt',null,'defeatedAt',null,
      'rewardClaimedAt',null,'teamChangeAvailableAt',null,'serverNow',clock_timestamp(),
      'heroes',public.boss_team_json(v_user),
      'ownedHeroes',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'heroKey',h.hero_key,'name',h.name,'image',h.image,'rarity',public.normalize_hero_rarity(h.rarity),'level',h.level) order by h.created_at) from public.player_heroes h where h.user_id=v_user),'[]'::jsonb));
    return v_base || public.global_boss_overlay(v_user)
      || jsonb_build_object('autoAttack', public.global_boss_auto_attack_state_json(v_user));
  end if;
  v_base:=jsonb_build_object('id',c.id,'bossId',c.boss_id,'bossName',c.boss_name,'bossLevel',c.boss_level,
    'bossMaxHp',c.boss_max_hp,'bossCurrentHp',c.boss_current_hp,'bossAttack',c.boss_attack,
    'bossAttackIntervalSeconds',c.boss_attack_interval_seconds,'rewardAmount',c.reward_amount,'status',c.status,
    'bossActive',v_active,'bossStartsAt',b.starts_at,'bossEndsAt',b.ends_at,
    'totalDamageDealt',c.total_damage_dealt,'defeats',defeats_count,'startedAt',c.started_at,
    'lastProcessedAt',c.last_processed_at,'nextHeroAttackAt',c.next_hero_attack_at,'bossLastAttackAt',c.boss_last_attack_at,
    'bossNextAttackAt',c.boss_next_attack_at,'defeatedAt',c.defeated_at,'rewardClaimedAt',c.reward_claimed_at,
    'teamChangeAvailableAt',c.team_change_available_at,'serverNow',clock_timestamp(),
    'heroes',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'heroId',s.hero_id,'name',h.name,'image',h.image,'rarity',s.rarity,'slot',s.slot,'level',s.level,'baseAtk',s.base_atk,'finalAtk',s.final_atk,'baseHp',s.base_hp,'maxHp',s.max_hp,'currentHp',s.current_hp,'isAlive',s.is_alive,'knockedOutAt',s.knocked_out_at,'reviveAt',s.revive_at,'reviveProtected',s.revive_protected,'reviveAttackAt',s.revive_attack_at,'reviveAttackUsed',s.revive_attack_used) order by s.slot) from public.hero_combat_state s join public.player_heroes h on h.id=s.hero_id where s.combat_id=c.id and s.slot is not null),public.boss_team_json(v_user)),
    'ownedHeroes',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'heroKey',h.hero_key,'name',h.name,'image',h.image,'rarity',public.normalize_hero_rarity(h.rarity),'level',h.level) order by h.created_at) from public.player_heroes h where h.user_id=v_user),'[]'::jsonb));
  return v_base || public.global_boss_overlay(v_user)
    || jsonb_build_object('autoAttack', public.global_boss_auto_attack_state_json(v_user));
end $$;

-- 9) Schedule every minute (timestamp-driven, so no attack window is lost)
SELECT cron.unschedule('mythreon-global-boss-auto-atk')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'mythreon-global-boss-auto-atk');
SELECT cron.schedule('mythreon-global-boss-auto-atk', '* * * * *',
  $$SELECT public.process_global_boss_auto_attacks(500);$$);
