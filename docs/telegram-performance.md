# Desempenho no Telegram — análise e validação

## Causas confirmadas
- Rapier aceitava até 0,5 segundo acumulado por quadro, repetindo até 30 passos físicos depois de um travamento, enquanto câmera/animação limitavam seu tempo a 0,05 segundo. Essa divergência podia avançar o corpo de uma vez e deixar a apresentação atrasada.
- Oceano tinha ciclos independentes de movimentação e desenho. Câmera usava fator fixo por desenho, variando sua resposta com a taxa de quadros.
- Oceano e minimapa preparavam separadamente imagens e cinco recortes de ilhas; consultas de regiões aconteciam em cada desenho.

## Correções
- Um controlador no ciclo R3F alimenta Rapier com tempo limitado, preservando seu passo fixo de 60 Hz. Frames longos e retorno de segundo plano não são recuperados de uma vez.
- Personagem e câmera seguem uma âncora visual suavizada; animações também descartam pausas longas.
- Oceano desenha dentro do ciclo de navegação, com câmera baseada em tempo, recortes compartilhados, consultas limitadas e descarte de navios fora da tela.
- Qualidade alta/balanceada/baixo consumo responde ao tempo observado: ajusta resolução, poeira e esteiras sem alterar preços, velocidades configuradas, controles, recompensas ou posições oficiais.
- Altura estável do Telegram ignora eventos intermediários. Segundo plano suspende desenho contínuo e limpa comandos. Eventos de cancelamento respeitam o ponteiro ativo.
- Diagnóstico opcional de desenvolvimento: `?gamePerf`, sem painel ou logs de produção; FPS, tempo médio/pico, custo da atualização e contagem de entidades.

## Arquivos
`src/gamePerformance.ts`, `src/gamePerformance.test.ts`, `src/useGameViewport.ts`, `src/telegram.ts`, `src/components/GrandLineOcean.tsx`, `src/components/IllustratedOcean.tsx`, `src/components/NavalMiniMap.tsx`, `src/components/IslandExploration.tsx`, `src/components/IslandJoystick.tsx`, `src/components/island3d/IslandFrameDriver.tsx`, `src/components/island3d/IslandFrameDriver.test.ts`, `src/components/island3d/IslandScene.tsx`, `src/components/island3d/IslandPlayer.tsx`, `src/components/island3d/IslandModels.tsx`, `src/navalRendering.ts`, `src/oceanPresentation.ts`.

## Testes realizados
- 26 testes automatizados de tempo, controlador, costa/píer, movimento naval, envio de comandos e permissões Telegram.
- Equivalência de 120 segundos de tempo admitido a 30, 60 e 120 Hz; pausa longa não avança a física.
- Cena isolada com interface existente: desembarque, dois minutos de caminhada, mudanças de direção, cinco pressões/solturas do joystick e retorno de visibilidade sem reiniciar posição.
- Travamento intencional de 1,5 s, câmera acompanhando; recuperação da cena, sem reprodução automática de toda a pausa.
- Eventos de altura estável/intermediária simulados; navegação e soltura no oceano; densidade 3x com canvas limitado às dimensões CSS.
- Compilação automática sem erros.

## Limitações
Não houve teste no Telegram em aparelho físico, sessão assinada ou partida real. As cenas usam controles reais sem chamadas ao servidor nem alterações de bens. Headless usa renderização por software e não prova FPS de um celular; a cena de 1280×1800 mostrou custo gráfico elevado, não custo alto da física. Mudança de orientação física, várias entidades em combate real e fluidez sustentada em aparelhos intermediários continuam pendentes. Não foi publicada esta atualização.