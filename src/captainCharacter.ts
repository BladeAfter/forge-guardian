import { voyageHeroArt } from './voyageArt';
export type CaptainStyle = 'male' | 'female';
export const captainCharacters = {
  male: { name: 'Pirata', image: voyageHeroArt.deckblade },
  female: { name: 'Pirata', image: voyageHeroArt.starshot },
};
export function readCaptainStyle(telegramId?: string): CaptainStyle {
  if (!telegramId) return 'male';
  try { return localStorage.getItem(`mythic-seas.captain.${telegramId}`) === 'female' ? 'female' : 'male'; } catch { return 'male'; }
}
export function saveCaptainStyle(telegramId: string, style: CaptainStyle) {
  try { localStorage.setItem(`mythic-seas.captain.${telegramId}`, style); } catch { /* Cosmetic preference only. */ }
}