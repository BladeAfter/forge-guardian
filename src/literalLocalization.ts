import { LITERAL_TRANSLATIONS } from './locales/literalTranslations';
import { TREASURE_TRANSLATIONS } from './locales/islandTreasure';
import type { LanguageCode } from './locales/registry';

export function localizeLiteral(language: LanguageCode, text: string): string {
  const translation = TREASURE_TRANSLATIONS[language][text.trim()] ?? LITERAL_TRANSLATIONS[language][text.trim()];
  if (!translation) return text;
  return `${text.match(/^\s*/)?.[0] ?? ''}${translation}${text.match(/\s*$/)?.[0] ?? ''}`;
}