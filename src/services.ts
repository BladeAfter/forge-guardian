import type {SpecialEventsDashboard} from './specialEvents';
import type {SpendingEventDashboard} from './spendingEvent';
import { createClient } from '@supabase/supabase-js';
import { forgeFetch } from './apiClient';
import { supabaseAnonKey, supabaseUrl } from './supabaseEnv';
import type { GameState } from './types';
import { buildDefaults } from './utils';
import type { BossCombat, GlobalBossRanking } from './combat';
import type { ReferralDashboard } from './referrals';
import type {PetActionResponse,PetDashboard} from './pets';
import type {PvpBattleResult,PvpDashboard,PvpHero,PvpOpponent} from './pvp';
import type { TonPaymentIntent, WalletSummary } from './wallet';
import type { TelegramPlayerProfile } from './playerProfile';
import {officialGameDayKey} from './calendarRewards';
import type {CalendarClaimResult,CalendarDashboard,ChestOpenResult,PlayerInventory} from './calendarRewards';

import type{PassTier,PassXpGain,SeasonPassDashboard,SeasonPassOrder}from'./seasonPass';
import type{CommunityPoolDashboard}from'./communityPool';
import type{DailyQuestsDashboard,QuestClaimResult}from'./quests';
import type {FusionDashboard,FusionResult, RarityFusionDashboard, RarityFusionResult} from './heroFusion';
import type {MarketBrowse,MarketBuyResult,MarketCreateResult,MarketItemType,MarketMine,MarketSellable,MarketSort} from './market';


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

// Offline/demo only: mirrors the official 21:00 America/Sao_Paulo rollover, never the device midnight.
const localDateKey = (date = new Date()) => officialGameDayKey(date);


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
      // Legacy local saves could hold a fake default balance; the server balance overwrites it on load.
      balance: 0,
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

/** Local village progression used whenever the server state is unavailable. */
export const buildLocalGameState = (telegramInitData: string): GameState => loadDemoState(telegramInitData);

export const fetchGameState = async (telegramInitData: string): Promise<GameState> => {
  if (import.meta.env.DEV || !supabase) return loadDemoState(telegramInitData);
  console.log('[GAME STATE] requesting server state');

  // A hanging request must never freeze the loading screen: the local state wins after 8s.
  const timeout = new Promise<{ data: null; error: null; timedOut: true }>((resolve) =>
    setTimeout(() => resolve({ data: null, error: null, timedOut: true }), 8_000));
  const result = await Promise.race([
    supabase.rpc('get_game_state', { telegram_init_data: telegramInitData }).then((response) => ({ ...response, timedOut: false as const })),
    timeout
  ]) as { data: unknown; error: { code?: string; message?: string } | null; timedOut: boolean };
  const { data, error } = result;
  if (result.timedOut) {
    console.error('[GAME STATE] server timeout, using local village state');
    return loadDemoState(telegramInitData);
  }

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


const BOSS_ERRORS:Record<string,string>={BOSS_NOT_ACTIVE:'Nenhum chefe ativo no momento. Aguarde o próximo desafio.',BOSS_TEAM_EMPTY:'Monte sua equipe antes de atacar o chefe.',HERO_NOT_OWNED:'Este herói não pertence a você.',INVALID_SLOT:'Slot inválido.',INVALID_TEAM:'Equipe inválida.',PLAYER_NOT_FOUND:'Jogador não encontrado.'};
const bossErrorMessage=(raw:string,fallback:string)=>{const key=Object.keys(BOSS_ERRORS).find(code=>raw.includes(code));return key?BOSS_ERRORS[key]:(raw||fallback)};

export async function bossRequest(telegramInitData: string, action: 'get'|'process'|'team'|'claim'|'attack'='process', heroIds?: string[]): Promise<BossCombat> {
  const response=await forgeFetch('boss',({initData:telegramInitData,action,heroIds}));
  const payload=await response.json().catch(()=>null) as BossCombat & {error?:string} | null;
  if(!response.ok || !payload) throw new Error(bossErrorMessage(payload?.error||'','Unable to synchronize boss combat.'));
  return payload;
}

/** Global boss ranking (shared server cycle) — read-only. */
export async function fetchGlobalBossRanking(telegramInitData:string,limit=50):Promise<GlobalBossRanking>{
  const response=await forgeFetch('boss',({initData:telegramInitData,action:'ranking',limit}));
  const payload=await response.json().catch(()=>null) as GlobalBossRanking&{error?:string}|null;
  if(!response.ok||!payload)throw new Error(bossErrorMessage(payload?.error||'','Não foi possível carregar o ranking do chefe.'));
  return {...payload,top:Array.isArray(payload.top)?payload.top:[]};
}

/** Attacking is the ONLY boss operation that requires an active boss. */
export const attackBossOnServer=(initData:string)=>bossRequest(initData,'attack');


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

/** Equipping/removing heroes works with or without an active boss (team is persisted server-side). */
export async function equipCombatHeroOnServer(telegramInitData:string,heroId:string,slot:1|2|3|4|5):Promise<BossCombat>{
  const response=await forgeFetch('boss',({initData:telegramInitData,action:'equip',hero_id:heroId,slot}));
  const payload=await response.json().catch(()=>null) as BossCombat & {error?:string}|null;
  if(!response.ok||!payload)throw new Error(bossErrorMessage(payload?.error||'','Não foi possível equipar o herói.'));
  return payload;
}

export async function unequipCombatHeroOnServer(telegramInitData:string,slot:1|2|3|4|5):Promise<BossCombat>{
  const response=await forgeFetch('boss',({initData:telegramInitData,action:'unequip',slot}));
  const payload=await response.json().catch(()=>null) as BossCombat & {error?:string}|null;
  if(!response.ok||!payload)throw new Error(bossErrorMessage(payload?.error||'','Não foi possível remover o herói.'));
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
export type PetAction={action:'dashboard'}|{action:'activate';playerPetId:string}|{action:'evolve';playerPetId:string;idempotencyKey?:string}|{action:'feed';playerPetId:string;foodCode:string;quantity:number;idempotencyKey?:string}|{action:'hatch';eggId:string;idempotencyKey:string}|{action:'recover-hatch';idempotencyKey:string}|{action:'buy-egg';eggId:string;quantity:number;idempotencyKey:string}|{action:'buy-food';foodCode:string;quantity:number;idempotencyKey:string};
const PET_ERRORS:Record<string,string>={PET_NOT_OWNED:'Este pet não pertence a você.',PET_MAX_LEVEL:'Este pet já está no nível máximo.',PET_LEVEL_TOO_LOW:'Nível insuficiente para evoluir.',PET_FULLY_EVOLVED:'Este pet já alcançou a forma final.',NOT_ENOUGH_PET_FOOD:'Você não tem comida suficiente.',NOT_ENOUGH_PET_FRAGMENTS:'Fragmentos insuficientes para evoluir.',NOT_ENOUGH_FORGE_COINS:'FC insuficientes.',FOOD_NOT_FOUND:'Comida indisponível.',FOOD_NOT_PURCHASABLE:'Esta comida não está à venda.',EGG_NOT_FOUND:'Ovo indisponível.',EGG_NOT_OWNED:"YOU DON'T OWN THIS EGG",EGG_ALREADY_OPENING:'EGG ALREADY OPENING',EGG_OPENING_FAILED:'EGG OPENING FAILED',EGG_RATES_INVALID:'EGG OPENING FAILED',EGG_NOT_PURCHASABLE:'Este ovo não pode ser comprado (evento exclusivo).',EGG_REQUIRES_TON:'Este ovo é vendido apenas em TON.',EGG_LIMIT_REACHED:'Você atingiu o limite de compra deste ovo.',PLAYER_NOT_FOUND:'Jogador não encontrado.'};
export async function petRequest(telegramInitData:string,input:PetAction={action:'dashboard'}):Promise<PetActionResponse>{const response=await forgeFetch('pets',({initData:telegramInitData,...input}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar o servidor dos pets.');const payload=await response.json().catch(()=>null) as (PetActionResponse&{error?:string})|null;if(!response.ok||!payload){const raw=payload?.error||'';throw new Error(PET_ERRORS[raw]||raw||'Não foi possível carregar os pets.')}return payload}
export type PvpAction={action:'dashboard'|'search'|'fusion'|'rarity-fusion'}|{action:'rarity-fuse';heroIds:string[];idempotencyKey:string}|{action:'fuse';mainHeroId:string;materialIds:string[]}|{action:'lock';heroId:string;locked:boolean}|{action:'equip';teamType:'attack'|'defense';slot:number;heroId:string}|{action:'remove';teamType:'attack'|'defense';slot:number}|{action:'battle';opponentId:string}|{action:'buy-tickets';quantity:number;idempotencyKey:string};
export async function pvpRequest<T=PvpDashboard>(telegramInitData:string,input:PvpAction={action:'dashboard'}):Promise<T>{const response=await forgeFetch('pvp',({initData:telegramInitData,...input}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar a Arena.');const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload){const raw=payload?.error||'',limit=/DAILY_LIMIT_(\d+)/.exec(raw),friendly:Record<string,string>={ATTACK_TEAM_EMPTY:'Equipe de ataque vazia.',NO_PVP_TICKETS:'Você não possui tickets.',OPPONENT_UNAVAILABLE:'Adversário indisponível.',INVALID_DEFENSE_TEAM:'Equipe defensiva inválida.',BATTLE_ALREADY_STARTED:'A batalha já foi iniciada.',INSUFFICIENT_FC:'FC insuficientes para esta compra.',INVALID_PACK:'Pacote de tickets indisponível.'};if(limit)throw new Error(Number(limit[1])>0?`Limite diário: você pode comprar apenas ${limit[1]} ticket(s) hoje.`:'Limite diário de compra de tickets atingido.');throw new Error(friendly[raw]||raw||'Não foi possível processar o PvP.')}return payload}
export const searchPvpOpponents=(initData:string)=>pvpRequest<{opponents:PvpOpponent[]}>(initData,{action:'search'});
export const startPvpBattle=(initData:string,opponentId:string)=>pvpRequest<PvpBattleResult>(initData,{action:'battle',opponentId});
/** Ticket purchase: the server owns price, daily limit and Battle Pass validation. */
export const buyPvpTickets=(initData:string,quantity:number,idempotencyKey:string)=>pvpRequest<PvpDashboard>(initData,{action:'buy-tickets',quantity,idempotencyKey});

export type WalletAction={action:'summary'}|{action:'verify-deposit'}|{action:'deposit';amountTon:number;walletAddress:string;idempotencyKey:string}|{action:'withdraw';amountFc:number;walletAddress:string;idempotencyKey:string}|{action:'egg-order';eggId:string;idempotencyKey:string}|{action:'verify-egg-purchases'};
export async function walletRequest<T=WalletSummary>(telegramInitData:string,input:WalletAction={action:'summary'}):Promise<T>{const response=await forgeFetch('wallet',({initData:telegramInitData,...input}));const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível processar a carteira.');return payload}
export const createDepositIntent=(initData:string,amountTon:number,walletAddress:string,idempotencyKey:string)=>walletRequest<TonPaymentIntent>(initData,{action:'deposit',amountTon,walletAddress,idempotencyKey});
export const requestWithdrawal=(initData:string,amountFc:number,walletAddress:string,idempotencyKey:string)=>walletRequest(initData,{action:'withdraw',amountFc,walletAddress,idempotencyKey});
export const createEggTonOrder=(initData:string,eggId:string,idempotencyKey:string)=>walletRequest<TonPaymentIntent>(initData,{action:'egg-order',eggId,idempotencyKey});
/** Single reconciler for premium egg purchases: checks the blockchain and hatches every paid egg once. */
export const verifyEggPurchases=(initData:string)=>walletRequest<{checked:number;completed:string[];pending:string[];results:Array<Record<string,unknown>>}>(initData,{action:'verify-egg-purchases'});
/** Asks the backend to check the TON blockchain and credit any confirmed pending deposit. */
export const verifyPendingDeposits=(initData:string)=>walletRequest<{checked:number;confirmed:string[];alreadyCredited?:string[];pending:string[]}>(initData,{action:'verify-deposit'});

export async function fetchTelegramProfile(telegramInitData:string):Promise<TelegramPlayerProfile>{
  const response=await forgeFetch('profile',({initData:telegramInitData}));
  const payload=await response.json().catch(()=>null) as (TelegramPlayerProfile&{error?:string})|null;
  if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar seu perfil do Telegram.');
  return {...payload,telegramId:String(payload.telegramId)};
}
export async function calendarRequest<T=CalendarDashboard>(telegramInitData:string,action:'dashboard'|'claim'|'inventory'='dashboard',day?:number):Promise<T>{const response=await forgeFetch('calendar',({initData:telegramInitData,action,day}));const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar o calendário.');return payload}
export const claimCalendarDay=(initData:string,day:number)=>calendarRequest<CalendarClaimResult>(initData,'claim',day);
/** Chests and eggs the player already owns, so a stored item can always be opened later. */
export async function fetchPlayerInventory(initData:string):Promise<PlayerInventory>{const payload=await calendarRequest<PlayerInventory>(initData,'inventory');return {chests:Array.isArray(payload.chests)?payload.chests:[],eggs:Array.isArray(payload.eggs)?payload.eggs:[]}}
const CHEST_ERRORS:Record<string,string>={CHEST_NOT_OWNED:'Este baú não está no seu inventário.',ITEM_NOT_FOUND:'Este baú não está mais no seu inventário.',CHEST_NOT_CONFIGURED:'Baú indisponível no momento.',CHEST_RATES_SUM_INVALID:'Baú indisponível no momento.',NO_ELIGIBLE_HERO:'Nenhum herói disponível para este baú.',PLAYER_NOT_FOUND:'Jogador não encontrado.'};
/** The rarity roll and the hero pick happen only on the server. */
export async function openCalendarChest(initData:string,inventoryItemId:string,source:'calendar'|'shop'|'pass'|'mission'|'event'='calendar'):Promise<ChestOpenResult>{const response=await forgeFetch('calendar',({initData,action:'open-chest',inventoryItemId,source}));const payload=await response.json().catch(()=>null)as(ChestOpenResult&{error?:string})|null;if(!response.ok||!payload?.hero){const raw=payload?.error||'';if(raw)console.error('[open-chest]',raw);
  // Never surface SQL/technical text to the player: only mapped codes are shown.
  throw new Error(CHEST_ERRORS[raw]||'Não foi possível abrir o baú. Tente novamente.')}return payload}
export async function seasonPassRequest<T=SeasonPassDashboard>(initData:string,action:'dashboard'|'order'|'claim'|'recent-xp'|'buy-level'='dashboard',data:Record<string,unknown>={}):Promise<T>{const response=await forgeFetch('season-pass',({initData,action,...data}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar o servidor do Passe.');const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar o Passe.');return payload}
/** Level purchase is server-authoritative: price, daily limit and new level all come from the backend. */
export const buySeasonPassLevels=(initData:string,levels:number)=>seasonPassRequest(initData,'buy-level',{levels,idempotencyKey:crypto.randomUUID()});
export const createSeasonPassOrder=(initData:string,tier:PassTier)=>seasonPassRequest<SeasonPassOrder>(initData,'order',{tier,idempotencyKey:crypto.randomUUID()});
/** Battle Pass XP gains registered by the backend since a timestamp (client only renders them). */
export const fetchRecentPassXp=(initData:string,since:string|null)=>seasonPassRequest<PassXpGain[]>(initData,'recent-xp',{since});
/** Server-side reconciler for TON battle pass payments: only the backend can activate a pass. */
export async function verifyPassPurchases(initData:string):Promise<{checked:number;completed:string[];pending:string[];results:Array<Record<string,unknown>>;dashboard?:SeasonPassDashboard}>{const response=await forgeFetch('season-pass',({initData,action:'verify'}));const payload=await response.json().catch(()=>null)as(Record<string,unknown>&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível verificar o pagamento do Passe.');return payload as never}
export async function communityPoolRequest(initData:string):Promise<CommunityPoolDashboard>{const response=await forgeFetch('pool',({initData,action:'dashboard'}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar a Pool Comunitária.');const payload=await response.json().catch(()=>null)as(CommunityPoolDashboard&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar a Pool Comunitária.');return payload}

/** Special events (EVENTS tab): backend-computed ranking, never a client-side count. */
export async function specialEventsRequest(initData:string):Promise<SpecialEventsDashboard>{const response=await forgeFetch('events',({initData,action:'dashboard'}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar os eventos especiais.');const payload=await response.json().catch(()=>null)as(SpecialEventsDashboard&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar os eventos especiais.');return payload}

// Hero collection is independent from PvP stats/matchmaking: a PvP failure must
// never wipe the collection, and an empty collection is a valid empty state.
export async function fetchPlayerHeroes(initData:string):Promise<{heroes:PvpHero[]}>{
  const response=await forgeFetch('pvp',{initData,action:'heroes'});
  if(response.status===404)throw new Error('Backend indisponível: não foi possível carregar sua coleção de heróis.');
  const payload=await response.json().catch(()=>null)as{heroes?:PvpHero[];error?:string}|null;
  if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar sua coleção de heróis.');
  return {heroes:Array.isArray(payload.heroes)?payload.heroes:[]};
}

export type RewardHistoryItem={reward_type:string;reward_key:string|null;reward_name:string;rarity:string|null;quantity:number;image_url:string|null;source:string|null;created_at:string};
export type RewardHistory={items:RewardHistoryItem[];total:number};
/** Read-only history of rewards the player already received (no delivery side effects). */
export async function fetchRewardHistory(telegramInitData:string,limit=5,offset=0):Promise<RewardHistory>{
  const response=await forgeFetch('rewards',({initData:telegramInitData,limit,offset}));
  const payload=await response.json().catch(()=>null) as (RewardHistory&{error?:string})|null;
  if(!response.ok||!payload)throw new Error(payload?.error||'Unable to load your reward history.');
  return {items:Array.isArray(payload.items)?payload.items:[],total:Number(payload.total??0)};
}

// ------------------------------------------------------- official channel rewards
export type ChannelReward={key:'news'|'community'|'payments';title:string;subtitle:string;url:string;rewardFc:number;enabled:boolean;verifiable:boolean;joined:boolean;claimed:boolean;rewardReceived:number;claimedAt:string|null};
export type ChannelRewards={channels:ChannelReward[];status?:'claimed'|'already_claimed';creditedFc?:number};
const CHANNEL_ERRORS:Record<string,string>={
  CHANNEL_NOT_AVAILABLE:'This channel reward is not available right now.',
  PLAYER_NOT_FOUND:'Player not found.',
};
/** One-time reward per Telegram ID + channel: granted by the backend, no membership check. */
export async function channelsRequest(telegramInitData:string,input:{action:'dashboard'}|{action:'verify';channelKey:string}={action:'dashboard'}):Promise<ChannelRewards>{
  const response=await forgeFetch('channels',({initData:telegramInitData,...input}));
  const payload=await response.json().catch(()=>null) as (ChannelRewards&{error?:string})|null;
  if(!response.ok||!payload){const raw=payload?.error||'';throw new Error(CHANNEL_ERRORS[raw]||raw||'Unable to load the official channels.')}
  return {...payload,channels:Array.isArray(payload.channels)?payload.channels:[]};
}

/** Marks the given notifications as read on the SERVER so they never show up again on relaunch. */
export async function markNotificationsRead(telegramInitData:string,ids:string[]):Promise<{updated:number}>{
  const response=await forgeFetch('notifications',{initData:telegramInitData,action:'mark-read',ids});
  const payload=await response.json().catch(()=>null) as {updated?:number;error?:string}|null;
  if(!response.ok)throw new Error(payload?.error||'Unable to update your notifications.');
  return {updated:Number(payload?.updated??0)};
}




// ---------------------------------------------------------------- daily quests
export type QuestAction={action:'dashboard'}|{action:'claim';code:string}|{action:'claim-chest'};
const QUEST_ERRORS:Record<string,string>={QUEST_NOT_FOUND:'This quest is no longer available.',QUEST_NOT_COMPLETED:'Finish this quest first.',QUEST_ALREADY_CLAIMED:'You already claimed this quest today.',QUESTS_NOT_COMPLETED:'Complete all 5 quests to unlock the chest.',BONUS_ALREADY_CLAIMED:'The daily quest chest was already claimed today.',PLAYER_NOT_FOUND:'Player not found.'};
/** Quest progress is written only by server-side event hooks; the client can just read and claim. */
export async function questsRequest<T=DailyQuestsDashboard>(telegramInitData:string,input:QuestAction={action:'dashboard'}):Promise<T>{
  const response=await forgeFetch('quests',({initData:telegramInitData,...input}));
  if(response.status===404)throw new Error('Backend unavailable: unable to reach the quests server.');
  const payload=await response.json().catch(()=>null) as (T&{error?:string})|null;
  if(!response.ok||!payload){const raw=payload?.error||'';throw new Error(QUEST_ERRORS[raw]||raw||'Unable to load your daily quests.')}
  return payload;
}
export const fetchDailyQuests=(initData:string)=>questsRequest<DailyQuestsDashboard>(initData,{action:'dashboard'});
export const claimDailyQuest=(initData:string,code:string)=>questsRequest<QuestClaimResult>(initData,{action:'claim',code});
export const claimDailyQuestChest=(initData:string)=>questsRequest<QuestClaimResult>(initData,{action:'claim-chest'});

// ------------------------------------------------------------- hero fusion (ascension)
const FUSION_ERRORS:Record<string,string>={HERO_NOT_OWNED:'Este herói não pertence a você.',HERO_MAX_STARS:'Este herói já está no máximo de estrelas.',NOT_ENOUGH_DUPLICATES:'Você não tem cópias suficientes deste herói.',NOT_ENOUGH_FORGE_COINS:'FC insuficientes para a fusão.',PLAYER_NOT_FOUND:'Jogador não encontrado.'};
const fusionError=(raw:string)=>FUSION_ERRORS[raw]||raw||'Não foi possível concluir a fusão.';
async function fusionRequest<T>(initData:string,input:PvpAction):Promise<T>{
  try{return await pvpRequest<T>(initData,input)}catch(error){throw new Error(fusionError(error instanceof Error?error.message:''))}
}
export const fetchHeroFusion=(initData:string)=>fusionRequest<FusionDashboard>(initData,{action:'fusion'});
export const fuseHeroes=(initData:string,mainHeroId:string,materialIds:string[])=>fusionRequest<FusionResult>(initData,{action:'fuse',mainHeroId,materialIds});
const RARITY_FUSION_ERRORS:Record<string,string>={FUSION_DISABLED:'A fusão de heróis está temporariamente desativada.',NEED_EXACT_HEROES:'Selecione exatamente 5 heróis diferentes.',HERO_NOT_OWNED:'Um dos heróis selecionados não pertence a você.',HERO_LOCKED:'Remova o bloqueio dos heróis antes de fundir.',HERO_EQUIPPED:'Retire os heróis das equipes de PvP/Chefe antes de fundir.',RARITY_MISMATCH:'Todos os heróis precisam ter a mesma raridade.',MAX_FUSION_RARITY:'Heróis Lendários não podem ser fundidos em Ancestrais.',NOT_ENOUGH_FC:'FC insuficientes para a fusão.',NO_ELIGIBLE_HERO:'Nenhum herói disponível no pool desta raridade.',PLAYER_NOT_FOUND:'Jogador não encontrado.'};
async function rarityFusionRequest<T>(initData:string,input:PvpAction):Promise<T>{
  try{return await pvpRequest<T>(initData,input)}
  catch(error){const raw=error instanceof Error?error.message:'';throw new Error(RARITY_FUSION_ERRORS[raw]||raw||'Não foi possível concluir a fusão.')}
}
export const fetchRarityFusion=(initData:string)=>rarityFusionRequest<RarityFusionDashboard>(initData,{action:'rarity-fusion'});
export const fuseHeroesByRarity=(initData:string,heroIds:string[],idempotencyKey:string)=>rarityFusionRequest<RarityFusionResult>(initData,{action:'rarity-fuse',heroIds,idempotencyKey});
export const setHeroLock=(initData:string,heroId:string,locked:boolean)=>fusionRequest<{heroId:string;locked:boolean}>(initData,{action:'lock',heroId,locked});

// ------------------------------------------------------------- player market (FC only)
const MARKET_ERRORS:Record<string,string>={
  PLAYER_NOT_FOUND:'Jogador não encontrado.',
  INVALID_ITEM_TYPE:'Categoria inválida.',
  INVALID_ITEM:'Item inválido.',
  INVALID_PRICE:'Preço inválido.',
  PRICE_BELOW_MINIMUM:'Preço abaixo do mínimo permitido.',
  PRICE_ABOVE_MAXIMUM:'Preço acima do máximo permitido.',
  TOO_MANY_ACTIVE_LISTINGS:'Você atingiu o limite de anúncios ativos.',
  ITEM_NOT_OWNED:'Este item não pertence a você.',
  ALREADY_LISTED:'Este item já está anunciado.',
  HERO_LOCKED:'Remova o bloqueio do herói antes de vender.',
  HERO_NOT_TRADABLE:'Este herói não pode ser vendido.',
  HERO_IN_PVP_TEAM:'Retire o herói da equipe de PvP antes de vender.',
  HERO_IN_BOSS_TEAM:'Retire o herói da equipe do Chefe antes de vender.',
  HERO_LISTED_IN_MARKET:'Este herói está anunciado no mercado.',
  PET_IS_ACTIVE:'Desative o pet antes de vender.',
  PET_NOT_TRADABLE:'Este pet não pode ser vendido.',
  PET_LISTED_IN_MARKET:'Este pet está anunciado no mercado.',
  ITEM_NOT_TRADABLE:'Este item não pode ser vendido.',
  LISTING_NOT_FOUND:'Anúncio não encontrado.',
  LISTING_NOT_ACTIVE:'Este anúncio não está mais ativo.',
  NOT_LISTING_OWNER:'Este anúncio não é seu.',
  ITEM_NO_LONGER_AVAILABLE:'Item não está mais disponível.',
  CANNOT_BUY_OWN_LISTING:'Você não pode comprar seu próprio anúncio.',
  NOT_ENOUGH_FORGE_COINS:'FC insuficientes para esta compra.',
};
export type MarketAction=
  |{action:'browse';itemType?:MarketItemType|'all';rarity?:string;sort?:MarketSort;limit?:number;offset?:number}
  |{action:'sellable'}
  |{action:'mine'}
  |{action:'create';itemType:MarketItemType;itemInstanceId?:string;itemCode?:string;priceFc:number}
  |{action:'cancel';listingId:string}
  |{action:'buy';listingId:string};
export async function marketRequest<T>(initData:string,input:MarketAction):Promise<T>{
  const response=await forgeFetch('market',{initData,...input});
  if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar o mercado.');
  const payload=await response.json().catch(()=>null) as (T&{error?:string})|null;
  if(!response.ok||!payload){const raw=payload?.error||'';throw new Error(MARKET_ERRORS[raw]||raw||'Não foi possível processar o mercado.')}
  return payload;
}
export const fetchMarketBrowse=(initData:string,itemType:MarketItemType|'all',rarity:string,sort:MarketSort)=>marketRequest<MarketBrowse>(initData,{action:'browse',itemType,rarity,sort,limit:60});
export const fetchMarketSellable=(initData:string)=>marketRequest<MarketSellable>(initData,{action:'sellable'});
export const fetchMarketMine=(initData:string)=>marketRequest<MarketMine>(initData,{action:'mine'});
export const createMarketListing=(initData:string,input:{itemType:MarketItemType;itemInstanceId?:string;itemCode?:string;priceFc:number})=>marketRequest<MarketCreateResult>(initData,{action:'create',...input});
export const cancelMarketListing=(initData:string,listingId:string)=>marketRequest<{ok:boolean}>(initData,{action:'cancel',listingId});
export const buyMarketListing=(initData:string,listingId:string)=>marketRequest<MarketBuyResult>(initData,{action:'buy',listingId});

/** Spending Event (SPENDING EVENT tab): the backend counts every confirmed spend. */
export async function spendingEventRequest(initData:string,limit=20):Promise<SpendingEventDashboard>{const response=await forgeFetch('spending-event',({initData,action:'dashboard',limit}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar o Evento de Gastos.');const payload=await response.json().catch(()=>null)as(SpendingEventDashboard&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar o Evento de Gastos.');return payload}
