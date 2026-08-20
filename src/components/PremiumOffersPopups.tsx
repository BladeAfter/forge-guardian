import { useEffect, useMemo, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { usePremiumOffers } from '../hooks';
import { markPremiumOfferSeen } from '../services';
import type { PremiumOfferType } from '../premiumOffers';
import { FounderPackCard } from './FounderPackCard';
import { VeteranVaultV2Card } from './VeteranVaultV2Card';

/**
 * 🎁 Fila diária de ofertas premium — Founder Pack primeiro, Veteran Vault depois.
 *
 * O servidor decide tudo: quem é elegível, se o popup está ligado, a frequência e o limite de
 * 1 exibição por oferta por dia (no fuso oficial). Ao abrir cada popup registramos a exibição no
 * backend, então o mesmo jogador só volta a vê-lo no próximo dia — mesmo trocando de dispositivo.
 */
export function PremiumOffersPopups({ telegramInitData }: { telegramInitData: string }) {
  const client = useQueryClient();
  const { data } = usePremiumOffers(telegramInitData, Boolean(telegramInitData));
  const [index, setIndex] = useState(0);
  const [marked, setMarked] = useState<PremiumOfferType[]>([]);

  // Fila da sessão: ofertas da fila oficial do servidor + qualquer oferta ainda elegível
  // (Founder Pack primeiro, Veteran Vault depois) para que nenhuma seja engolida no mesmo dia.
  const queue = useMemo(() => {
    const serverQueue = Array.isArray(data?.queue) ? (data!.queue as PremiumOfferType[]) : [];
    const eligible: PremiumOfferType[] = [];
    if (data?.founder?.eligible && data.founder.popupFrequency !== 'DISABLED') eligible.push('FOUNDER_PACK');
    if (data?.veteran?.eligible && data.veteran.windowOpen && data.veteran.popupFrequency !== 'DISABLED') {
      eligible.push('VETERAN_VAULT');
    }
    const ordered = eligible.length ? eligible : serverQueue;
    return ordered.filter((offer, position) => ordered.indexOf(offer) === position);
  }, [data]);

  const current: PremiumOfferType | null = queue[index] ?? null;




  // Registra no servidor que o popup foi mostrado hoje (idempotente por dia/oferta).
  useEffect(() => {
    if (!current || marked.includes(current)) return;
    setMarked(previous => [...previous, current]);
    void markPremiumOfferSeen(telegramInitData, current)
      .catch(() => { /* o servidor volta a oferecer no próximo carregamento */ });
  }, [current, marked, telegramInitData]);

  const advance = () => {
    if (current) void markPremiumOfferSeen(telegramInitData, current, true).catch(() => {});
    setIndex(value => value + 1);
    void client.invalidateQueries({ queryKey: ['premium-offers'] });
  };

  if (!current) return null;

  if (current === 'FOUNDER_PACK') {
    return <FounderPackCard key="founder-popup" telegramInitData={telegramInitData} popupMode onPopupClose={advance} />;
  }
  return <VeteranVaultV2Card key="veteran-popup" telegramInitData={telegramInitData} popupMode onPopupClose={advance} />;
}
