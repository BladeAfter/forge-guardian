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

export type TowerRewards = {
  fragments: number;
  heroXp: number;
  petFood: number;
  heroChest: number;
  towerKey: number;
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
  dashboard: TowerDashboard;
};

/** Milestone rewards shown on the tower screen (presentational only). */
export const TOWER_MILESTONES = [
  { floor: 10, reward: '50,000 FC + Eternity Key x1' },
  { floor: 25, reward: 'Rare Fragments x15' },
  { floor: 50, reward: 'Legendary Fragments x10' },
  { floor: 75, reward: 'Mythic Egg x1' },
  { floor: 100, reward: 'Ancestral Fragments x25' },
] as const;
