# Roadmap

- [ ] Reduzir travamentos no desembarque e na caminhada, com câmera interpolada, cena leve e desembarque mais ágil; preservar mapa e colisões.

- [x] Fazer o personagem da arena e seu retrato acompanharem o pirata selecionado, com cinco artes apoiadas no chão e composição portuária preservada. Troca visual, retrato correspondente, joystick e callbacks oficiais conferidos isoladamente; 27 testes passaram. Validação real no Telegram pendente.

- [x] Renovar a aba Kraken conforme a referência portuária: duas artes IA inéditas, Kraken proporcional, capitão no chão, HUD limpa e controles circulares. Artes, joystick, callbacks de golpe/equipamento/ranking e poderes bloqueados conferidos isoladamente; 24 testes passaram. Validação real dentro do Telegram indisponível.

- [x] Limpar e compactar cards do passe, remover fundo dos cards e nível repetido, destacar nome/quantidade e liberar rolagem por toque sobre as recompensas. Arraste sem abrir detalhes, chegada ao nível 30 e callback oficial de resgate conferidos isoladamente; compilação automática OK. Validação com conta real dentro do Telegram indisponível.

- [x] Remover faixa clara do píer, dobrar tamanho dos piratas e aproximar câmera; substituir cenário físico antigo por piso nivelado e obstáculos traçados em cada mapa ilustrado. Dez testes passaram; desembarque, conversa, bloqueio na palmeira inclusive com salto/esquiva e retorno ao navio conferidos em cena isolada. Compilação automática OK. Sessão real do Telegram não disponível para validação completa.

- [x] Suavizar navio na Grand Line entre posições aprovadas, sem previsão de progresso; remover deslocamento vertical artificial e adicionar contato do casco/espuma animada. Onze testes passaram; joystick, frenagem e navegação compartilhada simulada conferidos no navegador. Sessão real do Telegram não disponível para confirmação.

- [x] Arena ajustada à referência: novas artes IA de capitão/capitã apoiados no chão, dragão proporcional à direita, cenário visível, tripulação vertical e ações circulares. Ataque oficial, poderes bloqueados, joystick, esquiva, ranking e expansão conferidos isoladamente; equivalência exata e sessão Telegram real não verificadas.

- [x] Gráfico do mercado refinado e compactado conforme referência: curva suave, preenchimento luminoso sutil, dias selecionáveis e moedas preservadas; conferência visual isolada sem cortes. Dados pessoais e exemplos explicitamente identificados preservados; sessão Telegram real não verificada.

- [x] Perfil renovado conforme referência premium: cenário naval, título/avatar destacados, personagem grande com seleção vertical, diário ao lado e canais oficiais. Imagens, seleção, passe, links e ausência de cortes conferidos isoladamente; dados e callbacks preservados. Conferência dentro do Telegram depende de sessão assinada.

- [x] Restaurar oceano ilustrado em canvas leve, corrigir seta de saída independente da rede, limitar desenho a 30fps e reduzir resolução/sombras na ilha; ocultar Veteran Vault em passe, tripulação, inventário e equipamentos. Passe renovado com seis artes IA náuticas e imagem de viagem; 15 testes passaram e seta, atracação, travessia de região, imagens e callback de resgate conferidos isoladamente. Entregas, tipos e preços oficiais preservados: peças de navios/mapas com nova utilidade não implementados, dependem de regras e catálogo oficiais. Sessão Telegram assinada indisponível, experiência completa real e eliminação do lag em aparelho não verificadas.

- [ ] Finalizar entrega dos avisos no @MythicSeasPayout: duas artes IA criadas e disponíveis, fila privada ligada a depósitos creditados e saques pagos, proteção de duplicidade e recuperação de falhas implantadas; três testes passaram. Bloqueio confirmado pelo Telegram: @MythreonBot não consegue acessar os membros do canal; adicioná-lo como administrador com permissão de publicar. Nenhuma transação falsa foi publicada; envio real ainda não verificado. Indexador e saques automáticos antigos continuam pausados.

- [x] Recuperar o mapa ilustrado da ilha e caracterizar o personagem com tricórnio, faixa vermelha, insígnia e tapa-olho; movimento, desembarque, conversa e retorno ao navio conferidos em cena isolada. 16 testes passaram, compilação automática OK; ações autenticadas no Telegram não verificadas por falta de sessão Telegram assinada.

- [x] Ampliar Grand Line para oceano contínuo sem bordas: limites removidos no cliente e na validação oficial, regiões determinísticas com colisão compartilhada e origem flutuante, horizonte 3D, navio GLB, esteira e balanço, aceleração/desaceleração local, zoom sem revelar o mapa todo e retorno às coordenadas da ilha visitada. Navegação além dos antigos limites, mudança de região, joystick e callback de atracação verificados em cena isolada; 161 testes passaram, compilação automática OK. Fluxo real autenticado no Telegram não verificado por falta de sessão Telegram assinada; novas regiões reutilizam as cinco aventuras oficiais, sem criar prêmios. Modelos/skins personalizados de oceano ainda precisam de paridade completa com o estaleiro; o navio 3D usa o GLB pirata existente.

- [x] Corrigir porto 3D: navio na água ao lado do píer sem interseção; berço aprofundado, linha d'água, balanço, amarras, reflexo estilizado, ondas e passarela animada. Atracação, desembarque contínuo até a praia, conversa e retorno ao convés verificados em cena isolada; dez testes passaram, compilação automática OK. Fluxo autenticado no Telegram não verificado; regras e recompensas preservadas.

- [x] Exploração inteiramente 3D substituída pela preferência posterior do usuário: mapa ilustrado com movimento e desembarque preservados; não continuar acabamento de cenário low-poly ou câmera third-person.
  - Base 3D implementada com Three.js/R3F/Rapier, modelos GLB CC0 com texturas incorporadas, terreno volumétrico, água animada, navio atracado/passarela, câmera orbital com zoom/colisão e personagens animados. Desembarque, corrida/sprint, diálogo e callback de embarque conferidos em cena isolada; renderização final sem exceções nem requisições falhas. 157 testes passaram; compilação automática sem erros.
  - Pendente: acabamento AAA, modelos/animações de alta fidelidade, ajuste fino dos pés/IK, profundidade de campo, vegetação densa, reações físicas aos ataques e poderes oficiais. Combate é apresentação dos resultados existentes do servidor no mesmo cenário, não combate livre autoritativo; recompensas e aventuras autenticadas no Telegram ainda não verificadas. Ilha usa base low-poly, não qualidade console prometida.

- [x] Excluir raridades Ancestral, NFT Exclusivo e Celestial de heróis e mascotes: catálogos e vínculos removidos, contagens restantes dessas raridades em zero; filtros e chances limpos, recriação bloqueada por triggers nas migrações 0112–0113, Admin Bot implantado. Proteção de pagamentos preservada; 24 testes passaram. Sessão Telegram real não verificada.

- [x] Refazer Tripulação como convés vivo com arte IA, capitão, membros selecionáveis, câmera e ficha individual; remover Fusão, Inventário e filtros desta tela. Seleção, progresso de XP, detalhes, turnos e fechamento verificados isoladamente; 24 testes passaram. Equipamentos oficiais preservados.
  - Pendente: treino mostra progresso oficial, não concede XP por clique; Haki, frutas, energia e novos poderes indisponíveis. Bônus de funções dependem de regras oficiais; rótulos piratas são cosméticos. Ações reais de equipamento no Telegram não verificadas por falta de sessão assinada.

- [x] Refazer a apresentação da arena do chefe global com duas artes IA, capitão do perfil, mascote físico, tripulação lateral, joystick, golpe animado, esquiva visual, fases visuais e controles compactos. Corrigidos cortes dos controles e sobreposição do mascote na inspeção visual; 24 testes passaram e fluxo isolado conferido no navegador. Dano, recompensas, equipe e tempos oficiais preservados.
  - Pendente: Haki, frutas, energia, ultimate, combos com dano e esquiva real não existem nas regras oficiais; poderes permanecem bloqueados, movimento/esquiva/fases são cosméticos. Combate real no Telegram não verificado por falta de sessão Telegram assinada.

- [x] Liberar o acesso após o reinício: manutenção e bloqueio de reset desativados com autorização do usuário; marco financeiro do reinício preservado, saques automáticos e PvP naval não reativados. Carregamento real das telas no Telegram ainda não verificado.

- [ ] Sistema de navios: seis modelos e skins, customização física, presença de jogadores reais, combate naval autoritativo, abordagem, progressão e reparos com materiais.
  - Seis modelos IA, seis estilos, bandeira/proa/decoração/esteira no canvas e estaleiro; presença por polling autenticado, manobra validada, canhões de bordo, habilidade, fuga, dano, XP, reparos e transferência atômica de BERRIES/materiais implementados. Onze testes passaram e estaleiro/navegação verificados isoladamente.
  - Bloqueios: sessão real do Telegram indisponível para testes; manutenção/reset já desativados. Percentual, origem e limites do saque de BERRIES/itens não definidos, PvP permanece desativado. Abordagem aplica dano naval validado, mas combate físico de personagens nos conveses ainda não implementado. Materiais de reparo padrão: 5 madeira e 3 ferro por nível, configuráveis.

- [x] Criar desembarque animado, caminhada com joystick, cinco cenários de ilhas, personagem compartilhado com perfil, NPC físico, encontros baseados nos nós oficiais e embarque de retorno. Oito testes passaram; atracação, desembarque, caminhada, conversa e retorno verificados em cena isolada.
  - Recompensas e aventuras autenticadas no Telegram não verificadas durante a manutenção. Equipamentos, itens de mascotes e novas categorias de tesouro dependem de catálogos e regras oficiais ainda não existentes no Realm; nenhum prêmio foi inventado. Escolha visual masculina/feminina salva neste dispositivo; sincronização entre dispositivos não implementada.

- [x] Trocar as setas da Grand Line por joystick arrastável; movimento com captura fora da base, parada ao soltar e retorno ao centro verificados na cena isolada, com aparência conferida em tela grande e pequena. Acesso real no Telegram não verificado.

- [x] Substituir ovos e sua loja por Baús Misteriosos de mascotes: cinco artes inéditas, loja e carteira renovadas, inventário e recompensas com nomes de baús, abertura com tampa animada. Dez testes passaram; imagens, seleção, revelação e retorno verificados isoladamente. Compras reais no Telegram não verificadas durante a manutenção do jogo; preços, chances e entregas preservados.

- [x] Corrigir a abertura da Grand Line: oceano imediato sem depender do carregamento das atividades; saldo existente repassado e validação do servidor mantida ao atracar. Cena verificada isoladamente sem resposta das atividades; quatro testes de navegação passaram. Acesso real no Telegram não verificado.

- [ ] Varrer as telas ativas e substituir referências visuais e textos do jogo antigo, preservando identificadores e regras.
  - Catálogo visual central, construções e personagens base, oficina naval, exploração, cavernas e batalhas renovados com artes piratas; rótulos Grand Line, Duelos do Convés e BERRIES aplicados. Doze artes carregadas no navegador; atividades autenticadas no Telegram não verificadas. Hashtags, handles, storage keys, memos e RPCs preservados; materiais e construções fornecidos pelo servidor ainda exigem auditoria visual.

- [x] Remover da interface packs, pop-ups promocionais, staking e acessos Tower/Familiar Hunt/Expeditions do jogo antigo; imports e renderizações removidos das telas, visual pirata preservado. Acesso real pelo Telegram não verificado.

- [x] Executar reinício total: jogadores, heróis, pets, equipamentos, anúncios, leilões, clãs e registros financeiros com contagens verificadas em zero; catálogos preservados e processos automáticos pausados.
- [x] Renomear Mercado para Bazar do Porto e Leilão para Pregão dos Piratas; remover Troca Privada da interface sem mudar compras e lances. Verificação visual isolada inconclusiva; acesso real pelo Telegram não verificado.

- [x] Criar a primeira experiência navegável de GRAND LINE: oceano, cinco ilhas físicas, navios animados, garrafa com pista, passagem secreta e atracação nas atividades existentes; navegação, descoberta e callbacks verificados isoladamente. Sem novas recompensas ou batalhas navais; acesso real pelo Telegram não verificado.

- [x] Renovar o tema completo da Pool Comunitária e suas abas sem alterar valores, regras ou ações; arte, paleta, seleção de Eventos e retorno verificados isoladamente.

- [x] Renovar o Mercado com visão de negociações, gráfico, ranking e histórico, mantendo a manutenção e identificando exemplos; gráficos, moeda e expansão testados isoladamente, sem pagamentos.

- [x] Refazer o Perfil como ficha de capitão Mythic Seas, preservando dados, passe e recompensas oficiais; arte e callback do passe verificados isoladamente, sem compras reais.

- [x] Substituir ícones dos três contratos de recrutamento por imagens padronizadas, preservando preços e callbacks; três artes carregadas e cliques 1/5/10 verificados isoladamente, sem compras reais.

- [x] Excluir bens NFT e inventários antigos no reinício total; a preservação financeira anterior foi substituída pelo reset executado.

- [x] Trocar a marca exibida para Mythic Seas nos textos da interface, metadados, políticas, manifesto da carteira e mensagens das funções do bot; preservar URLs, pagamentos, hashtags e identificadores internos.

- [x] Substituir artes antigas restantes de pets e heróis pelas novas artes piratas, preservando inventários e regras. Catálogos: 120 pets, 278 heróis, 12 modelos Sub-NFT e 124.408 imagens de heróis possuídos atualizados; 47 testes passaram e as 13 artes carregaram.

- [x] Remover Canais Parceiros e calendário de recompensas da interface e seus acessos, preservando bens recebidos.

- [x] Refazer os indicadores BERRIES e TON como bilhetes náuticos com artes inéditas, sem alterar saldos ou acesso à carteira.

- [x] Redesenhar a Loja de Heróis como recrutamento de tripulação pirata anime, preservando preços, chances e pagamentos; arte e botões verificados isoladamente na prévia, sem executar compras reais no Telegram.

- [x] Verificar erros Features/Index: arquivos e chamadas ausentes na versão atual; erros não reproduzidos na abertura da prévia.
- [x] Executar reset: contas do jogo, saldos, progresso, bens e históricos removidos; estrutura, configurações e catálogos preservados.
- [ ] Criar artes inéditas por IA para os novos pets e heróis e substituir referências antigas conforme o novo catálogo.
  - Oito artes inéditas de pets e cinco de heróis criadas; agora aplicadas a todos os catálogos, inclusive NFTs, celestiais e exclusivos, sem apagar dados. As formas de evolução compartilham a nova arte base; artes individuais para cada evolução ainda não foram criadas.
  - Validação anterior: 56 testes de pets, fusão, passe e combate passaram. Reset executado posteriormente com indexador TON e saques automáticos pausados.
- [ ] Tratar os três alertas de acesso a históricos/configuração durante o reset, preservando acesso exclusivo do servidor aos dados privados.

- [x] Corrigir o erro de tipagem da nova raridade Celestial no preview.
- [x] Aplicar identidade visual pirata anime original em todo o jogo sem alterar sistemas ou fluxos.
- [x] Trocar a apresentação de FC para BERRIES e aplicar uma moeda pirata original sem alterar a economia.
- [x] Ocultar os cartões de NFT, breeding, roleta e eventos promocionais indicados, preservando os sistemas.

- [x] Refazer a tela de duelos como Duelos do Convés: nova arte pirata, indicadores compactos, controles compartilhados e navegação em português; cabeçalho e botão de ingressos verificados isoladamente. Batalha real pelo Telegram não verificada.
