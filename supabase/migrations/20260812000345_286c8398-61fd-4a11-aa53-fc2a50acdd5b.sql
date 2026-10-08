CREATE OR REPLACE FUNCTION public.market_block_locked_hero()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  rec jsonb;
  hid uuid;
  locked boolean;
begin
  rec := to_jsonb(coalesce(new, old));
  hid := coalesce(rec->>'hero_id', rec->>'player_hero_id')::uuid;
  if hid is null then
    return coalesce(new, old);
  end if;
  select market_locked into locked from player_heroes where id = hid;
  if locked then
    raise exception 'HERO_LISTED_IN_MARKET';
  end if;
  return coalesce(new, old);
end
$function$;