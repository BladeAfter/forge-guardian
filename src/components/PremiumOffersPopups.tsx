import { useEffect, useMemo, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { usePremiumOffers } from '../hooks';
import { claimDailyOfferImpression, markPremiumOfferSeen, trackOfferImpression } from '../services';
import type { PremiumOfferType } from '../premiumOffers';
import { FounderPackCard } from './FounderPackCard';
import { VeteranVaultV2Card } from './VeteranVaultV2Card';
import { CelestialPackCard } from './CelestialPackCard';

/**
 * 🎁 Fila diária de ofertas premium com PRIORIDADE server-side
 * (Celestial Mystery Pack 100 > Founder Pack 50 > Veteran Vault 40).
 *
 * O servidor decide tudo: elegibilidade, janela, estoque, limite de compra, se o popup está ligado,
 * a frequência e o limite de 1 exibição por oferta por dia (no fuso oficial), por CONTA — nunca por
 * dispositivo. O Celestial Mystery Pack usa o claim atômico `claim_daily_offer_impression`, então
 * dois requests simultâneos nunca abrem dois popups. Fechar o popup só silencia o dia: a oferta
 * continua disponível em OFERTAS PREMIUM.
 *
 * `active` mantém o popup fora de momentos ruins (batalha, PvP, pagamento, revelações): só abrimos
 * na Home/Village, com um pequeno atraso depois de a tela principal estabilizar.
 */
export function PremiumOffersPopups({ telegramInitData, active = true }: { telegramInitData: string; active?: boolean }) {
  const client = useQueryClient();
  const { data } = usePremiumOffers(telegramInitData, Boolean(telegramInitData));
  const [index, setIndex] = useState(0);
  const [marked, setMarked] = useState<string[]>([]);
  const [ready, setReady] = useState(false);
  const [celestialClaim, setCelestialClaim] = useState<'idle' | 'pending' | 'show' | 'blocked'>('idle');

  // Fila do servidor (já ordenada por prioridade). Mostramos no máximo 1 popup por sessão.
  const queue = useMemo(() => {
    const serverQueue = Array.isArray(data?.queue) ? (data!.queue as string[]) : [];
    return serverQueue.filter((offer, position) => serverQueue.indexOf(offer) === position);
  }, [data]);

  const current = queue[index] ?? null;

  // Pequeno atraso após os dados carregarem (nada aparece antes da tela principal estabilizar).
  useEffect(() => {
    if (!active || !data) { setReady(false); return; }
    const timer = window.setTimeout(() => setReady(true), 900);
    return () => window.clearTimeout(timer);
  }, [active, data]);

  // Claim atômico da impressão diária do Celestial Mystery Pack (autoridade é o servidor).
  useEffect(() => {
    if (!ready || current !== 'CELESTIAL_MYSTERY_PACK' || celestialClaim !== 'idle') return;
    setCelestialClaim('pending');
    void claimDailyOfferImpression(telegramInitData, 'CELESTIAL_MYSTERY_PACK')
      .then(result => setCelestialClaim(result.status === 'SHOW' ? 'show' : 'blocked'))
      .catch(() => setCelestialClaim('blocked'));
  }, [ready, current, celestialClaim, telegramInitData]);

  // Founder/Veteran mantêm o registro original de exibição (1x/dia por oferta).
  useEffect(() => {
    if (!ready || !current || current === 'CELESTIAL_MYSTERY_PACK' || marked.includes(current)) return;
    setMarked(previous => [...previous, current]);
    void markPremiumOfferSeen(telegramInitData, current as PremiumOfferType)
      .catch(() => { /* o servidor volta a oferecer no próximo carregamento */ });
  }, [ready, current, marked, telegramInitData]);

  const advance = () => {
    if (current === 'CELESTIAL_MYSTERY_PACK') {
      void trackOfferImpression(telegramInitData, 'CELESTIAL_MYSTERY_PACK', 'dismissed').catch(() => {});
    } else if (current) {
      void markPremiumOfferSeen(telegramInitData, current as PremiumOfferType, true).catch(() => {});
    }
    setIndex(value => value + 1);
    setCelestialClaim('idle');
    void client.invalidateQueries({ queryKey: ['premium-offers'] });
  };

  if (!ready || !current) return null;

  if (current === 'CELESTIAL_MYSTERY_PACK') {
    if (celestialClaim === 'blocked') return null;
    if (celestialClaim !== 'show') return null;
    return <CelestialPackCard key="celestial-popup" telegramInitData={telegramInitData} popupMode onPopupClose={advance} />;
  }
  if (current === 'FOUNDER_PACK') {
    return <FounderPackCard key="founder-popup" telegramInitData={telegramInitData} popupMode onPopupClose={advance} />;
  }
  return <VeteranVaultV2Card key="veteran-popup" telegramInitData={telegramInitData} popupMode onPopupClose={advance} />;
}
