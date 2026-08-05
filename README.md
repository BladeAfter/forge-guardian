# Forge Guardian

Analise o projeto completo do Forge Village e implemente uma integração total com Supabase, além de um painel administrativo controlado por um bot do Telegram.

Não recrie o jogo do zero.

Preserve:

- interface atual;
- sistema de heróis;
- sistema de pets;
- ovos;
- PvP;
- chefe;
- calendário;
- missões;
- passe;
- pool;
- carteira TON;
- saldo FC;
- convites;
- rankings;
- autenticação Telegram;
- TanStack Query;
- TonConnect;
- navegação atual.

Toda informação importante do jogo deve ficar persistida no Supabase.

==================================================
ADMINISTRADOR PRINCIPAL
==================================================

O administrador principal é o Telegram ID:

8118569391

Somente esse Telegram ID deve receber acesso total inicialmente.

Criar uma variável segura no backend:

TELEGRAM_SUPER_ADMIN_ID=8118569391

Não deixar esse valor como única proteção no frontend.

Toda ação administrativa deve validar o Telegram ID no backend.

==================================================
OBJETIVO
==================================================

Criar duas formas de administração:

1. Painel administrativo dentro do jogo;
2. Bot administrativo no Telegram.

As duas formas devem usar o mesmo backend, as mesmas permissões e os mesmos logs.

Tudo que existe no jogo deve poder ser administrado, respeitando segurança, validações e histórico.

==================================================
SUPABASE
==================================================

Conectar todo o jogo ao Supabase.

Não usar localStorage como fonte oficial para:

- saldo;
- inventário;
- heróis;
- pets;
- ovos;
- níveis;
- XP;
- compras;
- passes;
- pool;
- missões;
- rankings;
- convites;
- banimentos;
- carteira;
- depósitos;
- saques;
- logs;
- recompensas;
- calendário;
- PvP;
- chefe.

O localStorage pode ser usado apenas para preferências visuais temporárias.

==================================================
SEGURANÇA DO SUPABASE
==================================================

Nunca colocar no frontend:

- SUPABASE_SERVICE_ROLE_KEY;
- token do bot;
- chave privada;
- seed;
- segredo administrativo;
- credencial de carteira;
- API key sensível.

Usar:

- anon key somente no frontend;
- service role somente no backend;
- Edge Functions ou server functions;
- RLS;
- autenticação validada;
- roles administrativas.

==================================================
AUTENTICAÇÃO TELEGRAM
==================================================

Validar Telegram initData no backend.

Não confiar apenas em:

window.Telegram.WebApp.initDataUnsafe

Criar função centralizada:

validateTelegramInitData()

Ela deve:

- validar hash;
- validar auth_date;
- validar user.id;
- rejeitar dados expirados;
- localizar ou criar profile;
- retornar Telegram ID como string.

==================================================
SISTEMA DE ROLES
==================================================

Criar roles:

- super_admin
- admin
- moderator
- support
- finance
- content_manager
- player

O Telegram ID 8118569391 deve receber:

super_admin

O super_admin pode:

- acessar tudo;
- conceder roles;
- remover roles;
- editar configurações;
- administrar economia;
- administrar conteúdo;
- administrar jogadores;
- administrar pagamentos;
- visualizar logs.

==================================================
TABELAS PRINCIPAIS
==================================================

Antes de criar qualquer tabela, localize as estruturas existentes.

Reutilize e adapte quando possível.

Garantir tabelas equivalentes para:

profiles
admin_roles
admin_permissions
admin_audit_logs
game_settings
economy_settings
heroes
player_heroes
pets
player_pets
pet_eggs
player_inventory
missions
player_missions
daily_calendar
calendar_claims
season_passes
season_pass_rewards
player_season_passes
pvp_profiles
pvp_teams
pvp_battles
pvp_rankings
bosses
boss_combats
pool_settings
pool_seasons
pool_points
pool_rewards
referrals
referral_commissions
wallet_connections
wallet_deposits
wallet_withdrawals
ton_transactions
player_balances
notifications
bans
admin_commands
admin_command_sessions

==================================================
PERFIL DO JOGADOR
==================================================

profiles deve conter:

- id uuid;
- telegram_id text unique;
- username;
- first_name;
- last_name;
- photo_url;
- role;
- status;
- fc_balance;
- wallet_address;
- is_banned;
- ban_reason;
- banned_until;
- created_at;
- updated_at;
- last_login_at.

Telegram ID deve ser tratado como string.

==================================================
PAINEL ADMINISTRATIVO NO JOGO
==================================================

Criar rota fullscreen:

/admin

Ela só pode abrir para usuários autorizados.

Mostrar:

- resumo do jogo;
- jogadores;
- economia;
- heróis;
- pets;
- ovos;
- missões;
- calendário;
- PvP;
- chefe;
- pool;
- passe;
- convites;
- carteira;
- depósitos;
- saques;
- logs;
- configurações.

==================================================
BOT ADMINISTRATIVO DO TELEGRAM
==================================================

Criar bot administrativo integrado ao backend.

O bot deve receber comandos somente no privado.

Validar obrigatoriamente:

- Telegram ID;
- role;
- permissão;
- estado da sessão;
- expiração;
- confirmação para ações críticas.

Usuário principal permitido inicialmente:

8118569391

Usuários não autorizados recebem:

“Acesso negado.”

==================================================
TOKEN DO BOT
==================================================

Usar variável de ambiente:

TELEGRAM_ADMIN_BOT_TOKEN

Nunca salvar o token:

- no frontend;
- no GitHub;
- em código público;
- em arquivos versionados;
- em logs.

==================================================
COMANDOS PRINCIPAIS DO BOT
==================================================

Criar menu com botões inline.

Comando inicial:

/admin

Mostrar:

- Jogadores
- Economia
- Heróis
- Pets
- Ovos
- Missões
- Calendário
- PvP
- Chefe
- Pool
- Passe
- Convites
- Carteiras
- Depósitos
- Saques
- Logs
- Configurações

==================================================
ADMINISTRAR JOGADORES
==================================================

Permitir:

- buscar por Telegram ID;
- buscar por username;
- buscar por nome;
- visualizar perfil;
- visualizar saldo;
- visualizar heróis;
- visualizar pets;
- visualizar carteira;
- visualizar depósitos;
- visualizar saques;
- visualizar convites;
- visualizar banimentos;
- visualizar histórico.

Comandos:

/player 8118569391

/player @username

/balance 8118569391

==================================================
SALDO FC
==================================================

Permitir:

- adicionar FC;
- remover FC;
- definir saldo;
- bloquear saldo;
- desbloquear saldo;
- visualizar histórico.

Exemplos:

/add_fc 8118569391 100000

/remove_fc 8118569391 50000

/set_fc 8118569391 250000

Nunca alterar saldo sem:

- transação;
- motivo;
- log;
- confirmação;
- idempotência.

==================================================
DEPÓSITOS E SAQUES TON
==================================================

Permitir:

- listar depósitos pendentes;
- visualizar depósito;
- confirmar;
- rejeitar;
- marcar fraude;
- listar saques;
- aprovar saque;
- rejeitar saque;
- marcar como processado;
- salvar tx_hash;
- visualizar carteira do usuário.

Comandos:

/deposits_pending

/withdrawals_pending

/approve_withdrawal ID

/reject_withdrawal ID motivo

Não enviar TON diretamente pelo bot sem uma camada segura de assinatura.

Não armazenar seed ou chave privada do Tesouro no bot.

Se houver saque automático, usar serviço isolado e seguro.

==================================================
CARTEIRAS CONECTADAS
==================================================

Permitir:

- listar carteiras;
- buscar endereço;
- visualizar usuário vinculado;
- bloquear carteira;
- desbloquear carteira;
- identificar múltiplas contas;
- visualizar histórico de transações.

Não mostrar seed ou chave privada.

==================================================
BANIR E DESBANIR
==================================================

Comandos:

/ban TELEGRAM_ID motivo

/ban_until TELEGRAM_ID DATA motivo

/unban TELEGRAM_ID

Ao banir:

- bloquear login;
- bloquear PvP;
- bloquear saque;
- bloquear compra;
- bloquear coleta;
- manter dados para auditoria;
- enviar notificação.

Ação precisa de confirmação.

Exemplo:

“Confirmar banimento de 8118569391?”

[CONFIRMAR]
[CANCELAR]

==================================================
GERENCIAMENTO DE HERÓIS
==================================================

O bot deve permitir:

- listar heróis;
- criar herói;
- editar herói;
- ativar;
- desativar;
- remover do catálogo;
- alterar nome;
- alterar imagem;
- alterar raridade;
- alterar ATK;
- alterar HP;
- alterar crescimento;
- alterar arquétipo;
- alterar habilidade;
- alterar disponibilidade;
- entregar herói para jogador;
- remover herói de jogador.

Comandos:

/heroes

/create_hero

/edit_hero HERO_ID

/give_hero TELEGRAM_ID HERO_ID

/remove_player_hero PLAYER_HERO_ID

==================================================
UPLOAD DE IMAGENS
==================================================

Permitir enviar imagem pelo próprio bot.

Fluxo:

1. admin escolhe “Criar Herói”;
2. informa nome;
3. informa raridade;
4. informa atributos;
5. envia imagem;
6. backend valida arquivo;
7. salva no Supabase Storage;
8. retorna URL;
9. cria herói;
10. mostra preview;
11. pede confirmação.

Tipos permitidos:

- PNG;
- JPG;
- WEBP.

Limites:

- tamanho máximo configurável;
- validar MIME;
- gerar nome único;
- não confiar na extensão;
- rejeitar arquivos executáveis.

==================================================
GERENCIAMENTO DE PETS
==================================================

Permitir:

- criar pet;
- editar pet;
- remover;
- ativar/desativar;
- mudar nome;
- mudar imagem;
- mudar raridade;
- mudar benefícios;
- mudar habilidades;
- mudar XP;
- mudar custo;
- mudar nível máximo;
- mudar estágio;
- entregar pet;
- remover pet;
- alterar fragmentos.

Comandos:

/pets

/create_pet

/edit_pet PET_ID

/give_pet TELEGRAM_ID PET_ID RARITY

/remove_player_pet PLAYER_PET_ID

==================================================
NÍVEL E XP DOS PETS
==================================================

Permitir configurar:

- XP necessário;
- custo de alimentação;
- XP por comida;
- custo de evolução;
- multiplicador por raridade;
- nível máximo;
- estágios visuais.

Permitir editar individualmente:

- nível;
- XP;
- estágio;
- ativo/inativo.

Todas as mudanças devem gerar log.

==================================================
GERENCIAMENTO DE OVOS
==================================================

Permitir:

- criar ovo;
- editar ovo;
- remover ovo;
- mudar nome;
- mudar imagem;
- alterar preço em FC;
- alterar preço em TON;
- alterar chances;
- definir pets elegíveis;
- definir limite;
- ativar/desativar;
- entregar ovo;
- remover ovo.

Comandos:

/eggs

/create_egg

/edit_egg EGG_ID

/give_egg TELEGRAM_ID EGG_ID QUANTITY

As chances devem totalizar exatamente 100%.

==================================================
MISSÕES
==================================================

Permitir:

- criar missão;
- editar missão;
- remover;
- ativar/desativar;
- alterar recompensa;
- alterar XP;
- alterar objetivo;
- alterar frequência;
- definir diária;
- semanal;
- social;
- evento.

Comandos:

/missions

/create_mission

/edit_mission MISSION_ID

==================================================
CALENDÁRIO
==================================================

Permitir:

- editar cada um dos 30 dias;
- alterar FC;
- alterar baú;
- alterar ovo;
- alterar item;
- ativar/desativar;
- resetar ciclo;
- visualizar claims.

==================================================
PASSE DA TEMPORADA
==================================================

Permitir:

- criar temporada;
- encerrar temporada;
- alterar data;
- alterar preço;
- alterar XP por nível;
- alterar recompensas;
- alterar herói exclusivo;
- alterar Ovo Mítico;
- alterar selo;
- entregar passe;
- remover passe;
- visualizar compras.

==================================================
PVP
==================================================

Permitir:

- ativar/desativar PvP;
- alterar tickets;
- alterar regeneração;
- alterar recompensas;
- alterar troféus;
- alterar ligas;
- resetar temporada;
- visualizar batalhas;
- visualizar ranking;
- remover batalha inválida;
- banir jogador suspeito;
- editar configuração de matchmaking.

Não permitir alterar manualmente o vencedor de uma batalha concluída sem criar registro de correção.

==================================================
CHEFE
==================================================

Permitir:

- alterar nome;
- alterar imagem;
- alterar HP;
- alterar ATK;
- alterar recompensa;
- alterar intervalo de ataque;
- alterar tempo;
- resetar chefe;
- criar novo chefe;
- visualizar dano por jogador;
- alterar progressão.

==================================================
POOL EM TON
==================================================

Permitir:

- visualizar saldo da pool;
- adicionar TON manualmente;
- remover TON manualmente;
- alterar pontos mínimos;
- alterar regras;
- alterar percentuais;
- alterar data de distribuição;
- alterar horário;
- pausar;
- cancelar;
- iniciar distribuição;
- visualizar ranking;
- visualizar elegíveis;
- visualizar vencedores;
- corrigir prêmio.

Comandos:

/pool

/pool_balance

/pool_set_date YYYY-MM-DD HH:mm

/pool_distribute

A distribuição deve exigir confirmação dupla.

==================================================
RANKINGS
==================================================

Permitir:

- visualizar ranking PvP;
- ranking Pool;
- ranking de convites;
- ranking de chefe;
- resetar ranking;
- excluir conta fraudulenta;
- recalcular ranking;
- alterar temporada.

==================================================
CONVITES
==================================================

Permitir:

- visualizar rede;
- buscar indicador;
- alterar configuração;
- corrigir vínculo somente como super_admin;
- alterar percentuais;
- visualizar comissões;
- bloquear comissão;
- reverter comissão indevida.

Toda alteração de vínculo precisa de motivo.

==================================================
CONFIGURAÇÕES GERAIS
==================================================

Permitir editar pelo bot:

- conversão FC/TON;
- depósito mínimo;
- saque mínimo;
- taxa de saque;
- limite diário;
- preço dos ovos;
- preço dos passes;
- XP;
- custos;
- recompensas;
- chances;
- cooldowns;
- textos;
- datas;
- status de manutenção.

==================================================
FLUXO CONVERSACIONAL DO BOT
==================================================

Não exigir comandos longos para tudo.

Usar sessões com botões.

Exemplo:

Admin toca:

Heróis

Bot responde:

- Criar
- Editar
- Desativar
- Entregar
- Remover
- Voltar

Admin escolhe Criar.

Bot pergunta:

1. Nome
2. Raridade
3. Arquétipo
4. ATK
5. HP
6. Imagem
7. Habilidade
8. Confirmar

Salvar sessão no backend com expiração.

==================================================
CONFIRMAÇÃO DE AÇÕES CRÍTICAS
==================================================

Exigir confirmação para:

- banir;
- desbanir;
- remover saldo;
- excluir item;
- remover herói;
- remover pet;
- alterar pool;
- distribuir TON;
- aprovar saque;
- rejeitar saque;
- resetar ranking;
- resetar temporada;
- alterar conversão;
- conceder admin.

A confirmação deve mostrar antes/depois.

==================================================
AUDITORIA
==================================================

Criar admin_audit_logs:

- id;
- admin_telegram_id;
- admin_role;
- action;
- entity_type;
- entity_id;
- before_data;
- after_data;
- reason;
- ip opcional;
- user_agent opcional;
- source;
- command;
- created_at.

source pode ser:

- telegram_bot;
- admin_panel;
- system.

Nenhuma ação administrativa importante pode ocorrer sem log.

==================================================
IDEMPOTÊNCIA
==================================================

Toda ação financeira ou de entrega deve usar idempotency_key.

Exemplos:

admin_add_fc:{command_id}
admin_give_hero:{command_id}
admin_give_pet:{command_id}
admin_pool_distribution:{season_id}
admin_approve_withdrawal:{withdrawal_id}

==================================================
PAINEL DE LOGS PELO BOT
==================================================

Comandos:

/logs

/logs_today

/logs_admin TELEGRAM_ID

/logs_player TELEGRAM_ID

/logs_entity TYPE ID

Mostrar paginação.

Não mostrar segredos.

==================================================
NOTIFICAÇÕES
==================================================

Quando uma ação afetar jogador, enviar notificação interna.

Exemplos:

- saldo ajustado;
- herói recebido;
- pet recebido;
- saque aprovado;
- saque rejeitado;
- conta banida;
- conta desbanida;
- recompensa entregue.

==================================================
RLS
==================================================

Criar policies para:

- jogador consultar seus próprios dados;
- jogador não alterar saldo;
- jogador não alterar recompensa;
- jogador não alterar role;
- admin consultar conforme permissão;
- ações sensíveis somente pelo backend.

Não depender apenas de esconder botões.

==================================================
EDGE FUNCTIONS OU SERVER FUNCTIONS
==================================================

Criar endpoints equivalentes:

/api/admin/players
/api/admin/balances
/api/admin/heroes
/api/admin/pets
/api/admin/eggs
/api/admin/missions
/api/admin/calendar
/api/admin/pass
/api/admin/pvp
/api/admin/boss
/api/admin/pool
/api/admin/referrals
/api/admin/wallets
/api/admin/deposits
/api/admin/withdrawals
/api/admin/logs
/api/telegram/admin-webhook

Todo endpoint deve validar:

- origem;
- autenticação;
- Telegram ID;
- role;
- permissão;
- payload;
- rate limit.

==================================================
WEBHOOK DO BOT
==================================================

Criar webhook seguro para Telegram.

Validar secret token do webhook.

Variável:

TELEGRAM_WEBHOOK_SECRET

Não aceitar requests sem secret válido.

==================================================
RATE LIMIT
==================================================

Aplicar limite para:

- comandos;
- buscas;
- uploads;
- ações financeiras;
- login;
- webhook.

==================================================
MODO DE MANUTENÇÃO
==================================================

Permitir ativar pelo bot:

/maintenance_on

/maintenance_off

Quando ativo:

- jogadores veem aviso;
- admins continuam acessando;
- pagamentos podem ser bloqueados;
- saques podem ser pausados.

==================================================
BACKUP E SEGURANÇA
==================================================

Criar orientações e estrutura para:

- backups do Supabase;
- retenção de logs;
- exportação de dados;
- recuperação;
- revisão de roles.

Não implementar deleção irreversível sem confirmação.

Preferir soft delete:

- deleted_at;
- is_active;
- status.

==================================================
INTERFACE DO PAINEL ADMIN
==================================================

Visual dark fantasy do Forge Village.

Adicionar sidebar:

- Dashboard
- Jogadores
- Economia
- Conteúdo
- Combate
- Financeiro
- Comunidade
- Logs
- Configurações

Em mobile, usar menu compacto.

==================================================
DASHBOARD ADMIN
==================================================

Mostrar:

- jogadores totais;
- jogadores ativos;
- FC em circulação;
- TON recebido;
- saques pendentes;
- depósitos pendentes;
- pool atual;
- heróis existentes;
- pets existentes;
- batalhas PvP;
- usuários banidos;
- erros recentes.

==================================================
TESTES OBRIGATÓRIOS
==================================================

Criar testes para:

1. Telegram ID 8118569391 recebe super_admin;
2. usuário comum não acessa admin;
3. bot rejeita ID não autorizado;
4. service role não aparece no frontend;
5. saldo só muda pelo backend;
6. alteração gera log;
7. banimento funciona;
8. desbanimento funciona;
9. criar herói funciona;
10. editar herói funciona;
11. upload de imagem funciona;
12. criar pet funciona;
13. editar ovo funciona;
14. chances de ovo validam 100%;
15. missão pode ser criada;
16. pool aceita alteração de data;
17. pool não distribui duas vezes;
18. saque exige confirmação;
19. comando duplicado não duplica ação;
20. ações críticas exigem confirmação;
21. RLS bloqueia acesso indevido;
22. webhook inválido é rejeitado;
23. typecheck passa;
24. testes passam;
25. build passa.

==================================================
MIGRATIONS
==================================================

Criar migrations organizadas.

Não colocar tudo em uma migration gigantesca sem necessidade.

Separar:

- roles e permissões;
- logs;
- conteúdo;
- economia;
- financeiro;
- bot admin;
- RLS;
- índices;
- funções SQL.

==================================================
ENTREGA
==================================================

Antes de implementar:

1. analise todas as páginas;
2. analise todas as tabelas;
3. analise as server functions;
4. analise autenticação;
5. analise TonConnect;
6. analise saldo;
7. analise compras;
8. analise missões;
9. analise PvP;
10. analise Pool;
11. analise Passe;
12. analise Pets;
13. analise Heróis.

Depois implemente diretamente nos arquivos reais.

Não deixar:

- TODO;
- mock;
- role validada apenas no frontend;
- service role exposta;
- token do bot no código;
- ações sem log;
- ações financeiras sem idempotência;
- exclusão irreversível sem confirmação;
- comando administrativo sem validação;
- imports quebrados;
- erros TypeScript.

Ao finalizar, informe:

- arquivos criados;
- arquivos alterados;
- migrations;
- tabelas;
- policies RLS;
- funções administrativas;
- comandos do bot;
- roles;
- permissões;
- variáveis de ambiente necessárias;
- resultado do typecheck;
- resultado dos testes;
- resultado do build.@secret:TELEGRAM_BOT_TOKEN

This project was built with [Lovable](https://lovable.dev).

## Build with Lovable

Continue developing this project in the [Lovable editor](https://lovable.dev/projects/a1010e38-3156-4844-b5b9-f707f0d57268).

- **Ship faster**: describe what you want to build and Lovable handles the code.
- **Stay in sync**: every change made in Lovable is committed straight to this repository.
- **Full ownership**: this code is yours. Push to `main` on GitHub and your changes sync back into Lovable, ready for your next prompt.

## Development

Prefer working locally? You need Node.js and npm — [install with nvm](https://github.com/nvm-sh/nvm#installing-and-updating).

```sh
git clone <this-repository-url>
cd <repository-name>
npm i
npm run dev
```
