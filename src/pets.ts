import type {PetRarity} from './petRules';

export type PetBuffs = Record<string, number>;
export type PetSecondaryBuff = { key: string; value: number; rarity: string; tier: number };
export type PetNextEvolution = {
  tier: number;
  label: string;
  requiredLevel: number;
  fcCost: number;
  fragmentCost: number;
  newBuffChance: number;
  maxSecondaryBuffs: number;
  primaryFrom: number;
  primaryTo: number;
};

export type PetCatalogItem = {
  id: string; name: string; slug: string; species: string; category: string; description: string;
  basePassives: PetBuffs; activeSkill: Record<string, unknown> | null;
  images: Record<'baby' | 'young' | 'adult' | 'ancestral', string>;
  discovered: boolean; bestRarity: PetRarity | null; bestLevel: number | null;
};

export type PlayerPet = {
  id: string; petId: string; name: string; slug: string; species: string; category: string;
  rarity: PetRarity; level: number; maxLevel: number; xp: number; xpRequired: number; isMaxLevel: boolean;
  evolutionTier: number; evolutionLabel: string; evolutionStage: string;
  fragments: number; isActive: boolean; image: string;
  buffs: PetBuffs; primaryBuffKey: string | null; primaryBuffValue: number;
  secondaryBuffs: PetSecondaryBuff[]; power: number; activeSkill: Record<string, unknown> | null;
  nextEvolution: PetNextEvolution | null; canEvolve: boolean;
};

export type PetEgg = { id: string; name: string; slug: string; image: string; priceFc: number | null; priceTon: number | null; quantity: number; rarityRates: Record<string, number>; isPurchasable?: boolean; premiumOnly?: boolean; dailyQuantity?: number | null; perPlayerLimit?: number | null; availabilityLabel?: string | null };
export type PetFood = { code: string; name: string; rarity: string; xpValue: number; icon: string; quantity: number };
export type PetFragmentEntry = { playerPetId: string; petName: string; image: string; rarity: PetRarity; quantity: number };
export type PetEvolutionTier = { tier: number; label: string; requiredLevel: number; fcCost: number; fragmentCost: number; newBuffChance: number };
export type PetInventory = { food: number; universalFragments: number };
export type PetHistory = { id: string; eggName: string; petName: string | null; rarity: PetRarity | null; duplicateFragments: number; createdAt: string };

export type PetDashboard = {
  activePet: PlayerPet | null;
  playerPets: PlayerPet[];
  catalog: PetCatalogItem[];
  eggs: PetEgg[];
  foods: PetFood[];
  fragments: PetFragmentEntry[];
  evolutionTiers: PetEvolutionTier[];
  inventory: PetInventory;
  history: PetHistory[];
  bonuses: PetBuffs;
  balance: number;
};

export type PetFeedResult = { xpGained: number; levelsGained: number; level: number; xp: number; foodName: string; quantity: number };
export type PetEvolveResult = {
  petName: string; tier: number; label: string; primaryBuffKey: string | null;
  primaryBefore: number; primaryAfter: number;
  newBuff: { key: string; value: number; rarity: string } | null;
  fcSpent: number; fragmentsSpent: number;
};
export type PetHatchResult = { name: string; rarity: string; image: string; duplicateFragments: number; petId?: string };

/** Envelope returned by every pet action. Mutating actions wrap the fresh dashboard. */
export type PetActionResponse = Partial<PetDashboard> & {
  dashboard?: PetDashboard;
  result?: PetHatchResult;
  feedResult?: PetFeedResult;
  evolveResult?: PetEvolveResult;
};
