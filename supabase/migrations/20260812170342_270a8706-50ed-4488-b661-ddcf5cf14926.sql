-- 1. Official stat generation ranges + validation (single source of truth)
create or replace function public.hero_stat_ranges(p_rarity text)
returns table(min_atk numeric, max_atk numeric, min_hp numeric, max_hp numeric, min_ag numeric, max_ag numeric, min_hg numeric, max_hg numeric)
language sql immutable set search_path = public as $$
  select s.min_atk,s.max_atk,s.min_hp,s.max_hp,s.min_ag,s.max_ag,s.min_hg,s.max_hg from (values
    ('common',100,180,1000,1800,.025,.030,.040,.045),
    ('uncommon',140,230,1400,2300,.028,.033,.042,.048),
    ('rare',180,300,1800,3000,.031,.036,.045,.051),
    ('epic',230,380,2300,3800,.034,.039,.048,.054),
    ('legendary',300,500,3000,5000,.037,.042,.051,.057),
    ('mythic',420,700,4200,7000,.040,.045,.054,.060),
    ('ancestral',600,950,6000,9500,.043,.048,.057,.063)
  ) s(rarity,min_atk,max_atk,min_hp,max_hp,min_ag,max_ag,min_hg,max_hg)
  where s.rarity = public.normalize_hero_rarity(p_rarity);
$$;

create or replace function public.ensure_pvp_hero_stats()
returns trigger language plpgsql set search_path = public as $$
declare r text;seed text;min_atk numeric;max_atk numeric;min_hp numeric;max_hp numeric;min_ag numeric;max_ag numeric;min_hg numeric;max_hg numeric;atk_mult numeric:=1;hp_mult numeric:=1;fuse numeric:=1;kinds text[]:=array['warrior','assassin','tank','mage','archer','support'];
begin
  r:=normalize_hero_rarity(new.rarity);
  new.hero_template_id:=coalesce(new.hero_template_id,new.hero_key,new.name);
  seed:=coalesce(new.stats_seed,new.id::text||':'||new.hero_template_id||':'||new.user_id::text||':'||new.created_at::text);
  new.stats_seed:=seed;
  new.archetype:=coalesce(new.archetype,kinds[1+(abs(hashtextextended(seed||':kind',0))%6)::int]);
  select g.min_atk,g.max_atk,g.min_hp,g.max_hp,g.min_ag,g.max_ag,g.min_hg,g.max_hg
    into min_atk,max_atk,min_hp,max_hp,min_ag,max_ag,min_hg,max_hg
    from hero_stat_ranges(r) g;
  case new.archetype
    when 'warrior' then hp_mult:=1.15;
    when 'assassin' then atk_mult:=1.15;hp_mult:=.9;
    when 'tank' then atk_mult:=.85;hp_mult:=1.3;
    when 'mage' then atk_mult:=1.2;hp_mult:=.85;
    when 'archer' then atk_mult:=1.1;
    when 'support' then atk_mult:=.9;hp_mult:=1.1;
    else new.archetype:='warrior';hp_mult:=1.15;
  end case;
  -- Generate when missing OR when the stored value is below the rarity floor (broken legacy data).
  if new.base_atk is null or new.base_atk < min_atk then
    new.base_atk:=least(max_atk, greatest(min_atk, round((min_atk+pvp_stat_unit(seed||':atk')*(max_atk-min_atk))*atk_mult)));
  end if;
  if new.base_hp is null or new.base_hp < min_hp then
    new.base_hp:=least(max_hp, greatest(min_hp, round((min_hp+pvp_stat_unit(seed||':hp')*(max_hp-min_hp))*hp_mult)));
  end if;
  if new.attack_growth is null or new.attack_growth <= 0 then new.attack_growth:=round(min_ag+pvp_stat_unit(seed||':ag')*(max_ag-min_ag),5);end if;
  if new.hp_growth is null or new.hp_growth <= 0 then new.hp_growth:=round(min_hg+pvp_stat_unit(seed||':hg')*(max_hg-min_hg),5);end if;
  new.level:=greatest(1,coalesce(new.level,1));
  new.fusion_level:=greatest(0,coalesce(new.fusion_level,0));
  fuse:=hero_fusion_multiplier(new.fusion_level);
  new.final_atk:=greatest(1,round((new.base_atk+coalesce(new.bonus_atk,0))*power(1+new.attack_growth,new.level-1)*fuse));
  new.final_hp:=greatest(1,round((new.base_hp+coalesce(new.bonus_hp,0))*power(1+new.hp_growth,new.level-1)*fuse));
  new.stats_generated_at:=coalesce(new.stats_generated_at,now());
  return new;
end $$;

-- 2. Chest opening: stop writing boss-scale stats, defer to the official generator
CREATE OR REPLACE FUNCTION public.open_hero_chest(p_telegram_id bigint, p_inventory_item_id uuid, p_source text DEFAULT 'calendar'::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  u uuid; inv player_inventory%rowtype; cfg chest_reward_tables%rowtype;
  rar text; allowed text[]; hero record; pick record;
  basea numeric; baseh numeric; seed int; new_id uuid; open_no int; key text; fallback_from text;
begin
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('hero_chest:'||u::text,0));

  select * into inv from player_inventory where id=p_inventory_item_id and user_id=u for update;
  if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_FOUND'; end if;

  select * into cfg from chest_reward_tables where chest_code=inv.item_code and enabled;
  if cfg.chest_code is null then raise exception 'CHEST_NOT_CONFIGURED'; end if;

  seed:=(random()*1000000)::int;
  select r.rarity, r.allowed into rar, allowed from roll_chest_rarity(
    coalesce((cfg.rarity_rates->>'common')::numeric,0),
    coalesce((cfg.rarity_rates->>'uncommon')::numeric,0),
    coalesce((cfg.rarity_rates->>'rare')::numeric,0),
    coalesce((cfg.rarity_rates->>'epic')::numeric,0),
    coalesce((cfg.rarity_rates->>'legendary')::numeric,0),
    coalesce((cfg.rarity_rates->>'ancestral')::numeric,0)
  ) r;

  select * into pick from roll_hero_for_rarity(rar,allowed);
  hero:=pick.hero; rar:=pick.final_rarity; fallback_from:=pick.fallback_from;

  select count(*)+1 into open_no from calendar_chest_open_history where inventory_item_id=inv.id;
  key:='chest_open:'||inv.id||':'||open_no;

  update player_inventory set quantity=quantity-1, updated_at=now() where id=inv.id;
  insert into player_heroes(user_id,hero_key,name,rarity,level,image,attribute_seed)
    values(u,hero.hero_key,hero.name,rar,1,hero.image,seed) returning id into new_id;
  select ph.base_atk, ph.base_hp into basea, baseh from player_heroes ph where ph.id=new_id;
  insert into calendar_chest_open_history(user_id,inventory_item_id,result_hero_id,result_rarity,idempotency_key,result_hero_key,result_hero_name,result_hero_image)
    values(u,inv.id,new_id,rar,key,hero.hero_key,hero.name,hero.image);
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name,fallback_from)
    values(u,p_telegram_id,coalesce(nullif(p_source,''),'calendar'),inv.item_code,'hero_chest',rar,new_id,hero.name,fallback_from);

  return jsonb_build_object('hero',jsonb_build_object('id',new_id,'name',hero.name,'image',hero.image,'rarity',rar,'level',1,'baseAtk',basea,'baseHp',baseh),
    'chest',jsonb_build_object('code',cfg.chest_code,'name',cfg.name,'subtitle',cfg.subtitle),
    'inventory',get_player_inventory(p_telegram_id));
end;
$function$;

-- 3. Season pass exclusive hero: use official generation instead of hardcoded 210/2200
CREATE OR REPLACE FUNCTION public.deliver_season_exclusive()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$declare r season_pass_rewards%rowtype;e season_exclusive_rewards%rowtype;k text;begin select*into r from season_pass_rewards where id=new.reward_id;select*into e from season_exclusive_rewards where season_id=r.season_id and pass_tier=r.tier and reward_code=r.reward_code and enabled;if e.id is null then return new;end if;k:=case e.reward_kind when'hero'then'season_pass_exclusive_hero:'else'season_pass_mythic_egg:'end||e.season_id||':'||new.user_id||':'||e.pass_tier;insert into season_exclusive_deliveries(season_id,user_id,reward_id,delivery_kind,idempotency_key)values(e.season_id,new.user_id,e.id,e.reward_kind,k)on conflict do nothing;if not found then return new;end if;if e.reward_kind='hero'then insert into player_heroes(user_id,hero_key,name,image,rarity,level,is_season_exclusive,exclusive_season_id,exclusive_pass_tier,exclusive_badge,exclusive_passive,tradable)values(new.user_id,e.reward_code,e.display_name,e.image_url,'epic',1,true,e.season_id,'adventurer',e.badge,e.passive,false);else insert into player_inventory(user_id,item_type,item_code,quantity,is_exclusive,season_id,pass_tier,exclusive_reward_code,tradable)values(new.user_id,'pet_egg',e.reward_code,1,true,e.season_id,'legendary',e.reward_code,false)on conflict(user_id,item_type,item_code)do nothing;end if;return new;end$function$;

-- 4. Audit trail of the repair
create table if not exists public.hero_stat_repair_audit (
  id uuid primary key default gen_random_uuid(),
  hero_id uuid not null,
  user_id uuid not null,
  hero_key text,
  rarity text not null,
  old_base_atk numeric,
  old_base_hp numeric,
  new_base_atk numeric,
  new_base_hp numeric,
  created_at timestamptz not null default now()
);
GRANT ALL ON public.hero_stat_repair_audit TO service_role;
ALTER TABLE public.hero_stat_repair_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service role manages hero stat repair audit" ON public.hero_stat_repair_audit
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- 5. Audit + repair only the broken heroes (valid heroes stay untouched)
with broken as (
  select ph.id, ph.user_id, ph.hero_key, normalize_hero_rarity(ph.rarity) as rarity,
         ph.base_atk as old_atk, ph.base_hp as old_hp
  from player_heroes ph
  cross join lateral hero_stat_ranges(ph.rarity) g
  where ph.base_atk is null or ph.base_atk < g.min_atk or ph.base_hp is null or ph.base_hp < g.min_hp
)
insert into hero_stat_repair_audit(hero_id,user_id,hero_key,rarity,old_base_atk,old_base_hp)
select id,user_id,hero_key,rarity,old_atk,old_hp from broken;

update player_heroes ph
set base_atk = case when ph.base_atk is null or ph.base_atk < f.min_atk then null else ph.base_atk end,
    base_hp = case when ph.base_hp is null or ph.base_hp < f.min_hp then null else ph.base_hp end,
    attack_growth = case when ph.attack_growth is null or ph.attack_growth <= 0 then null else ph.attack_growth end,
    hp_growth = case when ph.hp_growth is null or ph.hp_growth <= 0 then null else ph.hp_growth end,
    updated_at = now()
from (
  select x.id, g.min_atk, g.min_hp
  from player_heroes x
  cross join lateral hero_stat_ranges(x.rarity) g
  where x.id in (select hero_id from hero_stat_repair_audit where new_base_atk is null)
) f
where ph.id = f.id;

update hero_stat_repair_audit a
set new_base_atk = ph.base_atk, new_base_hp = ph.base_hp
from player_heroes ph
where ph.id = a.hero_id and a.new_base_atk is null;