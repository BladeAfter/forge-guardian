alter table public.founder_pack_config add column if not exists signup_from timestamptz not null default now();
update public.founder_pack_config set signup_from = now();

create or replace function public.founder_pack_state(p_telegram_id bigint)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare u public.game_players; c public.founder_pack_config; v_owned boolean; v_expires timestamptz;
        v_eligible boolean; v_pending public.founder_pack_purchases; v_admin boolean;
begin
  select * into u from public.game_players where telegram_id = p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  c := public.founder_pack_settings();
  select exists (select 1 from public.founder_pack_purchases
                  where user_id = u.id and status in ('paid','settled')) into v_owned;
  v_expires := u.created_at + make_interval(days => greatest(1, c.eligibility_days));
  v_eligible := c.enabled and not v_owned and now() < v_expires
                and u.created_at >= c.signup_from;
  v_admin := p_telegram_id = 8118569391;
  select * into v_pending from public.founder_pack_purchases
   where user_id = u.id and status = 'pending' and expires_at > now()
   order by created_at desc limit 1;

  return jsonb_build_object(
    'enabled', c.enabled,
    'show', v_eligible or (v_admin and c.enabled and not v_owned),
    'testMode', (v_admin and not v_eligible),
    'eligible', v_eligible,
    'purchased', v_owned,
    'priceTon', c.price_ton,
    'amountNano', round(c.price_ton * 1000000000)::text,
    'eligibilityDays', c.eligibility_days,
    'eligibleUntil', v_expires,
    'signupFrom', c.signup_from,
    'accountCreatedAt', u.created_at,
    'availableTon', round(coalesce(u.ton_balance, 0), 9),
    'mythAmount', c.myth_amount,
    'fragments', c.fragments,
    'passTier', c.pass_tier,
    'pendingOrder', case when v_pending.id is null then null else jsonb_build_object(
        'orderId', v_pending.id, 'paymentAddress', v_pending.payment_address,
        'amountNano', v_pending.amount_nano, 'amountTon', v_pending.price_ton,
        'paymentComment', v_pending.payment_comment, 'expiresAt', v_pending.expires_at) end);
end $function$;
revoke all on function public.founder_pack_state(bigint) from public, anon, authenticated;