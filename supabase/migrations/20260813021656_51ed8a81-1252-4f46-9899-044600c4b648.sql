-- ============ TOWER OF ETERNITY: solo dungeon, 100 floors, individual progress ============

CREATE TABLE IF NOT EXISTS public.tower_bosses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  boss_key text NOT NULL UNIQUE,
  floor_index int NOT NULL UNIQUE CHECK (floor_index BETWEEN 1 AND 10),
  name text NOT NULL,
  theme text NOT NULL DEFAULT '',
  role text NOT NULL DEFAULT '',
  behavior text NOT NULL DEFAULT 'heavy',
  base_hp numeric NOT NULL DEFAULT 20000,
  base_atk numeric NOT NULL DEFAULT 900,
  base_def numeric NOT NULL DEFAULT 120,
  base_speed int NOT NULL DEFAULT 100,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.tower_bosses TO service_role;
ALTER TABLE public.tower_bosses ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.tower_progress (
  user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
  current_floor int NOT NULL DEFAULT 1 CHECK (current_floor BETWEEN 1 AND 100),
  highest_floor int NOT NULL DEFAULT 0 CHECK (highest_floor BETWEEN 0 AND 100),
  attempts_used int NOT NULL DEFAULT 0,
  attempts_date date NOT NULL DEFAULT (now() AT TIME ZONE 'utc')::date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.tower_progress TO service_role;
ALTER TABLE public.tower_progress ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.tower_team_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  slot int NOT NULL CHECK (slot BETWEEN 1 AND 5),
  hero_id uuid NOT NULL REFERENCES public.player_heroes(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, slot),
  UNIQUE (user_id, hero_id)
);
GRANT ALL ON public.tower_team_slots TO service_role;
ALTER TABLE public.tower_team_slots ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.tower_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  floor int NOT NULL,
  boss_key text NOT NULL,
  result text NOT NULL CHECK (result IN ('win','loss')),
  turns int NOT NULL DEFAULT 0,
  cost_fc numeric NOT NULL DEFAULT 0,
  first_clear boolean NOT NULL DEFAULT false,
  rewards jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tower_runs_user_idx ON public.tower_runs(user_id, created_at DESC);
GRANT ALL ON public.tower_runs TO service_role;
ALTER TABLE public.tower_runs ENABLE ROW LEVEL SECURITY;

INSERT INTO public.tower_bosses (boss_key, floor_index, name, theme, role, behavior, base_hp, base_atk, base_def, base_speed) VALUES
  ('abyssal_warden',   1, 'Abyssal Warden',   'abyss',     'tank',      'heavy',   26000, 780,  180, 92),
  ('infernal_behemoth',2, 'Infernal Behemoth','fire',      'bruiser',   'burn',    24000, 980,  130, 96),
  ('frost_tyrant',     3, 'Frost Tyrant',     'ice',       'controller','freeze',  28000, 860,  200, 90),
  ('venom_hydra',      4, 'Venom Hydra',      'poison',    'dot',       'poison',  25000, 900,  140, 104),
  ('storm_colossus',   5, 'Storm Colossus',   'storm',     'burst',     'stun',    27000, 1050, 150, 108),
  ('shadow_queen',     6, 'Shadow Queen',     'shadow',    'debuffer',  'curse',   26000, 1000, 145, 112),
  ('iron_juggernaut',  7, 'Iron Juggernaut',  'metal',     'fortress',  'crush',   34000, 1080, 260, 84),
  ('ancient_treant',   8, 'Ancient Treant',   'nature',    'sustain',   'regen',   32000, 1020, 210, 88),
  ('celestial_reaper', 9, 'Celestial Reaper', 'celestial', 'assassin',  'execute', 28000, 1180, 165, 124),
  ('eternal_dragon',  10, 'Eternal Dragon',   'dragon',    'final',     'dragon',  40000, 1300, 230, 116)
ON CONFLICT (boss_key) DO UPDATE SET
  name=EXCLUDED.name, theme=EXCLUDED.theme, role=EXCLUDED.role, behavior=EXCLUDED.behavior,
  base_hp=EXCLUDED.base_hp, base_atk=EXCLUDED.base_atk, base_def=EXCLUDED.base_def,
  base_speed=EXCLUDED.base_speed, updated_at=now();

-- ---------- Entry cost per floor bracket ----------
CREATE OR REPLACE FUNCTION public.tower_entry_cost(p_floor int)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_floor >= 100 THEN 2000000
    WHEN p_floor >= 91 THEN 1250000
    WHEN p_floor >= 81 THEN 1000000
    WHEN p_floor >= 71 THEN 800000
    WHEN p_floor >= 61 THEN 650000
    WHEN p_floor >= 51 THEN 500000
    WHEN p_floor >= 41 THEN 400000
    WHEN p_floor >= 31 THEN 300000
    WHEN p_floor >= 21 THEN 200000
    WHEN p_floor >= 11 THEN 150000
    ELSE 100000 END::numeric;
$$;

-- ---------- Boss of a given floor, with difficulty scaling ----------
CREATE OR REPLACE FUNCTION public.tower_boss_for_floor(p_floor int)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
declare f int := greatest(1, least(100, coalesce(p_floor,1)));
  b public.tower_bosses; tier int; step int; mult numeric; hp numeric; atk numeric; def numeric;
begin
  select * into b from public.tower_bosses where floor_index = ((f - 1) % 10) + 1;
  if b.boss_key is null then raise exception 'TOWER_BOSS_MISSING'; end if;
  tier := ceil(f / 10.0)::int;            -- 1..10
  step := ((f - 1) % 10);                 -- 0..9 inside the tier
  mult := power(1.55, tier - 1) * (1 + 0.06 * step);
  hp  := round(b.base_hp * mult);
  atk := round(b.base_atk * power(1.34, tier - 1) * (1 + 0.04 * step));
  def := round(b.base_def * power(1.22, tier - 1) * (1 + 0.03 * step));
  return jsonb_build_object(
    'heroId','tower-boss','name',b.name,'bossKey',b.boss_key,'theme',b.theme,'role',b.role,
    'behavior',b.behavior,'floor',f,'tier',tier,'rarity','boss',
    'finalHp',hp,'finalAtk',atk,'defense',def,'speed',b.base_speed + tier,
    'level',f,'imageUrl',null,
    'recommendedPower', round(hp * 0.35 + atk * 6)::bigint,
    'entryCost', public.tower_entry_cost(f)
  );
end $$;

-- ---------- Team helpers ----------
CREATE OR REPLACE FUNCTION public.tower_team_json(p_user uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  select coalesce(jsonb_agg(public.pvp_hero_json(h) || jsonb_build_object('slot', s.slot) order by s.slot), '[]'::jsonb)
  from public.tower_team_slots s join public.player_heroes h on h.id = s.hero_id
  where s.user_id = p_user;
$$;

CREATE OR REPLACE FUNCTION public.save_tower_team_slot(p_telegram_id bigint, p_slot int, p_hero_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare v_user uuid; v_key text;
begin
  select id into v_user from public.game_players where telegram_id = p_telegram_id;
  if v_user is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if p_slot is null or p_slot < 1 or p_slot > 5 then raise exception 'INVALID_SLOT'; end if;
  select public.pvp_hero_template_key(h) into v_key from public.player_heroes h where h.id = p_hero_id and h.user_id = v_user;
  if v_key is null then raise exception 'HERO_NOT_FOUND'; end if;
  if exists(
    select 1 from public.tower_team_slots s join public.player_heroes h on h.id = s.hero_id
    where s.user_id = v_user and s.slot <> p_slot and public.pvp_hero_template_key(h) = v_key
  ) then raise exception 'TOWER_DUPLICATE_HERO_TEAM'; end if;
  delete from public.tower_team_slots where user_id = v_user and (slot = p_slot or hero_id = p_hero_id);
  insert into public.tower_team_slots(user_id, slot, hero_id) values (v_user, p_slot, p_hero_id);
  return public.get_tower_dashboard(p_telegram_id);
end $$;

CREATE OR REPLACE FUNCTION public.remove_tower_team_slot(p_telegram_id bigint, p_slot int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare v_user uuid;
begin
  select id into v_user from public.game_players where telegram_id = p_telegram_id;
  if v_user is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  delete from public.tower_team_slots where user_id = v_user and slot = p_slot;
  return public.get_tower_dashboard(p_telegram_id);
end $$;

-- ---------- Progress (always starts at floor 1) ----------
CREATE OR REPLACE FUNCTION public.tower_ensure_progress(p_user uuid)
RETURNS public.tower_progress LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare p public.tower_progress; v_today date := (now() at time zone 'utc')::date;
begin
  insert into public.tower_progress(user_id) values (p_user) on conflict (user_id) do nothing;
  select * into p from public.tower_progress where user_id = p_user;
  if p.attempts_date <> v_today then
    update public.tower_progress set attempts_used = 0, attempts_date = v_today, updated_at = now() where user_id = p_user;
    select * into p from public.tower_progress where user_id = p_user;
  end if;
  return p;
end $$;

-- ---------- Rewards ----------
CREATE OR REPLACE FUNCTION public.tower_floor_rewards(p_floor int, p_first boolean)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  select jsonb_build_object(
    'fragments', greatest(1, floor((6 + p_floor * 0.9) * (case when p_first then 1 else 0.5 end))::int),
    'heroXp',    greatest(10, floor((120 + p_floor * 45) * (case when p_first then 1 else 0.5 end))::int),
    'petFood',   case when p_first and p_floor % 5 = 0 then 10 when p_first then 3 else 1 end,
    'heroChest', case when p_first and p_floor % 5 = 0 then 1 else 0 end,
    'towerKey',  case when p_first and p_floor % 10 = 0 then 1 else 0 end
  );
$$;

CREATE OR REPLACE FUNCTION public.tower_grant_rewards(p_user uuid, p_floor int, p_first boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare r jsonb := public.tower_floor_rewards(p_floor, p_first); v_food text;
begin
  if (r->>'fragments')::int > 0 then
    insert into public.player_inventory(user_id,item_type,item_code,quantity)
    values (p_user,'fragments','fragments',(r->>'fragments')::int)
    on conflict (user_id,item_type,item_code) do update set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;
  if (r->>'heroChest')::int > 0 then
    insert into public.player_inventory(user_id,item_type,item_code,quantity)
    values (p_user,'hero_chest','common_chest',(r->>'heroChest')::int)
    on conflict (user_id,item_type,item_code) do update set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;
  if (r->>'towerKey')::int > 0 then
    insert into public.player_inventory(user_id,item_type,item_code,quantity)
    values (p_user,'tower_key','eternity_key',(r->>'towerKey')::int)
    on conflict (user_id,item_type,item_code) do update set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;
  if (r->>'petFood')::int > 0 then
    select code into v_food from public.pet_food_items order by coalesce(nullif(code,''),'') limit 1;
    if v_food is not null then
      insert into public.player_pet_food(user_id,food_code,quantity)
      values (p_user,v_food,(r->>'petFood')::int)
      on conflict (user_id,food_code) do update set quantity = public.player_pet_food.quantity + excluded.quantity, updated_at = now();
    end if;
  end if;
  return r;
end $$;

-- ---------- Turn-based simulation: 5 heroes vs 1 tower boss ----------
CREATE OR REPLACE FUNCTION public.simulate_tower_battle(a jsonb, b jsonb, seed text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare
  n int; i int; k int; rnd int := 0; turn int := 0; log jsonb := '[]'::jsonb;
  ids text[] := '{}'; hp numeric[] := '{}'; maxhp numeric[] := '{}'; atk numeric[] := '{}';
  hdef numeric[] := '{}'; spd numeric[] := '{}'; frozen int[] := '{}'; poison int[] := '{}';
  boss_hp numeric; boss_max numeric; boss_atk numeric; boss_def numeric; behavior text;
  dmg numeric; red numeric; var numeric; debuff numeric := 1; winner text := null;
  alive int; tgt int; heal numeric; strike numeric; targets int; ast jsonb;
begin
  select array_agg(x->>'heroId' order by coalesce((x->>'speed')::numeric,0) desc, x->>'heroId'),
         array_agg(greatest(1,(x->>'finalHp')::numeric) order by coalesce((x->>'speed')::numeric,0) desc, x->>'heroId'),
         array_agg(greatest(1,(x->>'finalHp')::numeric) order by coalesce((x->>'speed')::numeric,0) desc, x->>'heroId'),
         array_agg(greatest(1,(x->>'finalAtk')::numeric) order by coalesce((x->>'speed')::numeric,0) desc, x->>'heroId'),
         array_agg(coalesce((x->>'defense')::numeric,0) order by coalesce((x->>'speed')::numeric,0) desc, x->>'heroId'),
         array_agg(coalesce((x->>'speed')::numeric,0) order by coalesce((x->>'speed')::numeric,0) desc, x->>'heroId')
    into ids, hp, maxhp, atk, hdef, spd
    from jsonb_array_elements(a) x;
  n := coalesce(array_length(ids,1),0);
  if n = 0 then
    return jsonb_build_object('battleLog','[]'::jsonb,'attackerState','[]'::jsonb,
      'defenderState', jsonb_build_array(b || jsonb_build_object('currentHp',(b->>'finalHp')::numeric)),
      'winnerSide','defender','totalTurns',1);
  end if;
  frozen := array_fill(0, array[n]); poison := array_fill(0, array[n]);

  boss_max := greatest(1,(b->>'finalHp')::numeric); boss_hp := boss_max;
  boss_atk := greatest(1,(b->>'finalAtk')::numeric); boss_def := coalesce((b->>'defense')::numeric,0);
  behavior := coalesce(b->>'behavior','heavy');

  <<battle>>
  loop
    rnd := rnd + 1;
    if rnd > 400 then exit; end if;

    -- heroes act, fastest first
    for i in 1..n loop
      if hp[i] <= 0 then continue; end if;
      if frozen[i] > 0 then frozen[i] := frozen[i] - 1; continue; end if;
      turn := turn + 1;
      red := boss_def / (boss_def + 900);
      var := 0.94 + public.pvp_stat_unit(seed||':'||turn||':h')*0.12;
      dmg := greatest(1, round(atk[i] * (1 - red) * var));
      boss_hp := greatest(0, boss_hp - dmg);
      log := log || jsonb_build_array(jsonb_build_object('turn',turn,'side','attacker','attackerId',ids[i],
        'targetId','tower-boss','damage',dmg::int,'remainingHp',boss_hp::int));
      if boss_hp <= 0 then winner := 'attacker'; exit battle; end if;
    end loop;

    -- damage over time on heroes
    for i in 1..n loop
      if hp[i] > 0 and poison[i] > 0 then
        poison[i] := poison[i] - 1;
        turn := turn + 1;
        dmg := greatest(1, round(boss_atk * 0.12));
        hp[i] := greatest(0, hp[i] - dmg);
        log := log || jsonb_build_array(jsonb_build_object('turn',turn,'side','defender','attackerId','tower-boss',
          'targetId',ids[i],'damage',dmg::int,'remainingHp',hp[i]::int,'skill','dot'));
      end if;
    end loop;

    select count(*) into alive from generate_subscripts(hp,1) s where hp[s] > 0;
    if alive = 0 then winner := 'defender'; exit battle; end if;

    -- boss AI (one behavior per boss)
    strike := 1.0; targets := 1;
    if behavior = 'dragon' and rnd % 2 = 0 then targets := n; strike := 0.75;
    elsif behavior = 'burn' and rnd % 3 = 0 then targets := n; strike := 0.7;
    elsif behavior = 'poison' then targets := 2; strike := 0.85;
    elsif behavior = 'execute' then targets := 2; strike := 0.95;
    elsif behavior = 'crush' then strike := 1.6;
    elsif behavior = 'stun' then strike := 1.5;
    elsif behavior = 'freeze' then strike := 1.2;
    elsif behavior = 'curse' then strike := 1.15;
    elsif behavior = 'regen' then strike := 1.25;
    else strike := 1.3;
    end if;

    if behavior = 'regen' and rnd % 3 = 0 then
      heal := round(boss_max * 0.05);
      boss_hp := least(boss_max, boss_hp + heal);
      log := log || jsonb_build_array(jsonb_build_object('turn',turn,'side','defender','attackerId','tower-boss',
        'targetId','tower-boss','damage',0,'remainingHp',boss_hp::int,'skill','regen','heal',heal::int));
    end if;

    for k in 1..targets loop
      -- target selection: executioners hunt the weakest, others pick semi-randomly
      if behavior in ('execute','crush') then
        select s into tgt from generate_subscripts(hp,1) s where hp[s] > 0 order by hp[s]/greatest(1,maxhp[s]) limit 1;
      else
        select s into tgt from generate_subscripts(hp,1) s where hp[s] > 0
          order by (case when k = 1 then 0 else 1 end), abs(hashtextextended(seed||rnd::text||k::text||s::text,0)) limit 1;
      end if;
      if tgt is null then exit; end if;
      turn := turn + 1;
      red := hdef[tgt] / (hdef[tgt] + 900);
      var := 0.95 + public.pvp_stat_unit(seed||':'||turn||':b')*0.10;
      dmg := greatest(1, round(boss_atk * strike * debuff * (1 - red) * var));
      hp[tgt] := greatest(0, hp[tgt] - dmg);
      log := log || jsonb_build_array(jsonb_build_object('turn',turn,'side','defender','attackerId','tower-boss',
        'targetId',ids[tgt],'damage',dmg::int,'remainingHp',hp[tgt]::int,'skill',behavior));
      if behavior = 'freeze' and hp[tgt] > 0 and rnd % 2 = 0 then frozen[tgt] := 1; end if;
      if behavior = 'stun' and hp[tgt] > 0 and public.pvp_stat_unit(seed||':'||turn||':stun') < 0.35 then frozen[tgt] := 1; end if;
      if behavior = 'poison' and hp[tgt] > 0 then poison[tgt] := 3; end if;
      if behavior = 'burn' and hp[tgt] > 0 then poison[tgt] := 2; end if;
    end loop;

    if behavior = 'curse' then debuff := least(1.6, debuff * 1.04); end if;

    select count(*) into alive from generate_subscripts(hp,1) s where hp[s] > 0;
    if alive = 0 then winner := 'defender'; exit battle; end if;
  end loop;

  if winner is null then winner := case when boss_hp <= 0 then 'attacker' else 'defender' end; end if;

  select coalesce(jsonb_agg(x || jsonb_build_object('currentHp',
      coalesce((select hp[s] from generate_subscripts(ids,1) s where ids[s] = x->>'heroId'), (x->>'finalHp')::numeric)::int)),'[]'::jsonb)
    into ast from jsonb_array_elements(a) x;

  return jsonb_build_object('battleLog',log,'attackerState',ast,
    'defenderState', jsonb_build_array(b || jsonb_build_object('currentHp',boss_hp::int)),
    'winnerSide',winner,'totalTurns',greatest(1,turn));
end $$;

-- ---------- Dashboard ----------
CREATE OR REPLACE FUNCTION public.get_tower_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare pl public.game_players; p public.tower_progress; v_limit int; v_boss jsonb; v_team jsonb; v_hist jsonb;
begin
  select * into pl from public.game_players where telegram_id = p_telegram_id;
  if pl.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  p := public.tower_ensure_progress(pl.id);
  v_limit := greatest(1, public.setting_num('tower_daily_attempts', 5)::int);
  v_boss := public.tower_boss_for_floor(p.current_floor);
  v_team := public.tower_team_json(pl.id);
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'floor',r.floor,'bossKey',r.boss_key,'result',r.result,
      'turns',r.turns,'rewards',r.rewards,'createdAt',r.created_at) order by r.created_at desc),'[]'::jsonb)
    into v_hist from (select * from public.tower_runs where user_id = pl.id order by created_at desc limit 10) r;
  return jsonb_build_object(
    'floor', p.current_floor, 'totalFloors', 100, 'highestFloor', p.highest_floor,
    'attemptsUsed', p.attempts_used, 'attemptsLimit', v_limit,
    'attemptsRemaining', greatest(0, v_limit - p.attempts_used),
    'entryCost', public.tower_entry_cost(p.current_floor),
    'balanceFc', round(coalesce(pl.forge_coins,0)),
    'boss', v_boss,
    'firstClear', p.current_floor > p.highest_floor,
    'rewards', public.tower_floor_rewards(p.current_floor, p.current_floor > p.highest_floor),
    'replayRewards', public.tower_floor_rewards(p.current_floor, false),
    'team', v_team,
    'teamPower', (select coalesce(sum((x->>'power')::numeric),0)::bigint from jsonb_array_elements(v_team) x),
    'history', v_hist
  );
end $$;

-- ---------- Enter the dungeon (atomic: cost, attempt, battle, rewards, progress) ----------
CREATE OR REPLACE FUNCTION public.tower_enter_floor(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare pl public.game_players; p public.tower_progress; v_limit int; v_cost numeric; v_floor int;
  v_boss jsonb; v_team jsonb; sim jsonb; v_win boolean; v_first boolean; v_rewards jsonb := '{}'::jsonb;
  v_buffs jsonb; seed text;
begin
  select * into pl from public.game_players where telegram_id = p_telegram_id for update;
  if pl.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if pl.banned then raise exception 'PLAYER_BANNED'; end if;
  p := public.tower_ensure_progress(pl.id);
  v_limit := greatest(1, public.setting_num('tower_daily_attempts', 5)::int);
  if p.attempts_used >= v_limit then raise exception 'TOWER_NO_ATTEMPTS'; end if;

  v_floor := p.current_floor;
  v_cost := public.tower_entry_cost(v_floor);
  if coalesce(pl.forge_coins,0) < v_cost then raise exception 'INSUFFICIENT_FC'; end if;

  v_team := public.tower_team_json(pl.id);
  if jsonb_array_length(v_team) = 0 then raise exception 'TOWER_TEAM_EMPTY'; end if;
  if (select count(distinct public.pvp_hero_template_key(h)) from public.tower_team_slots s
        join public.player_heroes h on h.id = s.hero_id where s.user_id = pl.id) <> jsonb_array_length(v_team)
  then raise exception 'TOWER_DUPLICATE_HERO_TEAM'; end if;

  -- only the ACTIVE pet grants bonuses, resolved server-side
  v_buffs := coalesce(public.get_pet_bonuses(pl.id), '{}'::jsonb);
  v_team := public.pvp_apply_pet_modifiers(v_team, v_buffs);

  v_boss := public.tower_boss_for_floor(v_floor);
  seed := gen_random_uuid()::text;
  sim := public.simulate_tower_battle(v_team, v_boss, seed);
  v_win := (sim->>'winnerSide') = 'attacker';
  v_first := v_floor > p.highest_floor;

  update public.game_players set forge_coins = greatest(0, coalesce(forge_coins,0) - v_cost), updated_at = now()
    where id = pl.id;
  update public.tower_progress set attempts_used = attempts_used + 1, updated_at = now() where user_id = pl.id;

  if v_win then
    v_rewards := public.tower_grant_rewards(pl.id, v_floor, v_first);
    update public.tower_progress
      set highest_floor = greatest(highest_floor, v_floor),
          current_floor = least(100, v_floor + 1),
          updated_at = now()
      where user_id = pl.id;
  end if;

  insert into public.tower_runs(user_id,floor,boss_key,result,turns,cost_fc,first_clear,rewards)
  values (pl.id, v_floor, v_boss->>'bossKey', case when v_win then 'win' else 'loss' end,
          greatest(1,(sim->>'totalTurns')::int), v_cost, v_win and v_first, v_rewards);

  return jsonb_build_object(
    'result', case when v_win then 'win' else 'loss' end,
    'floor', v_floor, 'boss', v_boss, 'costFc', v_cost,
    'firstClear', v_win and v_first,
    'rewards', v_rewards,
    'totalTurns', greatest(1,(sim->>'totalTurns')::int),
    'battleLog', sim->'battleLog',
    'attackerState', sim->'attackerState',
    'defenderState', sim->'defenderState',
    'team', v_team,
    'dashboard', public.get_tower_dashboard(p_telegram_id)
  );
end $$;

REVOKE ALL ON FUNCTION public.get_tower_dashboard(bigint) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.tower_enter_floor(bigint) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.save_tower_team_slot(bigint,int,uuid) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.remove_tower_team_slot(bigint,int) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.tower_grant_rewards(uuid,int,boolean) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.simulate_tower_battle(jsonb,jsonb,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.tower_ensure_progress(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_tower_dashboard(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.tower_enter_floor(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.save_tower_team_slot(bigint,int,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.remove_tower_team_slot(bigint,int) TO service_role;