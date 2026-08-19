/**
 * 🎁 PREMIUM OFFERS — Founder Pack + Veteran Vault.
 *
 * Tipagem de exibição apenas. O servidor decide a fila de popups (Founder primeiro, Veteran depois),
 * o limite de 1 popup por oferta por dia (fuso oficial configurável pelo Admin Bot) e a elegibilidade.
 * O cliente só renderiza a verdade do servidor e informa quando o popup foi exibido/fechado.
 */
import type { FounderPackState } from './founderPack';
import type { VeteranV2State } from './veteranVaultV2';

export type PremiumOfferType = 'FOUNDER_PACK' | 'VETERAN_VAULT';

export type PremiumOffersState = {
  dayKey: string;
  timezone: string;
  /** Ordem oficial dos popups do dia; vazia quando nada deve aparecer. */
  queue: PremiumOfferType[];
  founder: FounderPackState & { popupSeenToday: boolean; popupFrequency: string };
  veteran: VeteranV2State & { popupSeenToday: boolean; popupFrequency: string; windowOpen: boolean };
};
