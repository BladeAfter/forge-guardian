import { voyageHeroArt, voyagePetArt } from './voyageArt';
import { mascotChestImage } from './gameAssets';
import { pirateEquipmentImage } from './pirateEquipmentArt';

const petImages = Object.values(voyagePetArt);
const heroImages = Object.values(voyageHeroArt);
const stableIndex = (key: string, length: number) => {
  let hash = 0;
  for (const char of key) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return hash % length;
};

/** Legacy creature and mascot-container artwork only; gameplay values are untouched. */
export function replaceVoyageImage(image: string): string {
  const equipment = pirateEquipmentImage(image);
  if (equipment) return equipment;
  if (/\/pet-eggs\/|\/veteran\/egg-|\/pets-sub-nft\/sub-egg|season-1-mythic-egg/i.test(image)) return mascotChestImage(image);
  if (image.includes('/new-voyage/')) return image;
  const kind = /\/(?:pets(?:-[^/]*)?|pet-images)\//.test(image) ? 'pet'
    : /\/(?:heroes(?:-[^/]*)?|hero-images)\//.test(image) ? 'hero' : null;
  if (!kind) return image;
  const filename = image.split('?')[0].split('/').pop() ?? image;
  const pool = kind === 'pet' ? petImages : heroImages;
  return pool[stableIndex(filename, pool.length)];
}

/** Cosmetic normalization for histories and payloads retaining old image URLs. */
export function replaceLegacyCreatureArt(payload: unknown): unknown {
  if (Array.isArray(payload)) return payload.map(replaceLegacyCreatureArt);
  if (!payload || typeof payload !== 'object') return payload;
  return Object.fromEntries(Object.entries(payload).map(([key, value]) => [key,
    typeof value === 'string' && /^(image|imageUrl|image_url|battle_image|image_.*_url)$/.test(key)
      ? replaceVoyageImage(value) : replaceLegacyCreatureArt(value),
  ]));
}