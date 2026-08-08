import { createClient } from '@supabase/supabase-js';
import { forgeFetch } from './apiClient';
import { supabaseAnonKey, supabaseUrl } from './supabaseEnv';
import type { GameState } from './types';
import { buildDefaults } from './utils';
import type { BossCombat } from './combat';
import type { ReferralDashboard } from './referrals';
import type {PetActionResponse,PetDashboard} from './pets';
import type {PvpBattleResult,PvpDashboard,PvpHero,PvpOpponent} from './pvp';
import type { TonPaymentIntent, WalletSummary } from './wallet';
import type { TelegramPlayerProfile } from './playerProfile';
import type {CalendarClaimResult,CalendarDashboard} from './calendarRewards';
import type{PassTier,SeasonPassDashboard,SeasonPassOrder}from'./seasonPass';
import type{CommunityPoolDashboard}from'./communityPool';

const demoPlayerId = (telegramInitData: string) => {
  try {
    const user = new URLSearchParams(telegramInitData).get('user');
    if (user) return String((JSON.parse(user) as { id?: number }).id ?? 'browser');
  } catch {
    // Invalid development init data falls back to an isolated browser profile.
  }
  return 'browser';
};

const demoStorageKey = (telegramInitData: string) => `forge-village-demo-state-v2:${demoPlayerId(telegramInitData)}`;

const localDateKey = (date = new Date()) => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
};

const applyDailyCycle = (state: GameState): GameState => {
  const today = localDateKey();
  if (state.lastLoginDate === today) return state;

  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  const isConsecutive = state.lastLoginDate === localDateKey(yesterday);
  const missions = state.missions.map((mission) => ({
    ...mission,
    complete: mission.id === 'mission-1',
    claimed: false
  }));

  return {
    ...state,
    loginStreak: isConsecutive ? state.loginStreak + 1 : 1,
    lastLoginDate: today,
    dailyCycleDate: today,
    missions
  };
};

const loadDemoState = (telegramInitData: string): GameState => {
  const defaults = buildDefaults();
  const storageKey = demoStorageKey(telegramInitData);
  try {
    const saved = localStorage.getItem(storageKey);
    if (!saved) return applyDailyCycle(defaults);
    const state = JSON.parse(saved) as GameState;
    const elapsedHours = Math.max(0, Date.now() - new Date(state.lastCollectedAt).getTime()) / 3_600_000;
    const productionPerHour = state.buildings.reduce((sum, building) => sum + building.productionPerHour, 0);
    const capacity = state.buildings.reduce((sum, building) => sum + building.storage, 0);
    return applyDailyCycle({
      ...defaults,
      ...state,
      offlineProduction: Math.min(capacity, Math.floor(productionPerHour * Math.min(elapsedHours, state.settings.offlineCapHours)))
    });
  } catch {
    localStorage.removeItem(storageKey);
    return applyDailyCycle(defaults);
  }
};

export const saveDemoState = (state: GameState, telegramInitData: string) => {
  if (!supabase) localStorage.setItem(demoStorageKey(telegramInitData), JSON.stringify(state));
};

const supabaseKey = supabaseAnonKey;

export const supabase = supabaseUrl && supabaseKey ? createClient(supabaseUrl, supabaseKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false
  }
}) : null;

export const fetchGameState = async (telegramInitData: string): Promise<GameState> => {
  if (import.meta.env.DEV || !supabase) return loadDemoState(telegramInitData);

  const { data, error } = await supabase.rpc('get_game_state', {
    telegram_init_data: telegramInitData
  });

  // The village economy (buildings/missions) has no server table yet: when the
  // RPC is absent we keep the local progression instead of breaking the screen.
  if (error?.code === 'PGRST202' || error?.code === '42883') {
    console.error('[FORGE API ERROR]', { feature: 'game-state', endpoint: 'rpc:get_game_state', status: 404, error, response: null });
    return loadDemoState(telegramInitData);
  }
  if (error) throw new Error(error.message);
  if (!data) throw new Error('The game backend returned no data.');
  return data as GameState;
};


export async function bossRequest(telegramInitData: string, action: 'get'|'process'|'team'|'claim'='process', heroIds?: string[]): Promise<BossCombat> {
  const response=await forgeFetch('boss',({initData:telegramInitData,action,heroIds}));
  const payload=await response.json().catch(()=>null) as BossCombat & {error?:string} | null;
  if(!response.ok || !payload) throw new Error(payload?.error || 'Unable to synchronize boss combat.');
  return payload;
}

export type HeroShopConfig={prices:Record<string,number>;odds:Record<string,number>;version?:number};

/** Recruitment prices and summon odds come from admin settings, never hardcoded. */
export async function fetchHeroShopConfig(telegramInitData:string):Promise<HeroShopConfig>{
  const response=await forgeFetch('boss',({initData:telegramInitData,action:'shop'}));
  const payload=await response.json().catch(()=>null) as HeroShopConfig&{error?:string}|null;
  if(!response.ok||!payload?.prices)throw new Error(payload?.error||'Unable to load hero shop config.');
  return payload;
}

export async function recruitHeroesOnServer(telegramInitData:string,count:1|5|10){
  const response=await forgeFetch('boss',({initData:telegramInitData,action:'recruit',count}));
  const payload=await response.json().catch(()=>null) as {heroes:Array<{heroKey:string}>;balance:number;error?:string}|null;
  if(!response.ok||!payload)throw new Error(payload?.error||'Recruitment failed.'); return payload;
}

export async function equipCombatHeroOnServer(telegramInitData:string,heroId:string,slot:1|2|3|4|5):Promise<BossCombat>{
  const response=await forgeFetch('boss',({initData:telegramInitData,action:'equip',hero_id:heroId,slot}));
  const payload=await response.json().catch(()=>null) as BossCombat & {error?:string}|null;
  if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível equipar o herói.');
  return payload;
}

export async function fetchReferralDashboard(telegramInitData:string,level?:1|2|3,offset=0):Promise<ReferralDashboard>{
  const response=await forgeFetch('referral',({initData:telegramInitData,action:'dashboard',level,offset,limit:20}));
  const payload=await response.json().catch(()=>null) as ReferralDashboard&{error?:string}|null;
  if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar seus convites.');
  return {...payload,invites:Array.isArray(payload.invites)?payload.invites:[],tree:Array.isArray(payload.tree)?payload.tree:[],ranking:Array.isArray(payload.ranking)?payload.ranking:[],bonuses:Array.isArray(payload.bonuses)?payload.bonuses:[],notifications:Array.isArray(payload.notifications)?payload.notifications:[]};
}
export async function bindReferral(telegramInitData:string,inviterTelegramId:number){
  const response=await forgeFetch('referral',({initData:telegramInitData,action:'bind',inviterTelegramId}));
  const payload=await response.json().catch(()=>null) as {linked?:boolean;error?:string}|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível registrar o convite.');return payload;
}
export type PetAction={action:'dashboard'}|{action:'activate';playerPetId:string}|{action:'evolve';playerPetId:string;idempotencyKey?:string}|{action:'feed';playerPetId:string;foodCode:string;quantity:number;idempotencyKey?:string}|{action:'hatch';eggId:string;idempotencyKey:string};
const PET_ERRORS:Record<string,string>={PET_NOT_OWNED:'Este pet não pertence a você.',PET_MAX_LEVEL:'Este pet já está no nível máximo.',PET_LEVEL_TOO_LOW:'Nível insuficiente para evoluir.',PET_FULLY_EVOLVED:'Este pet já alcançou a forma final.',NOT_ENOUGH_PET_FOOD:'Você não tem comida suficiente.',NOT_ENOUGH_PET_FRAGMENTS:'Fragmentos insuficientes para evoluir.',NOT_ENOUGH_FORGE_COINS:'Forge Coins insuficientes.',FOOD_NOT_FOUND:'Comida indisponível.',PLAYER_NOT_FOUND:'Jogador não encontrado.'};
export async function petRequest(telegramInitData:string,input:PetAction={action:'dashboard'}):Promise<PetActionResponse>{const response=await forgeFetch('pets',({initData:telegramInitData,...input}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar o servidor dos pets.');const payload=await response.json().catch(()=>null) as (PetActionResponse&{error?:string})|null;if(!response.ok||!payload){const raw=payload?.error||'';throw new Error(PET_ERRORS[raw]||raw||'Não foi possível carregar os pets.')}return payload}
export type PvpAction={action:'dashboard'|'search'}|{action:'equip';teamType:'attack'|'defense';slot:number;heroId:string}|{action:'remove';teamType:'attack'|'defense';slot:number}|{action:'battle';opponentId:string};
export async function pvpRequest<T=PvpDashboard>(telegramInitData:string,input:PvpAction={action:'dashboard'}):Promise<T>{const response=await forgeFetch('pvp',({initData:telegramInitData,...input}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar a Arena.');const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload){const raw=payload?.error||'',friendly:Record<string,string>={ATTACK_TEAM_EMPTY:'Equipe de ataque vazia.',NO_PVP_TICKETS:'Você não possui tickets.',OPPONENT_UNAVAILABLE:'Adversário indisponível.',INVALID_DEFENSE_TEAM:'Equipe defensiva inválida.',BATTLE_ALREADY_STARTED:'A batalha já foi iniciada.'};throw new Error(friendly[raw]||raw||'Não foi possível processar o PvP.')}return payload}
export const searchPvpOpponents=(initData:string)=>pvpRequest<{opponents:PvpOpponent[]}>(initData,{action:'search'});
export const startPvpBattle=(initData:string,opponentId:string)=>pvpRequest<PvpBattleResult>(initData,{action:'battle',opponentId});
export type WalletAction={action:'summary'}|{action:'deposit';amountTon:number;walletAddress:string;idempotencyKey:string}|{action:'withdraw';amountFc:number;walletAddress:string;idempotencyKey:string}|{action:'egg-order';eggId:string;idempotencyKey:string};
export async function walletRequest<T=WalletSummary>(telegramInitData:string,input:WalletAction={action:'summary'}):Promise<T>{const response=await forgeFetch('wallet',({initData:telegramInitData,...input}));const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível processar a carteira.');return payload}
export const createDepositIntent=(initData:string,amountTon:number,walletAddress:string,idempotencyKey:string)=>walletRequest<TonPaymentIntent>(initData,{action:'deposit',amountTon,walletAddress,idempotencyKey});
export const requestWithdrawal=(initData:string,amountFc:number,walletAddress:string,idempotencyKey:string)=>walletRequest(initData,{action:'withdraw',amountFc,walletAddress,idempotencyKey});
export const createEggTonOrder=(initData:string,eggId:string,idempotencyKey:string)=>walletRequest<TonPaymentIntent>(initData,{action:'egg-order',eggId,idempotencyKey});

export async function fetchTelegramProfile(telegramInitData:string):Promise<TelegramPlayerProfile>{
  const response=await forgeFetch('profile',({initData:telegramInitData}));
  const payload=await response.json().catch(()=>null) as (TelegramPlayerProfile&{error?:string})|null;
  if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar seu perfil do Telegram.');
  return {...payload,telegramId:String(payload.telegramId)};
}
export async function calendarRequest<T=CalendarDashboard>(telegramInitData:string,action:'dashboard'|'claim'='dashboard',day?:number):Promise<T>{const response=await forgeFetch('calendar',({initData:telegramInitData,action,day}));const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar o calendário.');return payload}
export const claimCalendarDay=(initData:string,day:number)=>calendarRequest<CalendarClaimResult>(initData,'claim',day);
export async function openCalendarChest(initData:string,inventoryItemId:string){const response=await forgeFetch('calendar',({initData,action:'open-chest',inventoryItemId}));const payload=await response.json().catch(()=>null)as{hero:{id:string;name:string;image:string;rarity:string;level:number;baseAtk:number;baseHp:number};error?:string}|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível abrir o baú.');return payload}
export async function seasonPassRequest<T=SeasonPassDashboard>(initData:string,action:'dashboard'|'order'|'claim'='dashboard',data:Record<string,unknown>={}):Promise<T>{const response=await forgeFetch('season-pass',({initData,action,...data}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar o servidor do Passe.');const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar o Passe.');return payload}
export const createSeasonPassOrder=(initData:string,tier:PassTier)=>seasonPassRequest<SeasonPassOrder>(initData,'order',{tier,idempotencyKey:crypto.randomUUID()});
export async function communityPoolRequest(initData:string):Promise<CommunityPoolDashboard>{const response=await forgeFetch('pool',({initData,action:'dashboard'}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar a Pool Comunitária.');const payload=await response.json().catch(()=>null)as(CommunityPoolDashboard&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar a Pool Comunitária.');return payload}

// Hero collection is independent from PvP stats/matchmaking: a PvP failure must
// never wipe the collection, and an empty collection is a valid empty state.
export async function fetchPlayerHeroes(initData:string):Promise<{heroes:PvpHero[]}>{
  const response=await forgeFetch('pvp',{initData,action:'heroes'});
  if(response.status===404)throw new Error('Backend indisponível: não foi possível carregar sua coleção de heróis.');
  const payload=await response.json().catch(()=>null)as{heroes?:PvpHero[];error?:string}|null;
  if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar sua coleção de heróis.');
  return {heroes:Array.isArray(payload.heroes)?payload.heroes:[]};
}
