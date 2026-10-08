import type { PvpHero } from './pvp';

/** Tower of Eternity (solo dungeon). Every value here is produced server-side. */
export type TowerBoss = {
  heroId: string;
  bossKey: string;
  name: string;
  theme: string;
  role: string;
  behavior: string;
  floor: number;
  tier: number;
  rarity: string;
  finalHp: number;
  finalAtk: number;
  defense: number;
  speed: number;
  level: number;
  imageUrl?: string | null;
  recommendedPower: number;
  entryCost: number;
};

export type TowerEquipmentDrop = {
  instanceId: string;
  code: string;
  name: string;
  slot: 'weapon' | 'armor' | 'ring' | string;
  kind?: string | null;
  heroClass?: string | null;
  rarity: string;
  tier?: number | null;
  imageUrl?: string | null;
  bonusAttack?: number | null;
  bonusDefense?: number | null;
  bonusHp?: number | null;
  power?: number | null;
  /** Floor that produced the drop (server-side). */
  floor?: number | null;
  /** True when this floor granted its one-time drop. */
  firstDropForFloor?: boolean;
};

export type TowerRewards = {
  fragments: number;
  heroXp: number;
  petFood: number;
  heroChest: number;
  towerKey: number;
  /** Chest rarity granted on this floor (server-side). */
  chestCode?: string | null;
  /** Straight BERRIES bonus paid on a clear. */
  forgeCoins?: number;
  /** Universal fragments (hero fusion currency). */
  universalFragments?: number;
  /** Drop chance in % for each tower key, per floor band (display only). */
  keyChances?: Record<string, number>;
  /** Keys actually granted on this clear (code -> quantity). */
  keys?: Record<string, number>;
  /** Premium chest drop chance in % per floor band (display only). */
  chestChances?: Record<string, number>;
  /** Premium chests actually granted on this clear (code -> quantity). */
  chests?: Record<string, number>;
  /** Equipment instance dropped on this clear (null when nothing dropped). */
  equipment?: TowerEquipmentDrop | null;
};

/** The 3 collectible tower keys. They have NO function yet — inventory display only. */
export const TOWER_KEYS = [
  { code: 'eternity_key', name: 'Eternity Key', rarity: 'rare', image: '/assets/game/ui/eternity-key.png', color: '#60a5fa' },
  { code: 'void_key', name: 'Void Key', rarity: 'epic', image: '/assets/game/ui/void-key.png', color: '#c084fc' },
  { code: 'celestial_key', name: 'Celestial Key', rarity: 'legendary', image: '/assets/game/ui/celestial-key.png', color: '#fbbf24' },
] as const;

/** The 3 premium chests the Tower can drop (openable with the matching key). */
export const TOWER_CHESTS = [
  { code: 'eternity_chest', name: 'Eternity Chest', rarity: 'rare', color: '#60a5fa', image: '/__l5e/assets-v1/407a3f1a-03ba-4083-b84d-93211f7ecb10/eternity-chest.png' },
  { code: 'void_chest', name: 'Void Chest', rarity: 'epic', color: '#c084fc', image: '/__l5e/assets-v1/39ea795d-06ae-4444-b586-e687a010fb84/void-chest.png' },
  { code: 'celestial_chest', name: 'Celestial Chest', rarity: 'legendary', color: '#fbbf24', image: '/__l5e/assets-v1/b8e274b2-1f0a-4de9-9693-8702f557ea8c/celestial-chest.png' },
] as const;

export type PetSummary = {
  activePet: { name: string; image: string; level?: number; rarity?: string } | null;
  bonuses: Record<string, number>;
};

export type TowerRun = {
  id: string;
  floor: number;
  bossKey: string;
  result: 'win' | 'loss';
  turns: number;
  rewards: TowerRewards | Record<string, never>;
  createdAt: string;
};

export type TowerDashboard = {
  floor: number;
  totalFloors: number;
  highestFloor: number;
  attemptsUsed: number;
  attemptsLimit: number;
  attemptsRemaining: number;
  entryCost: number;
  /** Second entry option: internal TON price per attempt. */
  entryCostTon?: number;
  balanceFc: number;
  /** Internal (available) TON balance, server-side. */
  balanceTon?: number;
  boss: TowerBoss;
  firstClear: boolean;
  rewards: TowerRewards;
  replayRewards: TowerRewards;
  team: PvpHero[];
  teamPower: number;
  history: TowerRun[];
  /** Same structure used by the Boss: active pet + its real buffs. */
  petSummary?: PetSummary | null;
};

export type TowerBattle = {
  result: 'win' | 'loss';
  floor: number;
  boss: TowerBoss;
  costFc: number;
  costTon?: number;
  paidWith?: 'fc' | 'ton';
  firstClear: boolean;
  rewards: TowerRewards | Record<string, never>;
  totalTurns: number;
  battleLog: Array<{ turn: number; side: 'attacker' | 'defender'; attackerId: string; targetId: string; damage: number; remainingHp: number; skill?: string; heal?: number }>;
  attackerState: Array<PvpHero & { currentHp?: number }>;
  defenderState: Array<TowerBoss & { currentHp?: number }>;
  team: PvpHero[];
  petSummary?: PetSummary | null;
  dashboard: TowerDashboard;
};

/** Tower leaderboard: highest floor reached, then team power, then who got there first. */
export type TowerRankingEntry = {
  rank: number;
  userId: string;
  name: string;
  username?: string | null;
  photoUrl?: string | null;
  floor: number;
  power: number;
  updatedAt?: string | null;
  isYou: boolean;
};
export type TowerRanking = {
  totalPlayers: number;
  highestFloor: number;
  top: TowerRankingEntry[];
  you: { rank: number; floor: number; power: number; updatedAt?: string | null } | null;
};

/** Milestone rewards shown on the tower screen (presentational only). */
export const TOWER_MILESTONES = [
  { floor: 10, reward: '50,000 BERRIES + Eternity Key x1 + Eternity Chest x1' },
  { floor: 20, reward: 'Eternity Chest x2' },
  { floor: 25, reward: '100,000 BERRIES + Universal Frag. x15 + Void Key x1' },
  { floor: 30, reward: 'Void Chest x1' },
  { floor: 40, reward: 'Eternity Chest x2' },
  { floor: 50, reward: '150,000 BERRIES + Epic Gear Chest + Void Key x1 + Void Chest x2' },
  { floor: 60, reward: 'Celestial Chest x1' },
  { floor: 70, reward: 'Void Chest x2' },
  { floor: 75, reward: '250,000 BERRIES + Universal Frag. x25 + Celestial Key x1' },
  { floor: 80, reward: 'Celestial Chest x1' },
  { floor: 90, reward: 'Celestial Chest x2' },
  { floor: 100, reward: '500,000 BERRIES + Legendary Gear Chest + Celestial Key x1 + Celestial Chest x3' },
] as const;
