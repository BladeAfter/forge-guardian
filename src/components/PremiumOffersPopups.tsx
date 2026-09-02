import { useEffect, useRef, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { confirmPremiumOfferPopupShown, markPremiumOfferSeen, reservePremiumOfferPopup, trackOfferImpression } from '../services';
import type { PremiumOfferType } from '../premiumOffers';
import { FounderPackCard } from './FounderPackCard';
import { VeteranVaultV2Card } from './VeteranVaultV2Card';
import { CelestialPackCard } from './CelestialPackCard';
import { MythicVanguardPackCard } from './MythicVanguardPackCard';

const log = (message: string, extra?: unknown) => {
  if (import.meta.env.DEV) console.info(`[PremiumOfferPopup] ${message}`, extra ?? '');
};

/**
 * 🎁 POPUP AUTOMÁTICO DIÁRIO DAS OFERTAS PREMIUM.
 *
 * Este componente é montado no bootstrap do app (App.tsx), NÃO na aba OFERTAS: assim que o jogador
 * está autenticado, o player carregado e a Vila pronta, ele pergunta ao servidor qual oferta deve
 * aparecer — o jogador não precisa clicar em nada.
 *
 * Fluxo anti-"queimar impressão":
 *   1. `popup-reserve` → o servidor escolhe 0 ou 1 oferta (prioridade: Sovereign 200 > Celestial 100
 *      > Founder 50 > Veteran 40) e NÃO grava impressão nenhuma;
 *   2. o modal abre de verdade;
 *   3. só depois de montado chamamos `popup-confirm-shown`, que grava a impressão do dia de forma
 *      atômica por (conta, oferta, dia) — multi-device e duas sessões simultâneas ficam seguros.
 *
 * `active` mantém o popup fora de momentos ruins (batalha, PvP, pagamentos, popups críticos): ele só
 * abre sobre a Vila/Home, com um pequeno atraso depois de a tela estabilizar. Fechar apenas silencia
 * o dia — a oferta continua listada em OFERTAS PREMIUM.
 */
export function PremiumOffersPopups({ telegramInitData, active = true }: { telegramInitData: string; active?: boolean }) {
  const client = useQueryClient();
  const [offer, setOffer] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const requested = useRef(false);
  const confirmed = useRef(false);

  // 1️⃣ Startup check: dispara sozinho quando a Home/Vila está pronta.
  useEffect(() => {
    if (!active || !telegramInitData || done || requested.current) return;
    requested.current = true;
    const timer = window.setTimeout(() => {
      log('startup check started');
      void reservePremiumOfferPopup(telegramInitData)
        .then(result => {
          if (!result.shouldShow || !result.offerId) {
            log('no eligible offer', result.reason ?? 'NO_ELIGIBLE_OFFER');
            setDone(true);
            return;
          }
          log(`eligible offer: ${result.offerId}`);
          log('opening modal', result.offerId);
          setOffer(result.offerId);
        })
        .catch(error => {
          console.warn('[PremiumOfferPopup] failed_to_open', error instanceof Error ? error.message : error);
          setDone(true);
        });
    }, 900);
    return () => window.clearTimeout(timer);
  }, [active, telegramInitData, done]);

  // 3️⃣ Confirmação da impressão SÓ depois de o modal montar.
  useEffect(() => {
    if (!offer || confirmed.current) return;
    confirmed.current = true;
    void confirmPremiumOfferPopupShown(telegramInitData, offer)
      .then(() => log('impression recorded', offer))
      .catch(error => console.warn('[PremiumOfferPopup] impression_failed', error instanceof Error ? error.message : error));
  }, [offer, telegramInitData]);

  const close = () => {
    if (offer === 'CELESTIAL_MYSTERY_PACK' || offer === 'CELESTIAL_SOVEREIGN_PACK' || offer === 'MYTHIC_VANGUARD_PACK') {
      void trackOfferImpression(telegramInitData, offer, 'dismissed').catch(() => {});
    } else if (offer) {
      void markPremiumOfferSeen(telegramInitData, offer as PremiumOfferType, true).catch(() => {});
    }
    setOffer(null);
    setDone(true);
    void client.invalidateQueries({ queryKey: ['premium-offers'] });
  };

  if (!offer) return null;

  if (offer === 'CELESTIAL_MYSTERY_PACK') {
    return <CelestialPackCard key="celestial-popup" telegramInitData={telegramInitData} popupMode onPopupClose={close} />;
  }
  if (offer === 'MYTHIC_VANGUARD_PACK') {
    return <MythicVanguardPackCard key="vanguard-popup" telegramInitData={telegramInitData} popupMode onPopupClose={close} />;
  }
  if (offer === 'FOUNDER_PACK') {
    return <FounderPackCard key="founder-popup" telegramInitData={telegramInitData} popupMode onPopupClose={close} />;
  }
  return <VeteranVaultV2Card key="veteran-popup" telegramInitData={telegramInitData} popupMode onPopupClose={close} />;
}
