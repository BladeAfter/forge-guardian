-- ============================================================
-- GLOBAL BOSS: fix offline damage banking (root cause of the "Marcos" outlier)
-- Each process_boss_combat call used to simulate up to 7 DAYS of 10s hero ticks
-- in one shot, so a long polling gap was credited as ONE gigantic attack, and the
-- finishing tick was credited with the boss' whole remaining HP.
-- From now on, the simulated window per call is bounded, un-simulated idle time is
-- discarded, and every credit is compared with the theoretical maximum for the window.
-- ============================================================

INSERT INTO public.game_settings (key, value, category, label) VALUES
  ('global_boss_catchup_seconds', '60', 'boss', 'Global Boss catch-up window (s) — no pass'),
  ('global_boss_catchup_seconds_pass', '300', 'boss', 'Global Boss catch-up window (s) — Auto ATK pass')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.global_boss_damage_outliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid,
  combat_id uuid,
  user_id uuid,
  telegram_id bigint,
  kind text NOT NULL DEFAULT 'GLOBAL_BOSS_DAMAGE_OUTLIER',
  damage_credited numeric NOT NULL DEFAULT 0,
  expected_max numeric NOT NULL DEFAULT 0,
  team_damage_per_tick numeric NOT NULL DEFAULT 0,
  ticks_allowed integer NOT NULL DEFAULT 0,
  window_seconds integer NOT NULL DEFAULT 0,
  gap_seconds numeric NOT NULL DEFAULT 0,
  boss_defense numeric NOT NULL DEFAULT 0,
  damage_factor numeric NOT NULL DEFAULT 1,
  pass_tier text,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.global_boss_damage_outliers TO service_role;
ALTER TABLE public.global_boss_damage_outliers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "no direct client access" ON public.global_boss_damage_outliers;
CREATE POLICY "no direct client access" ON public.global_boss_damage_outliers
  FOR SELECT TO authenticated USING (false);

CREATE INDEX IF NOT EXISTS idx_gb_damage_outliers_cycle ON public.global_boss_damage_outliers (cycle_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gb_damage_outliers_user ON public.global_boss_damage_outliers (user_id, created_at DESC);

-- Official catch-up window: Auto ATK pass holders keep the worker cadence (300s),
-- everyone else only simulates the time they are actually connected.
CREATE OR REPLACE FUNCTION public.global_boss_catchup_seconds(p_user uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_tier text; v_val numeric;
BEGIN
  v_tier := public.global_boss_auto_pass_tier(p_user);
  SELECT NULLIF(btrim(value, '"'), '')::numeric INTO v_val FROM public.game_settings
   WHERE key = CASE WHEN v_tier IS NOT NULL THEN 'global_boss_catchup_seconds_pass' ELSE 'global_boss_catchup_seconds' END;
  RETURN GREATEST(10, LEAST(3600, COALESCE(v_val, CASE WHEN v_tier IS NOT NULL THEN 300 ELSE 60 END)))::int;
EXCEPTION WHEN OTHERS THEN
  RETURN CASE WHEN v_tier IS NOT NULL THEN 300 ELSE 60 END;
END $$;

REVOKE ALL ON FUNCTION public.global_boss_catchup_seconds(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.global_boss_catchup_seconds(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.process_boss_combat(p_telegram_id bigint, p_now timestamp with time zone DEFAULT clock_timestamp())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
 v_id uuid; b public.boss_templates; cyc public.global_boss_cycles; v_start_hp numeric; v_dealt_total numeric:=0; v_defeated boolean:=false;
 c public.boss_combats%rowtype;event_at timestamptz;special_at timestamptz;revive_event timestamptz;revive_attack_event timestamptz;cutoff timestamptz;team_damage numeric;target public.hero_combat_state%rowtype;dealt numeric;hero_count int;cycles bigint;kill_cycles bigint;v_def_factor numeric:=1;v_boss_atk numeric;bonuses jsonb;damage_bonus numeric:=0;damage_reduction numeric:=0;revive_speed numeric:=0;pet_slug text;skill_at timestamptz;skill_damage numeric;revive_damage numeric;v_protected boolean;
 v_window int;v_gap numeric;v_pass text;v_tick_damage numeric;v_ticks_allowed int;v_expected_max numeric;
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

 -- OFFLINE BANKING GUARD: never simulate more than the official catch-up window in a single
 -- call, and discard the idle time that was not simulated (it can no longer be banked).
 v_pass:=public.global_boss_auto_pass_tier(c.user_id);
 v_window:=public.global_boss_catchup_seconds(c.user_id);
 v_gap:=greatest(0,extract(epoch from (p_now-c.last_processed_at)));
 if c.last_processed_at < p_now-make_interval(secs=>v_window) then
   c.last_processed_at:=p_now-make_interval(secs=>v_window);
   c.next_hero_attack_at:=greatest(c.next_hero_attack_at,c.last_processed_at);
   c.boss_next_attack_at:=greatest(c.boss_next_attack_at,c.last_processed_at);
   if skill_at<>'infinity'::timestamptz then skill_at:=greatest(skill_at,c.last_processed_at); end if;
 end if;
 cutoff:=greatest(c.last_processed_at,least(p_now,c.last_processed_at+make_interval(secs=>v_window)));
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

 -- Idle time is never banked: processing always resumes from now.
 update public.boss_combats set boss_max_hp=c.boss_max_hp,boss_current_hp=c.boss_current_hp,total_damage_dealt=c.total_damage_dealt,status=c.status,defeated_at=c.defeated_at,last_processed_at=greatest(cutoff,p_now),next_hero_attack_at=greatest(c.next_hero_attack_at,p_now-make_interval(secs=>v_window)),boss_last_attack_at=c.boss_last_attack_at,boss_next_attack_at=greatest(c.boss_next_attack_at,p_now-make_interval(secs=>v_window)),pet_next_skill_at=case when pet_slug='pyron' then skill_at end,updated_at=clock_timestamp() where id=c.id;

 if v_dealt_total>0 then
   -- Sanity check (audit only, never blocks or caps the player): the credited damage must fit
   -- the theoretical maximum for this window (team damage per tick, pet skill and revive burst).
   select coalesce(sum(final_atk),0)*(1+damage_bonus/100)*v_def_factor into v_tick_damage
     from public.hero_combat_state where combat_id=c.id and slot is not null;
   v_ticks_allowed:=greatest(1,floor(v_window/10.0)::int+1);
   v_expected_max:=coalesce(v_tick_damage,0)*v_ticks_allowed*4+1;
   if v_dealt_total>v_expected_max and v_dealt_total>least(v_start_hp,greatest(v_expected_max,0)) then
     insert into public.global_boss_damage_outliers(cycle_id,combat_id,user_id,telegram_id,damage_credited,expected_max,
       team_damage_per_tick,ticks_allowed,window_seconds,gap_seconds,boss_defense,damage_factor,pass_tier,details)
     values (cyc.id,c.id,c.user_id,p_telegram_id,v_dealt_total,v_expected_max,coalesce(v_tick_damage,0),v_ticks_allowed,
       v_window,v_gap,coalesce(cyc.boss_defense,0),v_def_factor,v_pass,
       jsonb_build_object('bossStartHp',v_start_hp,'bossEndHp',c.boss_current_hp,'defeated',v_defeated,'petSlug',pet_slug,'bossDamageBonusPercent',damage_bonus));
   end if;
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