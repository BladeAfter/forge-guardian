-- Two overloads existed after the quantity/stackable rollout:
--   market_create_listing(bigint,text,uuid,text,numeric,text,numeric)            -- OBSOLETE (no quantity)
--   market_create_listing(bigint,text,uuid,text,numeric,text,numeric,integer)    -- CANONICAL
-- Because every trailing argument has a DEFAULT, PostgREST could not choose a
-- candidate. Drop ONLY the obsolete 7-argument version; the canonical one keeps
-- all current rules (min prices, NFT block, equipped block, stack locking).
drop function if exists public.market_create_listing(bigint, text, uuid, text, numeric, text, numeric);

notify pgrst, 'reload schema';