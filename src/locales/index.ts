import type { Dict, LanguageCode, LocaleBundle } from './registry';
import { common } from './common';
import { errors } from './errors';
import { home } from './home';
import { heroes } from './heroes';
import { pets } from './pets';
import { pvp } from './pvp';
import { boss } from './boss';
import { wallet } from './wallet';
import { profile } from './profile';
import { quests } from './quests';
import { pass } from './pass';
import { pool } from './pool';
import { clans } from './clans';

const BUNDLES: LocaleBundle[] = [common, errors, home, heroes, pets, pvp, boss, wallet, profile, quests, pass, pool, clans];

function merge(language: LanguageCode): Dict {
  const dict: Dict = {};
  for (const bundle of BUNDLES) Object.assign(dict, bundle[language] ?? {});
  return dict;
}

/** Fully merged dictionaries, one per supported language. */
export const DICTIONARIES: Record<LanguageCode, Dict> = {
  en: merge('en'),
  pt: merge('pt'),
  es: merge('es'),
  ru: merge('ru'),
};

export type { Dict, LanguageCode, LocaleBundle } from './registry';
export { LANGUAGE_CODES, LANGUAGE_LABELS, normalizeLanguage } from './registry';
