# Reset completo e novo catálogo pirata

## Resultado solicitado
- Reiniciar o jogo publicado e a prévia, que compartilham os mesmos dados.
- Excluir as contas do jogo, saldos, progresso, inventários, NFTs e históricos, inclusive financeiros e de auditoria, conforme confirmado.
- Criar por IA artes inteiramente novas de pets e heróis inspirados em criaturas e aventuras de One Piece, sem reutilizar nem editar imagens antigas.
- Preservar a vila pirata atual e os sistemas do jogo.

## Execução
1. Mapear as dependências entre contas, compras, saques, clãs, mercados e catálogos. Verificar trabalhos automáticos que poderiam recriar dados ou executar pagamentos durante o reset.
2. Preparar um novo catálogo compacto: oito criaturas inéditas e cinco heróis piratas, com artes individuais transparentes, criadas do zero. Retirar os antigos pets, suas evoluções e catálogos NFT de pets, heróis e equipamentos, incluindo ofertas que dependam deles; conservar os sistemas disponíveis para futura configuração.
3. Interromper operações concorrentes antes da limpeza. Apagar os registros confirmados em uma operação transacional com lista explícita de tabelas e verificação dos efeitos. Não apagar a estrutura, funções do jogo ou configurações essenciais do bot administrador.
4. Registrar o novo catálogo no servidor e atualizar todas as telas, recompensas, invocações e referências para não conceder itens antigos nem exibir imagens ausentes.
5. Remover os arquivos de arte antigos somente após substituir suas referências. Não excluir objetos compartilhados do armazenamento sem verificar usos anteriores.
6. Corrigir as permissões de históricos de ovos/roleta e verificar a configuração da loja da torre. Dados privados ficarão acessíveis apenas pelo servidor que valida o jogador Telegram.
7. Verificar cadastro de um jogador novo, inventário inicial, catálogo, invocação e imagens; conferir que os registros antigos foram removidos e que o bot administrador continua autorizado.

## Limites e consequências
- As 9.855 contas encontradas e seus bens serão apagados; o histórico de compras e saques também deixará de existir no jogo. Nada foi apagado ainda.
- O reset não cancela transferências já realizadas na rede TON, não destrói NFTs externos e não apaga contas pessoais do Telegram.
- Contas de autenticação gerenciadas, caso existam, exigem um mecanismo administrativo suportado; não serão apagadas por alterações diretas em tabelas protegidas.
- A limpeza não possui reversão garantida. Este plano não inclui cópia dos históricos, pois foi solicitado apagá-los também.

## Detalhes técnicos
- Manter a identidade Telegram validada no servidor e o Super Admin existente, sem privilégios no cliente.
- Usar ferramentas de dados para exclusão de registros, não migrações destinadas apenas a apagar dados. Mudanças de políticas passam pela ferramenta de migração.
- Centralizar referências visuais em `gameAssets.ts`; manter regras de gameplay independentes do tema.
- Os arquivos Features.tsx e pages/Index.tsx citados no relatório não existem nesta versão; não criar correções fictícias para eles.