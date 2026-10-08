revoke execute on function public.premium_offer_timezone() from anon, authenticated;
revoke execute on function public.premium_offer_day_key() from anon, authenticated;
revoke execute on function public.premium_offers_state(bigint) from anon, authenticated;
revoke execute on function public.premium_offer_popup_mark(bigint, text, boolean) from anon, authenticated;
revoke execute on function public.admin_premium_offers_overview(bigint) from anon, authenticated;
revoke execute on function public.admin_premium_offers_set(bigint, text, text, text) from anon, authenticated;

grant execute on function public.premium_offer_timezone() to service_role;
grant execute on function public.premium_offer_day_key() to service_role;
grant execute on function public.premium_offers_state(bigint) to service_role;
grant execute on function public.premium_offer_popup_mark(bigint, text, boolean) to service_role;
grant execute on function public.admin_premium_offers_overview(bigint) to service_role;
grant execute on function public.admin_premium_offers_set(bigint, text, text, text) to service_role;