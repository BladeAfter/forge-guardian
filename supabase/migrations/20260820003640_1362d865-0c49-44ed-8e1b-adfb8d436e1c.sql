WITH t(tid) AS (VALUES (1633499827::bigint),(1846251276),(1775192493),(6464718086),(5154918326),(1441236101),(6601476145),(6142779836),(5686579849),(7411228057),(1103543912),(5185148348),(8118569391)),
p AS (SELECT g.id FROM public.game_players g JOIN t ON t.tid=g.telegram_id),
inv AS (
  INSERT INTO public.player_inventory (user_id,item_type,item_code,quantity)
  SELECT id,'hero_chest','rare_chest',1 FROM p
  ON CONFLICT (user_id,item_type,item_code) DO UPDATE SET quantity=public.player_inventory.quantity+1, updated_at=now()
  RETURNING user_id
),
fc AS (
  UPDATE public.game_players g SET forge_coins=g.forge_coins+250000, updated_at=now() WHERE g.id IN (SELECT id FROM p) RETURNING g.id
),
myth AS (
  INSERT INTO public.myth_balances (user_id,amount) SELECT id,10000 FROM p
  ON CONFLICT (user_id) DO UPDATE SET amount=public.myth_balances.amount+10000, updated_at=now()
  RETURNING user_id
)
INSERT INTO public.myth_ledger (user_id,direction,amount,reason,admin_telegram_id)
SELECT id,'credit',10000,'admin_gift_bundle',8118569391 FROM p;