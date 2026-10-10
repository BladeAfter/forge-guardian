import { TUTORIAL_VIDEO } from './tutorialMedia.ts';
import { LOCALIZED_TUTORIAL_VIDEOS } from './tutorialLocalizedMedia.ts';
export function tutorialLanguage(value: unknown): string {
  if (typeof value !== 'string' || !value.trim()) return 'en';
  const base = value.trim().toLowerCase().replace(/_/g, '-').split('-')[0];
  return ({ iw: 'he', in: 'id', nb: 'no', nn: 'no', tl: 'fil' } as Record<string, string>)[base] ?? base;
}
export function tutorialForLanguage(value: unknown): { language: string; video: string } | null {
  const language = tutorialLanguage(value);
  const video = language === 'pt' ? TUTORIAL_VIDEO : LOCALIZED_TUTORIAL_VIDEOS[language];
  return video ? { language, video } : null;
}
export function languageFromUpdate(update: unknown): string {
  if (!update || typeof update !== 'object') return 'en';
  return tutorialLanguage((update as { message?: { from?: { language_code?: unknown } } }).message?.from?.language_code);
}
export function tutorialCaption(language: string): string {
  const copy: Record<string, string> = {
    pt: '🏴‍☠️ Bem-vindo a Mythic Seas, capitão!\n\nAssista ao tutorial da Grand Line e comece sua aventura.',
    ru: '🏴‍☠️ Добро пожаловать в Mythic Seas, капитан!\n\nПосмотрите обучение Grand Line и начните приключение.',
    en: '🏴‍☠️ Welcome to Mythic Seas, captain!\n\nWatch the Grand Line tutorial and begin your adventure.',
  };
  return `${copy[language] ?? '🏴‍☠️ Mythic Seas · Grand Line'}\n\n#MythicSeasbot`;
}
export function tutorialUnavailable(language: string): string {
  const copy: Record<string, string> = {
    ru: 'Обучающий ролик на вашем языке пока недоступен.',
    pt: 'O tutorial no seu idioma ainda não está disponível.',
    en: 'The tutorial in your language is not available yet.',
    es: 'El tutorial en tu idioma aún no está disponible.',
    fr: 'Le tutoriel dans votre langue n’est pas encore disponible.',
    de: 'Das Tutorial in deiner Sprache ist noch nicht verfügbar.',
    uk: 'Навчальне відео вашою мовою поки недоступне.',
  };
  return `🏴‍☠️ Mythic Seas\n\n${copy[language] ?? copy.en}`;
}