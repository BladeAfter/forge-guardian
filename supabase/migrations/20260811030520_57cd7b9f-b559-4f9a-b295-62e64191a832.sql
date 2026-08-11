-- Overlay: global boss data merged into the per-player boss payload.
CREATE OR REPLACE FUNCTION public.global_boss_overlay(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_boss_cycles; v_dmg numeric := 0; v_rank int; v_share numeric := 0;
        v_min numeric; v_est numeric := 0; v_last jsonb;
BEGIN
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  IF cyc.id IS NULL THEN
    SELECT * INTO cyc FROM public.global_boss_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF cyc.id IS NULL THEN RETURN '{}'::jsonb; END IF;

  SELECT jsonb_build_object('cycleNumber', c.cycle_number, 'name', c.boss_name, 'damage', l.damage_total,
                            'rank', l.rank, 'rewardFc', l.reward_fc, 'distributedAt', l.distributed_at)
    INTO v_last
    FROM public.global_boss_reward_ledger l JOIN public.global_boss_cycles c ON c.id = l.boss_cycle_id
   WHERE l.user_id = p_user ORDER BY l.distributed_at DESC LIMIT 1;

  SELECT damage_total INTO v_dmg FROM public.global_boss_participants WHERE boss_cycle_id = cyc.id AND user_id = p_user;
  v_dmg := COALESCE(v_dmg, 0);
  IF v_dmg > 0 THEN
    SELECT count(*) + 1 INTO v_rank FROM public.global_boss_participants
      WHERE boss_cycle_id = cyc.id AND damage_total > v_dmg;
  END IF;
  v_min := GREATEST(COALESCE(cyc.minimum_damage_fixed, 0), cyc.max_hp * COALESCE(cyc.minimum_damage_percent, 0) / 100.0);
  IF cyc.total_damage > 0 THEN
    v_share := v_dmg / cyc.total_damage;
    v_est := CASE WHEN v_dmg >= v_min THEN round(cyc.reward_pool_fc * v_share) ELSE COALESCE(cyc.minimum_reward_fc, 0) END;
  END IF;

  RETURN jsonb_build_object(
    'bossName', cyc.boss_name, 'bossLevel', cyc.boss_level,
    'bossMaxHp', cyc.max_hp, 'bossCurrentHp', cyc.current_hp,
    'rewardAmount', cyc.reward_pool_fc, 'totalDamageDealt', v_dmg,
    'bossActive', cyc.status = 'active',
    'globalBoss', jsonb_build_object(
      'cycleId', cyc.id, 'cycleNumber', cyc.cycle_number, 'name', cyc.boss_name, 'image', cyc.boss_image,
      'status', cyc.status, 'maxHp', cyc.max_hp, 'currentHp', cyc.current_hp,
      'rewardPoolFc', cyc.reward_pool_fc, 'totalDamage', cyc.total_damage, 'participants', cyc.participants,
      'startsAt', cyc.starts_at, 'endsAt', cyc.ends_at, 'defeatedAt', cyc.defeated_at,
      'minimumDamage', v_min, 'minimumRewardFc', cyc.minimum_reward_fc,
      'rankBonusEnabled', cyc.rank_bonus_enabled,
      'yourDamage', v_dmg, 'yourRank', v_rank, 'yourSharePercent', round(v_share * 100, 4),
      'estimatedReward', v_est,
      'lastReward', v_last));
END; $$;

-- Per-player simulation, global shared HP.
CREATE OR REPLACE FUNCTION public.process_boss_combat(p_telegram_id bigint, p_now timestamp with time zone DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare
 v_id uuid; b public.boss_templates; cyc public.global_boss_cycles; v_start_hp numeric; v_dealt_total numeric:=0; v_defeated boolean:=false;
 c public.boss_combats%rowtype;event_at timestamptz;special_at timestamptz;revive_event timestamptz;cutoff timestamptz;team_damage numeric;target public.hero_combat_state%rowtype;dealt numeric;hero_count int;cycles bigint;kill_cycles bigint;bonuses jsonb;damage_bonus numeric:=0;damage_reduction numeric:=0;revive_speed numeric:=0;pet_slug text;skill_at timestamptz;skill_damage numeric;
begin
 b:=public.active_boss_template();
 cyc:=public.ensure_global_boss_cycle();
 if b.code is null or cyc.id is null or cyc.status<>'active' then
   update public.boss_combats set status='expired',updated_at=clock_timestamp() where status='active'
     and user_id=(select id from public.game_players where telegram_id=p_telegram_id);
   return public.get_boss_combat(p_telegram_id);
 end if;
 v_id:=public.ensure_boss_combat(p_telegram_id);
 if v_id is null then return public.get_boss_combat(p_telegram_id); end if;
 select * into c from public.boss_combats where id=v_id for update;
 -- Global HP is the single source of truth; lock the cycle before touching it.
 select * into cyc from public.global_boss_cycles where id=cyc.id for update;
 if cyc.status<>'active' then return public.get_boss_combat(p_telegram_id); end if;

 if c.cycle_id is distinct from cyc.id then
   c.cycle_id:=cyc.id; c.total_damage_dealt:=0; c.boss_name:=cyc.boss_name; c.boss_level:=cyc.boss_level;
   c.reward_amount:=cyc.reward_pool_fc; c.status:='active'; c.defeated_at:=null; c.reward_claimed_at:=null;
   c.last_processed_at:=greatest(c.last_processed_at,cyc.starts_at,p_now-interval '1 hour');
   c.next_hero_attack_at:=greatest(c.next_hero_attack_at,c.last_processed_at);
   c.boss_next_attack_at:=greatest(c.boss_next_attack_at,c.last_processed_at);
   update public.boss_combats set cycle_id=c.cycle_id,total_damage_dealt=0,boss_name=c.boss_name,boss_level=c.boss_level,
     reward_amount=c.reward_amount,status='active',defeated_at=null,reward_claimed_at=null,
     last_processed_at=c.last_processed_at,next_hero_attack_at=c.next_hero_attack_at,boss_next_attack_at=c.boss_next_attack_at,
     updated_at=clock_timestamp() where id=c.id;
 end if;
 c.boss_max_hp:=cyc.max_hp; c.boss_current_hp:=cyc.current_hp; v_start_hp:=cyc.current_hp;
 if c.status<>'active' then return public.get_boss_combat(p_telegram_id);end if;

 bonuses:=public.get_pet_bonuses(c.user_id);damage_bonus:=coalesce((bonuses->>'boss_damage_percent')::numeric,0);damage_reduction:=coalesce((bonuses->>'boss_damage_reduction_percent')::numeric,0);revive_speed:=greatest(0,coalesce((bonuses->>'revive_speed_percent')::numeric,0));
 select p.slug into pet_slug from public.player_pets pp join public.pets p on p.id=pp.pet_id where pp.user_id=c.user_id and pp.is_active;
 skill_at:=case when pet_slug='pyron' then coalesce(c.pet_next_skill_at,c.started_at+interval '60 seconds') else 'infinity'::timestamptz end;
 cutoff:=greatest(c.last_processed_at,least(p_now,c.last_processed_at+interval '7 days'));
 loop
  exit when c.boss_current_hp<=0;
  select min(revive_at) into revive_event from public.hero_combat_state where combat_id=c.id and not is_alive;
  special_at:=least(c.boss_next_attack_at,coalesce(revive_event,'infinity'),skill_at,cutoff);
  if c.next_hero_attack_at<=special_at then
   select coalesce(sum(final_atk),0)*(1+damage_bonus/100),count(*) into team_damage,hero_count from public.hero_combat_state where combat_id=c.id and slot is not null and is_alive;
   cycles:=floor(extract(epoch from(special_at-c.next_hero_attack_at))/10)::bigint+1;
   if team_damage>0 then kill_cycles:=ceil(c.boss_current_hp/team_damage)::bigint;if kill_cycles<=cycles then event_at:=c.next_hero_attack_at+make_interval(secs=>((kill_cycles-1)*10)::int);dealt:=c.boss_current_hp;c.total_damage_dealt:=c.total_damage_dealt+dealt;c.boss_current_hp:=0;c.status:='defeated';c.defeated_at:=event_at;c.next_hero_attack_at:=event_at+interval '10 seconds';exit;end if;dealt:=least(c.boss_current_hp,team_damage*cycles);c.boss_current_hp:=greatest(0,c.boss_current_hp-dealt);c.total_damage_dealt:=c.total_damage_dealt+dealt;end if;
   c.next_hero_attack_at:=c.next_hero_attack_at+make_interval(secs=>(cycles*10)::int);
  end if;
  exit when special_at>=cutoff;event_at:=special_at;
  update public.hero_combat_state set is_alive=true,current_hp=max_hp,knocked_out_at=null,revive_at=null,updated_at=event_at where combat_id=c.id and not is_alive and revive_at<=event_at;
  if skill_at<=event_at then select coalesce(sum(final_atk),0)*3 into skill_damage from public.hero_combat_state where combat_id=c.id and slot is not null and is_alive;if skill_damage>0 then dealt:=least(c.boss_current_hp,skill_damage);c.boss_current_hp:=c.boss_current_hp-dealt;c.total_damage_dealt:=c.total_damage_dealt+dealt;if c.boss_current_hp=0 then c.status:='defeated';c.defeated_at:=event_at;exit;end if;end if;skill_at:=skill_at+interval '60 seconds';end if;
  if c.boss_next_attack_at<=event_at then select * into target from public.hero_combat_state where combat_id=c.id and slot is not null and is_alive order by random() limit 1 for update;if found then target.current_hp:=greatest(0,target.current_hp-greatest(1,round(c.boss_attack*public.rarity_resistance(target.rarity)*(1-damage_reduction/100))));update public.hero_combat_state set current_hp=target.current_hp,is_alive=(target.current_hp>0),knocked_out_at=case when target.current_hp=0 then event_at end,revive_at=case when target.current_hp=0 then event_at+make_interval(secs=>greatest(30,round(300/(1+revive_speed/100)))::int) end,updated_at=event_at where id=target.id;end if;c.boss_last_attack_at=event_at;c.boss_next_attack_at:=c.boss_next_attack_at+make_interval(secs=>c.boss_attack_interval_seconds);end if;
 end loop;

 -- Effective damage can never exceed the HP that was still available.
 v_dealt_total:=greatest(0,v_start_hp-c.boss_current_hp);
 v_defeated:=c.boss_current_hp<=0;

 update public.boss_combats set boss_max_hp=c.boss_max_hp,boss_current_hp=c.boss_current_hp,total_damage_dealt=c.total_damage_dealt,status=c.status,defeated_at=c.defeated_at,last_processed_at=cutoff,next_hero_attack_at=c.next_hero_attack_at,boss_last_attack_at=c.boss_last_attack_at,boss_next_attack_at=c.boss_next_attack_at,pet_next_skill_at=case when pet_slug='pyron' then skill_at end,updated_at=clock_timestamp() where id=c.id;

 if v_dealt_total>0 then
   update public.global_boss_cycles set current_hp=greatest(0,c.boss_current_hp),updated_at=now() where id=cyc.id;
   perform public.record_global_boss_damage(cyc.id,c.user_id,v_dealt_total);
 end if;
 if v_defeated then
   update public.global_boss_cycles set current_hp=0,status='defeated',defeated_at=coalesce(defeated_at,now()),updated_at=now()
     where id=cyc.id and status='active';
   perform public.distribute_global_boss_rewards(cyc.id);
 end if;

 return public.get_boss_combat(p_telegram_id);
end $$;

-- Merge the global overlay into the per-player payload.
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
    return v_base || public.global_boss_overlay(v_user);
  end if;
  v_base:=jsonb_build_object('id',c.id,'bossId',c.boss_id,'bossName',c.boss_name,'bossLevel',c.boss_level,
    'bossMaxHp',c.boss_max_hp,'bossCurrentHp',c.boss_current_hp,'bossAttack',c.boss_attack,
    'bossAttackIntervalSeconds',c.boss_attack_interval_seconds,'rewardAmount',c.reward_amount,'status',c.status,
    'bossActive',v_active,'bossStartsAt',b.starts_at,'bossEndsAt',b.ends_at,
    'totalDamageDealt',c.total_damage_dealt,'defeats',defeats_count,'startedAt',c.started_at,
    'lastProcessedAt',c.last_processed_at,'nextHeroAttackAt',c.next_hero_attack_at,'bossLastAttackAt',c.boss_last_attack_at,
    'bossNextAttackAt',c.boss_next_attack_at,'defeatedAt',c.defeated_at,'rewardClaimedAt',c.reward_claimed_at,
    'teamChangeAvailableAt',c.team_change_available_at,'serverNow',clock_timestamp(),
    'heroes',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'heroId',s.hero_id,'name',h.name,'image',h.image,'rarity',s.rarity,'slot',s.slot,'level',s.level,'baseAtk',s.base_atk,'finalAtk',s.final_atk,'baseHp',s.base_hp,'maxHp',s.max_hp,'currentHp',s.current_hp,'isAlive',s.is_alive,'knockedOutAt',s.knocked_out_at,'reviveAt',s.revive_at) order by s.slot) from public.hero_combat_state s join public.player_heroes h on h.id=s.hero_id where s.combat_id=c.id and s.slot is not null),public.boss_team_json(v_user)),
    'ownedHeroes',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'heroKey',h.hero_key,'name',h.name,'image',h.image,'rarity',public.normalize_hero_rarity(h.rarity),'level',h.level) order by h.created_at) from public.player_heroes h where h.user_id=v_user),'[]'::jsonb));
  return v_base || public.global_boss_overlay(v_user);
end $$;

-- Rewards are distributed automatically; the legacy claim only syncs state.
CREATE OR REPLACE FUNCTION public.claim_boss_reward(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_boss_cycles;
BEGIN
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status IN ('defeated','distributing') ORDER BY defeated_at DESC LIMIT 1;
  IF cyc.id IS NOT NULL THEN PERFORM public.distribute_global_boss_rewards(cyc.id); END IF;
  RETURN public.get_boss_combat(p_telegram_id);
END; $$;