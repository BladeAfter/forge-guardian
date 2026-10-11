# Roadmap

- [ ] Ajustar Kraken das Profundezas, ligar chama/escudo/raio/estrela ao ataque oficial compartilhado, orientar equipe vazia e mostrar contra-ataques confirmados; preservar dano, espera e recompensas.

- [x] Navio atracado com arte náutica nova e sem renderização duplicada de modelo/reflexo; animações reutilizadas por modelo, câmera dimensionada pela cena e gestos do Telegram capturados na ilha. Desembarque e caminhada por toque conferidos em cena isolada, 21 testes passaram; confirmação no Telegram real permanece pendente.

- [x] Joystick: fila enviada imediatamente após resposta pendente e latência incluída no intervalo; 11 testes passaram, toque/soltura conferidos com respostas simuladas e compilação OK. Posições oficiais, autenticação e regras preservadas.
- [ ] Confirmar joystick no Telegram real após publicar a atualização; bloqueio: sessão móvel Telegram indisponível e publicação não solicitada.

- [x] Tutorial PT-BR v3 entregue: 67,74 s horizontal 1920×1080, música sem narração; navegação/exploração originais e captura de combate simulado, navios parados durante disparos, etapas internas pulam 1→3 por corte de aviso antigo. Mídia portuguesa registrada e game-bot implantado; 11 testes passaram. Enviado ao @MythicSeasChat mensagem 301 e administrador mensagem 21; novo fixado, antiga mensagem 299 excluída e fixação confirmada. Outros idiomas preservados; coleção atualizada; nenhuma movimentação de bens reais.

- [x] Gravação de combate naval simulado entregue: 27 s vertical 1080×1920 com áudio sintetizado sem narração; captura da UI real com respostas locais roteirizadas, tiros/vida/impactos sobrepostos e navios parados durante os disparos. Movimento e quadros revisados, zero chamadas externas e nenhum saldo alterado; PvP real permanece desativado.

- [x] Combate naval ativado nas regras oficiais: 10% de BERRIES do derrotado, teto inicial conservador de 1.000, e madeira/ferro já usados em melhoria/reparo, 5% limitado a 3 unidades por material quando saldo >=20; origem: derrotado. Configuração lida e gate válido; RPCs continuam exclusivos do servidor e 5 testes navais passaram. Sem alteração direta de saldos.
- [ ] Validar batalha real e saque no Telegram com dois jogadores autenticados; bloqueio: sessões Telegram reais indisponíveis. Equipamentos e fragmentos não incluídos, pois ainda não têm utilidade naval implementada.

- [x] Tutorial v2 com trecho ilustrado de batalha naval enviado ao @MythicSeasChat (mensagem 299) e ao administrador pelo @MythicSeasbot (mensagem 17); nova publicação fixada e tutorial antigo (mensagem 4) excluído, com confirmação do Telegram. Envio por idioma no /start preservado.

- [x] Tesouro enterrado: X no chão e baú após Abrir; pista garantida na ilha concede um mapa por aventura, consumido atomicamente no servidor para um tesouro. Caminhada/coleta/abertura conferidas em cena isolada com respostas simuladas; 21 testes passaram, compilação OK, RPCs exclusivos do servidor e auto sem bypass. Prêmios existentes preservados; não foram criados achados aleatórios no mar.
- [ ] Conferir pista → mapa → X → baú com jogador real; bloqueio: sessão móvel autenticada do Telegram indisponível. O tutorial em vídeo ainda mostra a apresentação anterior.

- [x] Acrescentar trecho ilustrado dos controles de batalha naval aos 43 tutoriais: 57,27 s com áudio, mídia registrada e bot atualizado; 13 testes passaram, URLs PT/EN/RU disponíveis. Aviso traduzido distingue ilustração de gameplay; traduções do novo trecho sem revisão humana, conferência de movimento por amostragem.
- [ ] Substituir ilustração por gravação real de batalha naval; bloqueio: PvP desativado, nenhuma batalha registrada e gravação autenticada do Telegram indisponível.

- [x] Remover acessos MYTH de carteira, compra, passe, recrutamento, mineração, doações e rendimentos; manter TON/BERRIES e histórico financeiro.
- [ ] Concluir traduções sem exceção: 698 textos aplicados em 92 telas e 161 lacunas espanhol/russo preenchidas; faltam turco, textos dinâmicos, mensagens e demais literais. Bloqueio: créditos de IA esgotados.
- [x] Executar testes gerais: 216 testes passaram; acesso público conferido com zero abas antes da autorização.
- [ ] Conferir todas as abas autenticadas e os idiomas no jogo real; bloqueio: sessão móvel Telegram real do administrador.

- [x] Liberar testes antes do lançamento exclusivamente ao administrador 8490010993 autenticado pelo Telegram; configuração administrativa confirmada, funções implantadas e oito testes passaram. Outros IDs continuam bloqueados e acesso móvel permanece obrigatório.
- [ ] Confirmar entrada antecipada e menu administrativo com a sessão real de 8490010993 no Telegram; depende da interação do administrador.

- [x] Selecionar tutorial pelo idioma informado pelo Telegram; 42 versões traduzidas e português original, incluindo russo e inglês. Quadros dos passos e duração/áudio conferidos; trilha original sem narração, captura do jogo preservada em português. Idioma sem vídeo não consome envio nem recebe vídeo diferente.
- [ ] Conferir recebimento privado no Telegram com jogador real; depende de /start real. Cobertura ainda não inclui todos os idiomas existentes.

- [x] Preparar lançamento em 12/10/2026 às 18h UTC: espera em inglês, relógio do servidor, chat, convite único por Telegram ID e ranking de chegadas verificadas; jogo carregado somente após liberação e autenticação móvel. Servidor confirmou 423 antes do lançamento e 403 para desktop; acessos antigos também bloqueados. Convites não pagam recompensas durante espera.
- [ ] Conferir fluxo real convite → /start → Mini App móvel → ranking com jogador no Telegram; requer interação real. Restrição móvel usa sinais de plataforma e aparelho, não atestado inviolável de hardware; falsificação deliberada desses sinais não pode ser excluída pela API do Telegram.

- [x] Restaurar três acessos oficiais mesmo sem dados de recompensas; links e imagens conferidos. Resgate exige confirmação atual do Telegram, incluindo is_member para restritos, e rotina privada rejeita confirmação ausente. Nove testes passaram; bot administrador nos três canais e função implantada.
- [ ] Conferir entrada e resgate com jogador real no Telegram; depende de sessão e participação reais, sem pagamentos de teste.

- [x] Tutorial publicado e fixado no @MythicSeasChat e @MythicSeasNews, ambos confirmados pelo Telegram. Envio único por jogador configurado no /start e implantado; quatro testes passaram e webhook autenticado conferido.
- [ ] Confirmar recebimento privado do tutorial no primeiro /start com jogador real; depende de interação do jogador no Telegram.

- [x] Substituir bússola por minimapa náutico graduado com ilhas, portos, direção do navio e jogadores do servidor. Ampliação/redução e joystick conferidos isoladamente; 13 testes passaram. Confirmação com jogadores reais no Telegram indisponível.

- [x] Remover emendas quadradas com água própria e bordas espelhadas; reduzir ilhas e suavizar suas margens sem mudar colisões/atracação. Treze testes passaram; cena isolada e seleção de dois jogadores simulados conferidas, assim como envio/parada do joystick. Mundo aberto e jogadores reais retornados pelo servidor preservados; confirmação multijogador no Telegram requer sessões reais.

- [ ] Navegação Telegram: proteção contra gestos nativos, envio urgente sem adiamento por novos toques, retomada de conexão e retenção da posição aprovada implementados; 15 testes e arraste/soltura com respostas simuladas passaram. Bloqueios: atualizar a versão publicada e verificar com sessão Telegram real; causa no aparelho ainda não confirmada.

- [x] Proteger margens da ilha e píer com varredura de movimento e recuperação da última posição segura; caminhada, salto/esquiva na borda e embarque conferidos em cena isolada, 17 testes passaram. Navegação e recompensas preservadas; falta confirmação no Telegram real.

- [x] Boas-vindas ilustradas no /start de @MythicSeasbot com botão de iniciar; webhook ativado e resposta autenticada conferida, chamadas sem segredo rejeitadas. Permissão nativa de mensagens solicitada uma vez por sessão; recibos com valor, carteira, data UTC, hash e Tonviewer. Aceitação e abertura reais ainda precisam de conferência no Telegram.

- [x] Reduzir trabalho gráfico no desembarque e caminhada: câmera interpolada, cena memoizada sem sombras dinâmicas, cordas reutilizadas e colisores agrupados; desembarque mais ágil. Caminhada de ida/volta e desembarque conferidos isoladamente, 10 testes passaram. Fluidez no aparelho real via Telegram ainda não validada.

- [x] Fazer o personagem da arena e seu retrato acompanharem o pirata selecionado, com cinco artes apoiadas no chão e composição portuária preservada. Troca visual, retrato correspondente, joystick e callbacks oficiais conferidos isoladamente; 27 testes passaram. Validação real no Telegram pendente.

- [x] Renovar a aba Kraken conforme a referência portuária: duas artes IA inéditas, Kraken proporcional, capitão no chão, HUD limpa e controles circulares. Artes, joystick, callbacks de golpe/equipamento/ranking e poderes bloqueados conferidos isoladamente; 24 testes passaram. Validação real dentro do Telegram indisponível.

- [x] Limpar e compactar cards do passe, remover fundo dos cards e nível repetido, destacar nome/quantidade e liberar rolagem por toque sobre as recompensas. Arraste sem abrir detalhes, chegada ao nível 30 e callback oficial de resgate conferidos isoladamente; compilação automática OK. Validação com conta real dentro do Telegram indisponível.

- [x] Remover faixa clara do píer, dobrar tamanho dos piratas e aproximar câmera; substituir cenário físico antigo por piso nivelado e obstáculos traçados em cada mapa ilustrado. Dez testes passaram; desembarque, conversa, bloqueio na palmeira inclusive com salto/esquiva e retorno ao navio conferidos em cena isolada. Compilação automática OK. Sessão real do Telegram não disponível para validação completa.

- [x] Suavizar navio na Grand Line entre posições aprovadas, sem previsão de progresso; remover deslocamento vertical artificial e adicionar contato do casco/espuma animada. Onze testes passaram; joystick, frenagem e navegação compartilhada simulada conferidos no navegador. Sessão real do Telegram não disponível para confirmação.

- [x] Arena ajustada à referência: novas artes IA de capitão/capitã apoiados no chão, dragão proporcional à direita, cenário visível, tripulação vertical e ações circulares. Ataque oficial, poderes bloqueados, joystick, esquiva, ranking e expansão conferidos isoladamente; equivalência exata e sessão Telegram real não verificadas.

- [x] Gráfico do mercado refinado e compactado conforme referência: curva suave, preenchimento luminoso sutil, dias selecionáveis e moedas preservadas; conferência visual isolada sem cortes. Dados pessoais e exemplos explicitamente identificados preservados; sessão Telegram real não verificada.

- [x] Perfil renovado conforme referência premium: cenário naval, título/avatar destacados, personagem grande com seleção vertical, diário ao lado e canais oficiais. Imagens, seleção, passe, links e ausência de cortes conferidos isoladamente; dados e callbacks preservados. Conferência dentro do Telegram depende de sessão assinada.

- [x] Restaurar oceano ilustrado em canvas leve, corrigir seta de saída independente da rede, limitar desenho a 30fps e reduzir resolução/sombras na ilha; ocultar Veteran Vault em passe, tripulação, inventário e equipamentos. Passe renovado com seis artes IA náuticas e imagem de viagem; 15 testes passaram e seta, atracação, travessia de região, imagens e callback de resgate conferidos isoladamente. Entregas, tipos e preços oficiais preservados: peças de navios/mapas com nova utilidade não implementados, dependem de regras e catálogo oficiais. Sessão Telegram assinada indisponível, experiência completa real e eliminação do lag em aparelho não verificadas.

- [ ] Finalizar entrega dos avisos no @MythicSeasPayout: @MythicSeasbot confirmado como administrador, exemplo identificado como teste publicado; avisos compactos com carteira, Tonviewer e #MythicSeasbot #payout. Fila privada e proteção contra duplicidade preservadas. Entrega automática de um pagamento real ainda depende de transação elegível; indexador e saques automáticos antigos continuam pausados.

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
