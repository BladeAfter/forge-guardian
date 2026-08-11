/**
 * Shared types for the MYTHREON translation registry.
 *
 * Every namespace file (heroes, pets, pvp, ...) exports a `LocaleBundle`
 * containing the four supported languages. English is mandatory because it is
 * the global fallback for missing keys.
 */
export type LanguageCode = 'pt' | 'en' | 'es' | 'ru';

export type Dict = Record<string, string>;

export type LocaleBundle = {
  en: Dict;
  pt: Dict;
  es: Dict;
  ru: Dict;
};

export const LANGUAGE_CODES: LanguageCode[] = ['pt', 'en', 'es', 'ru'];

export const LANGUAGE_LABELS: Record<LanguageCode, string> = {
  pt: 'Português',
  en: 'English',
  es: 'Español',
  ru: 'Русский',
};

/** Maps any Telegram/browser locale (pt-BR, en-US, ru, ...) onto a supported code. */
export function normalizeLanguage(value: string | null | undefined): LanguageCode {
  const raw = String(value || '').toLowerCase();
  if (raw.startsWith('pt')) return 'pt';
  if (raw.startsWith('es')) return 'es';
  if (raw.startsWith('ru')) return 'ru';
  if (raw.startsWith('en')) return 'en';
  return 'en';
}
