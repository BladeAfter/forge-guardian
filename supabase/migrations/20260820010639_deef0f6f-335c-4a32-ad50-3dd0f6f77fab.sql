CREATE OR REPLACE FUNCTION public.auction_only_item(p_item_type text, p_rarity text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  select lower(coalesce(p_rarity,'')) in ('legendary','nft_exclusive','divine','celestial')
      or (lower(coalesce(p_item_type,'')) = 'hero'
          and lower(coalesce(p_rarity,'')) in ('mythic','ancestral'));
$$;

CREATE OR REPLACE FUNCTION public.market_min_price_ton(p_item_type text, p_rarity text)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  select case
    when lower(coalesce(p_item_type,'')) = 'hero'
     and lower(coalesce(p_rarity,'')) = 'legendary'
    then 5::numeric
    when lower(coalesce(p_item_type,'')) = 'hero'
     and lower(coalesce(p_rarity,'')) in ('mythic','ancestral','nft_exclusive','divine','celestial')
    then 10::numeric
    else 0.10::numeric
  end;
$$;