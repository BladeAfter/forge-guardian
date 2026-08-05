export type HeroRarity = 'common' | 'uncommon' | 'rare' | 'epic' | 'legendary';

export type ShopHero = {
  id: string;
  name: string;
  rarity: HeroRarity;
  image: string;
};

const asset = (path: string) => `/assets/game/heroes/${path}`;
const shop = (name: string) => asset(`shop/${name}.webp`);

export const HERO_CATALOG: ShopHero[] = [
  { id: 'common-1', name: 'Espadachim da Forja', rarity: 'common', image: asset('common-warrior.png') },
  { id: 'common-2', name: 'Guarda da Lança', rarity: 'common', image: shop('common-2') },
  { id: 'common-3', name: 'Batedor da Besta', rarity: 'common', image: shop('common-3') },
  { id: 'common-4', name: 'Médica da Vila', rarity: 'common', image: shop('common-4') },
  { id: 'common-5', name: 'Portador do Escudo', rarity: 'common', image: shop('common-5') },
  { id: 'uncommon-1', name: 'Arqueira Élfica', rarity: 'uncommon', image: asset('uncommon-archer.png') },
  { id: 'uncommon-2', name: 'Lâminas do Deserto', rarity: 'uncommon', image: shop('uncommon-2') },
  { id: 'uncommon-3', name: 'Caçador de Gelo', rarity: 'uncommon', image: shop('uncommon-3') },
  { id: 'uncommon-4', name: 'Rastreadora Feral', rarity: 'uncommon', image: shop('uncommon-4') },
  { id: 'uncommon-5', name: 'Ladino Esmeralda', rarity: 'uncommon', image: shop('uncommon-5') },
  { id: 'rare-1', name: 'Guardião Rúnico', rarity: 'rare', image: asset('rare-guardian.png') },
  { id: 'rare-2', name: 'Lanceira Real', rarity: 'rare', image: shop('rare-2') },
  { id: 'rare-3', name: 'Ferreiro das Runas', rarity: 'rare', image: shop('rare-3') },
  { id: 'rare-4', name: 'Clériga da Tempestade', rarity: 'rare', image: shop('rare-4') },
  { id: 'rare-5', name: 'Cavaleiro Leão', rarity: 'rare', image: shop('rare-5') },
  { id: 'epic-1', name: 'Maga Rúnica', rarity: 'epic', image: asset('epic-mage.png') },
  { id: 'epic-2', name: 'Mago Carmesim', rarity: 'epic', image: shop('epic-2') },
  { id: 'epic-3', name: 'Paladina Sombria', rarity: 'epic', image: shop('epic-3') },
  { id: 'epic-4', name: 'Artífice Arcano', rarity: 'epic', image: shop('epic-4') },
  { id: 'epic-5', name: 'Lanceira Celestial', rarity: 'epic', image: shop('epic-5') },
  { id: 'legendary-1', name: 'Cavaleiro Dragão', rarity: 'legendary', image: asset('legendary-dragon-knight.png') },
  { id: 'legendary-2', name: 'Rainha Fênix', rarity: 'legendary', image: shop('legendary-2') },
  { id: 'legendary-3', name: 'Rei Titã', rarity: 'legendary', image: shop('legendary-3') },
  { id: 'legendary-4', name: 'Imperatriz Lunar', rarity: 'legendary', image: shop('legendary-4') },
  { id: 'legendary-5', name: 'Imperador da Forja', rarity: 'legendary', image: shop('legendary-5') }
];

export const RARITY_ODDS: Array<{ rarity: HeroRarity; chance: number }> = [
  { rarity: 'legendary', chance: 0.3 },
  { rarity: 'epic', chance: 2.7 },
  { rarity: 'rare', chance: 10 },
  { rarity: 'uncommon', chance: 25 },
  { rarity: 'common', chance: 62 }
];

export const RARITY_COLORS: Record<HeroRarity, string> = {
  common: '#94a3b8', uncommon: '#4ade80', rare: '#60a5fa', epic: '#c084fc', legendary: '#fbbf24'
};

export const RARITY_DAMAGE: Record<HeroRarity, number> = {
  common: 0.15, uncommon: 0.25, rare: 0.4, epic: 0.7, legendary: 1.2
};

export const DEFAULT_BOSS_TEAM = ['common-1', 'uncommon-1', 'rare-1', 'epic-1', 'legendary-1'];
