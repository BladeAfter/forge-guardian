# MYTHIC POWER PACK — 20 TON MYTHIC PACK

Novo pack premium comprável várias vezes, com bônus exclusivo de primeira compra validado no servidor.

## Recompensas (toda compra)
- 40.000 MYTH (da reserva oficial, sem mint)
- 1 Ovo Mítico (ovo oficial `mythic-egg`)
- 1 Void Chest (`key_chest` / `void_chest`)
- 1 Baú de Equipamento Premium (item oficial de equipamento premium existente)
- 50 Fragmentos Universais (`fragments`)
- 20 Tickets PvP (`game_players.pvp_tickets`)
- 2 Eternity Keys + 1 Void Key (`tower_key`)
- 25 Comida Premium de Pet (`player_pet_food`, comida premium existente)
- 10.000 XP de Herói (via a função oficial de XP já usada pelos baús)

## Bônus de primeira compra (uma vez por jogador)
- +10.000 MYTH (total 50.000 na primeira compra)
- 1 Celestial Key (`celestial_key`)

A elegibilidade é decidida no servidor pelo histórico de compras entregues do pack — nunca pelo cliente. Pagamento pendente ou falho não consome o bônus; reentrega/retry não duplica.

## Pagamento
Mesma arquitetura dos packs existentes (Adventurer / Vanguard / Celestial):
- Saldo interno de TON >= 20 → debita os 20 TON internos, sem TonConnect.
- Saldo interno < 20 → não mistura: intenção de pagamento imutável no servidor e cobrança dos 20 TON (20.000.000.000 nanoton) inteiros via TonConnect, com verificação on-chain (destino, valor exato, tx não reutilizada) antes de qualquer entrega.
- Entrega atômica: tudo ou nada, com referência única de settlement (ordem + tx hash) para idempotência.

## Card na tela de Ofertas Premium
Card compacto no estilo dark fantasy do jogo (fundo navy/preto, bordas douradas, brilho violeta mítico, cristais azuis, partículas suaves), mobile-first:
- Título "20 TON MYTHIC PACK", subtítulo "Pacote premium de progressão"
- Destaques: 40.000 MYTH · Ovo Mítico · Void Chest · Equipamento Premium · 50 Fragmentos
- Linha "+ MAIS RECOMPENSAS" com o restante
- Selo "BÔNUS DE PRIMEIRA COMPRA · +10.000 MYTH · +1 Celestial Key" somente enquanto o servidor disser que o jogador é elegível
- CTA "COMPRAR POR 20 TON", com estados PAGAMENTO PENDENTE / PROCESSANDO / VERIFICAR PAGAMENTO
- Confirmação em dois passos, como nos outros packs
- Sem limite de compras; atualização imediata de MYTH, inventário, tickets, chaves e do selo após a compra

Textos em PT, EN, ES, RU e TR.

## Admin Bot
Nova entrada em SHOP / PACKS: status, preço, total de compras, TON recebido, bônus de primeira compra resgatados; ligar/desligar o pack e editar preço e quantidades das recompensas sem deploy.

## Histórico de compras
Registro por compra: data, TON pago, método (interno/TonConnect), recompensas entregues, bônus de primeira compra sim/não, tx hash e status.

## Detalhes técnicos
- Migração nova: `mythic_power_pack_config`, `mythic_power_pack_purchases`, `mythic_power_pack_items`, `mythic_power_pack_ledger` + RPCs `mythic_power_pack_settings/state/offer_state/start_purchase/confirm_order/deliver` e `admin_mythic_power_pack_overview/set`, espelhando o padrão do `adventurer_pack_*` (SECURITY DEFINER, GRANTs, RLS).
- Bônus de primeira compra: coluna `first_purchase_bonus` na tabela de compras + índice único parcial por `user_id` para garantir uma única concessão.
- Ações no `game-api`: `mythic-power-pack`, `-buy`, `-confirm`, `-verify`, seguindo as rotas dos packs atuais.
- Frontend: `src/mythicPowerPack.ts` (tipos + mensagens de erro), hook em `src/hooks.ts`, `src/components/MythicPowerPackCard.tsx`, `src/locales/mythicPowerPack.ts` e inclusão em `PremiumOffersModal.tsx`.
- Mapeamento de itens: usa os itens oficiais já existentes (`mythic-egg`, `void_chest`, `eternity_key`, `void_key`, `celestial_key`, `fragments`, comida premium de pet, baú de equipamento premium existente) — nenhum item duplicado é criado, nenhuma odd de baú/ovo é alterada.
- Nada de mudanças em passes, mercado, leilão, mineração TON/MYTH, yields NFT, saques ou outros packs.

## Testes
Compra com saldo interno suficiente, compra via TonConnect com saldo insuficiente, primeira compra (50.000 MYTH + Celestial Key), segunda compra (40.000 MYTH sem bônus), settlement duplicado, valor incorreto, pagamento pendente, e reabertura do app após a primeira compra.
