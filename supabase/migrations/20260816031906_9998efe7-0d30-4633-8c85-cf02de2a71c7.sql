create or replace function public.market_block_auction_only()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare rar text; kind text := lower(coalesce(new.item_type,''));
begin
  rar := lower(coalesce(new.snapshot->>'rarity',''));
  if public.auction_only_item(kind, rar) then
    raise exception 'AUCTION_ONLY_ITEM';
  end if;
  return new;
end $$;

drop trigger if exists market_listings_auction_only on public.market_listings;
create trigger market_listings_auction_only
before insert on public.market_listings
for each row execute function public.market_block_auction_only();

revoke all on function public.market_block_auction_only() from anon, authenticated;