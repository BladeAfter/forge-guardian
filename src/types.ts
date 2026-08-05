export type TabKey = 'village' | 'missions' | 'boss' | 'wallet' | 'profile';

export type BuildingState = {
  id: string;
  name: string;
  level: number;
  productionPerHour: number;
  storage: number;
  upgradeCost: number;
  locked: boolean;
};

export type MissionState = {
  id: string;
  title: string;
  description: string;
  reward: number;
  complete: boolean;
  claimed?: boolean;
};

export type BossState = {
  name: string;
  healthPercent: number;
  playerDamage: number;
  participants: number;
  timeRemaining: string;
  rewards: number;
  teamProgress: number;
  rewardClaimed?: boolean;
  maxHealth?: number;
  defeats?: number;
};

export type WalletState = {
  connected: boolean;
  address?: string;
  availableTon: number;
  depositTon: number;
  withdrawFc: number;
  pendingDeposits: DepositRequest[];
  pendingWithdrawals: WithdrawalRequest[];
};

export type DepositRequest = {
  id: string;
  tonAmount: number;
  status: 'pending' | 'confirmed' | 'rejected' | 'paid';
  createdAt: string;
};

export type WithdrawalRequest = {
  id: string;
  fcAmount: number;
  fee: number;
  status: 'pending' | 'confirmed' | 'rejected' | 'paid';
  createdAt: string;
};

export type GameSettings = {
  conversionRate: number;
  minDepositTon: number;
  minWithdrawalFc: number;
  withdrawalFeePercent: number;
  offlineCapHours: number;
};

export type LedgerEntry = {
  id: string;
  type: 'deposit' | 'withdrawal' | 'collect' | 'upgrade' | 'mission' | 'boss' | 'shop' | 'refund';
  amount: number;
  previousBalance: number;
  newBalance: number;
  reference: string;
  createdAt: string;
  metadata?: Record<string, unknown>;
};

export type GameState = {
  balance: number;
  level: number;
  loginStreak: number;
  lastLoginDate?: string;
  dailyCycleDate?: string;
  offlineProduction: number;
  lastCollectedAt: string;
  productionRate: number;
  buildings: BuildingState[];
  missions: MissionState[];
  boss: BossState;
  ledger: LedgerEntry[];
  settings: GameSettings;
  pendingDeposits: DepositRequest[];
  pendingWithdrawals: WithdrawalRequest[];
  heroInventory?: Record<string, number>;
  bossTeam?: string[];
};

export type LanguageStrings = {
  loading: string;
  welcome: string;
  welcomeBack: string;
  approxTon: string;
  productionPerHour: string;
  villageLevel: string;
  loginStreak: string;
  offlineProduction: string;
  collect: string;
  collected: string;
  buildings: string;
  villageBuildings: string;
  storage: string;
  upgradeCost: string;
  upgrade: string;
  missions: string;
  dailyQuests: string;
  boss: string;
  bossHealth: string;
  yourDamage: string;
  timeRemaining: string;
  hoursLeft: string;
  notEnoughFunds: string;
  wallet: string;
  profile: string;
  connectWallet: string;
  disconnectWallet: string;
  deposit: string;
  withdraw: string;
  depositTon: string;
  withdrawFc: string;
  depositHistory: string;
  withdrawHistory: string;
  pending: string;
  confirmed: string;
  rejected: string;
  paid: string;
  noWallet: string;
  missingBackend: string;
  tabs: {
    village: string;
    missions: string;
    boss: string;
    wallet: string;
    profile: string;
  };
  levelLabel: string;
};
