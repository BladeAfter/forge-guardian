# Restaurar atributos premium de pets

## Objetivo
Restaurar a fórmula histórica dos pets premium sem reduzir valores já existentes ao subir nível ou evoluir.

## Implementação
- Tratar **Pet NFT**, **Sub-NFT** e **Veteran Pet** pela mesma fórmula legada: base original × raridade × nível × evolução.
- Incluir `veteran_line` na proteção legada; hoje ele cai por engano na fórmula nova e atributos históricos acima de 100% são limitados a 40%.
- Manter os limites históricos somente quando existe um limite configurado especificamente para aquele atributo; atributos legados como HP/ATK não serão presos ao limite genérico de 40%.
- Corrigir também a prévia de próxima evolução e os dados de combate para usar `passives_override` e reconhecer Sub-NFT/Veteran, evitando diferença entre card e efeito real.
- Preservar a fórmula atual dos pets comuns e novos, sem alterar inventário, nível, evolução ou propriedade.

## Validação
- Auditar todos os Pet NFT, Sub-NFT e Veteran Pet existentes antes/depois.
- Confirmar que nenhum atributo premium diminui e que valores históricos (inclusive acima de 100%, como 102%) voltam a aparecer e são aplicados pelo servidor.
- Verificar build e chamadas que alimentam card, arena, chefes e recompensas.

## Detalhes técnicos
A mudança será feita nas funções centralizadas `player_pet_buffs`, `player_pet_json` e `calculate_pet_combat_stats`; `get_pet_bonuses` já delega para essa fonte única.
