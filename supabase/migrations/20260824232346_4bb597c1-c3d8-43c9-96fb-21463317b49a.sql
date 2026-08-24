-- ============ FAMILIAR HUNT: new pet combat mode (does NOT touch pet_expeditions) ============
CREATE TABLE IF NOT EXISTS public.familiar_hunt_missions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  theme text NOT NULL,
  rarity text NOT NULL DEFAULT 'common',
  description text,
  background text,
  sort_order int NOT NULL DEFAULT 0,
  enabled boolean NOT NULL DEFAULT true,
  recommended_power int NOT NULL DEFAULT 1000,
  max_runs_per_day int NOT NULL DEFAULT 5,
  enemies jsonb NOT NULL DEFAULT '[]'::jsonb,
  reward_pool jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.familiar_hunt_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  mission_id uuid NOT NULL REFERENCES public.familiar_hunt_missions(id) ON DELETE CASCADE,
  pet_ids uuid[] NOT NULL,
  team_power int NOT NULL DEFAULT 0,
  victory boolean NOT NULL DEFAULT false,
  rounds int NOT NULL DEFAULT 0,
  total_damage numeric NOT NULL DEFAULT 0,
  rewards jsonb NOT NULL DEFAULT '[]'::jsonb,
  battle_log jsonb NOT NULL DEFAULT '[]'::jsonb,
  game_day date NOT NULL DEFAULT public.game_day_key(),
  idempotency_key text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS familiar_hunt_runs_idem ON public.familiar_hunt_runs(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS familiar_hunt_runs_user_day ON public.familiar_hunt_runs(user_id, game_day);

GRANT ALL ON public.familiar_hunt_missions TO service_role;
GRANT ALL ON public.familiar_hunt_runs TO service_role;
ALTER TABLE public.familiar_hunt_missions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.familiar_hunt_runs ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS familiar_hunt_missions_touch ON public.familiar_hunt_missions;
CREATE TRIGGER familiar_hunt_missions_touch BEFORE UPDATE ON public.familiar_hunt_missions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ---------- seed missions ----------
INSERT INTO public.familiar_hunt_missions (code, name, theme, rarity, description, background, sort_order, recommended_power, max_runs_per_day, enemies, reward_pool) VALUES
('fh_forest','Clareira Corrompida','forest','common','Bestas da floresta tomadas por raízes malditas.','/assets/game/familiar-hunt/hunt-arena.jpg',1,1200,5,
 '[{"name":"Bruto da Ramagem","image":"/assets/game/familiar-hunt/monster-forest.png","hpRatio":1.2,"atkRatio":0.30},
   {"name":"Espreitador Musgoso","image":"/assets/game/familiar-hunt/monster-forest.png","hpRatio":1.0,"atkRatio":0.26},
   {"name":"Presa de Vinha","image":"/assets/game/familiar-hunt/monster-forest.png","hpRatio":1.0,"atkRatio":0.26}]'::jsonb,
 '[{"type":"pet_food","code":"pet_ration","min":2,"max":4,"chance":100},
   {"type":"fc","min":9000,"max":16000,"chance":100},
   {"type":"universal_fragment","min":1,"max":2,"chance":45},
   {"type":"pvp_ticket","min":1,"max":1,"chance":20}]'::jsonb),
('fh_cave','Fenda de Cristal','cave','uncommon','Colossos de pedra guardam veios de cristal vivo.','/assets/game/familiar-hunt/hunt-arena.jpg',2,2600,5,
 '[{"name":"Golem Cavernoso","image":"/assets/game/familiar-hunt/monster-cave.png","hpRatio":1.6,"atkRatio":0.32},
   {"name":"Bruto de Cristal","image":"/assets/game/familiar-hunt/monster-cave.png","hpRatio":1.2,"atkRatio":0.28},
   {"name":"Lasca Viva","image":"/assets/game/familiar-hunt/monster-cave.png","hpRatio":1.0,"atkRatio":0.26}]'::jsonb,
 '[{"type":"pet_food","code":"pet_ration","min":3,"max":6,"chance":100},
   {"type":"fc","min":18000,"max":32000,"chance":100},
   {"type":"universal_fragment","min":1,"max":3,"chance":60},
   {"type":"pvp_ticket","min":1,"max":2,"chance":30}]'::jsonb),
('fh_shadow','Véu das Sombras','shadow','rare','Criaturas de fumaça negra devoram a luz.','/assets/game/familiar-hunt/hunt-arena.jpg',3,5200,4,
 '[{"name":"Espectro do Véu","image":"/assets/game/familiar-hunt/monster-shadow.png","hpRatio":1.4,"atkRatio":0.36},
   {"name":"Ceifador Umbral","image":"/assets/game/familiar-hunt/monster-shadow.png","hpRatio":1.3,"atkRatio":0.34},
   {"name":"Sussurro Negro","image":"/assets/game/familiar-hunt/monster-shadow.png","hpRatio":1.1,"atkRatio":0.30}]'::jsonb,
 '[{"type":"pet_food","code":"pet_ration","min":4,"max":8,"chance":100},
   {"type":"fc","min":40000,"max":70000,"chance":100},
   {"type":"universal_fragment","min":2,"max":4,"chance":70},
   {"type":"pvp_ticket","min":1,"max":2,"chance":40},
   {"type":"equipment","rarity":"rare","min":1,"max":1,"chance":8}]'::jsonb),
('fh_fire','Cova Incandescente','fire','epic','Feras de lava fervem o ar da cova.','/assets/game/familiar-hunt/hunt-arena.jpg',4,9000,4,
 '[{"name":"Sabujo de Magma","image":"/assets/game/familiar-hunt/monster-fire.png","hpRatio":1.6,"atkRatio":0.40},
   {"name":"Cinza Ardente","image":"/assets/game/familiar-hunt/monster-fire.png","hpRatio":1.3,"atkRatio":0.36},
   {"name":"Chama Obsidiana","image":"/assets/game/familiar-hunt/monster-fire.png","hpRatio":1.3,"atkRatio":0.34}]'::jsonb,
 '[{"type":"pet_food","code":"pet_ration","min":6,"max":10,"chance":100},
   {"type":"fc","min":70000,"max":120000,"chance":100},
   {"type":"universal_fragment","min":3,"max":6,"chance":75},
   {"type":"pvp_ticket","min":1,"max":3,"chance":50},
   {"type":"equipment","rarity":"epic","min":1,"max":1,"chance":6}]'::jsonb),
('fh_frost','Trono Congelado','frost','epic','Golens de gelo protegem o trono eterno.','/assets/game/familiar-hunt/hunt-arena.jpg',5,14000,3,
 '[{"name":"Golem Glacial","image":"/assets/game/familiar-hunt/monster-frost.png","hpRatio":1.9,"atkRatio":0.40},
   {"name":"Garra de Gelo","image":"/assets/game/familiar-hunt/monster-frost.png","hpRatio":1.4,"atkRatio":0.38},
   {"name":"Eco Congelado","image":"/assets/game/familiar-hunt/monster-frost.png","hpRatio":1.4,"atkRatio":0.34}]'::jsonb,
 '[{"type":"pet_food","code":"pet_ration","min":8,"max":14,"chance":100},
   {"type":"fc","min":120000,"max":190000,"chance":100},
   {"type":"universal_fragment","min":4,"max":8,"chance":80},
   {"type":"pvp_ticket","min":2,"max":4,"chance":55},
   {"type":"equipment","rarity":"epic","min":1,"max":1,"chance":8}]'::jsonb),
('fh_elite','Caça ao Chefe de Elite','elite','legendary','Um senhor demoníaco aguarda apenas equipes de elite.','/assets/game/familiar-hunt/hunt-arena.jpg',6,24000,2,
 '[{"name":"Senhor da Guerra Demoníaco","image":"/assets/game/familiar-hunt/monster-elite.png","hpRatio":5.5,"atkRatio":0.95,"elite":true}]'::jsonb,
 '[{"type":"pet_food","code":"pet_ration","min":12,"max":20,"chance":100},
   {"type":"fc","min":220000,"max":380000,"chance":100},
   {"type":"universal_fragment","min":6,"max":12,"chance":90},
   {"type":"pvp_ticket","min":3,"max":6,"chance":70},
   {"type":"equipment","rarity":"legendary","min":1,"max":1,"chance":4}]'::jsonb)
ON CONFLICT (code) DO NOTHING;

-- ---------- state ----------
CREATE OR REPLACE FUNCTION public.familiar_hunt_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare u uuid; v_day date := public.game_day_key();
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.sub_nft_sync(u);

  return jsonb_build_object(
    'gameDay', v_day,
    'pets', coalesce((select jsonb_agg(jsonb_build_object(
        'playerPetId', pp.id, 'name', p.name,
        'image', coalesce(sn_t.image_url, p.image_adult_url, p.image_baby_url),
        'rarity', pp.rarity, 'level', pp.level,
        'power', public.pet_instance_power(pp.id),
        'isSubNft', sn.id is not null,
        'stage', sn.maturity_stage) order by public.pet_instance_power(pp.id) desc)
      from public.player_pets pp
      join public.pets p on p.id = pp.pet_id
      left join public.sub_nfts sn on sn.player_pet_id = pp.id or sn.id = pp.sub_nft_id
      left join public.sub_nft_templates sn_t on sn_t.id = sn.template_id
      where pp.user_id = u), '[]'::jsonb),
    'missions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'code', m.code, 'name', m.name, 'theme', m.theme, 'rarity', m.rarity,
        'description', m.description, 'background', m.background,
        'recommendedPower', m.recommended_power,
        'maxRunsPerDay', m.max_runs_per_day,
        'runsToday', (select count(*)::int from public.familiar_hunt_runs r
                       where r.user_id = u and r.mission_id = m.id and r.game_day = v_day),
        'enemies', (select jsonb_agg(jsonb_build_object(
              'name', e->>'name', 'image', e->>'image',
              'hp', round(m.recommended_power * coalesce((e->>'hpRatio')::numeric, 1)),
              'atk', round(m.recommended_power * coalesce((e->>'atkRatio')::numeric, 0.3)),
              'elite', coalesce((e->>'elite')::boolean, false)))
            from jsonb_array_elements(m.enemies) e),
        'rewards', m.reward_pool) order by m.sort_order)
      from public.familiar_hunt_missions m where m.enabled), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'missionName', m.name, 'victory', r.victory, 'rounds', r.rounds,
        'totalDamage', r.total_damage, 'rewards', r.rewards, 'createdAt', r.created_at)
        order by r.created_at desc)
      from (select * from public.familiar_hunt_runs where user_id = u order by created_at desc limit 10) r
      join public.familiar_hunt_missions m on m.id = r.mission_id), '[]'::jsonb));
end $$;

-- ---------- battle ----------
CREATE OR REPLACE FUNCTION public.familiar_hunt_battle(
  p_telegram_id bigint, p_mission_id uuid, p_pet_ids uuid[], p_idempotency_key text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare
  u uuid; m public.familiar_hunt_missions; prev public.familiar_hunt_runs;
  pid uuid; i int; j int; k int; rounds int := 0; dmg numeric; crit boolean;
  pet_hp numeric[] := '{}'; pet_max numeric[] := '{}'; pet_atk numeric[] := '{}';
  pet_name text[] := '{}'; pet_img text[] := '{}'; pet_pow numeric[] := '{}';
  en_hp numeric[] := '{}'; en_max numeric[] := '{}'; en_atk numeric[] := '{}';
  en_name text[] := '{}'; en_img text[] := '{}'; en_elite boolean[] := '{}';
  entry jsonb; log jsonb := '[]'::jsonb; total_dmg numeric := 0;
  team_power numeric := 0; won boolean := false; alive_pets int; alive_en int;
  target int; low numeric; qty int; out_rewards jsonb := '[]'::jsonb;
  tpl public.equipment_templates; v_food text; runs_today int; v_pow numeric;
  v_run public.familiar_hunt_runs;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  if p_idempotency_key is not null then
    select * into prev from public.familiar_hunt_runs where user_id = u and idempotency_key = p_idempotency_key;
    if prev.id is not null then
      return jsonb_build_object('ok', true, 'replay', true, 'runId', prev.id, 'victory', prev.victory,
        'rounds', prev.rounds, 'totalDamage', prev.total_damage, 'rewards', prev.rewards, 'log', prev.battle_log);
    end if;
  end if;

  select * into m from public.familiar_hunt_missions where id = p_mission_id and enabled;
  if m.id is null then raise exception 'MISSION_NOT_FOUND'; end if;
  if array_length(p_pet_ids, 1) is distinct from 3 then raise exception 'TEAM_MUST_HAVE_3_PETS'; end if;
  if (select count(distinct x) from unnest(p_pet_ids) x) <> 3 then raise exception 'DUPLICATED_PET'; end if;

  select count(*)::int into runs_today from public.familiar_hunt_runs
   where user_id = u and mission_id = m.id and game_day = public.game_day_key();
  if runs_today >= m.max_runs_per_day then raise exception 'HUNT_DAILY_LIMIT'; end if;

  -- team
  foreach pid in array p_pet_ids loop
    if not exists (select 1 from public.player_pets where id = pid and user_id = u) then raise exception 'PET_NOT_YOURS'; end if;
    v_pow := greatest(1, coalesce(public.pet_instance_power(pid), 1));
    team_power := team_power + v_pow;
    pet_pow := pet_pow || v_pow;
    pet_max := pet_max || round(v_pow * 4.5);
    pet_hp := pet_hp || round(v_pow * 4.5);
    pet_atk := pet_atk || round(v_pow * 0.25);
    select coalesce(snt.image_url, p.image_adult_url, p.image_baby_url), p.name
      into pet_img[array_length(pet_img,1)], pet_name[array_length(pet_name,1)]
      from public.player_pets pp join public.pets p on p.id = pp.pet_id
      left join public.sub_nfts sn on sn.player_pet_id = pp.id or sn.id = pp.sub_nft_id
      left join public.sub_nft_templates snt on snt.id = sn.template_id
      where pp.id = pid;
    -- the assignment above cannot extend the array: rebuild explicitly
    select pet_name || coalesce(p.name,'Pet'), pet_img || coalesce(snt.image_url, p.image_adult_url, p.image_baby_url, '')
      into pet_name, pet_img
      from public.player_pets pp join public.pets p on p.id = pp.pet_id
      left join public.sub_nfts sn on sn.player_pet_id = pp.id or sn.id = pp.sub_nft_id
      left join public.sub_nft_templates snt on snt.id = sn.template_id
      where pp.id = pid;
  end loop;

  -- enemies scaled from the mission recommended power
  for entry in select * from jsonb_array_elements(m.enemies) loop
    en_name := en_name || coalesce(entry->>'name', 'Monstro');
    en_img := en_img || coalesce(entry->>'image', '');
    en_max := en_max || round(m.recommended_power * coalesce((entry->>'hpRatio')::numeric, 1) * 4.5);
    en_hp := en_hp || round(m.recommended_power * coalesce((entry->>'hpRatio')::numeric, 1) * 4.5);
    en_atk := en_atk || round(m.recommended_power * coalesce((entry->>'atkRatio')::numeric, 0.3));
    en_elite := en_elite || coalesce((entry->>'elite')::boolean, false);
  end loop;
  if coalesce(array_length(en_hp,1),0) = 0 then raise exception 'MISSION_NOT_FOUND'; end if;

  -- turn based simulation (max 40 rounds)
  while rounds < 40 loop
    rounds := rounds + 1;
    -- pets strike the weakest living enemy
    for i in 1 .. array_length(pet_hp,1) loop
      if pet_hp[i] <= 0 then continue; end if;
      target := null; low := null;
      for j in 1 .. array_length(en_hp,1) loop
        if en_hp[j] > 0 and (low is null or en_hp[j] < low) then low := en_hp[j]; target := j; end if;
      end loop;
      exit when target is null;
      crit := random() < 0.18;
      dmg := round(pet_atk[i] * (0.85 + random() * 0.3) * (case when crit then 1.9 else 1 end));
      dmg := greatest(1, dmg);
      en_hp[target] := greatest(0, en_hp[target] - dmg);
      total_dmg := total_dmg + dmg;
      log := log || jsonb_build_array(jsonb_build_object('round', rounds, 'side', 'pet', 'actor', i - 1,
        'target', target - 1, 'damage', dmg, 'crit', crit, 'ko', en_hp[target] <= 0,
        'targetHp', en_hp[target], 'targetMax', en_max[target]));
    end loop;

    alive_en := 0;
    for j in 1 .. array_length(en_hp,1) loop if en_hp[j] > 0 then alive_en := alive_en + 1; end if; end loop;
    if alive_en = 0 then won := true; exit; end if;

    -- enemies strike a random living pet
    for j in 1 .. array_length(en_hp,1) loop
      if en_hp[j] <= 0 then continue; end if;
      target := null;
      for k in 1 .. array_length(pet_hp,1) loop
        if pet_hp[k] > 0 and (target is null or random() < 0.5) then target := k; end if;
      end loop;
      exit when target is null;
      crit := random() < 0.10;
      dmg := greatest(1, round(en_atk[j] * (0.85 + random() * 0.3) * (case when crit then 1.7 else 1 end)));
      pet_hp[target] := greatest(0, pet_hp[target] - dmg);
      log := log || jsonb_build_array(jsonb_build_object('round', rounds, 'side', 'enemy', 'actor', j - 1,
        'target', target - 1, 'damage', dmg, 'crit', crit, 'ko', pet_hp[target] <= 0,
        'targetHp', pet_hp[target], 'targetMax', pet_max[target]));
    end loop;

    alive_pets := 0;
    for k in 1 .. array_length(pet_hp,1) loop if pet_hp[k] > 0 then alive_pets := alive_pets + 1; end if; end loop;
    exit when alive_pets = 0;
  end loop;

  -- rewards only on victory
  if won then
    for entry in select * from jsonb_array_elements(m.reward_pool) loop
      if (random() * 100) > coalesce((entry->>'chance')::numeric, 100) then continue; end if;
      qty := floor(random() * (coalesce((entry->>'max')::int,1) - coalesce((entry->>'min')::int,1) + 1))::int + coalesce((entry->>'min')::int,1);
      if qty <= 0 then continue; end if;
      case entry->>'type'
        when 'pet_food' then
          select f.code into v_food from public.pet_food_items f where f.code = nullif(entry->>'code','');
          if v_food is null then select f.code into v_food from public.pet_food_items f where f.code = 'pet_ration'; end if;
          if v_food is null then select f.code into v_food from public.pet_food_items f order by coalesce(f.xp_value,0) asc limit 1; end if;
          if v_food is not null then
            insert into public.player_pet_food(user_id, food_code, quantity) values (u, v_food, qty)
            on conflict (user_id, food_code) do update set quantity = public.player_pet_food.quantity + excluded.quantity, updated_at = now();
          end if;
        when 'universal_fragment' then perform public.add_universal_fragments(u, qty);
        when 'fc' then update public.game_players set forge_coins = coalesce(forge_coins,0) + qty, updated_at = now() where id = u;
        when 'pvp_ticket' then update public.game_players set pvp_tickets = coalesce(pvp_tickets,0) + qty, updated_at = now() where id = u;
        when 'equipment' then
          select * into tpl from public.equipment_templates
            where is_active and rarity = coalesce(entry->>'rarity','rare') order by random() limit 1;
          if tpl.id is not null then
            insert into public.player_equipment(user_id, template_id, source, source_ref) values (u, tpl.id, 'familiar_hunt', null);
          end if;
        else null;
      end case;
      out_rewards := out_rewards || jsonb_build_array(jsonb_build_object('type', entry->>'type',
        'code', coalesce(nullif(entry->>'code',''), entry->>'rarity', ''), 'quantity', qty));
    end loop;
  end if;

  insert into public.familiar_hunt_runs(user_id, mission_id, pet_ids, team_power, victory, rounds,
                                       total_damage, rewards, battle_log, idempotency_key)
  values (u, m.id, p_pet_ids, round(team_power)::int, won, rounds, total_dmg, out_rewards, log, p_idempotency_key)
  returning * into v_run;

  return jsonb_build_object('ok', true, 'runId', v_run.id, 'victory', won, 'rounds', rounds,
    'teamPower', round(team_power)::int, 'totalDamage', total_dmg, 'rewards', out_rewards, 'log', log,
    'team', (select jsonb_agg(jsonb_build_object('name', pet_name[x], 'image', pet_img[x],
              'maxHp', pet_max[x], 'hp', pet_hp[x], 'atk', pet_atk[x], 'power', pet_pow[x]))
             from generate_subscripts(pet_hp, 1) x),
    'enemies', (select jsonb_agg(jsonb_build_object('name', en_name[y], 'image', en_img[y],
              'maxHp', en_max[y], 'hp', en_hp[y], 'atk', en_atk[y], 'elite', en_elite[y]))
             from generate_subscripts(en_hp, 1) y),
    'runsToday', runs_today + 1, 'maxRunsPerDay', m.max_runs_per_day);
end $$;

REVOKE ALL ON FUNCTION public.familiar_hunt_state(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.familiar_hunt_state(bigint) TO service_role;
REVOKE ALL ON FUNCTION public.familiar_hunt_battle(bigint, uuid, uuid[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.familiar_hunt_battle(bigint, uuid, uuid[], text) TO service_role;