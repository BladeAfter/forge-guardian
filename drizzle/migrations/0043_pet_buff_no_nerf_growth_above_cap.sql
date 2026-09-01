-- O headroom anterior dividia a base pelo crescimento máximo, o que reduzia os buffs
-- já exibidos (jogadores viam atributos cair ~1/3 ao subir de nível).
-- Nova regra: o valor base nunca é reduzido (teto normal no nível 1) e o crescimento
-- por nível/estágio pode passar do teto até 1.5x (mesma folga usada nos buffs secundários).
CREATE OR REPLACE FUNCTION public.pet_effective_buff(p_base numeric, p_rarity text, p_level integer, p_stage integer, p_key text)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
declare raw numeric; cap numeric; lvl int; growth numeric; scaled numeric;
begin
  if p_base is null or p_base <= 0 then return coalesce(p_base, 0); end if;
  lvl := least(50, greatest(1, coalesce(p_level, 1)));
  growth := public.pet_stage_buff_multiplier(p_stage) * (1 + (lvl - 1) * 0.005);
  cap := public.pet_buff_cap(p_key);
  scaled := p_base * public.pet_rarity_multiplier(p_rarity);
  -- Base limitada ao teto normal: nível 1 mantém exatamente o valor histórico.
  if cap is not null and cap > 0 then
    scaled := least(scaled, cap);
    raw := least(scaled * growth, cap * 1.5);
  else
    raw := scaled * growth;
  end if;
  return round(least(raw, 150), 2);
end $function$;
