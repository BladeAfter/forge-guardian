CREATE OR REPLACE FUNCTION public.pass_locked_reward_config()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select value from game_settings where key = 'pass_locked_reward'),
                  jsonb_build_object('enabled', true, 'price_ton', 10));
$function$;

CREATE OR REPLACE FUNCTION public.buy_pass_locked_reward(p_telegram_id bigint, p_reward_id uuid, p_wallet_address text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u game_players%rowtype; r season_pass_rewards%rowtype; p player_season_pass%rowtype;
        cfg jsonb; v_price numeric; v_ver int; o pass_locked_reward_orders%rowtype;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then raise exception 'INVALID_REQUEST'; end if;
  select * into u from game_players where telegram_id = p_telegram_id for update;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if coalesce(u.banned,false) then raise exception 'PLAYER_BANNED'; end if;

  cfg := pass_locked_reward_config();
  if not coalesce((cfg->>'enabled')::boolean, true) then raise exception 'LOCKED_REWARD_PURCHASE_DISABLED'; end if;
  v_price := coalesce((cfg->>'price_ton')::numeric, 10);
  if v_price <= 0 then raise exception 'INVALID_PRICE'; end if;

  select * into r from season_pass_rewards where id = p_reward_id and enabled;
  if r.id is null then raise exception 'REWARD_NOT_FOUND'; end if;
  select * into p from player_season_pass where user_id = u.id and season_id = r.season_id;
  v_ver := case when coalesce(p.tier,'none') = 'none' then 2 else coalesce(p.pass_version, 1) end;
  if coalesce(r.min_pass_version,1) <= v_ver then raise exception 'REWARD_NOT_LOCKED'; end if;

  -- One paid unlock per user, ever.
  if exists (select 1 from pass_locked_reward_orders
              where user_id = u.id and status in ('paid','delivered','completed')) then
    raise exception 'LOCKED_REWARD_LIMIT_REACHED';
  end if;

  select * into o from pass_locked_reward_orders where idempotency_key = p_idempotency_key;
  if o.id is null then
    select * into o from pass_locked_reward_orders
      where user_id = u.id and reward_id = r.id and status = 'pending' and expires_at > now()
      order by created_at desc limit 1;
  end if;
  if o.id is not null and o.status = 'pending' then
    return jsonb_build_object('status','payment_required','method','ton_connect','orderId', o.id,
      'paymentAddress', o.payment_address, 'amountNano', o.amount_nano, 'amountTon', o.price_ton,
      'paymentComment', o.payment_comment, 'expiresAt', o.expires_at, 'priceTon', o.price_ton);
  end if;

  if round(coalesce(u.ton_balance,0), 9) >= round(v_price, 9) then
    update game_players set ton_balance = round(coalesce(ton_balance,0) - v_price, 9), updated_at = now() where id = u.id;
    insert into pass_locked_reward_orders(user_id, telegram_id, reward_id, season_id, price_ton, amount_nano,
      status, method, idempotency_key)
    values (u.id, p_telegram_id, r.id, r.season_id, v_price, round(v_price*1000000000)::text,
      'paid', 'internal_ton', p_idempotency_key)
    returning * into o;
    perform pass_locked_reward_deliver(o.id);
    return jsonb_build_object('status','completed','method','internal_ton','orderId', o.id,
      'priceTon', v_price, 'itemCode', r.reward_code,
      'dashboard', get_season_pass_dashboard(p_telegram_id),
      'inventory', get_player_inventory(p_telegram_id));
  end if;

  insert into pass_locked_reward_orders(user_id, telegram_id, reward_id, season_id, price_ton, amount_nano,
    payment_address, payment_comment, status, method, idempotency_key)
  values (u.id, p_telegram_id, r.id, r.season_id, v_price, round(v_price*1000000000)::text,
    wallet_hot_address(), 'forge_passchest:' || gen_random_uuid(), 'pending', 'ton_connect', p_idempotency_key)
  returning * into o;

  return jsonb_build_object('status','payment_required','method','ton_connect','orderId', o.id,
    'paymentAddress', o.payment_address, 'amountNano', o.amount_nano, 'amountTon', o.price_ton,
    'paymentComment', o.payment_comment, 'expiresAt', o.expires_at, 'priceTon', v_price,
    'availableTon', round(coalesce(u.ton_balance,0), 9));
end $function$;