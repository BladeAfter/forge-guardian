CREATE OR REPLACE FUNCTION public.process_boss_combat(p_telegram_id bigint, p_now timestamp with time zone DEFAULT clock_timestamp())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_id uuid; b public.boss_templates;
 c public.boss_combats%rowtype;event_at timestamptz;special_at timestamptz;revive_event timestamptz;cutoff timestamptz;team_damage numeric;target public.hero_combat_state%rowtype;dealt numeric;hero_count int;cycles bigint;kill_cycles bigint;bonuses jsonb;damage_bonus numeric:=0;damage_reduction numeric:=0;revive_speed numeric:=0;pet_slug text;skill_at timestamptz;skill_damage numeric;
begin
 b:=public.active_boss_template();
 if b.code is null then
   update public.boss_combats set status='expired',updated_at=clock_timestamp() where status='active'
     and user_id=(select id from public.game_players where telegram_id=p_telegram_id);
   return public.get_boss_combat(p_telegram_id);
 end if;
 v_id:=public.ensure_boss_combat(p_telegram_id);
 if v_id is null then return public.get_boss_combat(p_telegram_id); end if;
 select * into c from public.boss_combats where id=v_id for update;
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
  if c.boss_next_attack_at<=event_at then select * into target from public.hero_combat_state where combat_id=c.id and slot is not null and is_alive order by random() limit 1 for update;if found then target.current_hp:=greatest(0,target.current_hp-greatest(1,round(c.boss_attack*public.rarity_resistance(target.rarity)*(1-damage_reduction/100))));update public.hero_combat_state set current_hp=target.current_hp,is_alive=(target.current_hp>0),knocked_out_at=case when target.current_hp=0 then event_at end,revive_at=case when target.current_hp=0 then event_at+make_interval(secs=>greatest(30,round(300/(1+revive_speed/100)))::int) end,updated_at=event_at where id=target.id;end if;c.boss_last_attack_at:=event_at;c.boss_next_attack_at:=c.boss_next_attack_at+make_interval(secs=>c.boss_attack_interval_seconds);end if;
 end loop;
 update public.boss_combats set boss_current_hp=c.boss_current_hp,total_damage_dealt=c.total_damage_dealt,status=c.status,defeated_at=c.defeated_at,last_processed_at=cutoff,next_hero_attack_at=c.next_hero_attack_at,boss_last_attack_at=c.boss_last_attack_at,boss_next_attack_at=c.boss_next_attack_at,pet_next_skill_at=case when pet_slug='pyron' then skill_at end,updated_at=clock_timestamp() where id=c.id;
 return public.get_boss_combat(p_telegram_id);
end $function$;

CREATE OR REPLACE FUNCTION public.claim_boss_reward(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c boss_combats%rowtype; key text; next_hp numeric; next_attack numeric; next_reward numeric; v_user uuid; reward_bonus numeric:=0; paid numeric;
begin
 perform public.process_boss_combat(p_telegram_id); select id into v_user from game_players where telegram_id=p_telegram_id; select * into c from boss_combats where user_id=v_user and status='defeated' order by defeated_at desc limit 1 for update;
 if c.status<>'defeated' then raise exception 'Boss is not defeated'; end if; key:='boss_reward:'||c.id;
 reward_bonus:=greatest(0,coalesce((public.get_pet_bonuses(c.user_id)->>'reward_percent')::numeric,0));
 paid:=round(c.reward_amount*(1+reward_bonus/100));
 insert into boss_reward_transactions(user_id,combat_id,amount,idempotency_key) values(c.user_id,c.id,paid,key) on conflict(idempotency_key) do nothing;
 if found then update game_players set forge_coins=forge_coins+paid,boss_defeats=boss_defeats+1,updated_at=now() where id=c.user_id; end if;
 update boss_combats set status='rewarded',reward_claimed_at=coalesce(reward_claimed_at,now()),updated_at=now() where id=c.id;
 next_hp:=least(9000000000000000,round(c.boss_max_hp*1.08)); next_attack:=least(9000000000000000,round(c.boss_attack*1.05)); next_reward:=least(9000000000000000,round(c.reward_amount*1.05));
 insert into boss_combats(user_id,boss_level,boss_max_hp,boss_current_hp,boss_attack,reward_amount) values(c.user_id,c.boss_level+1,next_hp,next_hp,next_attack,next_reward);
 return public.process_boss_combat(p_telegram_id);
end $function$;