/**
 * NFT BREEDING + SUB-NFT + PET EXPEDITIONS — client types only.
 * Every rule (cost tier, breed count, cooldown, maturation, mining cap, success roll)
 * is resolved server-side; these shapes only mirror what the backend returns.
 */

export type BreedingBlockReason =
  | 'NFT_NOT_FOUND' | 'NFT_NOT_OWNED' | 'NFT_LOCKED'
  | 'MAX_BREEDING_REACHED' | 'BREEDING_COOLDOWN' | 'NFT_IN_BREEDING' | null;

export type BreedingNft = {
  nftId: string;
  serial: number;
  instance: string;
  name: string;
  image: string | null;
  element: string;
  breedCount: number;
  maxBreeds: number;
  cooldownUntil: string | null;
  nextCost: number;
  blockReason: BreedingBlockReason;
};

export type PartnerNft = {
  nftId: string;
  serial: number;
  name: string;
  image: string | null;
  element: string;
  breedCount: number;
  nextCost: number;
  ownerName: string | null;
  ownerUsername: string | null;
  ownerTelegramId: number;
};

type MiniNft = { serial: number; name: string; image?: string | null } | null;

export type BreedingRequestRow = {
  requestId: string;
  status: 'pending' | 'accepted';
  yourCost: number;
  partnerCost?: number;
  selfBreed?: boolean;
  expiresAt: string;
  paidYou: boolean;
  paidPartner: boolean;
  fromName?: string | null;
  fromUsername?: string | null;
  partnerName?: string | null;
  yourNft: MiniNft;
  partnerNft: MiniNft;
};

export type SubNftStage = 'EGG' | 'BABY' | 'JUVENILE' | 'ADULT';

export type SubNft = {
  id: string;
  instance: string;
  serial: number;
  name: string;
  image: string | null;
  element: string;
  stage: SubNftStage;
  birthTime: string;
  maturesAt: string;
  generation: number;
  trait: string | null;
  traitName: string | null;
  miningStatus: 'PENDING' | 'ACTIVE' | 'COMPLETE';
  rateTonDay: number;
  capTon: number;
  minedTon: number;
  unclaimedTon: number;
  parents: { a: { serial: number; name: string } | null; b: { serial: number; name: string } | null };
};

export type BreedingState = {
  enabled: boolean;
  settings: {
    maxBreeds: number;
    cooldownDays: number;
    costs: number[];
    ttlMinutes: number;
    minClaimTon: number;
    maturity: { babyHours: number; juvenileHours: number; adultHours: number };
  };
  tonBalance: number;
  myNfts: BreedingNft[];
  incoming: BreedingRequestRow[];
  outgoing: BreedingRequestRow[];
  subNfts: SubNft[];
  unclaimedTon: number;
};

export type ExpeditionPet = {
  playerPetId: string;
  name: string;
  image: string | null;
  rarity: string;
  level: number;
  power: number;
  isSubNft: boolean;
  stage: SubNftStage | null;
  trait: string | null;
  eligible: boolean;
  busy: boolean;
};

export type ExpeditionReward = { type: string; code?: string; rarity?: string; min?: number; max?: number; chance?: number; quantity?: number };

/** Per (player, mission, game day) attempt counters. Ads and BERRIES are independent limits. */
export type ExpeditionAttempts = {
  missionId: string;
  period: string;
  resetsAt: string;
  freeLimit: number;
  freeUsed: number;
  freeRemaining: number;
  adsUsed: number;
  adsLimit: number;
  adsRemaining: number;
  fcUsed: number;
  fcLimit: number;
  fcRemaining: number;
  extraAvailable: number;
  priceFc: number;
  canStart: boolean;
};

export type ExpeditionMission = {
  id: string;
  code: string;
  name: string;
  rarity: 'COMMON' | 'UNCOMMON' | 'RARE' | 'EPIC' | 'LEGENDARY';
  durationHours: number;
  requiredPower: number;
  element: string | null;
  rewards: ExpeditionReward[];
  attempts: ExpeditionAttempts;
};


export type ActiveExpedition = {
  id: string;
  missionName: string;
  missionRarity: string;
  startedAt: string;
  finishesAt: string;
  teamPower: number;
  successChance: number;
  ready: boolean;
  /** AD BOOST counters: rewarded ads already used on this expedition and the cap. */
  adBoostsUsed?: number;
  maxAdBoosts?: number;
  pets: { name: string; image: string | null }[] | null;
};

export type ExpeditionState = {
  limits?: { freeAttemptsPerDay: number; maxAdsPerMissionPerDay: number; maxFcPurchasesPerMissionPerDay: number };
  pets: ExpeditionPet[];

  missions: ExpeditionMission[];
  active: ActiveExpedition[];
  history: { id: string; missionName: string; success: boolean | null; rewards: ExpeditionReward[]; claimedAt: string }[];
};

/** Mirrors public.expedition_success_chance for the preview shown before starting. */
export const expeditionChance = (power: number, required: number, bonus = 0) =>
  Math.max(15, Math.min(95, Math.round(70 + (power / Math.max(1, required) - 1) * 50 + bonus)));

export const countdown = (iso: string | null | undefined) => {
  if (!iso) return '';
  const ms = new Date(iso).getTime() - Date.now();
  if (ms <= 0) return '00m';
  const days = Math.floor(ms / 86_400_000);
  const hours = Math.floor((ms % 86_400_000) / 3_600_000);
  const minutes = Math.floor((ms % 3_600_000) / 60_000);
  if (days > 0) return `${days}d ${String(hours).padStart(2, '0')}h`;
  if (hours > 0) return `${hours}h ${String(minutes).padStart(2, '0')}m`;
  return `${String(minutes).padStart(2, '0')}m`;
};

export const STAGE_LABEL: Record<SubNftStage, string> = {
  EGG: 'SUB-NFT EGG',
  BABY: 'BABY SUB-NFT',
  JUVENILE: 'JUVENILE SUB-NFT',
  ADULT: 'ADULT SUB-NFT',
};
