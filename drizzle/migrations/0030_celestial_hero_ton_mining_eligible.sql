-- Celestial heroes (auction/roulette line) were not in the TON mining rarity gate,
-- so their cards showed "MINING UNAVAILABLE" and the rarity rate resolved to 0.
create or replace function public.hero_mining_rarity_eligible(p_rarity text)
returns boolean language sql immutable security definer set search_path to 'public' as $$
  select lower(btrim(coalesce(p_rarity, ''))) in
    ('rare','epic','legendary','mythic','ancestral','celestial','divine','nft_exclusive');
$$;

insert into public.hero_mining_rates(rarity, ton_per_day)
values ('celestial', 0.20)
on conflict (rarity) do nothing;
