-- Aumenta o limite de membros dos clãs para 150.
-- Atualiza a fórmula por nível, o default para novos clãs e recalcula clãs existentes.

-- 1. Atualiza a função de limite por nível (cap 150 em vez de 60)
CREATE OR REPLACE FUNCTION public.clan_member_limit(p_level integer)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT LEAST(150, 18 + GREATEST(1, COALESCE(p_level,1)) * 2)
$$;

-- 2. Atualiza o limite default aplicado a clãs recém-criados
INSERT INTO public.game_settings(key, value, category, label)
VALUES ('clan_default_member_limit', to_jsonb(150::int), 'clans', 'Limite de membros aplicado a clãs recém-criados')
ON CONFLICT (key) DO UPDATE SET value = to_jsonb(150::int), updated_at = now();

-- 3. Recalcula member_limit de todos os clãs existentes, nunca reduzindo
UPDATE public.clans
SET member_limit = GREATEST(member_limit, LEAST(150, public.clan_member_limit(level))),
    updated_at = now()
WHERE member_limit < LEAST(150, public.clan_member_limit(level));
