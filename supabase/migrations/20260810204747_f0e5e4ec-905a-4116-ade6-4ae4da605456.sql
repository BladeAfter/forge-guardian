create or replace function public.simulate_pvp_battle(a jsonb, d jsonb, seed text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare r jsonb; turns int;
begin
  r := public.simulate_pvp_battle_core(a, d, seed);
  turns := greatest(1, least(50, coalesce((select max((x->>'turn')::int) from jsonb_array_elements(coalesce(r->'battleLog','[]'::jsonb)) x), 1)));
  return r || jsonb_build_object('turns', turns, 'totalTurns', turns);
end
$fn$;