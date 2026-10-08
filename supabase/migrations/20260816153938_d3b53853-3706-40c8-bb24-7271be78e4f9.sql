CREATE OR REPLACE FUNCTION public.process_boss_combat(p_telegram_id bigint, p_now timestamp with time zone DEFAULT clock_timestamp())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_id uuid; b public.boss_templates; cyc public.global_boss_cycles; v_start_hp numeric; v_dealt_total numeric:=0; v_defeated boolean:=false;
 c public.boss_combats%rowtype;event_at timestamptz;special_at timestamptz;revive_event timestamptz;revive_attack_event timestamptz;cutoff timestamptz;team_damage numeric;target public.hero_combat_state%rowtype;dealt numeric;hero_count int;cycles bigint;kill_cycles bigint;v_def_factor numeric:=1;v_boss_atk numeric;bonuses jsonb;damage_bonus numeric:=0;damage_reduction numeric:=0;revive_speed numeric:=0;pet_slug text;skill_at timestamptz;skill_damage numeric;revive_damage numeric;v_protected boolean;
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
 -- Official Global Boss difficulty: defense mitigates incoming damage, attack comes from the cycle.
 v_def_factor:=public.global_boss_damage_factor(cyc.boss_defense);
 v_boss_atk:=greatest(1,round(coalesce(nullif(cyc.boss_attack,0),c.boss_attack)));
 if c.boss_attack is distinct from v_boss_atk then
   c.boss_attack:=v_boss_atk;
   update public.boss_combats set boss_attack=v_boss_atk,updated_at=clock_timestamp() where id=c.id;
 end if;
 if c.status<>'active' then return public.get_boss_combat(p_telegram_id);end if;

 bonuses:=public.get_pet_bonuses(c.user_id);damage_bonus:=coalesce((bonuses->>'boss_damage_percent')::numeric,0);damage_reduction:=coalesce((bonuses->>'boss_damage_reduction_percent')::numeric,0);revive_speed:=greatest(0,coalesce((bonuses->>'revive_speed_percent')::numeric,0));
 select p.slug into pet_slug from public.player_pets pp join public.pets p on p.id=pp.pet_id where pp.user_id=c.user_id and pp.is_active;
 skill_at:=case when pet_slug='pyron' then coalesce(c.pet_next_skill_at,c.started_at+interval '60 seconds') else 'infinity'::timestamptz end;
 cutoff:=greatest(c.last_processed_at,least(p_now,c.last_processed_at+interval '7 days'));
 loop
  exit when c.boss_current_hp<=0;
  select min(revive_at) into revive_event from public.hero_combat_state where combat_id=c.id and not is_alive;
  select min(revive_attack_at) into revive_attack_event from public.hero_combat_state where combat_id=c.id and revive_protected and revive_attack_at is not null;
  special_at:=least(c.boss_next_attack_at,coalesce(revive_event,'infinity'),coalesce(revive_attack_event,'infinity'),skill_at,cutoff);
  if c.next_hero_attack_at<=special_at then
   select coalesce(sum(final_atk),0)*(1+damage_bonus/100)*v_def_factor,count(*) into team_damage,hero_count from public.hero_combat_state where combat_id=c.id and slot is not null and is_alive;
   cycles:=floor(extract(epoch from(special_at-c.next_hero_attack_at))/10)::bigint+1;
   if team_damage>0 then kill_cycles:=ceil(c.boss_current_hp/team_damage)::bigint;if kill_cycles<=cycles then event_at:=c.next_hero_attack_at+make_interval(secs=>((kill_cycles-1)*10)::int);dealt:=c.boss_current_hp;c.total_damage_dealt:=c.total_damage_dealt+dealt;c.boss_current_hp:=0;c.status:='defeated';c.defeated_at:=event_at;c.next_hero_attack_at:=event_at+interval '10 seconds';exit;end if;dealt:=least(c.boss_current_hp,team_damage*cycles);c.boss_current_hp:=greatest(0,c.boss_current_hp-dealt);c.total_damage_dealt:=c.total_damage_dealt+dealt;end if;
   c.next_hero_attack_at:=c.next_hero_attack_at+make_interval(secs=>(cycles*10)::int);
  end if;
  exit when special_at>=cutoff;event_at:=special_at;

  -- Individual revive: 25% of max HP + one guaranteed attack shortly after (protected until then).
  update public.hero_combat_state set is_alive=true,current_hp=greatest(1,round(max_hp*0.25)),knocked_out_at=null,revive_at=null,
    revive_protected=true,revive_attack_used=false,revive_attack_at=event_at+interval '700 milliseconds',
    revive_protected_until=event_at+interval '3 seconds',updated_at=event_at
    where combat_id=c.id and not is_alive and revive_at<=event_at;

  -- Guaranteed revive attack (normal ATK, normal pet bonuses only), then protection ends.
  select coalesce(sum(final_atk),0)*(1+damage_bonus/100)*v_def_factor into revive_damage from public.hero_combat_state
    where combat_id=c.id and slot is not null and is_alive and revive_protected and revive_attack_at is not null and revive_attack_at<=event_at;
  if coalesce(revive_damage,0)>0 then
   dealt:=least(c.boss_current_hp,revive_damage);c.boss_current_hp:=greatest(0,c.boss_current_hp-dealt);c.total_damage_dealt:=c.total_damage_dealt+dealt;
  end if;
  update public.hero_combat_state set revive_protected=false,revive_attack_used=true,revive_attack_at=null,revive_protected_until=null,updated_at=event_at
    where combat_id=c.id and revive_protected and revive_attack_at is not null and revive_attack_at<=event_at;
  -- Safety limit: protection can never outlive its 3s window.
  update public.hero_combat_state set revive_protected=false,revive_attack_at=null,revive_protected_until=null,updated_at=event_at
    where combat_id=c.id and revive_protected and revive_protected_until is not null and revive_protected_until<=event_at;
  if c.boss_current_hp<=0 then c.status:='defeated';c.defeated_at:=event_at;exit;end if;

  if skill_at<=event_at then select coalesce(sum(final_atk),0)*3*v_def_factor into skill_damage from public.hero_combat_state where combat_id=c.id and slot is not null and is_alive;if skill_damage>0 then dealt:=least(c.boss_current_hp,skill_damage);c.boss_current_hp:=c.boss_current_hp-dealt;c.total_damage_dealt:=c.total_damage_dealt+dealt;if c.boss_current_hp=0 then c.status:='defeated';c.defeated_at:=event_at;exit;end if;end if;skill_at:=skill_at+interval '60 seconds';end if;
  if c.boss_next_attack_at<=event_at then
   select * into target from public.hero_combat_state where combat_id=c.id and slot is not null and is_alive order by random() limit 1 for update;
   if found then
    v_protected:=target.revive_protected and not target.revive_attack_used;
    target.current_hp:=greatest(0,target.current_hp-greatest(1,round(c.boss_attack*public.rarity_resistance(target.rarity)*(1-damage_reduction/100))));
    if v_protected then target.current_hp:=greatest(1,target.current_hp); end if;
    update public.hero_combat_state set current_hp=target.current_hp,is_alive=(target.current_hp>0),
      knocked_out_at=case when target.current_hp=0 then event_at end,
      revive_at=case when target.current_hp=0 then event_at+make_interval(secs=>greatest(30,round(300/(1+revive_speed/100)))::int) end,
      revive_protected=case when target.current_hp=0 then false else revive_protected end,
      revive_attack_at=case when target.current_hp=0 then null else revive_attack_at end,
      revive_protected_until=case when target.current_hp=0 then null else revive_protected_until end,
      updated_at=event_at where id=target.id;
   end if;
   c.boss_last_attack_at=event_at;c.boss_next_attack_at:=c.boss_next_attack_at+make_interval(secs=>c.boss_attack_interval_seconds);
  end if;
 end loop;

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
end $function$;