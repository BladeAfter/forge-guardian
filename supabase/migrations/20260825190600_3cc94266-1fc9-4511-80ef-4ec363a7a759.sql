UPDATE public.familiar_hunt_settings
SET ton_loot = jsonb_set(
      ton_loot::jsonb,
      '{1,options}',
      '[[{"type":"fc","min":300000,"max":600000}]]'::jsonb
    ),
    loot_table_version = loot_table_version + 1,
    updated_at = now()
WHERE ton_loot::jsonb -> 1 ->> 'label' = 'PREMIUM';