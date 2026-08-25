-- ════════════════════════════════════════════════════════════════════════════
-- FAMILIAR HUNT V2 · LINEAR STAGE PROGRESSION + FC/TON ENTRY + SERVER LOOT
-- (does NOT touch pet_expeditions)
-- ════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.familiar_hunt_settings (
  id boolean PRIMARY KEY DEFAULT true,
  enabled boolean NOT NULL DEFAULT true,
  entry_fc bigint NOT NULL DEFAULT 100000,
  entry_ton numeric(12,4) NOT NULL DEFAULT 5,
  loot_table_version int NOT NULL DEFAULT 1,
  difficulty jsonb NOT NULL DEFAULT '{}'::jsonb,
  stage_pool jsonb NOT NULL DEFAULT '[]'::jsonb,
  fc_loot jsonb NOT NULL DEFAULT '[]'::jsonb,
  ton_loot jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT familiar_hunt_settings_singleton CHECK (id)
);
GRANT ALL ON public.familiar_hunt_settings TO service_role;
ALTER TABLE public.familiar_hunt_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.familiar_hunt_progress (
  user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
  current_familiar_hunt_stage int NOT NULL DEFAULT 1,
  highest_stage_completed int NOT NULL DEFAULT 0,
  total_runs int NOT NULL DEFAULT 0,
  total_wins int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.familiar_hunt_progress TO service_role;
ALTER TABLE public.familiar_hunt_progress ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.familiar_hunt_instances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  stage int NOT NULL,
  stage_name text,
  is_boss boolean NOT NULL DEFAULT false,
  payment_currency text NOT NULL,               -- fc | ton_internal | ton_external
  payment_amount numeric(20,6) NOT NULL DEFAULT 0,
  payment_amount_nano bigint NOT NULL DEFAULT 0,
  loot_table_version int NOT NULL DEFAULT 1,
  loot_pool text NOT NULL DEFAULT 'fc',         -- fc | ton
  team_snapshot jsonb NOT NULL DEFAULT '[]'::jsonb,
  team_power numeric NOT NULL DEFAULT 0,
  recommended_power numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending_payment', -- pending_payment | paid_pending_hunt | settled | expired
  payment_comment text UNIQUE,
  payment_address text,
  tx_hash text,
  received_amount_nano bigint,
  victory boolean,
  rounds int,
  total_damage numeric,
  rewards jsonb NOT NULL DEFAULT '[]'::jsonb,
  result_json jsonb,
  idempotency_key text,
  settled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.familiar_hunt_instances TO service_role;
ALTER TABLE public.familiar_hunt_instances ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS familiar_hunt_instances_idem
  ON public.familiar_hunt_instances(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS familiar_hunt_instances_user ON public.familiar_hunt_instances(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS familiar_hunt_instances_status ON public.familiar_hunt_instances(status);

DROP TRIGGER IF EXISTS familiar_hunt_settings_touch ON public.familiar_hunt_settings;
CREATE TRIGGER familiar_hunt_settings_touch BEFORE UPDATE ON public.familiar_hunt_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS familiar_hunt_progress_touch ON public.familiar_hunt_progress;
CREATE TRIGGER familiar_hunt_progress_touch BEFORE UPDATE ON public.familiar_hunt_progress
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS familiar_hunt_instances_touch ON public.familiar_hunt_instances;
CREATE TRIGGER familiar_hunt_instances_touch BEFORE UPDATE ON public.familiar_hunt_instances
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ── seed configuration ─────────────────────────────────────────────────────
INSERT INTO public.familiar_hunt_settings (id, enabled, entry_fc, entry_ton, loot_table_version, difficulty, stage_pool, fc_loot, ton_loot)
VALUES (true, true, 100000, 5, 1,
'{"basePower":1200,"growth":1.16,"bossEvery":5,"bossPowerMultiplier":1.35,"enemyHpFactor":4.5,
  "minionHpRatios":[1.2,1.0,1.0],"minionAtkRatios":[0.30,0.26,0.26],
  "bossHpRatio":4.4,"bossAtkRatio":0.82,"defPerStage":0.004,"defCap":0.32,
  "bossLootBonusWeight":1.5}'::jsonb,
'[{"theme":"forest","art":"/assets/game/familiar-hunt/monster-forest.png","arena":"/assets/game/familiar-hunt/hunt-arena.jpg","minions":["Bruto da Ramagem","Espreitador Musgoso","Presa de Vinha"],"boss":"Guardião da Ramagem"},
  {"theme":"cave","art":"/assets/game/familiar-hunt/monster-cave.png","arena":"/assets/game/familiar-hunt/hunt-arena.jpg","minions":["Golem Cavernoso","Bruto de Cristal","Lasca Viva"],"boss":"Colosso de Cristal"},
  {"theme":"shadow","art":"/assets/game/familiar-hunt/monster-shadow.png","arena":"/assets/game/familiar-hunt/hunt-arena.jpg","minions":["Espectro do Véu","Ceifador Umbral","Sussurro Negro"],"boss":"Shadow Warlord"},
  {"theme":"fire","art":"/assets/game/familiar-hunt/monster-fire.png","arena":"/assets/game/familiar-hunt/hunt-arena.jpg","minions":["Sabujo de Magma","Cinza Ardente","Chama Obsidiana"],"boss":"Senhor das Brasas"},
  {"theme":"frost","art":"/assets/game/familiar-hunt/monster-frost.png","arena":"/assets/game/familiar-hunt/hunt-arena.jpg","minions":["Golem Glacial","Garra de Gelo","Eco Congelado"],"boss":"Trono Congelado"},
  {"theme":"elite","art":"/assets/game/familiar-hunt/monster-elite.png","arena":"/assets/game/familiar-hunt/hunt-arena.jpg","minions":["Carrasco Demoníaco","Lâmina Profana","Presságio Sombrio"],"boss":"Senhor da Guerra Demoníaco"}]'::jsonb,
-- ═══ FC ENTRY LOOT (never returns FC) ═══
'[{"label":"COMMON","weight":40,"options":[
    [{"type":"pet_food","code":"pet_ration","min":5,"max":10}],
    [{"type":"universal_fragment","min":10,"max":20}]]},
  {"label":"UNCOMMON","weight":30,"options":[
    [{"type":"universal_fragment","min":20,"max":35}],
    [{"type":"pvp_ticket","min":3,"max":5}]]},
  {"label":"RARE","weight":20,"options":[
    [{"type":"chest","code":"rare_chest","min":1,"max":1}],
    [{"type":"equipment","rarity":"rare","min":1,"max":1}]]},
  {"label":"EPIC","weight":9,"options":[
    [{"type":"pet_food","code":"pet_rare_food","min":4,"max":8},{"type":"universal_fragment","min":15,"max":25}],
    [{"type":"chest","code":"epic_chest","min":1,"max":1}]]},
  {"label":"JACKPOT","weight":1,"options":[
    [{"type":"equipment","rarity":"epic","min":1,"max":1}]]}]'::jsonb,
-- ═══ TON ENTRY LOOT (premium) ═══
'[{"label":"STANDARD","weight":35,"options":[
    [{"type":"fc","min":250000,"max":500000},{"type":"chest","code":"rare_chest","min":1,"max":1}]]},
  {"label":"PREMIUM","weight":25,"options":[
    [{"type":"fc","min":500000,"max":800000},{"type":"chest","code":"epic_chest","min":1,"max":1}]]},
  {"label":"EPIC","weight":20,"options":[
    [{"type":"equipment","rarity":"epic","min":1,"max":1},{"type":"universal_fragment","min":25,"max":50}]]},
  {"label":"HIGH EPIC","weight":10,"options":[
    [{"type":"equipment","rarity":"epic","min":1,"max":1},{"type":"chest","code":"epic_chest","min":1,"max":1},{"type":"universal_fragment","min":50,"max":50}]]},
  {"label":"LEGENDARY","weight":7,"options":[
    [{"type":"chest","code":"legendary_chest","min":1,"max":1}],
    [{"type":"equipment","rarity":"legendary","min":1,"max":1}]]},
  {"label":"LEGENDARY PLUS","weight":2.5,"options":[
    [{"type":"equipment","rarity":"legendary","min":1,"max":1},{"type":"chest","code":"epic_chest","min":1,"max":1},{"type":"universal_fragment","min":40,"max":80}]]},
  {"label":"JACKPOT","weight":0.5,"options":[
    [{"type":"equipment","rarity":"legendary","min":1,"max":1},{"type":"chest","code":"legendary_chest","min":1,"max":1},{"type":"fc","min":800000,"max":1200000},{"type":"universal_fragment","min":100,"max":100}]]}]'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- ── stage definition (procedural, driven by the configurable curves) ───────
CREATE OR REPLACE FUNCTION public.familiar_hunt_stage_def(p_stage int)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
declare
  s public.familiar_hunt_settings; d jsonb; pool jsonb; entry jsonb;
  v_stage int := greatest(1, coalesce(p_stage, 1));
  base numeric; growth numeric; boss_every int; boss_mult numeric;
  is_boss boolean; rec numeric; idx int; enemies jsonb := '[]'::jsonb;
  hp_factor numeric; i int; ratios jsonb; atks jsonb; nm text;
begin
  select * into s from public.familiar_hunt_settings where id;
  d := coalesce(s.difficulty, '{}'::jsonb);
  pool := coalesce(s.stage_pool, '[]'::jsonb);
  base := coalesce((d->>'basePower')::numeric, 1200);
  growth := coalesce((d->>'growth')::numeric, 1.16);
  boss_every := greatest(1, coalesce((d->>'bossEvery')::int, 5));
  boss_mult := coalesce((d->>'bossPowerMultiplier')::numeric, 1.35);
  hp_factor := coalesce((d->>'enemyHpFactor')::numeric, 4.5);
  is_boss := (v_stage % boss_every) = 0;
  rec := round(base * power(growth, v_stage - 1) * (case when is_boss then boss_mult else 1 end));

  if jsonb_array_length(pool) = 0 then
    pool := '[{"theme":"forest","art":"","arena":"","minions":["Monstro","Monstro","Monstro"],"boss":"Chefe"}]'::jsonb;
  end if;
  idx := ((v_stage - 1) / boss_every) % jsonb_array_length(pool);
  entry := pool -> idx;

  if is_boss then
    enemies := jsonb_build_array(jsonb_build_object(
      'name', coalesce(entry->>'boss', 'Chefe'),
      'image', coalesce(entry->>'art', ''),
      'hp', round(rec * coalesce((d->>'bossHpRatio')::numeric, 4.4) * hp_factor),
      'atk', round(rec * coalesce((d->>'bossAtkRatio')::numeric, 0.82)),
      'elite', true));
  else
    ratios := coalesce(d->'minionHpRatios', '[1.2,1.0,1.0]'::jsonb);
    atks := coalesce(d->'minionAtkRatios', '[0.30,0.26,0.26]'::jsonb);
    for i in 0 .. jsonb_array_length(ratios) - 1 loop
      nm := coalesce(entry->'minions'->>i, entry->'minions'->>0, 'Monstro');
      enemies := enemies || jsonb_build_array(jsonb_build_object(
        'name', nm,
        'image', coalesce(entry->>'art', ''),
        'hp', round(rec * (ratios->>i)::numeric * hp_factor),
        'atk', round(rec * coalesce((atks->>i)::numeric, 0.26)),
        'elite', false));
    end loop;
  end if;

  return jsonb_build_object(
    'stage', v_stage,
    'name', case when is_boss then coalesce(entry->>'boss','Chefe') else coalesce(entry->'minions'->>0,'Caçada') end,
    'theme', entry->>'theme',
    'background', coalesce(entry->>'arena',''),
    'isBoss', is_boss,
    'recommendedPower', rec,
    'defReduction', least(coalesce((d->>'defCap')::numeric, 0.32),
                          coalesce((d->>'defPerStage')::numeric, 0.004) * v_stage),
    'enemies', enemies);
end $$;

-- ── grant one reward line (server-side quantities only) ────────────────────
CREATE OR REPLACE FUNCTION public.familiar_hunt_grant(p_user uuid, p_reward jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare
  v_type text := lower(coalesce(p_reward->>'type',''));
  v_min numeric := coalesce((p_reward->>'min')::numeric, 1);
  v_max numeric := greatest(coalesce((p_reward->>'max')::numeric, v_min), v_min);
  qty bigint; v_code text; tpl public.equipment_templates;
begin
  qty := floor(v_min + random() * (v_max - v_min + 1))::bigint;
  if qty <= 0 then return null; end if;

  if v_type = 'fc' then
    update public.game_players set forge_coins = coalesce(forge_coins,0) + qty, updated_at = now() where id = p_user;
  elsif v_type = 'pvp_ticket' then
    update public.game_players set pvp_tickets = coalesce(pvp_tickets,0) + qty::int, updated_at = now() where id = p_user;
  elsif v_type = 'universal_fragment' then
    perform public.add_universal_fragments(p_user, qty::int);
  elsif v_type = 'pet_food' then
    select f.code into v_code from public.pet_food_items f where f.code = nullif(p_reward->>'code','');
    if v_code is null then select f.code into v_code from public.pet_food_items f where f.code = 'pet_ration'; end if;
    if v_code is null then return null; end if;
    insert into public.player_pet_food(user_id, food_code, quantity) values (p_user, v_code, qty::int)
      on conflict (user_id, food_code) do update
        set quantity = public.player_pet_food.quantity + excluded.quantity, updated_at = now();
  elsif v_type = 'chest' then
    v_code := coalesce(nullif(p_reward->>'code',''), 'rare_chest');
    insert into public.player_inventory(user_id, item_type, item_code, quantity)
      values (p_user, 'hero_chest', v_code, qty::int)
      on conflict (user_id, item_type, item_code) do update
        set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
  elsif v_type = 'equipment' then
    v_code := coalesce(nullif(p_reward->>'rarity',''), 'rare');
    select * into tpl from public.equipment_templates
      where is_active and rarity = v_code order by random() limit 1;
    if tpl.id is null then return null; end if;
    insert into public.player_equipment(user_id, template_id, source) values (p_user, tpl.id, 'familiar_hunt');
    return jsonb_build_object('type','equipment','code', tpl.name, 'rarity', v_code, 'quantity', 1);
  else
    return null;
  end if;

  return jsonb_build_object('type', v_type,
    'code', coalesce(nullif(p_reward->>'code',''), nullif(p_reward->>'rarity',''), ''),
    'rarity', p_reward->>'rarity', 'quantity', qty);
end $$;

-- ── weighted server-side loot roll ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.familiar_hunt_roll_loot(p_user uuid, p_pool text, p_is_boss boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare
  s public.familiar_hunt_settings; tiers jsonb; tier jsonb; picked jsonb;
  total numeric := 0; roll numeric; acc numeric := 0; i int; w numeric;
  opts jsonb; option jsonb; line jsonb; granted jsonb := '[]'::jsonb; boss_w numeric;
begin
  select * into s from public.familiar_hunt_settings where id;
  tiers := case when lower(coalesce(p_pool,'fc')) = 'ton' then s.ton_loot else s.fc_loot end;
  if tiers is null or jsonb_array_length(tiers) = 0 then return jsonb_build_object('tier', null, 'rewards', '[]'::jsonb); end if;
  boss_w := coalesce((s.difficulty->>'bossLootBonusWeight')::numeric, 1.5);

  -- boss stages tilt the roll toward the rarer tiers (later tiers get extra weight)
  for i in 0 .. jsonb_array_length(tiers) - 1 loop
    w := coalesce((tiers->i->>'weight')::numeric, 1);
    if p_is_boss and i >= jsonb_array_length(tiers) - 2 then w := w * boss_w; end if;
    total := total + w;
  end loop;
  roll := random() * total;
  for i in 0 .. jsonb_array_length(tiers) - 1 loop
    w := coalesce((tiers->i->>'weight')::numeric, 1);
    if p_is_boss and i >= jsonb_array_length(tiers) - 2 then w := w * boss_w; end if;
    acc := acc + w;
    if roll <= acc then tier := tiers->i; exit; end if;
  end loop;
  if tier is null then tier := tiers->0; end if;

  opts := coalesce(tier->'options', '[]'::jsonb);
  if jsonb_array_length(opts) = 0 then return jsonb_build_object('tier', tier->>'label', 'rewards', '[]'::jsonb); end if;
  option := opts -> floor(random() * jsonb_array_length(opts))::int;

  for line in select * from jsonb_array_elements(option) loop
    -- FC entry can never pay FC back
    if lower(coalesce(p_pool,'fc')) = 'fc' and lower(coalesce(line->>'type','')) = 'fc' then continue; end if;
    picked := public.familiar_hunt_grant(p_user, line);
    if picked is not null then granted := granted || jsonb_build_array(picked); end if;
  end loop;

  return jsonb_build_object('tier', tier->>'label', 'rewards', granted);
end $$;

-- ── resolve a PAID instance exactly once (battle + loot + progression) ─────
CREATE OR REPLACE FUNCTION public.familiar_hunt_resolve(p_instance_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare
  inst public.familiar_hunt_instances; def jsonb; u uuid;
  pet_hp numeric[] := '{}'; pet_max numeric[] := '{}'; pet_atk numeric[] := '{}';
  pet_name text[] := '{}'; pet_img text[] := '{}'; pet_pow numeric[] := '{}';
  en_hp numeric[] := '{}'; en_max numeric[] := '{}'; en_atk numeric[] := '{}';
  en_name text[] := '{}'; en_img text[] := '{}'; en_elite boolean[] := '{}';
  row_json jsonb; i int; j int; k int; rounds int := 0; dmg numeric; crit boolean;
  log jsonb := '[]'::jsonb; total_dmg numeric := 0; won boolean := false;
  alive_pets int; alive_en int; target int; low numeric; def_cut numeric;
  loot jsonb; result jsonb; team_power numeric := 0;
begin
  select * into inst from public.familiar_hunt_instances where id = p_instance_id for update;
  if inst.id is null then raise exception 'HUNT_NOT_FOUND'; end if;
  if inst.status = 'settled' then return inst.result_json; end if;         -- one settlement only
  if inst.status <> 'paid_pending_hunt' then raise exception 'HUNT_NOT_PAID'; end if;
  u := inst.user_id;

  def := public.familiar_hunt_stage_def(inst.stage);
  def_cut := coalesce((def->>'defReduction')::numeric, 0);

  for row_json in select * from jsonb_array_elements(inst.team_snapshot) loop
    pet_name := pet_name || coalesce(row_json->>'name','Pet');
    pet_img := pet_img || coalesce(row_json->>'image','');
    pet_pow := pet_pow || coalesce((row_json->>'power')::numeric, 1);
    pet_max := pet_max || round(coalesce((row_json->>'power')::numeric,1) * 4.5);
    pet_hp := pet_hp || round(coalesce((row_json->>'power')::numeric,1) * 4.5);
    pet_atk := pet_atk || round(coalesce((row_json->>'power')::numeric,1) * 0.25);
    team_power := team_power + coalesce((row_json->>'power')::numeric, 1);
  end loop;
  if coalesce(array_length(pet_hp,1),0) = 0 then raise exception 'TEAM_MUST_HAVE_3_PETS'; end if;

  for row_json in select * from jsonb_array_elements(def->'enemies') loop
    en_name := en_name || coalesce(row_json->>'name','Monstro');
    en_img := en_img || coalesce(row_json->>'image','');
    en_max := en_max || coalesce((row_json->>'hp')::numeric, 1);
    en_hp := en_hp || coalesce((row_json->>'hp')::numeric, 1);
    en_atk := en_atk || coalesce((row_json->>'atk')::numeric, 1);
    en_elite := en_elite || coalesce((row_json->>'elite')::boolean, false);
  end loop;

  while rounds < 40 loop
    rounds := rounds + 1;
    for i in 1 .. array_length(pet_hp,1) loop
      if pet_hp[i] <= 0 then continue; end if;
      target := null; low := null;
      for j in 1 .. array_length(en_hp,1) loop
        if en_hp[j] > 0 and (low is null or en_hp[j] < low) then low := en_hp[j]; target := j; end if;
      end loop;
      exit when target is null;
      crit := random() < 0.18;
      dmg := greatest(1, round(pet_atk[i] * (0.85 + random() * 0.3) * (1 - def_cut)
              * (case when crit then 1.9 else 1 end)));
      en_hp[target] := greatest(0, en_hp[target] - dmg);
      total_dmg := total_dmg + dmg;
      log := log || jsonb_build_array(jsonb_build_object('round', rounds, 'side', 'pet', 'actor', i - 1,
        'target', target - 1, 'damage', dmg, 'crit', crit, 'ko', en_hp[target] <= 0,
        'targetHp', en_hp[target], 'targetMax', en_max[target]));
    end loop;

    alive_en := 0;
    for j in 1 .. array_length(en_hp,1) loop if en_hp[j] > 0 then alive_en := alive_en + 1; end if; end loop;
    if alive_en = 0 then won := true; exit; end if;

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

  loot := case when won then public.familiar_hunt_roll_loot(u, inst.loot_pool, inst.is_boss)
               else jsonb_build_object('tier', null, 'rewards', '[]'::jsonb) end;

  -- linear progression: a win unlocks exactly the next stage, a loss keeps the same one
  insert into public.familiar_hunt_progress(user_id, current_familiar_hunt_stage, highest_stage_completed, total_runs, total_wins)
  values (u, case when won then inst.stage + 1 else inst.stage end,
             case when won then inst.stage else 0 end, 1, case when won then 1 else 0 end)
  on conflict (user_id) do update set
    current_familiar_hunt_stage = case when won then greatest(public.familiar_hunt_progress.current_familiar_hunt_stage, inst.stage + 1)
                                       else public.familiar_hunt_progress.current_familiar_hunt_stage end,
    highest_stage_completed = case when won then greatest(public.familiar_hunt_progress.highest_stage_completed, inst.stage)
                                   else public.familiar_hunt_progress.highest_stage_completed end,
    total_runs = public.familiar_hunt_progress.total_runs + 1,
    total_wins = public.familiar_hunt_progress.total_wins + case when won then 1 else 0 end,
    updated_at = now();

  result := jsonb_build_object('ok', true, 'runId', inst.id, 'stage', inst.stage,
    'stageName', coalesce(inst.stage_name, def->>'name'), 'isBoss', inst.is_boss,
    'victory', won, 'rounds', rounds, 'teamPower', round(team_power)::int,
    'recommendedPower', inst.recommended_power, 'totalDamage', total_dmg,
    'lootTier', loot->>'tier', 'rewards', coalesce(loot->'rewards','[]'::jsonb), 'log', log,
    'paymentCurrency', inst.payment_currency, 'paymentAmount', inst.payment_amount,
    'team', (select jsonb_agg(jsonb_build_object('name', pet_name[x], 'image', pet_img[x],
              'maxHp', pet_max[x], 'hp', pet_hp[x], 'atk', pet_atk[x], 'power', pet_pow[x]) order by x)
             from generate_subscripts(pet_hp, 1) x),
    'enemies', (select jsonb_agg(jsonb_build_object('name', en_name[y], 'image', en_img[y],
              'maxHp', en_max[y], 'hp', en_hp[y], 'atk', en_atk[y], 'elite', en_elite[y]) order by y)
             from generate_subscripts(en_hp, 1) y));

  update public.familiar_hunt_instances set status = 'settled', victory = won, rounds = rounds,
    total_damage = total_dmg, rewards = coalesce(loot->'rewards','[]'::jsonb),
    result_json = result, settled_at = now(), updated_at = now()
  where id = inst.id;

  return result;
end $$;

-- ── start a hunt (FC / internal TON debited atomically, external => intent) ─
CREATE OR REPLACE FUNCTION public.familiar_hunt_start(
  p_telegram_id bigint, p_pet_ids uuid[], p_currency text DEFAULT 'fc', p_idempotency_key text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare
  s public.familiar_hunt_settings; u uuid; prev public.familiar_hunt_instances;
  v_stage int; def jsonb; snapshot jsonb := '[]'::jsonb; pid uuid; v_pow numeric;
  team_power numeric := 0; v_name text; v_img text; v_lvl int;
  v_currency text := lower(coalesce(nullif(p_currency,''),'fc'));
  v_cost numeric; v_before numeric; v_after numeric; inst_id uuid;
  v_comment text; v_address text; v_nano bigint;
begin
  select * into s from public.familiar_hunt_settings where id;
  if s.id is null or not s.enabled then raise exception 'FAMILIAR_HUNT_DISABLED'; end if;
  if v_currency not in ('fc','ton') then raise exception 'INVALID_CURRENCY'; end if;

  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  if p_idempotency_key is not null then
    select * into prev from public.familiar_hunt_instances where user_id = u and idempotency_key = p_idempotency_key;
    if prev.id is not null then
      if prev.status = 'settled' then return prev.result_json || jsonb_build_object('replay', true); end if;
      if prev.status = 'paid_pending_hunt' then return public.familiar_hunt_resolve(prev.id); end if;
      return jsonb_build_object('ok', true, 'needsPayment', true, 'huntId', prev.id,
        'paymentAddress', prev.payment_address, 'paymentComment', prev.payment_comment,
        'amountNano', prev.payment_amount_nano::text, 'amountTon', prev.payment_amount, 'stage', prev.stage);
    end if;
  end if;

  if array_length(p_pet_ids,1) is distinct from 3 then raise exception 'TEAM_MUST_HAVE_3_PETS'; end if;
  if (select count(distinct x) from unnest(p_pet_ids) x) <> 3 then raise exception 'DUPLICATED_PET'; end if;

  -- the stage is ALWAYS the server-side current stage: a client can never skip ahead
  insert into public.familiar_hunt_progress(user_id) values (u) on conflict (user_id) do nothing;
  select current_familiar_hunt_stage into v_stage from public.familiar_hunt_progress where user_id = u;
  v_stage := greatest(1, coalesce(v_stage, 1));
  def := public.familiar_hunt_stage_def(v_stage);

  foreach pid in array p_pet_ids loop
    select coalesce(p.name,'Pet'), coalesce(snt.image_url, p.image_adult_url, p.image_baby_url, ''), coalesce(pp.level,1)
      into v_name, v_img, v_lvl
      from public.player_pets pp
      join public.pets p on p.id = pp.pet_id
      left join public.sub_nfts sn on sn.player_pet_id = pp.id or sn.id = pp.sub_nft_id
      left join public.sub_nft_templates snt on snt.id = sn.template_id
      where pp.id = pid and pp.user_id = u limit 1;
    if v_name is null then raise exception 'PET_NOT_YOURS'; end if;
    v_pow := greatest(1, coalesce(public.pet_instance_power(pid), 1));
    team_power := team_power + v_pow;
    snapshot := snapshot || jsonb_build_array(jsonb_build_object('petId', pid, 'name', v_name,
      'image', v_img, 'power', v_pow, 'level', v_lvl));
  end loop;

  -- ═══ PAYMENT ═══ never mixes internal + external TON
  if v_currency = 'fc' then
    v_cost := coalesce(s.entry_fc, 0);
    select coalesce(forge_coins,0) into v_before from public.game_players where id = u for update;
    if v_before < v_cost then raise exception 'INSUFFICIENT_FC'; end if;
    v_after := v_before - v_cost;
    update public.game_players set forge_coins = v_after, updated_at = now() where id = u;
    insert into public.familiar_hunt_instances(user_id, stage, stage_name, is_boss, payment_currency,
      payment_amount, loot_table_version, loot_pool, team_snapshot, team_power, recommended_power,
      status, idempotency_key)
    values (u, v_stage, def->>'name', coalesce((def->>'isBoss')::boolean,false), 'fc',
      v_cost, s.loot_table_version, 'fc', snapshot, round(team_power), (def->>'recommendedPower')::numeric,
      'paid_pending_hunt', p_idempotency_key)
    returning id into inst_id;
    return public.familiar_hunt_resolve(inst_id);
  end if;

  v_cost := coalesce(s.entry_ton, 0);
  select coalesce(ton_balance,0) into v_before from public.game_players where id = u for update;
  if v_before >= v_cost then
    v_after := round(v_before - v_cost, 6);
    update public.game_players set ton_balance = v_after, updated_at = now() where id = u;
    insert into public.wallet_ledger(user_id, type, amount_fc, amount_ton, balance_before, balance_after, reference_id)
      values (u, 'familiar_hunt_entry', 0, -v_cost, v_before, v_after, 'familiar_hunt:stage:' || v_stage);
    insert into public.familiar_hunt_instances(user_id, stage, stage_name, is_boss, payment_currency,
      payment_amount, loot_table_version, loot_pool, team_snapshot, team_power, recommended_power,
      status, idempotency_key)
    values (u, v_stage, def->>'name', coalesce((def->>'isBoss')::boolean,false), 'ton_internal',
      v_cost, s.loot_table_version, 'ton', snapshot, round(team_power), (def->>'recommendedPower')::numeric,
      'paid_pending_hunt', p_idempotency_key)
    returning id into inst_id;
    return public.familiar_hunt_resolve(inst_id);
  end if;

  -- internal balance stays UNTOUCHED: the wallet is asked for the FULL entry
  select value_text into v_address from public.wallet_settings where key = 'ton_hot_wallet';
  if coalesce(v_address,'') = '' then raise exception 'TON_HOT_WALLET_MISSING'; end if;
  v_nano := round(v_cost * 1000000000)::bigint;
  inst_id := gen_random_uuid();
  v_comment := 'fh' || replace(inst_id::text, '-', '');
  insert into public.familiar_hunt_instances(id, user_id, stage, stage_name, is_boss, payment_currency,
    payment_amount, payment_amount_nano, loot_table_version, loot_pool, team_snapshot, team_power,
    recommended_power, status, payment_comment, payment_address, idempotency_key)
  values (inst_id, u, v_stage, def->>'name', coalesce((def->>'isBoss')::boolean,false), 'ton_external',
    v_cost, v_nano, s.loot_table_version, 'ton', snapshot, round(team_power),
    (def->>'recommendedPower')::numeric, 'pending_payment', v_comment, v_address, p_idempotency_key);

  return jsonb_build_object('ok', true, 'needsPayment', true, 'huntId', inst_id, 'stage', v_stage,
    'paymentAddress', v_address, 'paymentComment', v_comment,
    'amountNano', v_nano::text, 'amountTon', v_cost, 'internalTon', v_before);
end $$;

-- ── external payments: list, mark paid, resolve ────────────────────────────
CREATE OR REPLACE FUNCTION public.familiar_hunt_pending_payments(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare u uuid;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return jsonb_build_object(
    'awaitingPayment', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'stage', i.stage,
        'paymentComment', i.payment_comment, 'amountNano', i.payment_amount_nano::text,
        'amountTon', i.payment_amount, 'createdAt', i.created_at))
      from public.familiar_hunt_instances i
      where i.user_id = u and i.status = 'pending_payment'
        and i.created_at > now() - interval '3 days'), '[]'::jsonb),
    'paidPendingHunt', coalesce((select jsonb_agg(i.id)
      from public.familiar_hunt_instances i
      where i.user_id = u and i.status = 'paid_pending_hunt' and i.payment_currency = 'ton_external'), '[]'::jsonb));
end $$;

CREATE OR REPLACE FUNCTION public.familiar_hunt_mark_paid(p_instance_id uuid, p_tx_hash text, p_amount_nano numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare inst public.familiar_hunt_instances;
begin
  select * into inst from public.familiar_hunt_instances where id = p_instance_id for update;
  if inst.id is null then raise exception 'HUNT_NOT_FOUND'; end if;
  if inst.status = 'settled' then return jsonb_build_object('ok', true, 'status', 'settled'); end if;
  if inst.status = 'paid_pending_hunt' then return jsonb_build_object('ok', true, 'status', 'paid_pending_hunt'); end if;
  if coalesce(p_amount_nano,0) < (inst.payment_amount_nano * 97) / 100 then raise exception 'TON_AMOUNT_TOO_LOW'; end if;
  update public.familiar_hunt_instances
    set status = 'paid_pending_hunt', tx_hash = p_tx_hash,
        received_amount_nano = round(p_amount_nano)::bigint, updated_at = now()
  where id = inst.id;
  return jsonb_build_object('ok', true, 'status', 'paid_pending_hunt');
end $$;

-- ── player state: ONLY the current stage (linear, no mission list) ─────────
CREATE OR REPLACE FUNCTION public.familiar_hunt_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare u uuid; s public.familiar_hunt_settings; v_fc numeric; v_ton numeric;
        v_stage int; v_high int; def jsonb;
begin
  select * into s from public.familiar_hunt_settings where id;
  select id, coalesce(forge_coins,0), coalesce(ton_balance,0) into u, v_fc, v_ton
    from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.sub_nft_sync(u);

  insert into public.familiar_hunt_progress(user_id) values (u) on conflict (user_id) do nothing;
  select current_familiar_hunt_stage, highest_stage_completed into v_stage, v_high
    from public.familiar_hunt_progress where user_id = u;
  v_stage := greatest(1, coalesce(v_stage,1));
  def := public.familiar_hunt_stage_def(v_stage);

  return jsonb_build_object(
    'enabled', coalesce(s.enabled, false),
    'balances', jsonb_build_object('fc', v_fc, 'ton', v_ton),
    'entry', jsonb_build_object('fc', s.entry_fc, 'ton', s.entry_ton, 'lootTableVersion', s.loot_table_version),
    'progress', jsonb_build_object('currentStage', v_stage, 'highestStageCompleted', coalesce(v_high,0)),
    'stage', def,
    'dropRates', jsonb_build_object('fc', s.fc_loot, 'ton', s.ton_loot),
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
    'history', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'stage', i.stage,
        'stageName', i.stage_name, 'victory', i.victory, 'rounds', i.rounds,
        'totalDamage', i.total_damage, 'rewards', i.rewards,
        'currency', i.payment_currency, 'amount', i.payment_amount, 'createdAt', i.created_at)
        order by i.created_at desc)
      from (select * from public.familiar_hunt_instances
             where user_id = u and status = 'settled' order by created_at desc limit 15) i), '[]'::jsonb));
end $$;

-- ── admin (bot) ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_familiar_hunt_overview()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare s public.familiar_hunt_settings;
begin
  select * into s from public.familiar_hunt_settings where id;
  return jsonb_build_object(
    'enabled', s.enabled, 'entryFc', s.entry_fc, 'entryTon', s.entry_ton,
    'lootTableVersion', s.loot_table_version, 'difficulty', s.difficulty,
    'fcLoot', s.fc_loot, 'tonLoot', s.ton_loot,
    'runs', (select count(*) from public.familiar_hunt_instances where status = 'settled'),
    'runs24h', (select count(*) from public.familiar_hunt_instances where status = 'settled' and created_at > now() - interval '24 hours'),
    'wins', (select count(*) from public.familiar_hunt_instances where victory),
    'fcSpent', (select coalesce(sum(payment_amount),0) from public.familiar_hunt_instances where payment_currency = 'fc' and status = 'settled'),
    'tonPaid', (select coalesce(sum(payment_amount),0) from public.familiar_hunt_instances where payment_currency in ('ton_internal','ton_external') and status = 'settled'),
    'tonExternal', (select coalesce(sum(payment_amount),0) from public.familiar_hunt_instances where payment_currency = 'ton_external' and status = 'settled'),
    'pendingPayments', (select count(*) from public.familiar_hunt_instances where status = 'pending_payment'),
    'paidPendingHunt', (select count(*) from public.familiar_hunt_instances where status = 'paid_pending_hunt'),
    'topStages', coalesce((select jsonb_agg(x) from (
        select highest_stage_completed as stage, count(*) as players
        from public.familiar_hunt_progress group by 1 order by 1 desc limit 8) x), '[]'::jsonb),
    'rewardsDistributed', coalesce((select jsonb_agg(x) from (
        select r->>'type' as type, count(*) as times, sum(coalesce((r->>'quantity')::numeric,0)) as total
        from public.familiar_hunt_instances i, jsonb_array_elements(i.rewards) r
        where i.status = 'settled' group by 1 order by 3 desc limit 12) x), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(x) from (
        select i.stage, i.victory, i.payment_currency as currency, i.payment_amount as amount,
               i.rewards, i.created_at, g.telegram_id, g.username
        from public.familiar_hunt_instances i join public.game_players g on g.id = i.user_id
        where i.status = 'settled' order by i.created_at desc limit 10) x), '[]'::jsonb));
end $$;

CREATE OR REPLACE FUNCTION public.admin_familiar_hunt_set(p_key text, p_value text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare k text := lower(coalesce(p_key,''));
begin
  if k = 'enabled' then
    update public.familiar_hunt_settings set enabled = (lower(p_value) in ('1','true','on','sim')) where id;
  elsif k = 'entry_fc' then
    update public.familiar_hunt_settings set entry_fc = greatest(0, floor(p_value::numeric)::bigint) where id;
  elsif k = 'entry_ton' then
    update public.familiar_hunt_settings set entry_ton = greatest(0, p_value::numeric) where id;
  elsif k = 'difficulty' then
    update public.familiar_hunt_settings set difficulty = p_value::jsonb, loot_table_version = loot_table_version where id;
  elsif k = 'stage_pool' then
    update public.familiar_hunt_settings set stage_pool = p_value::jsonb where id;
  elsif k = 'fc_loot' then
    update public.familiar_hunt_settings set fc_loot = p_value::jsonb, loot_table_version = loot_table_version + 1 where id;
  elsif k = 'ton_loot' then
    update public.familiar_hunt_settings set ton_loot = p_value::jsonb, loot_table_version = loot_table_version + 1 where id;
  else
    raise exception 'INVALID_KEY';
  end if;
  return public.admin_familiar_hunt_overview();
end $$;

-- ── access: backend only ──────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.familiar_hunt_stage_def(int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.familiar_hunt_grant(uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.familiar_hunt_roll_loot(uuid, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.familiar_hunt_resolve(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.familiar_hunt_start(bigint, uuid[], text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.familiar_hunt_pending_payments(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.familiar_hunt_mark_paid(uuid, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.familiar_hunt_state(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_familiar_hunt_overview() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_familiar_hunt_set(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.familiar_hunt_stage_def(int) TO service_role;
GRANT EXECUTE ON FUNCTION public.familiar_hunt_grant(uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.familiar_hunt_roll_loot(uuid, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.familiar_hunt_resolve(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.familiar_hunt_start(bigint, uuid[], text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.familiar_hunt_pending_payments(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.familiar_hunt_mark_paid(uuid, text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.familiar_hunt_state(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_familiar_hunt_overview() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_familiar_hunt_set(text, text) TO service_role;

-- the old mission-based battle entry point is replaced by the linear flow
DROP FUNCTION IF EXISTS public.familiar_hunt_battle(bigint, uuid, uuid[], text, text);
DROP FUNCTION IF EXISTS public.familiar_hunt_battle(bigint, uuid, uuid[], text);