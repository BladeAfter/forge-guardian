# Corrigir popup automático das ofertas premium

## Implementação
- Só iniciar a reserva da oferta depois que o jogo, a Vila e as verificações de popups prioritários terminarem de carregar.
- Manter o controlador de ofertas montado durante o startup para evitar perder estado em transições.
- Adicionar um botão “X” global, acima do conteúdo do pack e respeitando a área segura do Telegram, garantindo que sempre seja possível fechar.
- Validar no preview mobile e conferir o build.

## Detalhes técnicos
- Ajustar o gate em `App.tsx` usando os estados de conclusão das consultas do Starter Pack e Giveaway.
- Reforçar o fechamento em `PremiumOffersPopups.tsx` com camada e `z-index` independentes do card interno.
