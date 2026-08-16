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
  /** Straight FC bonus paid on a clear. */
  forgeCoins?: number;
  /** Universal fragments (hero fusion currency). */
  universalFragments?: number;
  /** Drop chance in % for each tower key, per floor band (display only). */
  keyChances?: Record<string, number>;
  /** Keys actually granted on this clear (code -> quantity). */
  keys?: Record<string, number>;
  /** Equipment instance dropped on this clear (null when nothing dropped). */
  equipment?: TowerEquipmentDrop | null;
};

/** The 3 collectible tower keys. They have NO function yet — inventory display only. */
export const TOWER_KEYS = [
  { code: 'eternity_key', name: 'Eternity Key', rarity: 'rare', image: '/assets/game/ui/eternity-key.png', color: '#60a5fa' },
  { code: 'void_key', name: 'Void Key', rarity: 'epic', image: '/assets/game/ui/void-key.png', color: '#c084fc' },
  { code: 'celestial_key', name: 'Celestial Key', rarity: 'legendary', image: '/assets/game/ui/celestial-key.png', color: '#fbbf24' },
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
  balanceFc: number;
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
  { floor: 10, reward: '50,000 FC + Eternity Key x1' },
  { floor: 25, reward: 'Rare Fragments x15' },
  { floor: 50, reward: 'Legendary Fragments x10' },
  { floor: 75, reward: 'Mythic Egg x1' },
  { floor: 100, reward: 'Ancestral Fragments x25' },
] as const;
