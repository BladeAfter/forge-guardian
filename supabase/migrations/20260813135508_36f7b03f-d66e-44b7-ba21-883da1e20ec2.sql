create or replace function public.market_min_price_ton(p_item_type text, p_rarity text)
returns numeric
language sql
immutable
set search_path to 'public'
as $function$
  select case
    when lower(coalesce(p_item_type,'')) = 'hero'
     and lower(coalesce(p_rarity,'')) in ('legendary','mythic','ancestral','nft_exclusive','divine','celestial')
    then 10::numeric
    else 0.10::numeric
  end;
$function$;