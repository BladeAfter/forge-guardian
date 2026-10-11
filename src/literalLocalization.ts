import { LITERAL_TRANSLATIONS } from './locales/literalTranslations';
import { TREASURE_TRANSLATIONS } from './locales/islandTreasure';
import { ARENA_ACTION_TRANSLATIONS } from './locales/arenaActions';
import type { LanguageCode } from './locales/registry';

export function localizeLiteral(language: LanguageCode, text: string): string {
  const translation = ARENA_ACTION_TRANSLATIONS[language]?.[text.trim()] ?? TREASURE_TRANSLATIONS[language][text.trim()] ?? LITERAL_TRANSLATIONS[language][text.trim()];
  if (!translation) return text;
  return `${text.match(/^\s*/)?.[0] ?? ''}${translation}${text.match(/\s*$/)?.[0] ?? ''}`;
}