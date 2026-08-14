DO $$
DECLARE v jsonb; r jsonb := '{}'::jsonb; d text := 'test1111test1111test1111test1111';
BEGIN
  DELETE FROM public.device_accounts WHERE device_hash IN (d, 'test2222test2222test2222test2222');
  DELETE FROM public.device_registry WHERE device_hash IN (d, 'test2222test2222test2222test2222');

  r := r || jsonb_build_object('t1_accountA', public.check_device_access(990000001, d, 'android'));
  r := r || jsonb_build_object('t2_accountB', public.check_device_access(990000002, d, 'android'));
  r := r || jsonb_build_object('t3_accountC', public.check_device_access(990000003, d, 'android'));
  r := r || jsonb_build_object('t4_accountD', public.check_device_access(990000004, d, 'android'));
  r := r || jsonb_build_object('t5_accountA_returns', public.check_device_access(990000001, d, 'android'));
  r := r || jsonb_build_object('t6_accountD_retry', public.check_device_access(990000004, d, 'android'));
  r := r || jsonb_build_object('t8_other_device', public.check_device_access(990000005, 'test2222test2222test2222test2222', 'ios', '{"ipHash":"shared-ip"}'));
  r := r || jsonb_build_object('t11_admin_bypass', public.check_device_access(public.admin_super_id(), d, 'android'));
  r := r || jsonb_build_object('gate_blocked_D', public.device_access_blocked(990000004),
                               'gate_blocked_A', public.device_access_blocked(990000001),
                               'gate_blocked_admin', public.device_access_blocked(public.admin_super_id()));

  INSERT INTO public.anti_fake_logs(event, device_hash, telegram_id, metadata)
  VALUES ('ANTI_FAKE_SELFTEST', d, NULL, r);

  -- clean test data (keeps only the single self-test log row)
  DELETE FROM public.device_accounts WHERE device_hash IN (d, 'test2222test2222test2222test2222');
  DELETE FROM public.device_registry WHERE device_hash IN (d, 'test2222test2222test2222test2222');
  DELETE FROM public.anti_fake_logs WHERE event <> 'ANTI_FAKE_SELFTEST' AND device_hash IN (d, 'test2222test2222test2222test2222');
END $$;