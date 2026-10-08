-- Fix infinite recursion: the MYTH stats trigger recomputed stats, which expired
-- pending intents, whose UPDATE fired the same trigger again ("stack depth limit exceeded").
CREATE OR REPLACE FUNCTION public.myth_expire_payment_intents()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE n integer;
BEGIN
  -- Never touch the table while a stats refresh is running (that is what recursed).
  IF coalesce(current_setting('mythreon.myth_stats', true), '') = '1' THEN RETURN 0; END IF;
  -- Only write when there is really something to expire: an empty UPDATE still fires triggers.
  IF NOT EXISTS (SELECT 1 FROM public.myth_payment_intents WHERE status = 'pending' AND expires_at <= now()) THEN
    RETURN 0;
  END IF;
  UPDATE public.myth_payment_intents
     SET status = 'expired', updated_at = now()
   WHERE status = 'pending' AND expires_at <= now();
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $function$;

CREATE OR REPLACE FUNCTION public.myth_sale_refresh_public_stats()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE s jsonb;
BEGIN
  -- Re-entrancy guard: a nested refresh is always redundant.
  IF coalesce(current_setting('mythreon.myth_stats', true), '') = '1' THEN RETURN NULL; END IF;
  PERFORM set_config('mythreon.myth_stats', '1', true);
  s := public.myth_sale_stats();
  UPDATE public.myth_sale_public_stats SET
    sold = (s->>'sold')::numeric,
    burned = (s->>'burned')::numeric,
    reserved = (s->>'reserved')::numeric,
    available = (s->>'available')::numeric,
    ton_raised = (s->>'tonRaised')::numeric,
    myth_per_ton = (s->>'mythPerTon')::numeric,
    sale_status = s->>'saleStatus',
    updated_at = now()
  WHERE id;
  PERFORM set_config('mythreon.myth_stats', '0', true);
  RETURN NULL;
END $function$;