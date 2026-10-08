revoke execute on function public.market_item_details(bigint, text, uuid) from public, anon, authenticated;
revoke execute on function public.market_hero_details_json(uuid) from public, anon, authenticated;
revoke execute on function public.market_pet_details_json(uuid) from public, anon, authenticated;
revoke execute on function public.market_equipment_details_json(uuid) from public, anon, authenticated;
revoke execute on function public.market_stack_details_json(text, jsonb) from public, anon, authenticated;