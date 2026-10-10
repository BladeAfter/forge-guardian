import { languageFromUpdate, tutorialCaption } from './tutorialLanguages.ts';
export const WELCOME_ART = 'https://mythicseas.lovable.app/__l5e/assets-v1/223ef246-6b03-4e47-b5d7-2218bc1afb79/mythic-seas-welcome.jpg';
export function welcomeReply(update: unknown) {
  if (!update || typeof update !== 'object') return null;
  const value = update as { update_id?: unknown; message?: { text?: unknown; chat?: { id?: unknown; type?: unknown }; from?: { id?: unknown; is_bot?: unknown } } };
  const message = value.message;
  if (!Number.isSafeInteger(value.update_id) || !message || message.chat?.type !== 'private' ||
    !Number.isSafeInteger(message.chat.id) || message.chat.id !== message.from?.id || message.from?.is_bot === true ||
    typeof message.text !== 'string' || message.text.length > 256 || !/^\/start(?:@MythicSeasbot)?(?:\s|$)/i.test(message.text)) return null;
  return { method: 'sendPhoto', chat_id: message.chat.id, photo: WELCOME_ART,
    caption: tutorialCaption(languageFromUpdate(update)),
    reply_markup: { inline_keyboard: [[{ text: '▶ Mythic Seas', web_app: { url: 'https://mythicseas.lovable.app' } }]] } };
}