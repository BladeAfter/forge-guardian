import { forgeFetch } from './apiClient';

/**
 * Partner channels: the Mini App only ever knows NAME + REWARD + claimed state.
 * The real destination link lives in the backend and is resolved on GO.
 */
export type PartnerChannel = {
  id: string;
  name: string;
  rewardFc: number;
  claimed: boolean;
  visited: boolean;
  rewardReceived: number;
};

export type PartnerList = { partners: PartnerChannel[] };
export type PartnerVisit = { id: string; name: string; url: string; rewardFc: number; claimed: boolean };
export type PartnerClaim = PartnerList & { status: 'claimed' | 'already_claimed'; creditedFc: number; balance: number; partnerName?: string };

type PartnerAction =
  | { action: 'list' }
  | { action: 'go'; partnerId: string }
  | { action: 'claim'; partnerId: string };

const ERRORS: Record<string, string> = {
  PARTNER_NOT_AVAILABLE: 'Este parceiro não está mais disponível.',
  PARTNER_NOT_VISITED: 'Toque em GO primeiro para abrir o canal do parceiro.',
  PLAYER_NOT_FOUND: 'Perfil não encontrado. Reabra o jogo pelo Telegram.',
  INVALID_PARTNER: 'Parceiro inválido.',
};

async function partnersRequest<T>(initData: string, input: PartnerAction): Promise<T> {
  const response = await forgeFetch('partners', { initData, ...input });
  if (response.status === 404) throw new Error('Backend indisponível: não foi possível contatar os parceiros.');
  const payload = (await response.json().catch(() => null)) as (T & { error?: string }) | null;
  if (!response.ok || !payload) {
    const raw = payload?.error || '';
    throw new Error(ERRORS[raw] || raw || 'Não foi possível carregar os parceiros.');
  }
  return payload;
}

export const fetchPartners = (initData: string) => partnersRequest<PartnerList>(initData, { action: 'list' });
export const openPartner = (initData: string, partnerId: string) => partnersRequest<PartnerVisit>(initData, { action: 'go', partnerId });
export const claimPartner = (initData: string, partnerId: string) => partnersRequest<PartnerClaim>(initData, { action: 'claim', partnerId });
