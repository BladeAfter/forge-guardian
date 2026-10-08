CREATE OR REPLACE FUNCTION public.tower_boss_for_floor(p_floor integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $function$
declare f int := greatest(1, least(100, coalesce(p_floor,1)));
  b public.tower_bosses; tier int; step int; mult numeric; hp numeric; atk numeric; def numeric; dmult numeric;
begin
  select * into b from public.tower_bosses where floor_index = ((f - 1) % 10) + 1;
  if b.boss_key is null then raise exception 'TOWER_BOSS_MISSING'; end if;
  tier := ceil(f / 10.0)::int;            -- 1..10
  step := ((f - 1) % 10);                 -- 0..9 inside the tier
  dmult := case when f <= 10 then 0.50 else 1.0 end;  -- beginner curve on the first tier only
  if f <= 10 then
    -- Smooth, strictly increasing beginner curve (Floor 1 easiest, Floor 10 checkpoint).
    hp  := round(13000 * (1 + 0.1350 * step));
    atk := round(390 * (1 + 0.1408 * step));
    def := round(90 * (1 + 0.0690 * step));
  else
    mult := power(1.55, tier - 1) * (1 + 0.06 * step);
    hp  := round(b.base_hp * mult * dmult);
    atk := round(b.base_atk * power(1.34, tier - 1) * (1 + 0.04 * step) * dmult);
    def := round(b.base_def * power(1.22, tier - 1) * (1 + 0.03 * step) * dmult);
  end if;
  return jsonb_build_object(
    'heroId','tower-boss','name',b.name,'bossKey',b.boss_key,'theme',b.theme,'role',b.role,
    'behavior',b.behavior,'floor',f,'tier',tier,'rarity','boss',
    'finalHp',hp,'finalAtk',atk,'defense',def,'speed',b.base_speed + tier,
    'level',f,'imageUrl',null,'difficultyMultiplier',dmult,
    'recommendedPower', round(hp * 0.35 + atk * 6)::bigint,
    'entryCost', public.tower_entry_cost(f)
  );
end $function$;