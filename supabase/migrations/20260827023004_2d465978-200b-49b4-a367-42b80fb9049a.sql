-- 1) Explicit upgrade-management authority: LEADER + VICE (co-leader) only.
CREATE OR REPLACE FUNCTION public.clan_can_manage_upgrades(p_user uuid, p_clan uuid DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.clan_members m
     WHERE m.user_id = p_user
       AND (p_clan IS NULL OR m.clan_id = p_clan)
       AND lower(replace(m.role, '_', '-')) IN ('leader', 'co-leader', 'vice-leader', 'vice', 'deputy')
  );
$$;

REVOKE ALL ON FUNCTION public.clan_can_manage_upgrades(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_can_manage_upgrades(uuid, uuid) TO service_role;

-- 2) Audit trail for every collective-resource upgrade purchase.
CREATE TABLE IF NOT EXISTS public.clan_upgrade_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  upgrade_code text NOT NULL,
  old_level integer NOT NULL,
  new_level integer NOT NULL,
  resource_type text NOT NULL DEFAULT 'FC',
  cost numeric NOT NULL DEFAULT 0,
  treasury_before numeric NOT NULL DEFAULT 0,
  treasury_after numeric NOT NULL DEFAULT 0,
  performed_by uuid,
  performed_by_role text,
  idempotency_key text,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.clan_upgrade_audit TO service_role;
ALTER TABLE public.clan_upgrade_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY "clan_upgrade_audit_service_only" ON public.clan_upgrade_audit
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS clan_upgrade_audit_clan_idx ON public.clan_upgrade_audit(clan_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS clan_upgrade_audit_key_uidx
  ON public.clan_upgrade_audit(clan_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

-- 3) Atomic, idempotent, race-safe purchase paid strictly from the clan treasury.
CREATE OR REPLACE FUNCTION public.clan_upgrade_buy(p_telegram_id bigint, p_code text, p_key text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid; v_clan uuid; v_role text; cfgu public.clan_upgrade_config;
  v_level integer; v_cost numeric; v_clan_level integer;
  v_before numeric; v_after numeric; v_prev public.clan_upgrade_audit;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  -- Collective funds may only be spent by the leader or the vice-leader.
  IF NOT public.clan_can_manage_upgrades(v_uid, v_clan) THEN
    RAISE EXCEPTION 'UNAUTHORIZED_CLAN_ROLE';
  END IF;

  IF p_key IS NOT NULL THEN
    SELECT * INTO v_prev FROM public.clan_upgrade_audit
     WHERE clan_id = v_clan AND idempotency_key = p_key;
    IF v_prev.id IS NOT NULL THEN
      RETURN jsonb_build_object('status','duplicate','code', v_prev.upgrade_code,
                                'level', v_prev.new_level, 'cost', v_prev.cost);
    END IF;
  END IF;

  SELECT * INTO cfgu FROM public.clan_upgrade_config WHERE code = p_code AND enabled;
  IF cfgu.code IS NULL THEN RAISE EXCEPTION 'INVALID_UPGRADE'; END IF;

  SELECT level INTO v_clan_level FROM public.clans WHERE id = v_clan;
  IF v_clan_level < cfgu.required_clan_level THEN RAISE EXCEPTION 'CLAN_LEVEL_REQUIRED'; END IF;

  -- Lock the upgrade row first, then re-read the level so simultaneous
  -- leader/vice clicks cannot buy the same level twice or at a stale price.
  INSERT INTO public.clan_upgrades(clan_id, code, level) VALUES (v_clan, p_code, 0) ON CONFLICT DO NOTHING;
  SELECT level INTO v_level FROM public.clan_upgrades
   WHERE clan_id = v_clan AND code = p_code FOR UPDATE;
  IF v_level >= cfgu.max_level THEN RAISE EXCEPTION 'MAX_LEVEL'; END IF;

  v_cost := round(cfgu.base_cost_fc * power(cfgu.cost_growth, v_level));

  SELECT COALESCE(fc, 0) INTO v_before FROM public.clan_treasury WHERE clan_id = v_clan;
  v_before := COALESCE(v_before, 0);
  IF v_before < v_cost THEN RAISE EXCEPTION 'INSUFFICIENT_CLAN_FUNDS'; END IF;

  -- Treasury debit locks the treasury row and writes the ledger entry.
  v_after := public.clan_treasury_move(v_clan, v_uid, 'FC', -v_cost, 'CLAN_UPGRADE_PURCHASE');

  UPDATE public.clan_upgrades SET level = v_level + 1, updated_at = now()
   WHERE clan_id = v_clan AND code = p_code;

  INSERT INTO public.clan_upgrade_audit(clan_id, upgrade_code, old_level, new_level, resource_type,
                                        cost, treasury_before, treasury_after, performed_by,
                                        performed_by_role, idempotency_key)
  VALUES (v_clan, p_code, v_level, v_level + 1, 'FC', v_cost, v_before, v_after, v_uid, v_role, p_key);

  RETURN jsonb_build_object('status','upgraded','code', p_code, 'level', v_level + 1,
                            'cost', v_cost, 'treasury', v_after);
END $$;

REVOKE ALL ON FUNCTION public.clan_upgrade_buy(bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_upgrade_buy(bigint, text, text) TO service_role;

-- Retire the unprotected 2-arg overload so no caller can bypass the new rules.
DROP FUNCTION IF EXISTS public.clan_upgrade_buy(bigint, text);