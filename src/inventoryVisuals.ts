/**
 * Single source of truth for INVENTORY item art.
 *
 * The inventory is a read-only view over the real item sources, so every asset
 * here is the SAME file already used elsewhere in the game (chest art from the
 * calendar/chest screens, fragment art from the Season Pass, food emojis from
 * Pets → Food, egg art straight from `pet_eggs.image_url`). Nothing is copied
 * or duplicated, and resolution is done by STABLE keys (item code / item type),
 * never by the translated display name.
 */
import { PET_FOOD_ICONS } from './petLabels';
import type { InventoryItem } from './calendarRewards';

const ui = (file: string) => `/assets/game/ui/${file}`;
const chestArt = (file: string) => `/assets/game/chests/${file}`;

/** Official chest art, keyed by the rarity token found in the item code. */
const CHEST_BY_RARITY: Record<string, string> = {
  common: chestArt('common-chest.png'),
  uncommon: chestArt('common-chest.png'),
  rare: chestArt('rare-chest.png'),
  improved: chestArt('rare-chest.png'),
  epic: chestArt('epic-chest.png'),
  special: chestArt('epic-chest.png'),
  legendary: chestArt('legendary-chest.png'),
  mythic: chestArt('legendary-chest.png'),
  ancestral: chestArt('legendary-chest.png'),
};

const FRAGMENT_ART = ui('season-fragments.png');
const UNIVERSAL_FRAGMENT_ART = ui('universal-fragment.png');

/** Exact matches by stable item code (slug). */
const BY_CODE: Record<string, string> = {
  fragments: FRAGMENT_ART,
  fragment: FRAGMENT_ART,
  hero_fragments: FRAGMENT_ART,
  universal_fragment: UNIVERSAL_FRAGMENT_ART,
  universal_fragments: UNIVERSAL_FRAGMENT_ART,
  pvp_ticket: ui('season-pvp-ticket.png'),
  pet_food: ui('season-pet-food.png'),
};

const isImageUrl = (value?: string | null) =>
  !!value && (value.startsWith('http') || value.startsWith('/') || value.startsWith('data:'));

const rarityFromCode = (code: string) =>
  Object.keys(CHEST_BY_RARITY).find((token) => code.includes(token)) ?? null;

export type InventoryVisual = {
  /** Resolved image URL, or null when only an emoji/icon fallback exists. */
  image: string | null;
  /** Emoji glyph reused from Pets → Food (or a category emoji as last resort). */
  glyph: string | null;
  /** Rarity used for the slot border, inferred from the code when absent. */
  rarity: string | null;
};

/** Category emoji used only when no official asset exists for the item. */
const CATEGORY_GLYPH: Record<string, string> = {
  chests: '🎁', fragments: '💎', eggs: '🥚', food: '🍖', equipment: '🛡️', other: '📦',
};

export function getInventoryItemVisual(item: InventoryItem): InventoryVisual {
  const code = String(item.itemId ?? '').toLowerCase();
  const type = String(item.itemType ?? '').toLowerCase();
  const rarityToken = rarityFromCode(code) ?? rarityFromCode(type);
  const rarity = item.rarity ?? (rarityToken && rarityToken in CHEST_BY_RARITY && !['improved', 'special'].includes(rarityToken) ? rarityToken : null);

  // Food keeps the very same emoji icon key used by Pets → Food.
  if (type === 'food') {
    return {
      image: isImageUrl(item.image) ? (item.image as string) : BY_CODE[code] ?? null,
      glyph: isImageUrl(item.image) ? null : PET_FOOD_ICONS[String(item.image ?? '')] ?? PET_FOOD_ICONS[code] ?? '🍖',
      rarity,
    };
  }

  // 1. definition image from the backend (eggs, pet fragments, ...)
  if (isImageUrl(item.image)) return { image: item.image as string, glyph: null, rarity };

  // 2. official asset mapped by stable code / type
  const mapped =
    BY_CODE[code] ??
    BY_CODE[type] ??
    (type.includes('fragment') || code.includes('fragment')
      ? code.includes('universal') || type.includes('universal') ? UNIVERSAL_FRAGMENT_ART : FRAGMENT_ART
      : null) ??
    (type.includes('chest') || code.includes('chest') ? CHEST_BY_RARITY[rarityToken ?? 'common'] ?? CHEST_BY_RARITY.common : null);
  if (mapped) return { image: mapped, glyph: null, rarity };

  // 3. category fallback (emergency only)
  return { image: null, glyph: CATEGORY_GLYPH[item.category] ?? '📦', rarity };
}
