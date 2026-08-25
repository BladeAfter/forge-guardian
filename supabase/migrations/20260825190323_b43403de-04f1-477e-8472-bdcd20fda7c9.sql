-- Ajusta a faixa de FC da segunda opção de loot TON (PREMIUM)
-- de 500.000-800.000 para 300.000-600.000.
UPDATE public.familiar_hunt_settings
SET ton_loot = jsonb_set(
  ton_loot,
  '{1,options,0}',
  jsonb_build_object('type','fc','min',300000,'max',600000),
  false
)
WHERE id = true;

-- Incrementa a versão da tabela de loot para invalidar caches antigas.
UPDATE public.familiar_hunt_settings
SET loot_table_version = loot_table_version + 1
WHERE id = true;