create or replace function public.auction_only_item(p_item_type text, p_rarity text)
returns boolean language sql immutable set search_path to 'public' as $$
  select lower(coalesce(p_rarity,'')) in ('nft_exclusive','divine','celestial')
      or (lower(coalesce(p_item_type,'')) = 'hero'
          and lower(coalesce(p_rarity,'')) in ('mythic','ancestral'));
$$;

revoke all on function public.auction_only_item(text, text) from anon, authenticated;