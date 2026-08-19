// Gift heroes: unique presents granted manually. Mechanically they keep their
// real rarity (mythic), but cards show the "PRESENTE" label instead.
export const GIFT_HERO_KEYS = new Set<string>(['gift-xeravokk']);

export const isGiftHero = (heroKey?: string | null) => GIFT_HERO_KEYS.has(String(heroKey ?? ''));

export const GIFT_HERO_LABEL = 'PRESENTE';
