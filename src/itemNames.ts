/**
 * Localization of ITEM DISPLAY NAMES that come from the backend.
 *
 * Item names (chests, keys, eggs, fragments, pet food, PvP tickets, Season Pass
 * reward titles, ...) are stored in the database in Portuguese (a few legacy
 * rows in English). The UI language is client-side, so those strings used to
 * stay in Portuguese for every language.
 *
 * This module parses a backend name into `count + noun + modifiers` using
 * STABLE vocabulary (never per-item hardcoding) and rebuilds it in the active
 * language. Anything it cannot fully understand (hero names, equipment proper
 * names such as "RUNIC AEGIS", season slugs) is returned untouched.
 */
import { useLanguage } from './LanguageContext';
import type { LanguageCode } from './locales/registry';

type Noun =
  | 'chest' | 'key' | 'egg' | 'fragment' | 'food' | 'ticket' | 'hero' | 'pet'
  | 'equipment' | 'pack' | 'myth' | 'armor' | 'ring' | 'weapon' | 'skin';

type Mod =
  | 'common' | 'uncommon' | 'rare' | 'epic' | 'legendary' | 'mythic' | 'ancestral'
  | 'improved' | 'special' | 'premium' | 'exclusive' | 'universal' | 'celestial'
  | 'eternity' | 'void' | 'nft' | 'pvp' | 'dragon' | 'veteran' | 'mystery'
  /** Qualifier nouns ("chest OF equipment", "chest OF hero"). */
  | 'of_equipment' | 'of_hero' | 'of_pet' | 'of_evolution' | 'of_resources';

const strip = (value: string) =>
  value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase();

const CONNECTORS = new Set(['DE', 'DA', 'DO', 'DAS', 'DOS', 'OF', 'THE']);

const NOUN_TOKENS: Record<string, Noun> = {
  BAU: 'chest', BAUS: 'chest', CHEST: 'chest', CHESTS: 'chest',
  CHAVE: 'key', CHAVES: 'key', KEY: 'key', KEYS: 'key',
  OVO: 'egg', OVOS: 'egg', EGG: 'egg', EGGS: 'egg',
  FRAGMENTO: 'fragment', FRAGMENTOS: 'fragment', FRAGMENT: 'fragment', FRAGMENTS: 'fragment',
  RACAO: 'food', COMIDA: 'food', FOOD: 'food',
  TICKET: 'ticket', TICKETS: 'ticket',
  HEROI: 'hero', HEROIS: 'hero', HERO: 'hero', HEROES: 'hero',
  PET: 'pet', PETS: 'pet',
  EQUIPAMENTO: 'equipment', EQUIPAMENTOS: 'equipment', EQUIPMENT: 'equipment',
  PACOTE: 'pack', PACOTES: 'pack', PACK: 'pack',
  MYTH: 'myth',
  ARMADURA: 'armor', ARMOR: 'armor',
  ANEL: 'ring', RING: 'ring',
  ARMA: 'weapon', WEAPON: 'weapon',
  SKIN: 'skin',
};

/** Nouns that become qualifiers when they are not the head noun. */
const NOUN_AS_MOD: Partial<Record<Noun, Mod>> = {
  equipment: 'of_equipment', hero: 'of_hero', pet: 'of_pet',
};

const MOD_TOKENS: Record<string, Mod> = {
  COMUM: 'common', COMUNS: 'common', COMMON: 'common',
  INCOMUM: 'uncommon', INCOMUNS: 'uncommon', UNCOMMON: 'uncommon',
  RARO: 'rare', RARA: 'rare', RAROS: 'rare', RARAS: 'rare', RARE: 'rare',
  EPICO: 'epic', EPICA: 'epic', EPICOS: 'epic', EPICAS: 'epic', EPIC: 'epic',
  LENDARIO: 'legendary', LENDARIA: 'legendary', LENDARIOS: 'legendary', LENDARIAS: 'legendary', LEGENDARY: 'legendary',
  MITICO: 'mythic', MITICA: 'mythic', MITICOS: 'mythic', MYTHIC: 'mythic',
  ANCESTRAL: 'ancestral', ANCESTRAIS: 'ancestral',
  APRIMORADO: 'improved', APRIMORADA: 'improved', IMPROVED: 'improved',
  ESPECIAL: 'special', ESPECIAIS: 'special', SPECIAL: 'special',
  PREMIUM: 'premium',
  EXCLUSIVO: 'exclusive', EXCLUSIVA: 'exclusive', EXCLUSIVOS: 'exclusive', EXCLUSIVE: 'exclusive',
  UNIVERSAL: 'universal', UNIVERSAIS: 'universal',
  CELESTIAL: 'celestial', CELESTIAIS: 'celestial',
  ETERNIDADE: 'eternity', ETERNITY: 'eternity',
  VAZIO: 'void', VOID: 'void',
  NFT: 'nft',
  PVP: 'pvp',
  DRAGAO: 'dragon', DRAGON: 'dragon',
  VETERAN: 'veteran', VETERANO: 'veteran',
  MYSTERY: 'mystery', MISTERIO: 'mystery', MISTERIOSO: 'mystery',
  EVOLUCAO: 'of_evolution', EVOLUTION: 'of_evolution',
  RECURSOS: 'of_resources', RESOURCES: 'of_resources', RESOURCE: 'of_resources',
};

/** [singular, plural] per language. */
const NOUNS: Record<LanguageCode, Record<Noun, [string, string]>> = {
  pt: {
    chest: ['BAÚ', 'BAÚS'], key: ['CHAVE', 'CHAVES'], egg: ['OVO', 'OVOS'],
    fragment: ['FRAGMENTO', 'FRAGMENTOS'], food: ['RAÇÃO DE PET', 'RAÇÃO DE PET'],
    ticket: ['TICKET', 'TICKETS'], hero: ['HERÓI', 'HERÓIS'], pet: ['PET', 'PETS'],
    equipment: ['EQUIPAMENTO', 'EQUIPAMENTOS'], pack: ['PACOTE', 'PACOTES'], myth: ['MYTH', 'MYTH'],
    armor: ['ARMADURA', 'ARMADURAS'], ring: ['ANEL', 'ANÉIS'], weapon: ['ARMA', 'ARMAS'], skin: ['SKIN', 'SKINS'],
  },
  en: {
    chest: ['CHEST', 'CHESTS'], key: ['KEY', 'KEYS'], egg: ['EGG', 'EGGS'],
    fragment: ['FRAGMENT', 'FRAGMENTS'], food: ['PET FOOD', 'PET FOOD'],
    ticket: ['TICKET', 'TICKETS'], hero: ['HERO', 'HEROES'], pet: ['PET', 'PETS'],
    equipment: ['EQUIPMENT', 'EQUIPMENT'], pack: ['PACK', 'PACKS'], myth: ['MYTH', 'MYTH'],
    armor: ['ARMOR', 'ARMOR'], ring: ['RING', 'RINGS'], weapon: ['WEAPON', 'WEAPONS'], skin: ['SKIN', 'SKINS'],
  },
  es: {
    chest: ['COFRE', 'COFRES'], key: ['LLAVE', 'LLAVES'], egg: ['HUEVO', 'HUEVOS'],
    fragment: ['FRAGMENTO', 'FRAGMENTOS'], food: ['COMIDA DE MASCOTA', 'COMIDA DE MASCOTA'],
    ticket: ['TICKET', 'TICKETS'], hero: ['HÉROE', 'HÉROES'], pet: ['MASCOTA', 'MASCOTAS'],
    equipment: ['EQUIPO', 'EQUIPOS'], pack: ['PAQUETE', 'PAQUETES'], myth: ['MYTH', 'MYTH'],
    armor: ['ARMADURA', 'ARMADURAS'], ring: ['ANILLO', 'ANILLOS'], weapon: ['ARMA', 'ARMAS'], skin: ['SKIN', 'SKINS'],
  },
  ru: {
    chest: ['СУНДУК', 'СУНДУКИ'], key: ['КЛЮЧ', 'КЛЮЧИ'], egg: ['ЯЙЦО', 'ЯЙЦА'],
    fragment: ['ФРАГМЕНТ', 'ФРАГМЕНТЫ'], food: ['КОРМ ДЛЯ ПИТОМЦА', 'КОРМ ДЛЯ ПИТОМЦА'],
    ticket: ['ТИКЕТ', 'ТИКЕТЫ'], hero: ['ГЕРОЙ', 'ГЕРОИ'], pet: ['ПИТОМЕЦ', 'ПИТОМЦЫ'],
    equipment: ['СНАРЯЖЕНИЕ', 'СНАРЯЖЕНИЕ'], pack: ['НАБОР', 'НАБОРЫ'], myth: ['MYTH', 'MYTH'],
    armor: ['БРОНЯ', 'БРОНЯ'], ring: ['КОЛЬЦО', 'КОЛЬЦА'], weapon: ['ОРУЖИЕ', 'ОРУЖИЕ'], skin: ['СКИН', 'СКИНЫ'],
  },
  tr: {
    chest: ['SANDIK', 'SANDIKLAR'], key: ['ANAHTAR', 'ANAHTARLAR'], egg: ['YUMURTA', 'YUMURTALAR'],
    fragment: ['PARÇA', 'PARÇALAR'], food: ['PET YEMİ', 'PET YEMİ'],
    ticket: ['BİLET', 'BİLETLER'], hero: ['KAHRAMAN', 'KAHRAMANLAR'], pet: ['PET', 'PETLER'],
    equipment: ['EKİPMAN', 'EKİPMANLAR'], pack: ['PAKET', 'PAKETLER'], myth: ['MYTH', 'MYTH'],
    armor: ['ZIRH', 'ZIRHLAR'], ring: ['YÜZÜK', 'YÜZÜKLER'], weapon: ['SİLAH', 'SİLAHLAR'], skin: ['SKIN', 'SKINLER'],
  },
};

const MODS: Record<LanguageCode, Record<Mod, string>> = {
  pt: {
    common: 'COMUM', uncommon: 'INCOMUM', rare: 'RARO', epic: 'ÉPICO', legendary: 'LENDÁRIO',
    mythic: 'MÍTICO', ancestral: 'ANCESTRAL', improved: 'APRIMORADO', special: 'ESPECIAL',
    premium: 'PREMIUM', exclusive: 'EXCLUSIVO', universal: 'UNIVERSAL', celestial: 'CELESTIAL',
    eternity: 'DA ETERNIDADE', void: 'DO VAZIO', nft: 'NFT', pvp: 'PVP', dragon: 'DE DRAGÃO',
    veteran: 'VETERAN', mystery: 'MISTERIOSO', of_equipment: 'DE EQUIPAMENTO', of_hero: 'DE HERÓI',
    of_pet: 'DE PET', of_evolution: 'DE EVOLUÇÃO', of_resources: 'DE RECURSOS',
  },
  en: {
    common: 'COMMON', uncommon: 'UNCOMMON', rare: 'RARE', epic: 'EPIC', legendary: 'LEGENDARY',
    mythic: 'MYTHIC', ancestral: 'ANCESTRAL', improved: 'IMPROVED', special: 'SPECIAL',
    premium: 'PREMIUM', exclusive: 'EXCLUSIVE', universal: 'UNIVERSAL', celestial: 'CELESTIAL',
    eternity: 'ETERNITY', void: 'VOID', nft: 'NFT', pvp: 'PVP', dragon: 'DRAGON',
    veteran: 'VETERAN', mystery: 'MYSTERY', of_equipment: 'EQUIPMENT', of_hero: 'HERO',
    of_pet: 'PET', of_evolution: 'EVOLUTION', of_resources: 'RESOURCE',
  },
  es: {
    common: 'COMÚN', uncommon: 'POCO COMÚN', rare: 'RARO', epic: 'ÉPICO', legendary: 'LEGENDARIO',
    mythic: 'MÍTICO', ancestral: 'ANCESTRAL', improved: 'MEJORADO', special: 'ESPECIAL',
    premium: 'PREMIUM', exclusive: 'EXCLUSIVO', universal: 'UNIVERSAL', celestial: 'CELESTIAL',
    eternity: 'DE LA ETERNIDAD', void: 'DEL VACÍO', nft: 'NFT', pvp: 'PVP', dragon: 'DE DRAGÓN',
    veteran: 'VETERANO', mystery: 'MISTERIOSO', of_equipment: 'DE EQUIPO', of_hero: 'DE HÉROE',
    of_pet: 'DE MASCOTA', of_evolution: 'DE EVOLUCIÓN', of_resources: 'DE RECURSOS',
  },
  ru: {
    common: 'ОБЫЧНЫЙ', uncommon: 'НЕОБЫЧНЫЙ', rare: 'РЕДКИЙ', epic: 'ЭПИЧЕСКИЙ', legendary: 'ЛЕГЕНДАРНЫЙ',
    mythic: 'МИФИЧЕСКИЙ', ancestral: 'ПРАРОДИТЕЛЬСКИЙ', improved: 'УЛУЧШЕННЫЙ', special: 'ОСОБЫЙ',
    premium: 'ПРЕМИУМ', exclusive: 'ЭКСКЛЮЗИВНЫЙ', universal: 'УНИВЕРСАЛЬНЫЙ', celestial: 'НЕБЕСНЫЙ',
    eternity: 'ВЕЧНОСТИ', void: 'ПУСТОТЫ', nft: 'NFT', pvp: 'PVP', dragon: 'ДРАКОНА',
    veteran: 'ВЕТЕРАН', mystery: 'ТАИНСТВЕННЫЙ', of_equipment: 'СНАРЯЖЕНИЯ', of_hero: 'ГЕРОЯ',
    of_pet: 'ПИТОМЦА', of_evolution: 'ЭВОЛЮЦИИ', of_resources: 'РЕСУРСОВ',
  },
  tr: {
    common: 'SIRADAN', uncommon: 'NADİR OLMAYAN', rare: 'NADİR', epic: 'EPİK', legendary: 'EFSANEVİ',
    mythic: 'MİTİK', ancestral: 'ATASAL', improved: 'GELİŞMİŞ', special: 'ÖZEL',
    premium: 'PREMIUM', exclusive: 'ÖZEL ÜRETİM', universal: 'EVRENSEL', celestial: 'SEMAVİ',
    eternity: 'SONSUZLUK', void: 'BOŞLUK', nft: 'NFT', pvp: 'PVP', dragon: 'EJDERHA',
    veteran: 'VETERAN', mystery: 'GİZEMLİ', of_equipment: 'EKİPMAN', of_hero: 'KAHRAMAN',
    of_pet: 'PET', of_evolution: 'EVRİM', of_resources: 'KAYNAK',
  },
};

/** Word order per language: N = head noun, Q = qualifiers ("of X"), A = adjectives. */
const ORDER: Record<LanguageCode, ('N' | 'Q' | 'A')[]> = {
  pt: ['N', 'Q', 'A'],
  es: ['N', 'Q', 'A'],
  en: ['A', 'Q', 'N'],
  tr: ['A', 'Q', 'N'],
  ru: ['A', 'N', 'Q'],
};

/** Qualifier modifiers are grammatical complements, never adjectives. */
const QUALIFIER_MODS = new Set<Mod>(['of_equipment', 'of_hero', 'of_pet', 'of_evolution', 'of_resources', 'eternity', 'void', 'dragon']);

/** Adjectives that never inflect for number. */
const INVARIANT = new Set(['PREMIUM', 'NFT', 'PVP', 'VETERAN', 'VETERANO', 'SKIN', 'MYTH', 'ANCESTRAL']);

/** Plural agreement for the Latin languages (pt/es adjectives follow the noun). */
const pluralizeAdjective = (word: string, language: LanguageCode) => {
  if (language !== 'pt' && language !== 'es') return word;
  if (INVARIANT.has(word)) return word;
  return /[AEIOUÁÉÍÓÚ]$/.test(word) ? `${word}S` : `${word}ES`;
};


const isDigits = (token: string) => /^[\d.,]+$/.test(token);

type Parsed = { count: string | null; suffix: number | null; noun: Noun; mods: Mod[]; tail: string[] };

function parse(name: string): Parsed | null {
  const raw = name.trim();
  if (!raw) return null;
  let working = raw;
  let suffix: number | null = null;
  const suffixMatch = working.match(/\s*[xX](\d+)\s*$/);
  if (suffixMatch) {
    suffix = Number(suffixMatch[1]);
    working = working.slice(0, suffixMatch.index).trim();
  }
  const tokens = strip(working).split(/[\s·]+/).filter(Boolean);
  if (!tokens.length) return null;

  let count: string | null = null;
  if (isDigits(tokens[0])) count = working.trim().split(/[\s·]+/)[0];

  let noun: Noun | null = null;
  const mods: Mod[] = [];
  const tail: string[] = [];
  const originalTokens = working.trim().split(/[\s·]+/);

  for (let i = count ? 1 : 0; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (CONNECTORS.has(token)) continue;
    if (isDigits(token)) return null;
    const asNoun = NOUN_TOKENS[token];
    if (asNoun) {
      if (!noun) { noun = asNoun; continue; }
      const asMod = NOUN_AS_MOD[asNoun];
      if (asMod) { mods.push(asMod); continue; }
      return null;
    }
    const mod = MOD_TOKENS[token];
    if (mod) { mods.push(mod); continue; }
    // Unknown token: only tolerated as a trailing proper name (e.g. "OVO VETERAN DE AURETHON").
    if (noun && i >= tokens.length - 2) { tail.push(originalTokens[i]); continue; }
    return null;
  }
  if (!noun) return null;
  // "RAÇÃO DE PET" / "COMIDA DE PET": the pet qualifier is already inside the noun.
  const cleaned = noun === 'food' ? mods.filter(mod => mod !== 'of_pet') : mods;
  return { count, suffix, noun, mods: Array.from(new Set(cleaned)), tail };
}

const titleCase = (value: string) =>
  value.toLocaleLowerCase().replace(/(^|[\s·(\-/])([\p{L}])/gu, (_m, sep: string, ch: string) => sep + ch.toLocaleUpperCase());

/**
 * Rebuilds a backend item name in `language`. Returns the original string when
 * the name is not a generic item (hero/equipment proper names, slugs, ...).
 */
export function localizeItemName(name: string | null | undefined, language: LanguageCode): string {
  const original = String(name ?? '');
  if (!original.trim()) return original;
  if (language === 'pt') return original;
  const parsed = parse(original);
  if (!parsed) return original;

  const plural = parsed.count ? Number(parsed.count.replace(/[.,]/g, '')) !== 1 : false;
  const nounWord = NOUNS[language][parsed.noun][plural ? 1 : 0];
  const qualifiers = parsed.mods.filter(mod => QUALIFIER_MODS.has(mod)).map(mod => MODS[language][mod]);
  const adjectives = parsed.mods
    .filter(mod => !QUALIFIER_MODS.has(mod))
    .map(mod => (plural ? pluralizeAdjective(MODS[language][mod], language) : MODS[language][mod]));

  const groups: Record<'N' | 'Q' | 'A', string[]> = { N: [nounWord], Q: qualifiers, A: adjectives };
  const parts = ORDER[language].flatMap(group => groups[group]);

  let phrase = parts.join(' ');
  if (parsed.tail.length) phrase += ` ${parsed.tail.join(' ')}`;
  if (parsed.count) phrase = `${parsed.count} ${phrase}`;
  if (parsed.suffix !== null) phrase += ` x${parsed.suffix}`;

  const base = original.replace(/\s*[xX]\d+\s*$/, '');
  const wasUpper = base === base.toLocaleUpperCase();
  // Turkish dotted/dotless i does not survive a round trip through lower case.
  return wasUpper || language === 'tr' ? phrase : titleCase(phrase);
}


/** Hook version: localizes backend item names into the active UI language. */
export function useItemName(): (name: string | null | undefined) => string {
  const { language } = useLanguage();
  return (name) => localizeItemName(name, language);
}
