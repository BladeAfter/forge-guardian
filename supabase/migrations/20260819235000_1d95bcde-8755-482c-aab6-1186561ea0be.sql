revoke execute on function public.premium_offer_timezone() from public;
revoke execute on function public.premium_offer_day_key() from public;
revoke execute on function public.premium_offers_state(bigint) from public;
revoke execute on function public.premium_offer_popup_mark(bigint, text, boolean) from public;
revoke execute on function public.admin_premium_offers_overview(bigint) from public;
revoke execute on function public.admin_premium_offers_set(bigint, text, text, text) from public;