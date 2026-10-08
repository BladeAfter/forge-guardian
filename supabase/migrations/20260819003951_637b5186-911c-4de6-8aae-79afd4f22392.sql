do $$
declare n int; begin
  select jsonb_array_length(public.get_hero_fusion_dashboard(1310583958)->'heroes') into n;
  raise notice 'fusion heroes: %', n;
end $$;