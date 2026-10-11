ALTER TABLE public.naval_owned_ships ADD COLUMN IF NOT EXISTS mining_started_at timestamptz NOT NULL DEFAULT now();
COMMENT ON COLUMN public.naval_owned_ships.mining_started_at IS 'Mining accrual begins no earlier than activation/acquisition; never backdated, never a wallet balance.';
CREATE OR REPLACE FUNCTION public.naval_ship_mining_quote(p_user uuid,p_class text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $f$
WITH ship AS (
 SELECT o.*, EXISTS(SELECT 1 FROM public.ton_reward_ledger l WHERE l.user_id=o.user_id AND l.source_type='naval_ship' AND l.source_id=o.class_id AND l.direction='debit' AND l.status='completed' AND l.amount_ton=o.price_paid AND l.created_at>=o.acquired_at) AND o.price_paid>0 AND k.price_ton>0 AND o.class_id<>'marinheiro' AND NOT coalesce(p.banned,false) AND NOT coalesce((SELECT value='true'::jsonb FROM public.game_settings WHERE key='game_reset_in_progress'),false) AS eligible
 FROM public.naval_owned_ships o JOIN public.naval_ship_classes k ON k.id=o.class_id JOIN public.game_players p ON p.id=o.user_id WHERE o.user_id=p_user AND o.class_id=p_class
)
SELECT jsonb_build_object('eligible',eligible,'roiDays',40,'continuous',true,'dailyTon',CASE WHEN eligible THEN price_paid/40 ELSE 0 END,'startedAt',CASE WHEN eligible THEN greatest(mining_started_at,acquired_at) END,'accruedTon',CASE WHEN eligible THEN trunc((price_paid/40)*greatest(0,extract(epoch FROM (now()-greatest(mining_started_at,acquired_at))))/86400,9) ELSE 0 END,'payoutStatus',CASE WHEN eligible THEN 'funding_review' ELSE 'ineligible' END) FROM ship
$f$;
REVOKE ALL ON FUNCTION public.naval_ship_mining_quote(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.naval_ship_mining_quote(uuid,text) TO service_role;
COMMENT ON FUNCTION public.naval_ship_mining_quote(uuid,text) IS 'Read-only continuous accrual at purchase TON / 40 per day; confirmed debit required, free/granted ships excluded. No wallet credits, claims, payments or workers enabled.';
DO $do$
DECLARE d text:=pg_get_functiondef('public.naval_fleet_view(uuid)'::regprocedure);
BEGIN
 IF position('naval_ship_mining_quote' IN d)=0 THEN
  IF position('''canCustomize'',price_paid>0' IN d)=0 THEN RAISE EXCEPTION 'Fleet mining patch target missing'; END IF;
  d:=replace(d,'''canCustomize'',price_paid>0','''mining'',public.naval_ship_mining_quote(p_user,class_id),''canCustomize'',price_paid>0');
  EXECUTE d;
 END IF;
END $do$;