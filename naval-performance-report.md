# Grand Line — verificação de desempenho

## Escopo e causas encontradas

- Água: cada quadro executava dezenas de cópias, espelhamentos e salvamentos de contexto; substituídos por um padrão espelhado cacheado, mantendo a mesma textura e escala.
- Radar: timer independente de 200 ms; agora desenha a cada 200 ms dentro do único ciclo de animação naval.
- Toques: um destino novo durante um pedido em andamento perdia a prioridade de envio; a prioridade agora permanece até a resposta, com colapso de eventos repetidos.
- Interface: chamadas repetidas de atualização de velocidade/proximidade mesmo sem mudança; agora só atualiza quando o valor muda.
- Outros navios: poses desenhadas diretamente a cada resposta; agora aproximam apenas posições confirmadas, com limite de velocidade e descarte de jogadores ausentes.
- Qualidade: recebia delta já limitado, mascarando quadros lentos; agora recebe tempo bruto. Resolução extra limitada pelo tamanho da tela.
- Segundo plano: timers da navegação e dos baús eram rearmados mesmo sem efetuar pedidos; agora pausam até a volta.
- Cores de navios: serialização da paleta repetida em cada desenho; chave cacheada por paleta.
- Horizontal: radar sobrepunha o controle de velocidade; reposicionado sem retirar controles.

## Arquivos alterados

- `src/components/GrandLineOcean.tsx`: ciclo compartilhado, comandos por teclado urgentes, HUD somente quando muda, leitura da pose aprovada mais recente.
- `src/components/IllustratedOcean.tsx`: qualidade pelo tempo bruto, dimensões medidas, densidade limitada, frota interpolada, movimento sutil da água e redução de animações conforme preferência.
- `src/components/NavalMiniMap.tsx` e `.css`: radar no ciclo principal e posicionamento horizontal.
- `src/oceanPresentation.ts`: padrão espelhado cacheado, fallback de desenho preservado.
- `src/navalMotion.ts`: cache cosmético de aproximação de jogadores confirmados.
- `src/useNavalOcean.ts`: prioridade de comandos durante pedidos, pausa de timers.
- `src/useOceanChests.ts`: pausa de polling oculto e proteção na retomada.
- `src/shipCustomization.ts`: chave cacheada de cores.
- Testes em `useNavalOcean.test.ts`, `navalMotion.test.ts`, `oceanPresentation.test.ts`, `gamePerformance.test.ts`.

## Medições em navegador isolado

Chromium headless, viewport 1280×1800, densidade 2, respostas simuladas com atraso de 120 ms. Não usa sessão Telegram nem altera bens. Instrumentação adicionada somente à página temporária de teste.

| Medida, janela de 20 segundos | Antes | Depois |
|---|---:|---:|
| Chamadas drawImage | 40.225 | 3.977 |
| Atualizações React | 127 | 69 |
| FPS médio | 39,4 | 35,4 |
| Frame time p95 | 66,6 ms | 66,6 ms |
| Tempo acumulado de tarefas | 17,0 s | 18,2 s |
| Heap JS ao final | 12,2 MB | 12,7 MB |
| Heartbeats | 66 | 67 |
| Bytes de pedidos | 7.656 | 7.772 |
| Carregamento até pose visível | 2,43 s | 2,23 s |

Redução comprovada de 90,1% nas cópias de imagem e 45,7% nas atualizações React; **não houve ganho comprovado de FPS ou CPU na comparação curta**. Não se deve apresentar isso como eliminação do lag em aparelhos reais. O padrão reduz operações JavaScript, mas o preenchimento da tela ainda tem custo gráfico.

Cinco minutos contínuos após ajustes: 49,4 FPS médios, p95 33,4 ms, heap final 13,1 MB, 972 heartbeats (3,24/s), 112.752 bytes enviados, zero erros da cena. Sem baseline equivalente de cinco minutos, esse resultado não demonstra ganho percentual nem exclui vazamentos de memória.

Tela simulada 390×844, densidade 3, e horizontal 844×390: toque até mudança visível em 302,8 ms no último ensaio (latência de resposta controlada em 120 ms, leitura de posição a cada 180 ms). Não é tempo puro de animação. Velocidade alterou o comando enviado; animação e polling pausaram ocultos; retomada permaneceu parada; saída funcionou e não houve rolagem horizontal.

## Validação

51 testes passaram; compilação automática OK. Cena isolada confirmou toque, troca de destino, chegada, perda de foco, seleção de outro jogador e retorno ao porto. As entidades de teste existem somente nos scripts temporários, não no jogo. Servidor, regras, bens, TON Connect, colisões, preços e liquidação não foram alterados.

## Limitações

- Não realizado teste no WebView Telegram Android físico: aparelho e sessão Telegram assinada indisponíveis.
- Não verificado fluxo real com vários jogadores, atracação autenticada, combate ou reconexão de rede real.
- Testado por cinco minutos, não dez.
- Frequência e payload oficiais preservados; não implementada filtragem regional de servidor nem novo transporte multiplayer.
- Navegação segue poses aprovadas, sem previsão local: a latência de rede continua limitando a resposta visual.
- Nenhuma promessa de 60 FPS universal, melhoria de CPU ou eliminação definitiva do lag.