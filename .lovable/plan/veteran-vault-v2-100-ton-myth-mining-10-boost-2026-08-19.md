# Veteran Vault V2 — 100 TON, MYTH Mining, +10% Boost

O jogo já tem um Veteran Vault V1 (50 TON, ciclo de 45 dias, recompensas em TON/MYTH). O pedido descreve um pacote diferente: 100 TON, entrega instantânea de itens Veteran e mineração em MYTH com boost de +10%. Vou implementar como **VETERAN_VAULT_V2**, uma nova versão coexistindo com V1 (V1 continua válido para quem já comprou, mas sai de venda).

## Decisão de escopo
- V1 permanece intacto (ciclo de 45 dias dos compradores atuais continua rodando).
- V2 é o pacote novo: compra única por conta (`user_id + package_version`), 100 TON, sem ciclo diário — entrega atômica no momento da confirmação.
- Nada de TON Mining em nenhuma superfície Veteran.

## Fase 1 — Backend: linha VETERAN e templates
Nova migração:
- Coluna/flag `veteran_line` (bool) + `veteran_slug` em `hero_catalog`, `pets`/templates de pet, `pet_eggs`, `equipment_templates`, para marcar a linha VETERAN (separada de rarity).
- Tabelas novas:
  - `veteran_templates` (tipo: hero/pet/egg/dragon/weapon, template_id, egg→dragon pairing, base_daily_myth, enabled)
  - `veteran_vault_v2_purchases` (user_id, telegram_id, package_version, price_ton, expected_nanoton, payment_method, status, idempotency_key, expires_at, tx_hash, boost_percent_snapshot, myth_reward_snapshot, reward_configuration_version, delivered_at) + unique parcial `(user_id, package_version)` em status pago/entregue e unique em `tx_hash`
  - `veteran_vault_v2_items` (ownership: user_id, purchase_id, item_type, template_id, instance_id, source='VETERAN_VAULT_V2')
  - `veteran_mining_state` (por instância: owner, template, base_daily_myth, accrued, last_accrual_at, active_from)
  - `veteran_mining_pool` (funded / distributed) + `veteran_vault_myth_reward_pool`
  - `veteran_vault_v2_ledger` (auditoria de cada débito/crédito)
  - `veteran_vault_v2_config` (price_ton, popup_enabled, popup_frequency, boost_percent, myth_reference_rate, base daily MYTH por tipo, package_version)
- Templates criados por seed: 5 Veteran Heroes, 5 Veteran Pets, 5 Veteran Eggs, 5 Veteran Dragons (pareados 1:1 com os eggs), 5 Veteran Weapons — cada um com nome, stats, skills/buffs próprios e arte nova gerada por IA (não reaproveitar arte existente).

## Fase 2 — Backend: pagamento e entrega
- `veteran_v2_state(init_data)`: elegibilidade, preço, saldo interno, se já comprou, entitlement, popup config, mineração e projeções.
- `veteran_v2_start_purchase(idempotency_key, wallet)`: se saldo interno ≥ 100 TON → debita 100 TON internos e entrega; senão cria payment intent com `expected_nanoton = 100_000_000_000` (sem pagamento parcial, saldo interno intocado).
- `veteran_v2_confirm_order`: reaproveita o verificador on-chain já existente (destino, valor, comment, tx única) antes de entregar.
- `veteran_v2_deliver(purchase_id)`: transação com `SELECT ... FOR UPDATE` no purchase, checagem de já-entregue, sorteio 1 hero / 1 pet / 1 egg / 2 weapons distintas do pool VETERAN, débito do MYTH reward pool (1.000.000 MYTH sem alterar total supply), criação de ownership real (player_heroes, player_pets, inventário de egg, player_equipment), 5 baús lendários, 200 fragmentos, entitlement `VETERAN_VAULT_V2_OWNER` com `boost_percent_snapshot`, ledger, marca DELIVERED. Falha em qualquer etapa → rollback.

## Fase 3 — Backend: MYTH Mining Veteran
- `veteran_mining_accrue(user_id)`: acrual por timestamp, `base = daily_rate × elapsed`, `boost = base × boost_percent` só se o **dono atual** tiver o entitlement; egg não acumula; dragon começa a acumular em `hatch_completed_at`.
- Hook no hatch: egg deixa de existir e cria o Veteran Dragon pareado, ligando a mineração nesse instante (nunca egg+dragon juntos).
- `veteran_mining_claim`: debita `veteran_mining_pool`, credita `myth_balances`, registra ledger — total supply não muda, sem TonConnect.
- Transferência futura: boost depende do entitlement do dono atual, nunca da instância.

## Fase 4 — Frontend
- Popup global `VeteranVaultPopup` com arte nova, conteúdo do pacote, destaque `⚡ +10% MYTH MINING BOOST`, preço 100 TON, botões BUY / X, respeitando a frequência configurada e escondendo para quem já comprou.
- Reward screen `VETERAN VAULT UNLOCKED` listando tudo + boost ACTIVE.
- Badge `VETERAN` em cards, detalhes, inventário, coleção, seleção de equipe, equipamentos, telas de pet/hero/egg/dragon.
- Card de mineração Veteran mostrando `BASE / VAULT BOOST / TOTAL` em MYTH (nunca TON), status `VETERAN BENEFIT ACTIVE` na Wallet/Profile.
- Textos como ESTIMATED / PROJECTED / REFERENCE (sem promessa de retorno).

## Fase 5 — Admin Bot + i18n + testes
- Menu `🏆 VETERAN VAULT`: status, preço, popup status/frequência, vendas, TON arrecadado, versão, compradores, entregas, itens Veteran, MYTH reward pool, veteran mining pool, MYTH reference rate, mining settings (base/boost/effective por tipo), ROI simulator (30/90/365 dias com +10% e valor de referência em TON), boost settings, audit.
- i18n em PT, EN, ES, RU, TR para todas as strings novas.
- Testes dos 12 cenários da especificação (saldo interno, TonConnect 100 TON exatos, double-click, taxas com boost, egg sem mineração, egg→dragon, transferência sem entitlement, sem stacking, claim contra a pool, mudança de config pelo admin).

## Observações técnicas
- Preço, boost, taxas base e reference rate ficam em `veteran_vault_v2_config`, ajustáveis pelo bot sem deploy; compras guardam snapshot.
- Idempotência: unique em `idempotency_key`, unique parcial `(user_id, package_version)`, unique em `tx_hash`, e `delivered_at` verificado dentro do lock.
- Calibração de ROI ~90 dias vem do reference rate configurável (não é retorno garantido).
