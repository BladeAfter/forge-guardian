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
import { events } from './events';
import { market } from './market';
import { spending } from './spending';
import { clanBoss } from './clanBoss';
import { partners } from './partners';
import { tower } from './tower';
import { nftx } from './nftx';
import { expeditionExtra } from './expeditionExtra';
import { expeditionBoost } from './expeditionBoost';
import { pvpSelect } from './pvpSelect';
import { giveaway } from './giveaway';
import { activity } from './activity';
import { arsenal } from './arsenal';
import { pvpLeague } from './pvpLeague';
import { tactical } from './tactical';
import { clanAdmin } from './clanAdmin';
import { auction } from './auction';
import { nameMission } from './nameMission';
import { marketingPool } from './marketingPool';
import { clanWar } from './clanWar';
import { tr as trOverrides } from './tr';

const BUNDLES: LocaleBundle[] = [common, errors, home, heroes, pets, pvp, boss, wallet, profile, quests, pass, pool, clans, events, market, spending, clanBoss, partners, tower, nftx, expeditionExtra, expeditionBoost, pvpSelect, giveaway, activity, arsenal, pvpLeague, tactical, clanAdmin, auction, nameMission, marketingPool, clanWar];



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
  // Turkish: English base (technical fallback) fully overridden by tr.ts.
  tr: { ...merge('en'), ...merge('tr'), ...trOverrides },
};

export type { Dict, LanguageCode, LocaleBundle } from './registry';
export { LANGUAGE_CODES, LANGUAGE_LABELS, normalizeLanguage } from './registry';
