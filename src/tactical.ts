/**
 * TACTICAL ARENA (3v3) client contracts.
 *
 * The server is the single authority: the app only renders `tactical_dashboard`
 * / `tactical_match_json` and submits `skill + target`. No damage, cooldown,
 * rating or winner math happens here.
 */
export type TacticalSkillTarget = 'SELF' | 'SINGLE_ENEMY' | 'ALL_ENEMIES' | 'SINGLE_ALLY' | 'ALL_ALLIES';

export type TacticalSkill = {
  skillKey: string;
  nameKey: string;
  class: string;
  type: 'DAMAGE' | 'HEAL' | 'SHIELD' | 'BUFF' | 'DEBUFF' | 'DOT' | 'STUN' | 'CLEANSE';
  multiplier: number;
  cooldown: number;
  target: TacticalSkillTarget;
  duration: number;
  unlocked?: boolean;
  position?: number;
};

export type TacticalHero = {
  heroId: string;
  name: string;
  imageUrl: string;
  rarity: string;
  level: number;
  power: number;
  finalAtk: number;
  finalHp: number;
  class: string;
  slot?: number;
  isNft?: boolean;
  nftSerial?: number | null;
  archetype?: string;
  blockReason?: string | null;
  templateId?: string;
  heroKey?: string;
};

export type TacticalUnit = {
  uid: string;
  side: 'a' | 'b';
  slot: number;
  name: string;
  image: string;
  rarity: string;
  level: number;
  class: string;
  atk: number;
  hp: number;
  maxHp: number;
  def: number;
  speed: number;
  shield: number;
  alive: boolean;
  statuses: { key: string; turns?: number; value?: number }[];
  isNft?: boolean;
};

export type TacticalDashboard = {
  userId: string;
  config: { enabled?: boolean; teamSize?: number; deckSize?: number; turnTimerSeconds?: number; ticketCost?: number };
  available: boolean;
  testMode: boolean;
  isAdmin: boolean;
  rating: number;
  bestRating: number;
  league: string;
  wins: number;
  losses: number;
  matches: number;
  tickets: number;
  team: TacticalHero[];
  deck: TacticalSkill[];
  teamClasses: string[];
  skills: TacticalSkill[];
  activeMatchId: string | null;
  queue: { status?: string; enqueued_at?: string } | null;
  ownedHeroes: TacticalHero[];
};

export type TacticalMatch = {
  matchId: string;
  status: 'active' | 'finished' | 'abandoned';
  turn: number;
  side: 'a' | 'b';
  practice: boolean;
  units: Record<string, TacticalUnit>;
  deck: TacticalSkill[];
  cooldowns: Record<string, number>;
  you: string;
  opponent: string;
  opponentAvatar?: string | null;
  yourAvatar?: string | null;
  submitted: boolean;
  secondsLeft: number;
  turnTimerSeconds: number;
  damageScale: number;
  winner: 'you' | 'opponent' | 'draw' | null;
  ratingDelta: number | null;
  rating: number | null;
  log: { turn: number; entries: unknown[] }[];
};

export type TacticalQueueState = { status: 'idle' | 'searching' | 'matched'; matchId?: string; waitedSeconds?: number; practice?: boolean };

export type TacticalHistoryEntry = {
  matchId: string;
  opponent: string;
  practice: boolean;
  result: 'win' | 'loss' | 'draw';
  ratingChange: number;
  turns: number;
  createdAt: string;
};

export type TacticalRanking = {
  top: { position: number; userId: string; name: string; username?: string | null; avatarUrl?: string | null; rating: number; league: string; wins: number; losses: number }[];
  you: { position: number; rating: number; league: string } | null;
};

export const BASIC_ATTACK: TacticalSkill = {
  skillKey: 'basic_attack',
  nameKey: 'tactical.skill.basicAttack',
  class: 'any',
  type: 'DAMAGE',
  multiplier: 1,
  cooldown: 0,
  target: 'SINGLE_ENEMY',
  duration: 0,
};
