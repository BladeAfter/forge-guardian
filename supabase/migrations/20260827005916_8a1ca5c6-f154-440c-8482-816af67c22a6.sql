-- 0042: FAMILIAR HUNT REBALANCE (boss tankiness + honest recommended power)
update public.familiar_hunt_settings
set difficulty = difficulty
      || jsonb_build_object(
           'bossHpRatio', 2.6,
           'bossAtkRatio', 0.70,
           'recommendedDisplayFactor', 4.0
         ),
    updated_at = now()
where id;

create or replace function public.familiar_hunt_stage_def(p_stage integer)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  s public.familiar_hunt_settings; d jsonb; pool jsonb; entry jsonb;
  v_stage int := greatest(1, coalesce(p_stage, 1));
  base numeric; growth numeric; boss_every int; boss_mult numeric;
  is_boss boolean; rec numeric; rec_display numeric; disp_factor numeric;
  idx int; enemies jsonb := '[]'::jsonb;
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
  disp_factor := greatest(1, coalesce((d->>'recommendedDisplayFactor')::numeric, 4.0));
  is_boss := (v_stage % boss_every) = 0;
  rec := round(base * power(growth, v_stage - 1) * (case when is_boss then boss_mult else 1 end));
  rec_display := round(rec * disp_factor);

  if jsonb_array_length(pool) = 0 then
    pool := '[{"theme":"forest","art":"","arena":"","minions":["Monstro","Monstro","Monstro"],"boss":"Chefe"}]'::jsonb;
  end if;
  idx := ((v_stage - 1) / boss_every) % jsonb_array_length(pool);
  entry := pool -> idx;

  if is_boss then
    enemies := jsonb_build_array(jsonb_build_object(
      'name', coalesce(entry->>'boss', 'Chefe'),
      'image', coalesce(entry->>'art', ''),
      'hp', round(rec * coalesce((d->>'bossHpRatio')::numeric, 2.6) * hp_factor),
      'atk', round(rec * coalesce((d->>'bossAtkRatio')::numeric, 0.70)),
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
    'recommendedPower', rec_display,
    'defReduction', least(coalesce((d->>'defCap')::numeric, 0.32),
                          coalesce((d->>'defPerStage')::numeric, 0.004) * v_stage),
    'enemies', enemies);
end $function$;