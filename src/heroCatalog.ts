export type HeroRarity = 'common' | 'uncommon' | 'rare' | 'epic' | 'legendary';

export type ShopHero = {
  id: string;
  name: string;
  rarity: HeroRarity;
  image: string;
};

const asset = (path: string) => `/assets/game/heroes/${path}`;
const shop = (name: string) => asset(`shop/${name}.webp`);
const expanded = (name: string) => asset(`shop/expanded/${name}.png`);

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
  { id: 'legendary-5', name: 'Imperador da Forja', rarity: 'legendary', image: shop('legendary-5') },
  { id: 'common-6', name: 'Lâmina da Vila', rarity: 'common', image: expanded('common-village-blade') },
  { id: 'common-7', name: 'Guardiã da Lança', rarity: 'common', image: expanded('common-spear-warden') },
  { id: 'common-8', name: 'Brom Martelo-Firme', rarity: 'common', image: expanded('common-dwarf-smith') },
  { id: 'common-9', name: 'Arqueira do Bosque', rarity: 'common', image: expanded('common-wood-elf-archer') },
  { id: 'common-10', name: 'Escudo de Ferro', rarity: 'common', image: expanded('common-shield-bearer') },
  { id: 'uncommon-6', name: 'Batedora das Lâminas', rarity: 'uncommon', image: expanded('uncommon-twinblade-scout') },
  { id: 'uncommon-7', name: 'Elandor Folha-Verde', rarity: 'uncommon', image: expanded('uncommon-high-elf-ranger') },
  { id: 'uncommon-8', name: 'Dagna Engrenarruna', rarity: 'uncommon', image: expanded('uncommon-dwarf-runesmith') },
  { id: 'uncommon-9', name: 'Caçador da Besta', rarity: 'uncommon', image: expanded('uncommon-crossbow-hunter') },
  { id: 'uncommon-10', name: 'Sentinela Lunar', rarity: 'uncommon', image: expanded('uncommon-moon-elf-warder') },
  { id: 'rare-6', name: 'Thalion do Gelo', rarity: 'rare', image: expanded('rare-frost-elf') },
  { id: 'rare-7', name: 'Cavaleira da Coroa', rarity: 'rare', image: expanded('rare-royal-knight') },
  { id: 'rare-8', name: 'Dorrik Trovejante', rarity: 'rare', image: expanded('rare-dwarf-thunder') },
  { id: 'rare-9', name: 'Arqueira Solar', rarity: 'rare', image: expanded('rare-sun-elf') },
  { id: 'rare-10', name: 'Lanceiro Arcano', rarity: 'rare', image: expanded('rare-arcane-lancer') },
  { id: 'epic-6', name: 'Nyxara do Vazio', rarity: 'epic', image: expanded('epic-void-elf') },
  { id: 'epic-7', name: 'Templário da Chama', rarity: 'epic', image: expanded('epic-flame-templar') },
  { id: 'epic-8', name: 'Brynja Cristalina', rarity: 'epic', image: expanded('epic-dwarf-crystal') },
  { id: 'epic-9', name: 'Duelista das Estrelas', rarity: 'epic', image: expanded('epic-star-elf') },
  { id: 'epic-10', name: 'Lanceira Dracônica', rarity: 'epic', image: expanded('epic-dragon-lancer') },
  { id: 'legendary-6', name: 'Aurelius, Rei Celestial', rarity: 'legendary', image: expanded('legendary-celestial-king') },
  { id: 'legendary-7', name: 'Seraphina, Rainha Fênix', rarity: 'legendary', image: expanded('legendary-phoenix-queen') },
  { id: 'legendary-8', name: 'Thorgar, Alto Rei Anão', rarity: 'legendary', image: expanded('legendary-dwarf-high-king') },
  { id: 'legendary-9', name: 'Astrid da Tempestade', rarity: 'legendary', image: expanded('legendary-storm-valkyrie') },
  { id: 'legendary-10', name: 'Vaelor, Lâmina Sombria', rarity: 'legendary', image: expanded('legendary-shadow-blademaster') }
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
