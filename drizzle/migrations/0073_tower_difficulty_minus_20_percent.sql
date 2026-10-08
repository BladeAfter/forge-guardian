create or replace function public.tower_boss_for_floor(p_floor int)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare f int := greatest(1, least(100, coalesce(p_floor,1)));
  b public.tower_bosses; tier int; step int; mult numeric; hp numeric; atk numeric; def numeric; dmult numeric; n int;
  ease numeric := 0.80;
begin
  select count(*) into n from public.tower_bosses;
  if coalesce(n,0) = 0 then raise exception 'TOWER_BOSS_MISSING'; end if;
  select * into b from public.tower_bosses order by floor_index offset ((f - 1) % n) limit 1;
  if b.boss_key is null then raise exception 'TOWER_BOSS_MISSING'; end if;
  tier := ceil(f / 10.0)::int;
  step := ((f - 1) % 10);
  dmult := case when f <= 10 then 0.50 else 1.0 end;
  if f <= 10 then
    hp  := round(13000 * (1 + 0.1350 * step) * ease);
    atk := round(390 * (1 + 0.1408 * step) * ease);
    def := round(90 * (1 + 0.0690 * step) * ease);
  else
    mult := power(1.55, tier - 1) * (1 + 0.06 * step);
    hp  := round(b.base_hp * mult * dmult * ease);
    atk := round(b.base_atk * power(1.34, tier - 1) * (1 + 0.04 * step) * dmult * ease);
    def := round(b.base_def * power(1.22, tier - 1) * (1 + 0.03 * step) * dmult * ease);
  end if;
  return jsonb_build_object(
    'heroId','tower-boss','name',b.name,'bossKey',b.boss_key,'theme',b.theme,'role',b.role,
    'behavior',b.behavior,'floor',f,'tier',tier,'rarity','boss',
    'finalHp',hp,'finalAtk',atk,'defense',def,'speed',b.base_speed + tier,
    'level',f,'imageUrl',null,'difficultyMultiplier',dmult * ease,
    'recommendedPower', round(hp * 0.35 + atk * 6)::bigint,
    'entryCost', public.tower_entry_cost(f)
  );
end $$;