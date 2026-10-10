import { LITERAL_TRANSLATIONS } from './locales/literalTranslations';
import type { LanguageCode } from './locales/registry';

export function localizeLiteral(language: LanguageCode, text: string): string {
  return LITERAL_TRANSLATIONS[language][text] ?? text;
}