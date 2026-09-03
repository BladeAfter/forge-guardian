/**
 * MYTHREON REALM — client-side types and API access.
 *
 * The Realm is 100% server-authoritative: timers, costs, material ledger and every
 * reward roll live in the database (see `realm_*` RPCs). This module only carries the
 * shape of the payload and the friendly PT-BR error copy.
 */
import { forgeFetch } from './apiClient';

export type RealmRegion = {
  id: string;
  name: string;
  tagline: string;
  order_index: number;
  image_url: string | null;
  recommended_power: number;
  unlock_stronghold_level: number;
  unlock_requires_region: string | null;
  ruin_enabled: boolean;
};

export type RealmMaterial = {
  id: string;
  name: string;
  rarity: string;
  region_id: string | null;
  image_url: string | null;
  order_index: number;
};

export type RealmBuildingType = {
  id: string;
  name: string;
  description: string;
  image_url: string | null;
  max_level: number;
  base_fc_cost: number;
  base_seconds: number;
  cost_materials: Record<string, number>;
};

export type RealmBuilding = {
  id: string;
  building_type: string;
  level: number;
  status: 'idle' | 'upgrading' | 'ready';
  upgrade_finishes_at: string | null;
};

export type RealmRecipe = {
  id: string;
  name: string;
  category: string;
  inputs: Record<string, number>;
  fc_cost: number;
  craft_seconds: number;
  min_forge_level: number;
  output_kind: 'material' | 'item';
  output_ref: string;
  output_qty: number;
};

export type RealmExpedition = {
  id: string;
  region_id: string;
  expedition_type: 'gather' | 'deep';
  finishes_at: string;
  status: string;
  reward: Record<string, number> | null;
};

export type RealmCraftJob = {
  id: string;
  recipe_id: string;
  quantity: number;
  finishes_at: string;
  status: string;
};

export type RealmRuinRun = {
  id: string;
  region_id: string;
  current_room: number;
  hp: number;
  ruin_coins: number;
  status: string;
};

export type RealmRuinRoom = {
  id: string;
  room_index: number;
  branch: number;
  room_type: string;
  status: string;
  config: { difficulty?: number } | null;
};

export type RealmExploreLoot = {
  fc?: number;
  fragments?: number;
  materials?: Record<string, number>;
  outcome?: string;
};

export type RealmExploreRun = {
  id: string;
  region_id: string;
  hp: number;
  depth: number;
  final_depth: number;
  risk: number;
  loot: RealmExploreLoot | null;
  pending: { nodeId: string; nodeType: string; options: string[] } | null;
  status: string;
};

export type RealmExploreNodeType =
  | 'combat' | 'elite' | 'boss' | 'gather' | 'treasure' | 'event' | 'trap' | 'shrine' | 'rest';

export type RealmExploreNode = {
  id: string;
  depth: number;
  lane: number;
  node_type: RealmExploreNodeType;
  status: 'locked' | 'available' | 'active' | 'resolved' | 'skipped';
  config: { difficulty?: number; x?: number; y?: number } | null;
};

/** Result of entering/resolving one node — drives the combat overlay and loot toasts. */
export type RealmExploreLog = {
  nodeType?: RealmExploreNodeType;
  option?: string;
  damage?: number;
  fc?: number;
  fragments?: number;
  material?: string | null;
  materialQty?: number;
  rounds?: { round: number; playerHit: number; enemyHit: number }[];
  hp?: number;
  depth?: number;
  risk?: number;
  result?: 'ongoing' | 'failed' | 'cleared' | 'pending';
  reward?: RealmExploreLoot;
  nodeId?: string;
  options?: string[];
};

export type RealmBounty = {
  id: string;
  bounty_type: string;
  title: string;
  target: number;
  progress: number;
  reward: { fc?: number; fragments?: number };
  status: string;
};


export type RealmProfile = {
  stronghold_level: number;
  realm_level: number;
  realm_xp: number;
  current_region: string | null;
  ruins_completed: number;
  crafts_completed: number;
  buildings_upgraded: number;
};

export type RealmState = {
  profile: RealmProfile | null;
  fc: number;
  regions: RealmRegion[];
  materials: RealmMaterial[];
  buildingTypes: RealmBuildingType[];
  recipes: RealmRecipe[];
  buildings: RealmBuilding[];
  balances: Record<string, number>;
  expeditions: RealmExpedition[];
  crafting: RealmCraftJob[];
  ruinRun: RealmRuinRun | null;
  ruinRooms: RealmRuinRoom[];
  exploreRun: RealmExploreRun | null;
  exploreNodes: RealmExploreNode[];
  bounties: RealmBounty[];
  lastReward?: Record<string, unknown>;
  lastRoom?: Record<string, unknown>;
  lastNode?: RealmExploreLog;
  autoLog?: RealmExploreLog[];
};


const REALM_ERRORS: Record<string, string> = {
  REALM_LOCKED: 'O MYTHREON REALM ainda está em acesso antecipado.',
  REALM_BUILDING_BUSY: 'Esta construção já está em obras.',
  REALM_BUILDING_MAX: 'Nível máximo alcançado.',
  REALM_CASTLE_TOO_LOW: 'Suba o Castelo antes de evoluir esta construção.',
  REALM_NOT_ENOUGH_FC: 'Forge Coins insuficientes.',
  REALM_NOT_READY: 'Ainda não terminou.',
  REALM_REGION_LOCKED: 'Região bloqueada: evolua o Stronghold.',
  REALM_EXPEDITION_SLOTS_FULL: 'Todas as rotas de expedição estão ocupadas.',
  REALM_CRAFT_SLOTS_FULL: 'Todas as bancadas da Forja estão ocupadas.',
  REALM_FORGE_TOO_LOW: 'Nível da Forja insuficiente para esta receita.',
  REALM_BOUNTY_INCOMPLETE: 'Contrato ainda não concluído.',
  PLAYER_NOT_FOUND: 'Jogador não encontrado.',
};

export async function realmCall<T = RealmState>(initData: string, body: Record<string, unknown>): Promise<T> {
  const response = await forgeFetch('realm', { initData, ...body });
  const payload = (await response.json().catch(() => null)) as (T & { error?: string }) | null;
  if (!response.ok || !payload) {
    const raw = String(payload?.error || '');
    const match = Object.keys(REALM_ERRORS).find((code) => raw.includes(code));
    throw new Error(match ? REALM_ERRORS[match] : raw || 'Falha no MYTHREON REALM.');
  }
  return payload;
}

export const fetchRealmState = (initData: string) => realmCall(initData, { action: 'state' });
export const realmUpgradeBuilding = (initData: string, buildingType: string) =>
  realmCall(initData, { action: 'upgrade-building', buildingType });
export const realmClaimBuilding = (initData: string, buildingType: string) =>
  realmCall(initData, { action: 'claim-building', buildingType });
export const realmStartExpedition = (initData: string, regionId: string, expeditionType: 'gather' | 'deep') =>
  realmCall(initData, { action: 'start-expedition', regionId, expeditionType, idempotencyKey: crypto.randomUUID() });
export const realmClaimExpedition = (initData: string, expeditionId: string) =>
  realmCall(initData, { action: 'claim-expedition', expeditionId });
export const realmStartCraft = (initData: string, recipeId: string, quantity: number) =>
  realmCall(initData, { action: 'start-craft', recipeId, quantity, idempotencyKey: crypto.randomUUID() });
export const realmClaimCraft = (initData: string, jobId: string) =>
  realmCall(initData, { action: 'claim-craft', jobId });
export const realmRuinStart = (initData: string, regionId: string) =>
  realmCall(initData, { action: 'ruin-start', regionId });
export const realmRuinChoose = (initData: string, runId: string, branch: number) =>
  realmCall(initData, { action: 'ruin-choose', runId, branch });
export const realmRuinExtract = (initData: string, runId: string) =>
  realmCall(initData, { action: 'ruin-extract', runId });
export const realmEnsureBounties = (initData: string) => realmCall(initData, { action: 'bounties' });
export const realmClaimBounty = (initData: string, bountyId: string) =>
  realmCall(initData, { action: 'claim-bounty', bountyId });

// ── INTERACTIVE EXPLORATION ────────────────────────────────────────────────
export const realmExploreStart = (initData: string, regionId: string) =>
  realmCall(initData, { action: 'explore-start', regionId });
export const realmExploreEnter = (initData: string, runId: string, nodeId: string) =>
  realmCall(initData, { action: 'explore-enter', runId, nodeId });
export const realmExploreChoose = (initData: string, runId: string, option: string) =>
  realmCall(initData, { action: 'explore-choose', runId, option });
export const realmExploreExtract = (initData: string, runId: string) =>
  realmCall(initData, { action: 'explore-extract', runId });
export const realmExploreAuto = (initData: string, runId: string) =>
  realmCall(initData, { action: 'explore-auto', runId });
export const realmExploreAbandon = (initData: string, runId: string) =>
  realmCall(initData, { action: 'explore-abandon', runId });


/** Remaining seconds for a server timestamp, clamped at zero. */
export const realmSecondsLeft = (iso: string | null | undefined, now = Date.now()) =>
  !iso ? 0 : Math.max(0, Math.ceil((new Date(iso).getTime() - now) / 1000));

export function realmTimer(seconds: number) {
  if (seconds <= 0) return 'PRONTO';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return h > 0
    ? `${h}h ${String(m).padStart(2, '0')}m`
    : `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

export const REALM_ROOM_LABEL: Record<string, string> = {
  combat: 'COMBATE',
  elite: 'ELITE',
  boss: 'GUARDIÃO',
  treasure: 'TESOURO',
  trap: 'ARMADILHA',
  shrine: 'SANTUÁRIO',
  rest: 'DESCANSO',
};

// ── EXPLORATION COPY (PT-BR) ───────────────────────────────────────────────
export const REALM_NODE_LABEL: Record<string, string> = {
  combat: 'COMBATE',
  elite: 'ELITE',
  boss: 'GUARDIÃO',
  gather: 'COLETA',
  treasure: 'TESOURO',
  event: 'EVENTO',
  trap: 'ARMADILHA',
  shrine: 'SANTUÁRIO',
  rest: 'ACAMPAMENTO',
};

/** Short glyph per node — drawn inside the map pin (no icon library). */
export const REALM_NODE_GLYPH: Record<string, string> = {
  combat: '⚔', elite: '👹', boss: '👑', gather: '🌿',
  treasure: '💰', event: '✨', trap: '🩸', shrine: '🛐', rest: '🏕',
};

export const REALM_NODE_TONE: Record<string, string> = {
  combat: '#f87171', elite: '#fb923c', boss: '#facc15', gather: '#4ade80',
  treasure: '#fbbf24', event: '#c084fc', trap: '#fb7185', shrine: '#60a5fa', rest: '#34d399',
};

export const REALM_NODE_TITLE: Record<string, string> = {
  combat: 'EMBOSCADA',
  elite: 'CAÇADOR ELITE',
  boss: 'GUARDIÃO DA REGIÃO',
  gather: 'VEIO DE RECURSOS',
  treasure: 'BAÚ SELADO',
  event: 'ALTAR ESQUECIDO',
  trap: 'RUNAS INSTÁVEIS',
  shrine: 'SANTUÁRIO ANTIGO',
  rest: 'ACAMPAMENTO SEGURO',
};

export const REALM_NODE_DESC: Record<string, string> = {
  combat: 'Criaturas bloqueiam a trilha. Sua equipe entra em combate.',
  elite: 'Um predador marcado pelas sombras aguarda. Recompensa alta, risco alto.',
  boss: 'O guardião da região desperta. Vencer encerra a run com bônus.',
  gather: 'Recursos brilham entre as raízes. Extrair com força rende mais e machuca.',
  treasure: 'Um baú antigo lacrado por runas. Forçar pode acionar defesas.',
  event: 'Runas antigas pulsam em um altar coberto de musgo.',
  trap: 'O chão está tomado por runas instáveis. Avance com cuidado.',
  shrine: 'Uma bênção esquecida ainda vive aqui: cure-se ou canalize poder.',
  rest: 'Um ponto seguro para recuperar a equipe.',
};

export const REALM_OPTION_LABEL: Record<string, string> = {
  safe: 'COM SEGURANÇA',
  force: 'FORÇAR (+RISCO)',
  ignore: 'IGNORAR',
  accept: 'TOCAR NO ALTAR',
  offer: 'OFERECER RECURSOS',
  bless: 'RECEBER BÊNÇÃO',
  empower: 'CANALIZAR PODER',
  careful: 'AVANÇAR COM CUIDADO',
  default: 'AVANÇAR',
};

export const REALM_RISK_LABEL = (risk: number) =>
  risk >= 70 ? 'ALTÍSSIMO' : risk >= 45 ? 'ALTO' : risk >= 20 ? 'MÉDIO' : 'BAIXO';
