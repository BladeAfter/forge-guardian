-- 1) allow any real turn count in history
alter table public.pvp_battles drop constraint if exists pvp_battles_total_turns_check;
alter table public.pvp_battles add constraint pvp_battles_total_turns_check check (total_turns >= 1);

-- 2) simulator: no 50-turn rule, only real elimination + technical stalemate guard
CREATE OR REPLACE FUNCTION public.simulate_pvp_battle(a jsonb, d jsonb, seed text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ast jsonb;dst jsonb;initiative jsonb;entry jsonb;actor jsonb;target jsonb;side text;target_id text;log jsonb:='[]';
 raw numeric;reduction numeric;variance numeric;damage int;new_hp int;turn int:=0;last_turn int:=0;winner text;
 alive_a boolean;alive_d boolean;hp_a numeric;hp_d numeric;init_len int;
 idle int:=0;idle_limit int;hard_cap int:=100000;total_hp numeric;prev_hp numeric;stalled int:=0;
begin
 select coalesce(jsonb_agg(x||jsonb_build_object('currentHp',(x->>'finalHp')::int)),'[]')into ast from jsonb_array_elements(a)x;
 select coalesce(jsonb_agg(x||jsonb_build_object('currentHp',(x->>'finalHp')::int)),'[]')into dst from jsonb_array_elements(d)x;
 select jsonb_agg(jsonb_build_object('side',q.side,'heroId',q.hero_id)order by q.speed desc,q.level desc,q.tie)into initiative from(
   select'attacker'side,x->>'heroId'hero_id,coalesce((x->>'speed')::int,(x->>'level')::int)speed,(x->>'level')::int level,hashtextextended(seed||(x->>'heroId'),0)tie from jsonb_array_elements(a)x
   union all
   select'defender',x->>'heroId',coalesce((x->>'speed')::int,(x->>'level')::int),(x->>'level')::int,hashtextextended(seed||(x->>'heroId'),0) from jsonb_array_elements(d)x)q;
 if initiative is null or jsonb_array_length(initiative)=0 then
   return jsonb_build_object('attackerState',ast,'defenderState',dst,'battleLog',log,'winnerSide','defender','turns',1,'totalTurns',1,'stalemate',true);
 end if;
 init_len:=jsonb_array_length(initiative);
 idle_limit:=init_len*4+8;

 select coalesce(sum((x->>'currentHp')::numeric),0)into hp_a from jsonb_array_elements(ast)x;
 select coalesce(sum((x->>'currentHp')::numeric),0)into hp_d from jsonb_array_elements(dst)x;
 prev_hp:=hp_a+hp_d;

 loop
   turn:=turn+1;
   if turn>hard_cap then exit; end if;
   entry:=initiative->((turn-1)%init_len);
   side:=entry->>'side';actor:=null;target:=null;
   if side='attacker'then
     select x into actor from jsonb_array_elements(ast)x where x->>'heroId'=entry->>'heroId'and(x->>'currentHp')::int>0;
     select x into target from jsonb_array_elements(dst)x where(x->>'currentHp')::int>0 order by(x->>'currentHp')::numeric/greatest(1,(x->>'finalHp')::numeric),hashtextextended(seed||turn::text||(x->>'heroId'),0)limit 1;
   else
     select x into actor from jsonb_array_elements(dst)x where x->>'heroId'=entry->>'heroId'and(x->>'currentHp')::int>0;
     select x into target from jsonb_array_elements(ast)x where(x->>'currentHp')::int>0 order by(x->>'currentHp')::numeric/greatest(1,(x->>'finalHp')::numeric),hashtextextended(seed||turn::text||(x->>'heroId'),0)limit 1;
   end if;
   if actor is null or target is null then
     idle:=idle+1;
     if idle>idle_limit then exit; end if;
     continue;
   end if;
   idle:=0;
   last_turn:=turn;
   raw:=(actor->>'finalAtk')::numeric;
   reduction:=coalesce((target->>'defense')::numeric,0)/(coalesce((target->>'defense')::numeric,0)+300);
   variance:=.95+pvp_stat_unit(seed||':'||turn||':damage')*.10;
   damage:=greatest(1,round(raw*(1-reduction)*variance));
   new_hp:=greatest(0,(target->>'currentHp')::int-damage);
   target_id:=target->>'heroId';
   if side='attacker'then
     select jsonb_agg(case when x->>'heroId'=target_id then x||jsonb_build_object('currentHp',new_hp)else x end)into dst from jsonb_array_elements(dst)x;
   else
     select jsonb_agg(case when x->>'heroId'=target_id then x||jsonb_build_object('currentHp',new_hp)else x end)into ast from jsonb_array_elements(ast)x;
   end if;
   log:=log||jsonb_build_array(jsonb_build_object('turn',turn,'side',side,'attackerId',actor->>'heroId','targetId',target_id,'damage',damage,'remainingHp',new_hp));

   select coalesce(sum((x->>'currentHp')::numeric),0)into hp_a from jsonb_array_elements(ast)x;
   select coalesce(sum((x->>'currentHp')::numeric),0)into hp_d from jsonb_array_elements(dst)x;
   total_hp:=hp_a+hp_d;
   if total_hp>=prev_hp then stalled:=stalled+1; else stalled:=0; end if;
   prev_hp:=total_hp;
   if stalled>idle_limit*5 then exit; end if;

   select exists(select 1 from jsonb_array_elements(ast)x where(x->>'currentHp')::int>0),
          exists(select 1 from jsonb_array_elements(dst)x where(x->>'currentHp')::int>0) into alive_a,alive_d;
   if not alive_d then winner:='attacker';exit;
   elsif not alive_a then winner:='defender';exit;end if;
 end loop;

 if winner is null then
   -- technical stalemate only (should never happen in normal battles)
   select coalesce(sum((x->>'currentHp')::numeric/greatest(1,(x->>'finalHp')::numeric)),0)into hp_a from jsonb_array_elements(ast)x;
   select coalesce(sum((x->>'currentHp')::numeric/greatest(1,(x->>'finalHp')::numeric)),0)into hp_d from jsonb_array_elements(dst)x;
   winner:=case when hp_a>=hp_d then'attacker'else'defender'end;
   return jsonb_build_object('attackerState',ast,'defenderState',dst,'battleLog',log,'winnerSide',winner,'turns',greatest(1,last_turn),'totalTurns',greatest(1,last_turn),'stalemate',true);
 end if;
 return jsonb_build_object('attackerState',ast,'defenderState',dst,'battleLog',log,'winnerSide',winner,'turns',greatest(1,last_turn),'totalTurns',greatest(1,last_turn));
end$function$;

-- 3) drop the 50-turn clamp wherever it is baked into pvp functions
DO $$
declare r record; d text; nd text;
begin
  for r in select p.oid as oid, p.proname as proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname in ('start_pvp_battle','get_pvp_dashboard','pvp_battle_detail')
  loop
    d:=pg_get_functiondef(r.oid);
    nd:=replace(d,'least(50, greatest(1,','(greatest(1,');
    nd:=replace(nd,'least(50,greatest(1,','(greatest(1,');
    nd:=replace(nd,'least(50,last_turn)','last_turn');
    if nd<>d then execute nd; end if;
  end loop;
end $$;