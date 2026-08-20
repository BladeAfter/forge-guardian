create or replace function public.market_auction_exclusive_item(p_item_type text, p_rarity text)
returns boolean language sql immutable set search_path to 'public' as $$
  select lower(coalesce(p_rarity,'')) in ('nft_exclusive','divine','celestial')
      or (lower(coalesce(p_item_type,'')) = 'hero'
          and lower(coalesce(p_rarity,'')) in ('mythic','ancestral'));
$$;

create or replace function public.market_block_auction_only()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare rar text; kind text := lower(coalesce(new.item_type,''));
begin
  rar := lower(coalesce(new.snapshot->>'rarity',''));
  if public.market_auction_exclusive_item(kind, rar) then
    raise exception 'AUCTION_ONLY_ITEM';
  end if;
  return new;
end $$;

revoke all on function public.market_auction_exclusive_item(text, text) from anon, authenticated;
revoke all on function public.market_block_auction_only() from anon, authenticated;