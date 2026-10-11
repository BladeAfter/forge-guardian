# Piratas das ilhas

## Implementação
- Cinco modelos de ilha com três piratas e um líder, nomes/cores, materiais e BERRIES distintos.
- Patrulha, perseguição, espada com alcance/recarga, fases do líder e ataques especiais avisados; dano validado no servidor e colisões com obstáculos.
- Barras de vida, queda do inimigo, baús diferenciados e interface de coleta.
- Sessões privadas diárias por jogador/modelo: reentrar não recria inimigos; ilhas procedurais compartilham o limite do modelo.
- Configuração central em `island_pirate_config`, limitada por `validIslandSettings`. Sorteio: moedas garantidas mais material/equipamento; líder também pode conceder troféu exclusivo. Pesos comuns 70:25; líder 70:25:5.
- Resgate atômico com materiais Realm, player_equipment, player_inventory e wallet_ledger; nenhum TON.

## Arquivos alterados/criados
- Backend: `supabase/functions/_shared/islandGeometry.ts`, `islandCombat.ts`, `supabase/functions/game-api/islandPirates.ts`, `index.ts`.
- Cliente: `src/islandCombat.ts`, `src/useIslandPirates.ts`, `src/components/IslandExploration.tsx`, `src/pages/RealmPage.tsx`.
- Cena: `src/components/island3d/IslandScene.tsx`, `IslandPlayer.tsx`, `IslandCombatActors.tsx`, `IslandCombatActors.css`.
- Localização: `src/locales/islandCombat.ts`, `src/locales/index.ts`.
- Testes: `src/islandCombat.test.ts`, `src/islandPiratesSecurity.test.ts`.
- Migração aplicada: `drizzle/migrations/0140_island_pirate_encounters.sql`; tipos Supabase regenerados automaticamente.

## Verificações
- 34 testes passaram em cinco arquivos, incluindo colisões e navegação existentes.
- Banco: 30 equipamentos comuns e 30 raros elegíveis; RPCs novas executáveis somente por service_role.
- Playwright: DOM isolado confirmou nomes, três barras, baú e aviso, sem page errors. Capturas ficaram verdes no sandbox: aparência gráfica completa ainda não confirmada.
- Sem sessão Telegram assinada: fluxo autenticado até resgate real não executado. Testes da rota usam mocks; testes SQL verificam estrutura/privilégios, não uma transação real de recompensa.
- Nenhum saldo real alterado para testes; nenhum worker ativado; mineração naval preservada.