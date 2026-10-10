CREATE TABLE public.launch_registrations (
 telegram_id bigint PRIMARY KEY,
 display_name text NOT NULL DEFAULT 'Captain',
 inviter_telegram_id bigint,
 verified_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.launch_registrations TO service_role;
ALTER TABLE public.launch_registrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY launch_service_only ON public.launch_registrations FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE INDEX launch_inviter_idx ON public.launch_registrations(inviter_telegram_id) WHERE verified_at IS NOT NULL;
CREATE OR REPLACE FUNCTION public.register_launch_player(p_telegram_id bigint,p_name text,p_inviter bigint DEFAULT NULL,p_verified boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
 IF p_telegram_id IS NULL OR p_telegram_id <= 0 THEN RAISE EXCEPTION 'INVALID_PLAYER'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('launch_registration',0));
 IF p_inviter = p_telegram_id OR NOT EXISTS(SELECT 1 FROM public.launch_registrations WHERE telegram_id=p_inviter) THEN p_inviter := NULL; END IF;
 INSERT INTO public.launch_registrations(telegram_id,display_name,inviter_telegram_id,verified_at)
 VALUES(p_telegram_id,left(coalesce(nullif(p_name,''),'Captain'),64),p_inviter,CASE WHEN p_verified THEN now() ELSE NULL END)
 ON CONFLICT(telegram_id) DO UPDATE SET display_name=EXCLUDED.display_name,verified_at=coalesce(launch_registrations.verified_at,EXCLUDED.verified_at);
 RETURN jsonb_build_object('registered',true);
END $$;
REVOKE ALL ON FUNCTION public.register_launch_player(bigint,text,bigint,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.register_launch_player(bigint,text,bigint,boolean) TO service_role;
CREATE OR REPLACE FUNCTION public.launch_referral_board(p_telegram_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 WITH scores AS (
 SELECT p.telegram_id,p.display_name,count(c.telegram_id)::integer invites,p.created_at
 FROM public.launch_registrations p LEFT JOIN public.launch_registrations c ON c.inviter_telegram_id=p.telegram_id AND c.verified_at IS NOT NULL
 WHERE p.verified_at IS NOT NULL GROUP BY p.telegram_id,p.display_name,p.created_at
 ), ranked AS (SELECT *,row_number() OVER(ORDER BY invites DESC,created_at,telegram_id) position FROM scores)
 SELECT jsonb_build_object('invites',coalesce((SELECT invites FROM ranked WHERE telegram_id=p_telegram_id),0),'position',(SELECT position FROM ranked WHERE telegram_id=p_telegram_id),'ranking',coalesce((SELECT jsonb_agg(jsonb_build_object('position',position,'name',display_name,'invites',invites,'isYou',telegram_id=p_telegram_id) ORDER BY position) FROM ranked WHERE position<=20 AND invites>0),'[]'::jsonb));
$$;
REVOKE ALL ON FUNCTION public.launch_referral_board(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.launch_referral_board(bigint) TO service_role;