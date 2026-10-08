UPDATE public.myth_sale_config SET sale_status = 'active', updated_at = now() WHERE id;
UPDATE public.myth_token_settings SET status_label = 'Sale Live', updated_at = now() WHERE id;
UPDATE public.myth_sale_public_stats SET sale_status = 'active', updated_at = now() WHERE id;