-- Entrega de herói LENDÁRIO para os membros dos clãs que MATARAM a raid (status DEFEATED)
CREATE OR REPLACE FUNCTION public.clan_raid_grant_legendary_hero(p_user_id uuid, p_raid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE c public.hero_catalog; v_hero_id uuid;
BEGIN
  SELECT * INTO c
    FROM public.hero_catalog
   WHERE public.normalize_hero_rarity(rarity) = 'LEGENDARY'
   ORDER BY random()
   LIMIT 1;
  IF c.hero_key IS NULL THEN RETURN NULL; END IF;

  INSERT INTO public.player_heroes (user_id, hero_key, name, rarity, level, image)
  VALUES (p_user_id, c.hero_key, c.name, public.normalize_hero_rarity(c.rarity), 1, c.image)
  RETURNING id INTO v_hero_id;

  RETURN jsonb_build_object('heroId', v_hero_id, 'heroKey', c.hero_key, 'name', c.name, 'rarity', 'LEGENDARY');
END $$;

GRANT EXECUTE ON FUNCTION public.clan_raid_grant_legendary_hero(uuid, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.clan_raid_settle(p_raid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r public.clan_raid_cycles; cfg public.clan_collective_settings; cc public.clan_coin_settings;
        snap jsonb; v_min numeric; rec record; v_share numeric; v_reward jsonb;
        v_paid integer := 0; v_coins integer; v_rank integer; v_total numeric;
        v_hero jsonb; v_heroes integer := 0;
BEGIN
  cfg := public.clan_collective_cfg();
  cc := public.clan_coin_cfg();
  SELECT * INTO r FROM public.clan_raid_cycles WHERE id = p_raid FOR UPDATE;
  IF r.id IS NULL OR r.settled_at IS NOT NULL THEN RETURN jsonb_build_object('status','already'); END IF;
  IF r.status NOT IN ('DEFEATED','EXPIRED') THEN RETURN jsonb_build_object('status','active'); END IF;

  snap := COALESCE(r.rewards_snapshot, '{}'::jsonb);
  v_min := r.max_hp * COALESCE((snap->>'minDamagePct')::numeric, 0.5) / 100.0;
  SELECT COALESCE(sum(combat_damage), 0) INTO v_total FROM public.clan_raid_attacks WHERE raid_id = r.id;

  IF r.status = 'DEFEATED' OR NOT cfg.raid_full_kill_required THEN
    FOR rec IN
      SELECT user_id, sum(combat_damage) AS dmg,
             row_number() OVER (ORDER BY sum(combat_damage) DESC) AS rnk
        FROM public.clan_raid_attacks
       WHERE raid_id = r.id GROUP BY user_id HAVING sum(combat_damage) >= v_min
    LOOP
      v_share := CASE WHEN v_total > 0 THEN LEAST(1, rec.dmg / v_total) ELSE 0 END;
      v_rank := rec.rnk::int;
      v_coins := cc.raid_participation
               + CASE WHEN r.status = 'DEFEATED' THEN cc.raid_defeat ELSE 0 END
               + COALESCE(cc.raid_top_bonus[v_rank], 0);
      v_reward := jsonb_build_object(
        'fc', floor(COALESCE((snap->>'fcPool')::numeric, 0) * v_share),
        'coins', v_coins);
      INSERT INTO public.clan_raid_rewards(raid_id, clan_id, user_id, damage, payload)
      VALUES (r.id, r.clan_id, rec.user_id, rec.dmg, v_reward)
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        PERFORM public.clan_boss_deliver(rec.user_id, v_reward - 'coins');
        PERFORM public.clan_coin_award(rec.user_id, 'CLAN_RAID', r.id::text, v_coins);
        IF COALESCE((snap->>'clanXp')::int, 0) > 0 THEN
          PERFORM public.grant_clan_xp(rec.user_id, 'clan_raid', (snap->>'clanXp')::int);
        END IF;

        -- Herói LENDÁRIO garantido apenas quando o clã realmente MATOU a raid
        IF r.status = 'DEFEATED' THEN
          v_hero := public.clan_raid_grant_legendary_hero(rec.user_id, r.id);
          IF v_hero IS NOT NULL THEN
            v_reward := v_reward || jsonb_build_object('legendaryHero', v_hero);
            UPDATE public.clan_raid_rewards
               SET payload = v_reward
             WHERE raid_id = r.id AND user_id = rec.user_id;
            v_heroes := v_heroes + 1;
          END IF;
        END IF;

        v_paid := v_paid + 1;
      END IF;
    END LOOP;
  END IF;

  UPDATE public.clan_raid_cycles SET status = 'SETTLED', settled_at = now() WHERE id = r.id;
  RETURN jsonb_build_object('status','settled','rewarded', v_paid, 'legendaryHeroes', v_heroes);
END $function$;
