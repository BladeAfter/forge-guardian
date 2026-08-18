import type {SpecialEventsDashboard} from './specialEvents';
import type {SpendingEventDashboard,SpendingEventPopup} from './spendingEvent';
import type {MarketingPoolDashboard} from './marketingPool';
import { createClient } from '@supabase/supabase-js';
import { forgeFetch } from './apiClient';
import type { HeroMiningClaimResult, HeroMiningState } from './heroMining';
import { supabaseAnonKey, supabaseUrl } from './supabaseEnv';
import type { GameState } from './types';
import { buildDefaults } from './utils';
import type { BossCombat, GlobalBossAutoAttackState, GlobalBossRanking, GlobalBossHistoryRow } from './combat';
import type { ReferralDashboard } from './referrals';
import type {PetActionResponse,PetDashboard} from './pets';
import type {PvpAdsState,PvpBattleResult,PvpDashboard,PvpHero,PvpOpponent} from './pvp';
import type {TowerBattle,TowerDashboard,TowerRanking} from './tower';
import type { TonPaymentIntent, TonWallet, TonWithdrawalReceipt, WalletSummary ,MythWallet} from './wallet';
import type { MythSaleDashboard, MythSalePurchaseResult, MythSaleStats } from './mythSale';
import type { TelegramPlayerProfile } from './playerProfile';
import {officialGameDayKey} from './calendarRewards';
import type {CalendarClaimResult,CalendarDashboard,ChestOpenResult,FragmentSummonResult,PlayerInventory} from './calendarRewards';

import type{PassTier,PassXpGain,PassLockedPurchaseResult,SeasonPassDashboard,SeasonPassOrder}from'./seasonPass';
import type{CommunityPoolDashboard}from'./communityPool';
import type{DailyQuestsDashboard,QuestClaimResult}from'./quests';
import type {FusionDashboard,FusionResult, RarityFusionDashboard, RarityFusionResult} from './heroFusion';
import type {MarketBrowse,MarketBuyResult,MarketCreateResult,MarketCurrency,MarketItemType,MarketMine,MarketPaymentIntent,MarketPaymentStatus,MarketQuote,MarketSellable,MarketSort,MarketStatus} from './market';


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


const BOSS_ERRORS:Record<string,string>={BOSS_NOT_ACTIVE:'Nenhum chefe ativo no momento. Aguarde o próximo desafio.',BOSS_TEAM_EMPTY:'Monte sua equipe antes de atacar o chefe.',HERO_NOT_OWNED:'Este herói não pertence a você.',INVALID_SLOT:'Slot inválido.',INVALID_TEAM:'Equipe inválida.',PLAYER_NOT_FOUND:'Jogador não encontrado.',PET_LISTED_IN_MARKET:'Este pet está anunciado no mercado.',NFT_PET_ADMIN_ONLY:'Pets NFT só podem ser concedidos pelo administrador.',NFT_PET_IMMUTABLE:'Este pet NFT não pode ser alterado.',NFT_PET_NOT_TRANSFERABLE:'Este pet NFT não pode ser transferido.',PET_XP_SAME_PET:'Escolha um pet diferente para receber o XP.',PET_NO_XP:'Este pet não tem XP para recuperar.',TARGET_CANNOT_RECEIVE_XP:'O pet de destino não pode receber todo o XP.',SUB_NFT_NOT_ADULT:'Sub-NFT só pode ser resetado quando adulto.'};
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

export async function fetchGlobalBossHistory(telegramInitData:string,limit=10):Promise<GlobalBossHistoryRow[]>{
  const response=await forgeFetch('boss',({initData:telegramInitData,action:'history',limit}));
  const payload=await response.json().catch(()=>null) as GlobalBossHistoryRow[]|{error?:string}|null;
  if(!response.ok||!payload||!Array.isArray(payload))throw new Error(bossErrorMessage((payload as{error?:string}|null)?.error||'','Não foi possível carregar o histórico do chefe.'));
  return payload;
}

/** Season Pass benefit: enable/disable the offline Auto ATK on the Global Boss. */
export async function setGlobalBossAutoAttack(telegramInitData:string,enabled:boolean):Promise<GlobalBossAutoAttackState>{
  const response=await forgeFetch('boss',({initData:telegramInitData,action:'auto-attack',enabled}));
  const payload=await response.json().catch(()=>null) as GlobalBossAutoAttackState&{error?:string}|null;
  if(!response.ok||!payload)throw new Error(bossErrorMessage(payload?.error||'','Não foi possível atualizar o Auto ATK.'));
  return payload;
}

/** Attacking is the ONLY boss operation that requires an active boss. */
export const attackBossOnServer=(initData:string)=>bossRequest(initData,'attack');


export type HeroShopConfig={prices:Record<string,number>;odds:Record<string,number>;baseOdds?:Record<string,number>;rarityEnabled?:Record<string,boolean>;version?:number};

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
  return {...payload,invites:Array.isArray(payload.invites)?payload.invites:[],tree:Array.isArray(payload.tree)?payload.tree:[],ranking:Array.isArray(payload.ranking)?payload.ranking:[],bonuses:Array.isArray(payload.bonuses)?payload.bonuses:[],notifications:Array.isArray(payload.notifications)?payload.notifications:[],commissionHistory:Array.isArray(payload.commissionHistory)?payload.commissionHistory:[]};
}
export async function bindReferral(telegramInitData:string,inviterTelegramId:number){
  const response=await forgeFetch('referral',({initData:telegramInitData,action:'bind',inviterTelegramId}));
  const payload=await response.json().catch(()=>null) as {linked?:boolean;error?:string}|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível registrar o convite.');return payload;
}
export type PetAction={action:'dashboard'}|{action:'activate';playerPetId:string}|{action:'evolve';playerPetId:string;idempotencyKey?:string}|{action:'feed';playerPetId:string;foodCode:string;quantity:number;idempotencyKey?:string}|{action:'hatch';eggId:string;idempotencyKey:string}|{action:'recover-hatch';idempotencyKey:string}|{action:'buy-egg';eggId:string;quantity:number;idempotencyKey:string}|{action:'buy-egg-balance';eggId:string;idempotencyKey:string}|{action:'buy-food';foodCode:string;quantity:number;idempotencyKey:string}|{action:'xp-transfer-preview';playerPetId:string}|{action:'xp-transfer';playerPetId:string;targetPlayerPetId:string;idempotencyKey:string};
const PET_ERRORS:Record<string,string>={PET_NOT_OWNED:'Este pet não pertence a você.',PET_MAX_LEVEL:'Este pet já está no nível máximo.',PET_LEVEL_TOO_LOW:'Nível insuficiente para evoluir.',PET_FULLY_EVOLVED:'Este pet já alcançou a forma final.',NOT_ENOUGH_PET_FOOD:'Você não tem comida suficiente.',NOT_ENOUGH_PET_FRAGMENTS:'Fragmentos insuficientes para evoluir.',NOT_ENOUGH_FORGE_COINS:'FC insuficientes.',FOOD_NOT_FOUND:'Comida indisponível.',FOOD_NOT_PURCHASABLE:'Esta comida não está à venda.',EGG_NOT_FOUND:'Ovo indisponível.',EGG_NOT_OWNED:"YOU DON'T OWN THIS EGG",EGG_ALREADY_OPENING:'EGG ALREADY OPENING',EGG_OPENING_FAILED:'EGG OPENING FAILED',EGG_RATES_INVALID:'EGG OPENING FAILED',EGG_NOT_PURCHASABLE:'Este ovo não pode ser comprado (evento exclusivo).',EGG_REQUIRES_TON:'Este ovo é vendido apenas em TON.',EGG_NOT_AVAILABLE_FOR_TON:'Este ovo não está disponível para compra em TON.',INSUFFICIENT_TON_BALANCE:'Saldo TON interno insuficiente.',DAILY_EGG_LIMIT_REACHED:'Limite diário deste ovo atingido.',PLAYER_EGG_LIMIT_REACHED:'Você atingiu o limite de compra deste ovo.',EGG_LIMIT_REACHED:'Você atingiu o limite de compra deste ovo.',PLAYER_NOT_FOUND:'Jogador não encontrado.',PET_LISTED_IN_MARKET:'Este pet está anunciado no mercado.',NFT_PET_ADMIN_ONLY:'Pets NFT só podem ser concedidos pelo administrador.',NFT_PET_IMMUTABLE:'Este pet NFT não pode ser alterado.',NFT_PET_NOT_TRANSFERABLE:'Este pet NFT não pode ser transferido.'};
export async function petRequest(telegramInitData:string,input:PetAction={action:'dashboard'}):Promise<PetActionResponse>{const response=await forgeFetch('pets',({initData:telegramInitData,...input}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar o servidor dos pets.');const payload=await response.json().catch(()=>null) as (PetActionResponse&{error?:string})|null;if(!response.ok||!payload){const raw=payload?.error||'';if(raw)console.error('[MYTHREON PETS]',input.action,raw);throw new Error(PET_ERRORS[raw]||raw||'Não foi possível carregar os pets.')}return payload}
export type PvpAction={action:'dashboard'|'search'|'fusion'|'rarity-fusion'}|{action:'rarity-fuse';heroIds:string[];idempotencyKey:string}|{action:'fuse';mainHeroId:string;materialIds:string[];useFragments?:boolean;idempotencyKey?:string}|{action:'lock';heroId:string;locked:boolean}|{action:'equip';teamType:'attack'|'defense';slot:number;heroId:string}|{action:'remove';teamType:'attack'|'defense';slot:number}|{action:'battle';opponentId:string}|{action:'buy-tickets';quantity:number;idempotencyKey:string}|{action:'ads'}|{action:'ads-begin'}|{action:'ads-reward';viewId:string};
export async function pvpRequest<T=PvpDashboard>(telegramInitData:string,input:PvpAction={action:'dashboard'}):Promise<T>{const response=await forgeFetch('pvp',({initData:telegramInitData,...input}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar a Arena.');const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload){const raw=payload?.error||'',limit=/DAILY_LIMIT_(\d+)/.exec(raw),friendly:Record<string,string>={ATTACK_TEAM_EMPTY:'Equipe de ataque vazia.',NO_PVP_TICKETS:'Você não possui tickets.',OPPONENT_UNAVAILABLE:'Adversário indisponível.',INVALID_DEFENSE_TEAM:'Equipe defensiva inválida.',BATTLE_ALREADY_STARTED:'A batalha já foi iniciada.',INSUFFICIENT_FC:'FC insuficientes para esta compra.',INVALID_PACK:'Pacote de tickets indisponível.'};if(limit)throw new Error(Number(limit[1])>0?`Limite diário: você pode comprar apenas ${limit[1]} ticket(s) hoje.`:'Limite diário de compra de tickets atingido.');throw new Error(friendly[raw]||raw||'Não foi possível processar o PvP.')}return payload}
/** Level/XP recycling: preview (recoverable XP, cost, eligible targets) resolved server-side. */
export const fetchPetXpTransferPreview=(initData:string,playerPetId:string)=>petRequest(initData,{action:'xp-transfer-preview',playerPetId}) as Promise<import('./pets').PetXpTransferPreview>;
export const resetAndTransferPetXp=(initData:string,playerPetId:string,targetPlayerPetId:string,idempotencyKey:string)=>petRequest(initData,{action:'xp-transfer',playerPetId,targetPlayerPetId,idempotencyKey});
export const searchPvpOpponents=(initData:string)=>pvpRequest<{opponents:PvpOpponent[]}>(initData,{action:'search'});
export const startPvpBattle=(initData:string,opponentId:string)=>pvpRequest<PvpBattleResult>(initData,{action:'battle',opponentId});
/** Ticket purchase: the server owns price, daily limit and Battle Pass validation. */
export const buyPvpTickets=(initData:string,quantity:number,idempotencyKey:string)=>pvpRequest<PvpDashboard>(initData,{action:'buy-tickets',quantity,idempotencyKey});
/** Ads config + today's counter (entry interstitial / PvP block). */
export const fetchPvpAdsState=(initData:string)=>pvpRequest<{ads:PvpAdsState|null}>(initData,{action:'ads'});
/** Opens a rewarded ad view server-side (limit check only — no ticket is granted here). */
export const beginPvpAdView=(initData:string)=>pvpRequest<{viewId:string;blockId:string;ads:PvpAdsState}>(initData,{action:'ads-begin'});
/** Called ONLY after AdsGram confirms a valid completion. The server credits +1 ticket atomically. */
export const claimPvpAdReward=(initData:string,viewId:string)=>pvpRequest<{granted:boolean;reason?:string;tickets:number;ads:PvpAdsState}>(initData,{action:'ads-reward',viewId});

export type WalletAction={action:'summary'}|{action:'verify-deposit'}|{action:'deposit';amountTon:number;walletAddress:string;idempotencyKey:string;depositType:'ton_to_fc'|'ton_balance'}|{action:'ton-wallet'}|{action:'withdraw-ton';amountTon:number;walletAddress:string;idempotencyKey:string}|{action:'egg-order';eggId:string;idempotencyKey:string}|{action:'verify-egg-purchases'}|{action:'myth'}|{action:'myth-sale'}|{action:'myth-buy';mythAmount:number;idempotencyKey:string;walletAddress?:string}|{action:'myth-verify'};
export async function walletRequest<T=WalletSummary>(telegramInitData:string,input:WalletAction={action:'summary'}):Promise<T>{const response=await forgeFetch('wallet',({initData:telegramInitData,...input}));const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível processar a carteira.');return payload}
/** depositType decides the destination BEFORE payment: 'ton_to_fc' buys FC, 'ton_balance' tops up the internal TON balance 1:1. */
export const createDepositIntent=(initData:string,amountTon:number,walletAddress:string,idempotencyKey:string,depositType:'ton_to_fc'|'ton_balance'='ton_to_fc')=>walletRequest<TonPaymentIntent>(initData,{action:'deposit',amountTon,walletAddress,idempotencyKey,depositType});
/** Withdrawable TON balance: only official rewards land here, never FC. */
export const fetchTonWallet=(initData:string)=>walletRequest<TonWallet>(initData,{action:'ton-wallet'});
export const requestTonWithdrawal=(initData:string,amountTon:number,walletAddress:string,idempotencyKey:string)=>walletRequest<TonWithdrawalReceipt>(initData,{action:'withdraw-ton',amountTon,walletAddress,idempotencyKey});

/** MYTH Token: decorative read-only balance. No trading, price, conversion or withdrawal. */
export const fetchMythWallet=(initData:string)=>walletRequest<MythWallet>(initData,{action:'myth'});
/** MYTH TOKEN SALE: read-only dashboard (supply, sold, burned, TON raised, current price). */
export const fetchMythSale=(initData:string)=>walletRequest<MythSaleDashboard>(initData,{action:'myth-sale'});
/** The backend decides the method: internal TON when it covers 100%, otherwise a TonConnect intent. */
export const startMythPurchase=(initData:string,mythAmount:number,idempotencyKey:string,walletAddress?:string)=>walletRequest<MythSalePurchaseResult>(initData,{action:'myth-buy',mythAmount,idempotencyKey,walletAddress});
/** Checks the blockchain and settles any paid MYTH intent once (duplicate tx hashes are rejected). */
export const verifyMythPurchases=(initData:string)=>walletRequest<{checked:number;confirmed:string[];pending:string[];stats:MythSaleStats}>(initData,{action:'myth-verify'});
export const createEggTonOrder=(initData:string,eggId:string,idempotencyKey:string)=>walletRequest<TonPaymentIntent>(initData,{action:'egg-order',eggId,idempotencyKey});
/** Single reconciler for premium egg purchases: checks the blockchain and hatches every paid egg once. */
export const verifyEggPurchases=(initData:string)=>walletRequest<{checked:number;completed:string[];pending:string[];results:Array<Record<string,unknown>>}>(initData,{action:'verify-egg-purchases'});
/** Asks the backend to check the TON blockchain and credit any confirmed pending deposit. */
export const verifyPendingDeposits=(initData:string)=>walletRequest<{checked:number;confirmed:string[];credits?:Array<{id:string;depositType:'ton_to_fc'|'ton_balance';amountTon:number;amountFc:number}>;alreadyCredited?:string[];pending:string[]}>(initData,{action:'verify-deposit'});

export async function fetchTelegramProfile(telegramInitData:string):Promise<TelegramPlayerProfile>{
  const response=await forgeFetch('profile',({initData:telegramInitData}));
  const payload=await response.json().catch(()=>null) as (TelegramPlayerProfile&{error?:string})|null;
  if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar seu perfil do Telegram.');
  return {...payload,telegramId:String(payload.telegramId)};
}
export async function calendarRequest<T=CalendarDashboard>(telegramInitData:string,action:'dashboard'|'claim'|'inventory'='dashboard',day?:number):Promise<T>{const response=await forgeFetch('calendar',({initData:telegramInitData,action,day}));const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar o calendário.');return payload}
export const claimCalendarDay=(initData:string,day:number)=>calendarRequest<CalendarClaimResult>(initData,'claim',day);
/** Chests and eggs the player already owns, so a stored item can always be opened later. */
export async function fetchPlayerInventory(initData:string):Promise<PlayerInventory>{const payload=await calendarRequest<PlayerInventory>(initData,'inventory');return {chests:Array.isArray(payload.chests)?payload.chests:[],eggs:Array.isArray(payload.eggs)?payload.eggs:[],items:Array.isArray(payload.items)?payload.items:[]}}
const CHEST_ERRORS:Record<string,string>={CHEST_NOT_OWNED:'Este baú não está no seu inventário.',ITEM_NOT_FOUND:'Este baú não está mais no seu inventário.',CHEST_NOT_CONFIGURED:'Baú indisponível no momento.',CHEST_RATES_SUM_INVALID:'Baú indisponível no momento.',NO_ELIGIBLE_HERO:'Nenhum herói disponível para este baú.',PLAYER_NOT_FOUND:'Jogador não encontrado.',PET_LISTED_IN_MARKET:'Este pet está anunciado no mercado.',NFT_PET_ADMIN_ONLY:'Pets NFT só podem ser concedidos pelo administrador.',NFT_PET_IMMUTABLE:'Este pet NFT não pode ser alterado.',NFT_PET_NOT_TRANSFERABLE:'Este pet NFT não pode ser transferido.'};
/** The rarity roll and the hero pick happen only on the server. */
const SUMMON_ERRORS:Record<string,string>={NOT_ENOUGH_FRAGMENTS:'Fragmentos insuficientes.',NO_ELIGIBLE_HERO:'Nenhum herói disponível no pool.',PLAYER_NOT_FOUND:'Jogador não encontrado.'};
/** 5 fragments -> 1 random common/uncommon hero. Cost, odds and roll live in the RPC. */
export async function summonHeroWithFragments(initData:string,idempotencyKey=crypto.randomUUID()):Promise<FragmentSummonResult>{
  const response=await forgeFetch('calendar',({initData,action:'summon-hero',idempotencyKey}));
  const payload=await response.json().catch(()=>null)as(FragmentSummonResult&{error?:string})|null;
  if(!response.ok||!payload?.hero){const raw=payload?.error||'';if(raw)console.error('[summon-hero]',raw);throw new Error(SUMMON_ERRORS[raw]||raw||'Não foi possível resgatar o herói.')}
  return payload;
}
export async function openCalendarChest(initData:string,inventoryItemId:string,source:'calendar'|'shop'|'pass'|'mission'|'event'='calendar'):Promise<ChestOpenResult>{const response=await forgeFetch('calendar',({initData,action:'open-chest',inventoryItemId,source}));const payload=await response.json().catch(()=>null)as(ChestOpenResult&{error?:string})|null;if(!response.ok||!payload?.hero){const raw=payload?.error||'';if(raw)console.error('[open-chest]',raw);
  // Never surface SQL/technical text to the player: only mapped codes are shown.
  throw new Error(CHEST_ERRORS[raw]||'Não foi possível abrir o baú. Tente novamente.')}return payload}
/** Mythic chest (Battle Pass): the roll, duplicate protection and inventory update are server-side. */
export type ExclusiveChestReward={kind:'hero'|'pet'|'fallback';exclusive?:boolean;title?:string;name?:string;image?:string|null;rarity?:string;fragments?:number;forgeCoins?:number};
export async function openExclusiveChest(initData:string,inventoryItemId:string):Promise<{reward:ExclusiveChestReward;chestCode?:string;inventory?:PlayerInventory}>{
  const response=await forgeFetch('calendar',({initData,action:'open-exclusive-chest',inventoryItemId}));
  const payload=await response.json().catch(()=>null)as{reward?:ExclusiveChestReward;chestCode?:string;inventory?:PlayerInventory;error?:string}|null;
  if(!response.ok||!payload?.reward){const raw=payload?.error||'';if(raw)console.error('[open-exclusive-chest]',raw);
    throw new Error(CHEST_ERRORS[raw]||'Não foi possível abrir o baú mítico. Tente novamente.')}
  return payload as {reward:ExclusiveChestReward;chestCode?:string;inventory?:PlayerInventory};
}
/** Legend Chest: guaranteed random LEGENDARY equipment. Roll happens server-side. */
export type LegendChestEquipment={instanceId:string;code:string;name:string;slot:string;kind:string|null;heroClass?:string|null;rarity:string;tier?:number|null;imageUrl?:string|null;bonusAttack?:number;bonusDefense?:number;bonusHp?:number;power?:number};
export async function openLegendChest(initData:string,inventoryItemId:string):Promise<{equipment:LegendChestEquipment;inventory?:PlayerInventory}>{
  const response=await forgeFetch('calendar',({initData,action:'open-legend-chest',inventoryItemId}));
  const payload=await response.json().catch(()=>null)as{equipment?:LegendChestEquipment;inventory?:PlayerInventory;error?:string}|null;
  if(!response.ok||!payload?.equipment){const raw=payload?.error||'';if(raw)console.error('[open-legend-chest]',raw);
    throw new Error(CHEST_ERRORS[raw]||'Não foi possível abrir o Baú Lendário. Tente novamente.')}
  return payload as {equipment:LegendChestEquipment;inventory?:PlayerInventory};
}
export async function seasonPassRequest<T=SeasonPassDashboard>(initData:string,action:'dashboard'|'order'|'claim'|'recent-xp'|'buy-level'|'buy-locked-reward'|'verify-locked-reward'='dashboard',data:Record<string,unknown>={}):Promise<T>{const response=await forgeFetch('season-pass',({initData,action,...data}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar o servidor do Passe.');const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar o Passe.');return payload}
/** Level purchase is server-authoritative: price, daily limit and new level all come from the backend. */
export const buySeasonPassLevels=(initData:string,levels:number)=>seasonPassRequest(initData,'buy-level',{levels,idempotencyKey:crypto.randomUUID()});
/** Locked reward unlock (fixed TON price): the backend decides internal balance vs TonConnect. */
export const buyLockedPassReward=(initData:string,rewardId:string,walletAddress?:string|null)=>seasonPassRequest<PassLockedPurchaseResult>(initData,'buy-locked-reward',{rewardId,walletAddress:walletAddress??null,idempotencyKey:crypto.randomUUID()});
/** Reconciles TonConnect payments made for locked reward unlocks (idempotent, server-side). */
export const verifyLockedPassRewards=(initData:string)=>seasonPassRequest<{checked:number;completed:string[];pending:string[];dashboard?:SeasonPassDashboard}>(initData,'verify-locked-reward');

export const createSeasonPassOrder=(initData:string,tier:PassTier)=>seasonPassRequest<SeasonPassOrder>(initData,'order',{tier,idempotencyKey:crypto.randomUUID()});
/** Battle Pass XP gains registered by the backend since a timestamp (client only renders them). */
export const fetchRecentPassXp=(initData:string,since:string|null)=>seasonPassRequest<PassXpGain[]>(initData,'recent-xp',{since});
/** Server-side reconciler for TON battle pass payments: only the backend can activate a pass. */
export async function verifyPassPurchases(initData:string):Promise<{checked:number;completed:string[];pending:string[];results:Array<Record<string,unknown>>;dashboard?:SeasonPassDashboard}>{const response=await forgeFetch('season-pass',({initData,action:'verify'}));const payload=await response.json().catch(()=>null)as(Record<string,unknown>&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível verificar o pagamento do Passe.');return payload as never}
export async function communityPoolRequest(initData:string):Promise<CommunityPoolDashboard>{const response=await forgeFetch('pool',({initData,action:'dashboard'}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar a Pool Comunitária.');const payload=await response.json().catch(()=>null)as(CommunityPoolDashboard&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar a Pool Comunitária.');return payload}

/** Daily activity progress for the Community Pool "TODAY" panel (server is the source of truth). */
export type ActivityProgress={gameDay?:string;activities:Array<{activity:string;poolPoints:number;passXp:number;dailyCap:number;used:number;xpToday:number}>};
export async function activityProgressRequest(initData:string):Promise<ActivityProgress>{const response=await forgeFetch('pool',({initData,action:'activity'}));const payload=await response.json().catch(()=>null)as(ActivityProgress&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar seu progresso diário.');return{gameDay:payload.gameDay,activities:payload.activities??[]}}

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
const FUSION_ERRORS:Record<string,string>={HERO_NOT_OWNED:'Este herói não pertence a você.',HERO_MAX_STARS:'Este herói já está no máximo de estrelas.',NOT_ENOUGH_DUPLICATES:'Você não tem cópias suficientes deste herói.',NOT_ENOUGH_UNIVERSAL_FRAGMENTS:'Fragmentos universais insuficientes.',DUPLICATE_REQUEST:'Fusão já processada.',NFT_HERO_UNIQUE:'Heróis NFT exclusivos não podem ser fundidos.',NOT_ENOUGH_FORGE_COINS:'FC insuficientes para a fusão.',PLAYER_NOT_FOUND:'Jogador não encontrado.',PET_LISTED_IN_MARKET:'Este pet está anunciado no mercado.',NFT_PET_ADMIN_ONLY:'Pets NFT só podem ser concedidos pelo administrador.',NFT_PET_IMMUTABLE:'Este pet NFT não pode ser alterado.',NFT_PET_NOT_TRANSFERABLE:'Este pet NFT não pode ser transferido.'};
const fusionError=(raw:string)=>FUSION_ERRORS[raw]||raw||'Não foi possível concluir a fusão.';
async function fusionRequest<T>(initData:string,input:PvpAction):Promise<T>{
  try{return await pvpRequest<T>(initData,input)}catch(error){throw new Error(fusionError(error instanceof Error?error.message:''))}
}
export const fetchHeroFusion=(initData:string)=>fusionRequest<FusionDashboard>(initData,{action:'fusion'});
export const fuseHeroes=(initData:string,mainHeroId:string,materialIds:string[],idempotencyKey=crypto.randomUUID())=>fusionRequest<FusionResult>(initData,{action:'fuse',mainHeroId,materialIds,idempotencyKey});
/** Star fusion paid with universal fragments: no hero copy is consumed (server-side rule). */
export const fuseHeroWithFragments=(initData:string,mainHeroId:string,idempotencyKey=crypto.randomUUID())=>fusionRequest<FusionResult>(initData,{action:'fuse',mainHeroId,materialIds:[],useFragments:true,idempotencyKey});
const RARITY_FUSION_ERRORS:Record<string,string>={FUSION_DISABLED:'A fusão de heróis está temporariamente desativada.',NEED_EXACT_HEROES:'Selecione exatamente 5 heróis diferentes.',HERO_NOT_OWNED:'Um dos heróis selecionados não pertence a você.',HERO_LOCKED:'Remova o bloqueio dos heróis antes de fundir.',HERO_EQUIPPED:'Retire os heróis das equipes de PvP/Chefe antes de fundir.',RARITY_MISMATCH:'Todos os heróis precisam ter a mesma raridade.',MAX_FUSION_RARITY:'Heróis Lendários não podem ser fundidos em Ancestrais.',NOT_ENOUGH_FC:'FC insuficientes para a fusão.',NO_ELIGIBLE_HERO:'Nenhum herói disponível no pool desta raridade.',PLAYER_NOT_FOUND:'Jogador não encontrado.',PET_LISTED_IN_MARKET:'Este pet está anunciado no mercado.',NFT_PET_ADMIN_ONLY:'Pets NFT só podem ser concedidos pelo administrador.',NFT_PET_IMMUTABLE:'Este pet NFT não pode ser alterado.',NFT_PET_NOT_TRANSFERABLE:'Este pet NFT não pode ser transferido.'};
async function rarityFusionRequest<T>(initData:string,input:PvpAction):Promise<T>{
  try{return await pvpRequest<T>(initData,input)}
  catch(error){const raw=error instanceof Error?error.message:'';throw new Error(RARITY_FUSION_ERRORS[raw]||raw||'Não foi possível concluir a fusão.')}
}
export const fetchRarityFusion=(initData:string)=>rarityFusionRequest<RarityFusionDashboard>(initData,{action:'rarity-fusion'});
export const fuseHeroesByRarity=(initData:string,heroIds:string[],idempotencyKey:string)=>rarityFusionRequest<RarityFusionResult>(initData,{action:'rarity-fuse',heroIds,idempotencyKey});
export const setHeroLock=(initData:string,heroId:string,locked:boolean)=>fusionRequest<{heroId:string;locked:boolean}>(initData,{action:'lock',heroId,locked});

// ------------------------------------------------------------- player market (FC + TON)
const MARKET_ERRORS:Record<string,string>={PRICE_BELOW_MINIMUM_LEGENDARY:'Heróis Lendários ou superiores custam no mínimo 10 TON.',INVALID_QUANTITY:'Quantidade inválida.',EQUIPMENT_EQUIPPED:'Desequipe o item antes de anunciá-lo.',
  PLAYER_NOT_FOUND:'Jogador não encontrado.',
  PET_ALREADY_OWNED:'Você já possui esse pet. Só é possível ter um de cada espécie.',
  INVALID_ITEM_TYPE:'Categoria inválida.',
  INVALID_ITEM:'Item inválido.',
  INVALID_PRICE:'Preço inválido.',
  INVALID_CURRENCY:'Moeda inválida.',
  PRICE_BELOW_MINIMUM:'Preço abaixo do mínimo permitido.',
  PRICE_ABOVE_MAXIMUM:'Preço acima do máximo permitido.',
  TOO_MANY_ACTIVE_LISTINGS:'Você atingiu o limite de anúncios ativos.',
  ITEM_NOT_OWNED:'Este item não pertence a você.',
  ALREADY_LISTED:'Este item já está anunciado.',
  HERO_LOCKED:'Remova o bloqueio do herói antes de vender.',
  HERO_NOT_TRADABLE:'Este herói não pode ser vendido.',NFT_EXCLUSIVE_NOT_TRADEABLE:'NFT Exclusive não pode ser vendido no mercado.',
  HERO_IN_PVP_TEAM:'Retire o herói da equipe de PvP antes de vender.',
  HERO_IN_BOSS_TEAM:'Retire o herói da equipe do Chefe antes de vender.',
  HERO_LISTED_IN_MARKET:'Este herói está anunciado no mercado.',
  PET_IS_ACTIVE:'Desative o pet antes de vender.',
  PET_NOT_TRADABLE:'Este pet não pode ser vendido.',
  PET_LISTED_IN_MARKET:'Este pet está anunciado no mercado.',
  ITEM_NOT_TRADABLE:'Este item não pode ser vendido.',
  LISTING_NOT_FOUND:'Anúncio não encontrado.',
  LISTING_NOT_ACTIVE:'Este anúncio não está mais ativo.',
  LISTING_RESERVED:'Este anúncio está reservado para outro comprador. Tente novamente em alguns minutos.',
  NOT_LISTING_OWNER:'Este anúncio não é seu.',
  ITEM_NO_LONGER_AVAILABLE:'Item não está mais disponível.',
  CANNOT_BUY_OWN_LISTING:'Você não pode comprar seu próprio anúncio.',
  NOT_ENOUGH_FORGE_COINS:'FC insuficientes para esta compra.',
  NOT_ENOUGH_TON_BALANCE:'Saldo TON interno insuficiente. Pague com a carteira.',
  ACCOUNT_TOO_NEW:'Sua conta ainda não pode vender no mercado.',
  WALLET_REQUIRED:'Conecte sua carteira TON para continuar.',
  PAYMENT_NOT_FOUND:'Pagamento não encontrado.',
  PAYMENT_EXPIRED:'A reserva expirou. Tente comprar novamente.',
  TX_ALREADY_USED:'Esta transação já foi utilizada.',
  MARKET_UNDER_MAINTENANCE:'O mercado está em manutenção.',
};
export type MarketAction=
  |{action:'status'}
  |{action:'browse';itemType?:MarketItemType|'all';rarity?:string;sort?:MarketSort;currency?:MarketCurrency|'all';limit?:number;offset?:number}
  |{action:'sellable'}
  |{action:'quote';itemType:MarketItemType;itemInstanceId?:string;itemCode?:string}
  |{action:'mine'}
  |{action:'create';itemType:MarketItemType;itemInstanceId?:string;itemCode?:string;currency:MarketCurrency;priceFc?:number;priceTon?:number}
  |{action:'cancel';listingId:string}
  |{action:'buy';listingId:string}
  |{action:'payment-intent';listingId:string;walletAddress:string}
  |{action:'payment-status';paymentId:string}
  |{action:'payment-cancel';paymentId:string};
export async function marketRequest<T>(initData:string,input:MarketAction):Promise<T>{
  const response=await forgeFetch('market',{initData,...input});
  if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar o mercado.');
  const payload=await response.json().catch(()=>null) as (T&{error?:string})|null;
  if(!response.ok||!payload){
    const raw=payload?.error||'';
    // Only known business codes are shown. Raw database/PostgREST text (function
    // signatures, SQL states) stays in the logs and never reaches the player.
    const known=MARKET_ERRORS[raw];
    if(!known)console.error('[MARKET]',raw);
    // Unknown but clearly a business code (SCREAMING_SNAKE, no SQL noise): show it
    // readable instead of a generic message. Raw SQL text still stays hidden.
    const isBusinessCode=/^[A-Z][A-Z0-9_]{2,48}$/.test(raw);
    throw new Error(known||(isBusinessCode?`Mercado: ${raw.replace(/_/g,' ').toLowerCase()}.`:'Não foi possível processar o mercado. Tente novamente.'));

  }
  return payload;
}
export const fetchMarketStatus=(initData:string)=>marketRequest<MarketStatus>(initData,{action:'status'});
export const fetchMarketBrowse=(initData:string,itemType:MarketItemType|'all',rarity:string,sort:MarketSort,currency:MarketCurrency|'all'='all')=>marketRequest<MarketBrowse>(initData,{action:'browse',itemType,rarity,sort,currency,limit:60});
export const fetchMarketSellable=(initData:string)=>marketRequest<MarketSellable>(initData,{action:'sellable'});
export const fetchMarketQuote=(initData:string,input:{itemType:MarketItemType;itemInstanceId?:string;itemCode?:string})=>marketRequest<MarketQuote>(initData,{action:'quote',...input});
export const fetchMarketMine=(initData:string)=>marketRequest<MarketMine>(initData,{action:'mine'});
export const createMarketListing=(initData:string,input:{itemType:MarketItemType;itemInstanceId?:string;itemCode?:string;currency:MarketCurrency;priceFc?:number;priceTon?:number;quantity?:number})=>marketRequest<MarketCreateResult>(initData,{action:'create',...input});
export const cancelMarketListing=(initData:string,listingId:string)=>marketRequest<{ok:boolean}>(initData,{action:'cancel',listingId});
export const buyMarketListing=(initData:string,listingId:string)=>marketRequest<MarketBuyResult>(initData,{action:'buy',listingId});
/** External wallet payment: reserves the listing and returns the exact transfer data. */
export const createMarketPaymentIntent=(initData:string,listingId:string,walletAddress:string)=>marketRequest<MarketPaymentIntent>(initData,{action:'payment-intent',listingId,walletAddress});
export const fetchMarketPaymentStatus=(initData:string,paymentId:string)=>marketRequest<MarketPaymentStatus>(initData,{action:'payment-status',paymentId});
export const cancelMarketPaymentIntent=(initData:string,paymentId:string)=>marketRequest<{ok:boolean}>(initData,{action:'payment-cancel',paymentId});
/** Polls the reservation until the backend confirms the on-chain transfer. */
export async function waitForMarketPayment(initData:string,paymentId:string,attempts=20,delayMs=6000):Promise<MarketPaymentStatus|null>{
  for(let index=0;index<attempts;index+=1){
    await new Promise(resolve=>setTimeout(resolve,delayMs));
    const status=await fetchMarketPaymentStatus(initData,paymentId).catch(()=>null);
    if(status&&status.status!=='pending')return status;
  }
  return null;
}


/** Spending Event (SPENDING EVENT tab): the backend counts every confirmed spend. */
export async function spendingEventRequest(initData:string,limit=20):Promise<SpendingEventDashboard>{const response=await forgeFetch('spending-event',({initData,action:'dashboard',limit}));if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar o Evento de Gastos.');const payload=await response.json().catch(()=>null)as(SpendingEventDashboard&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar o Evento de Gastos.');return payload}

/** POOL MARKETING tab: read-only project expense transparency (admin-bot driven). */
export async function marketingPoolRequest(initData:string,limit=50):Promise<MarketingPoolDashboard>{const response=await forgeFetch('marketing-pool',{initData,limit});const payload=await response.json().catch(()=>null)as(MarketingPoolDashboard&{error?:string})|null;if(!response.ok||!payload)throw new Error(payload?.error||'Não foi possível carregar o Pool de Marketing.');return payload}

/**
 * Entry highlight for an ACTIVE Spending Event. Never blocks the boot: any failure
 * resolves as `{show:false}` so the game keeps running exactly as before.
 */
export async function spendingEventPopupRequest(initData:string):Promise<SpendingEventPopup>{
  try{
    const response=await forgeFetch('spending-event',{initData,action:'popup'});
    if(!response.ok)return{show:false};
    const payload=await response.json().catch(()=>null) as SpendingEventPopup|null;
    return payload&&payload.show?payload:{show:false};
  }catch{return{show:false}}
}

/** Records that the player saw the highlight (per user + per event, so it follows the account). */
export async function markSpendingEventPopupSeen(initData:string):Promise<void>{
  try{await forgeFetch('spending-event',{initData,action:'popup-seen'})}catch{/* silent: cosmetic only */}
}

/* ---------------- Promotional campaign popup (MYTHREON GIVEAWAY) ---------------- */
export type CampaignPopup={show:boolean;campaignId?:string;groupUrl?:string;reason?:string};

/**
 * Shown ONCE per player per campaignId (server-owned). Failure-tolerant: any error
 * resolves as `{show:false}` so the boot is never blocked.
 */
export async function campaignPopupRequest(initData:string):Promise<CampaignPopup>{
  try{
    const response=await forgeFetch('campaign-popup',{initData,action:'status'});
    if(!response.ok)return{show:false};
    const payload=await response.json().catch(()=>null) as CampaignPopup|null;
    return payload&&payload.show?payload:{show:false};
  }catch{return{show:false}}
}

/** Records shown/dismiss/join for the campaign; never grants any reward. */
export async function markCampaignPopup(initData:string,campaignId:string,action:'shown'|'dismiss'|'join'):Promise<void>{
  try{await forgeFetch('campaign-popup',{initData,action,campaignId})}catch{/* silent: cosmetic only */}
}

/* ---------------- Starter Pack (new accounts from 2026-08-13, UTC-3) ---------------- */
export type StarterPackStatus={show:boolean;eligible?:boolean;claimed?:boolean;claimedAt?:string|null;
 rewards?:{fc:number;eggCode:string;eggQuantity:number;chestCode:string;chestQuantity:number}};

/** Never blocks the boot: any failure resolves as "don't show". */
export async function starterPackStatusRequest(initData:string):Promise<StarterPackStatus>{
  try{
    const response=await forgeFetch('starter-pack',{initData,action:'status'});
    if(!response.ok)return{show:false};
    const payload=await response.json().catch(()=>null) as StarterPackStatus|null;
    return payload??{show:false};
  }catch{return{show:false}}
}

/** Atomic server-side delivery. Throws so the popup can keep itself open and offer a retry. */
export async function claimStarterPackRequest(initData:string):Promise<{claimed:boolean;alreadyClaimed?:boolean;balance?:number}>{
  const response=await forgeFetch('starter-pack',{initData,action:'claim'});
  const payload=await response.json().catch(()=>null) as({claimed:boolean;alreadyClaimed?:boolean;balance?:number;error?:string})|null;
  if(!response.ok||!payload)throw new Error(payload?.error||'STARTER_PACK_CLAIM_FAILED');
  return payload;
}

/* ---------------- Tower of Eternity (solo dungeon, 100 floors) ---------------- */
export type TowerAction={action:'dashboard'}|{action:'equip';slot:number;heroId:string}|{action:'remove';slot:number}|{action:'enter';payWith?:'fc'|'ton'}|{action:'ranking';limit?:number};
const TOWER_ERRORS:Record<string,string>={TOWER_TEAM_EMPTY:'Selecione sua equipe antes de entrar na masmorra.',TOWER_NO_ATTEMPTS:'Você já usou todas as tentativas de hoje.',TOWER_DUPLICATE_HERO_TEAM:'Heróis duplicados não são permitidos na equipe.',INSUFFICIENT_FC:'FC insuficiente para entrar na masmorra.',HERO_NOT_FOUND:'Herói indisponível.',INVALID_SLOT:'Espaço inválido.',PLAYER_NOT_FOUND:'Jogador não encontrado.',PLAYER_BANNED:'Conta suspensa.'};
export async function towerRequest<T=TowerDashboard>(telegramInitData:string,input:TowerAction={action:'dashboard'}):Promise<T>{
 const response=await forgeFetch('tower',{initData:telegramInitData,...input});
 if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar a Torre.');
 const payload=await response.json().catch(()=>null) as (T&{error?:string})|null;
 if(!response.ok||!payload){const raw=payload?.error||'';throw new Error(TOWER_ERRORS[raw]||raw||'Não foi possível processar a Torre da Eternidade.')}
 return payload}
export const fetchTowerDashboard=(initData:string)=>towerRequest<TowerDashboard>(initData,{action:'dashboard'});
export const equipTowerHero=(initData:string,slot:number,heroId:string)=>towerRequest<TowerDashboard>(initData,{action:'equip',slot,heroId});
export const removeTowerHero=(initData:string,slot:number)=>towerRequest<TowerDashboard>(initData,{action:'remove',slot});
export const enterTowerFloor=(initData:string,payWith:'fc'|'ton'='fc')=>towerRequest<TowerBattle>(initData,{action:'enter',payWith});
export const fetchTowerRanking=(initData:string,limit=50)=>towerRequest<TowerRanking>(initData,{action:'ranking',limit});


/**
 * NFT EXCLUSIVE rewards — the player only ever sees their OWN unit.
 * The NFT Reward Pool (balance, reserved, health, revenue) is backend-only and
 * is never returned to the Mini App; only the admin bot can read it.
 */
export type NftRewardState={hasNft:boolean;serial?:number;totalSupply:number;dailyYieldTon?:number;availableTon?:number;lifetimeEarnedTon?:number;minClaimTon?:number;canClaim?:boolean;lastClaimAt?:string|null};
export type NftClaimResult=NftRewardState&{ok:boolean;claimId:string;amountTon:number};

const NFT_ERRORS:Record<string,string>={
  NFT_NOT_FOUND:'Acesso inválido.',
  CLAIM_TOO_SMALL:'Nenhum TON disponível para resgate ainda.',
  POOL_INSUFFICIENT:'Nenhum TON disponível para resgate ainda.',
  PLAYER_NOT_FOUND:'Jogador não encontrado.',
};

const nftError=(code:string,fallback:string)=>NFT_ERRORS[code]??fallback;

export async function fetchNftReward(telegramInitData:string):Promise<NftRewardState>{
  const response=await forgeFetch('nft',{initData:telegramInitData,action:'my'});
  const payload=await response.json().catch(()=>null) as NftRewardState&{error?:string}|null;
  if(!response.ok||!payload)throw new Error(nftError(payload?.error||'','Não foi possível carregar seu NFT.'));
  return payload;
}

export async function claimNftReward(telegramInitData:string):Promise<NftClaimResult>{
  const response=await forgeFetch('nft',{initData:telegramInitData,action:'claim'});
  const payload=await response.json().catch(()=>null) as NftClaimResult&{error?:string}|null;
  if(!response.ok||!payload)throw new Error(nftError(payload?.error||'','Não foi possível resgatar a recompensa. Tente novamente.'));
  return payload;
}

/** One NFT EXCLUSIVE pet owned by the player. Pool data is never part of this payload. */
export type NftRewardItem={positionId:string;serial:number;name:string;rarity:string;level:number;image?:string|null;tierTon:number;dailyYieldTon:number;availableTon:number;lifetimeEarnedTon:number;roiReached?:boolean;minClaimTon:number;canClaim:boolean;lastClaimAt?:string|null};
export type NftRewardList={totalSupply:number;items:NftRewardItem[]};

/**
 * Loads the NFT EXCLUSIVE pets owned by the player. `NFT_NOT_FOUND` (or the
 * legacy single-unit payload with `hasNft:false`) is an EMPTY state, never an
 * error. If the list route is unavailable we fall back to the single-unit route
 * so an NFT that already exists in MY PETS is still shown here.
 */
export async function fetchMyNftRewards(telegramInitData:string):Promise<NftRewardList>{
  const response=await forgeFetch('nft',{initData:telegramInitData,action:'mine'});
  const payload=await response.json().catch(()=>null) as NftRewardList&{error?:string}|null;
  if(response.ok&&payload&&Array.isArray(payload.items))return {totalSupply:payload.totalSupply??10,items:payload.items};
  const code=payload?.error||'';
  if(code==='NFT_NOT_FOUND')return {totalSupply:payload?.totalSupply??10,items:[]};
  console.error('[NFT LIST FAILED]',{status:response.status,error:code||null});
  // Fallback: reuse the single-unit endpoint (same owner resolution, same data).
  try{
    const single=await fetchNftReward(telegramInitData);
    if(!single.hasNft)return {totalSupply:single.totalSupply??10,items:[]};
    return {totalSupply:single.totalSupply??10,items:[{
      positionId:'single',serial:single.serial??1,name:'NFT EXCLUSIVE',rarity:'nft_exclusive',level:1,image:null,
      tierTon:0,dailyYieldTon:single.dailyYieldTon??0,availableTon:single.availableTon??0,
      lifetimeEarnedTon:single.lifetimeEarnedTon??0,minClaimTon:single.minClaimTon??0,
      canClaim:Boolean(single.canClaim),lastClaimAt:single.lastClaimAt??null,
    }]};
  }catch(fallbackError){
    console.error('[NFT FALLBACK FAILED]',fallbackError);
    throw new Error(nftError(code,'Não foi possível carregar seus NFTs.'));
  }
}

export async function claimNftPosition(telegramInitData:string,positionId:string):Promise<NftRewardList&{amountTon:number}>{
  if(positionId==='single'){
    const single=await claimNftReward(telegramInitData);
    const list=await fetchMyNftRewards(telegramInitData);
    return {...list,amountTon:single.amountTon};
  }
  const response=await forgeFetch('nft',{initData:telegramInitData,action:'claim-one',positionId});
  const payload=await response.json().catch(()=>null) as NftRewardList&{amountTon:number;error?:string}|null;
  if(!response.ok||!payload)throw new Error(nftError(payload?.error||'','Não foi possível resgatar a recompensa. Tente novamente.'));
  return {totalSupply:payload.totalSupply??10,items:payload.items??[],amountTon:payload.amountTon??0};
}

/**
 * BUY NFT store. Sale data only: price, tier daily yield, supply and status.
 * The NFT Reward Pool (balance, reserved, health, treasury) is never part of this payload.
 */
export type NftShopItem={id:string;serial:number;instance:string;name:string;slug:string;image?:string|null;rarity:string;priceTon:number;tierTon:number;dailyYieldTon:number;supply:number;status:'AVAILABLE'|'SOLD_OUT';ownedByMe:boolean;passives?:Record<string,number>};
export type NftShop={totalSupply:number;sold:number;available:number;items:NftShopItem[];balanceTon:number};

const NFT_SHOP_ERRORS:Record<string,string>={
  NFT_SOLD_OUT:'Este NFT já foi vendido.',
  NFT_NOT_FOR_SALE:'Este NFT não está disponível para compra.',
  NFT_ALREADY_OWNED:'Este NFT já possui um proprietário.',
  INSUFFICIENT_TON_BALANCE:'Saldo TON interno insuficiente.',
  INVALID_NFT:'NFT inválido.',
};

export async function fetchNftShop(telegramInitData:string):Promise<NftShop>{
  const response=await forgeFetch('nft',{initData:telegramInitData,action:'shop'});
  const payload=await response.json().catch(()=>null) as NftShop&{error?:string}|null;
  if(!response.ok||!payload||!Array.isArray(payload.items))throw new Error(nftError(payload?.error||'','Não foi possível carregar a loja de NFTs.'));
  return payload;
}

/** Buys with the internal withdrawable TON balance (atomic; the server owns every rule). */
export async function buyNftWithBalance(telegramInitData:string,nftId:string,idempotencyKey:string){
  const response=await forgeFetch('nft',{initData:telegramInitData,action:'buy-balance',nftId,idempotencyKey});
  const payload=await response.json().catch(()=>null) as {status?:string;playerPetId?:string;serial?:number;petName?:string;error?:string}|null;
  if(!response.ok||!payload)throw new Error(NFT_SHOP_ERRORS[payload?.error||'']??nftError(payload?.error||'','Não foi possível concluir a compra.'));
  return payload;
}

/** Creates the on-chain order for TON Connect (unique comment binds payment ↔ NFT). */
export async function createNftTonOrder(telegramInitData:string,nftId:string,idempotencyKey:string){
  const response=await forgeFetch('nft',{initData:telegramInitData,action:'order',nftId,idempotencyKey});
  const payload=await response.json().catch(()=>null) as {id:string;paymentAddress:string;amountNano:string;amountTon:number;paymentComment:string;expiresAt:string;error?:string}|null;
  if(!response.ok||!payload)throw new Error(NFT_SHOP_ERRORS[payload?.error||'']??nftError(payload?.error||'','Não foi possível iniciar o pagamento.'));
  return payload;
}

export type NftPurchaseVerification={checked:number;completed:string[];alreadyDelivered:string[];pending:string[];results:Array<{status?:string;petName?:string;serial?:number}>};
/** Confirms on-chain NFT payments and delivers the pet exactly once. */
export async function verifyNftPurchases(telegramInitData:string):Promise<NftPurchaseVerification>{
  const response=await forgeFetch('nft',{initData:telegramInitData,action:'verify-purchases'});
  const payload=await response.json().catch(()=>null) as NftPurchaseVerification&{error?:string}|null;
  if(!response.ok||!payload)throw new Error(nftError(payload?.error||'','Não foi possível verificar o pagamento.'));
  return {checked:payload.checked??0,completed:payload.completed??[],alreadyDelivered:payload.alreadyDelivered??[],pending:payload.pending??[],results:payload.results??[]};
}

/**
 * NFT EXCLUSIVE HEROES — same structure as the NFT pets store.
 * Sale data only (price, daily yield through hero mining, supply, status).
 */
export type NftHeroShopItem={id:string;serial:number;instance:string;name:string;slug:string;image?:string|null;rarity:string;priceTon:number;tierTon:number;dailyYieldTon:number;supply:number;status:'AVAILABLE'|'SOLD_OUT';ownedByMe:boolean;atk?:number;hp?:number};
export type NftHeroShop={totalSupply:number;sold:number;available:number;items:NftHeroShopItem[];balanceTon:number};
export type NftHeroOwned={nftId:string;playerHeroId:string|null;serial:number;instance:string;name:string;image?:string|null;rarity:string;level:number;stars:number;atk:number;hp:number;tierTon:number;dailyYieldTon:number};

export async function fetchNftHeroShop(telegramInitData:string):Promise<NftHeroShop>{
  const response=await forgeFetch('nft-hero',{initData:telegramInitData,action:'shop'});
  const payload=await response.json().catch(()=>null) as NftHeroShop&{error?:string}|null;
  if(!response.ok||!payload||!Array.isArray(payload.items))throw new Error(nftError(payload?.error||'','Não foi possível carregar a loja de heróis NFT.'));
  return payload;
}

export async function fetchMyNftHeroes(telegramInitData:string):Promise<{totalSupply:number;items:NftHeroOwned[]}>{
  const response=await forgeFetch('nft-hero',{initData:telegramInitData,action:'mine'});
  const payload=await response.json().catch(()=>null) as {totalSupply?:number;items?:NftHeroOwned[];error?:string}|null;
  if(!response.ok||!payload||!Array.isArray(payload.items)){
    if(payload?.error==='NFT_HERO_NOT_FOUND')return {totalSupply:10,items:[]};
    throw new Error(nftError(payload?.error||'','Não foi possível carregar seus heróis NFT.'));
  }
  return {totalSupply:payload.totalSupply??10,items:payload.items};
}

/** Buys with the internal withdrawable TON balance (atomic; the server owns every rule). */
export async function buyNftHeroWithBalance(telegramInitData:string,nftId:string,idempotencyKey:string){
  const response=await forgeFetch('nft-hero',{initData:telegramInitData,action:'buy-balance',nftId,idempotencyKey});
  const payload=await response.json().catch(()=>null) as {status?:string;playerHeroId?:string;serial?:number;heroName?:string;error?:string}|null;
  if(!response.ok||!payload)throw new Error(NFT_SHOP_ERRORS[payload?.error||'']??nftError(payload?.error||'','Não foi possível concluir a compra.'));
  return payload;
}

/** Creates the on-chain order for TON Connect (unique comment binds payment ↔ NFT hero). */
export async function createNftHeroTonOrder(telegramInitData:string,nftId:string,idempotencyKey:string){
  const response=await forgeFetch('nft-hero',{initData:telegramInitData,action:'order',nftId,idempotencyKey});
  const payload=await response.json().catch(()=>null) as {id:string;paymentAddress:string;amountNano:string;amountTon:number;paymentComment:string;expiresAt:string;error?:string}|null;
  if(!response.ok||!payload)throw new Error(NFT_SHOP_ERRORS[payload?.error||'']??nftError(payload?.error||'','Não foi possível iniciar o pagamento.'));
  return payload;
}

export async function verifyNftHeroPurchases(telegramInitData:string):Promise<NftPurchaseVerification>{
  const response=await forgeFetch('nft-hero',{initData:telegramInitData,action:'verify-purchases'});
  const payload=await response.json().catch(()=>null) as NftPurchaseVerification&{error?:string}|null;
  if(!response.ok||!payload)throw new Error(nftError(payload?.error||'','Não foi possível verificar o pagamento.'));
  return {checked:payload.checked??0,completed:payload.completed??[],alreadyDelivered:payload.alreadyDelivered??[],pending:payload.pending??[],results:payload.results??[]};
}

/**
 * MYTHREON ARSENAL — the player's full equipment collection (normal + NFT 1/1)
 * and the primary store for NFT EXCLUSIVE EQUIPMENT. Every rule (supply 1/1,
 * weapon class, ownership, payment) is enforced server-side.
 */
export type ArsenalItem={instanceId:string;code:string;name:string;slot:'weapon'|'armor'|'ring';kind:string|null;rarity:string|null;image:string|null;level:number;power:number;heroClass:string|null;bonusAttack:number;bonusDefense:number;bonusHp:number;listed:boolean;tradable:boolean;isNft:boolean;serial:number|null;instance:string|null;equippedHeroId:string|null;equippedHeroName:string|null};
export type NftEquipShopItem={id:string;code:string;name:string;slot:'weapon'|'armor'|'ring';kind:string|null;rarity:string;image:string|null;power:number;serial:number;instance:string;supply:number;status:'AVAILABLE'|'SOLD_OUT';priceTon:number;heroClass:string|null;bonusAttack:number;bonusDefense:number;bonusHp:number;description:string|null;ownedByMe:boolean|null};
export type NftEquipShop={totalSupply:number;sold:number;available:number;balanceTon:number;items:NftEquipShopItem[]};

export async function fetchArsenal(telegramInitData:string):Promise<{items:ArsenalItem[]}>{
  const response=await forgeFetch('arsenal',{initData:telegramInitData});
  const payload=await response.json().catch(()=>null) as {items?:ArsenalItem[];error?:string}|null;
  if(!response.ok||!payload||!Array.isArray(payload.items))throw new Error(nftError(payload?.error||'','Não foi possível carregar o arsenal.'));
  return {items:payload.items};
}

export async function fetchNftEquipmentShop(telegramInitData:string):Promise<NftEquipShop>{
  const response=await forgeFetch('nft-equip',{initData:telegramInitData,action:'shop'});
  const payload=await response.json().catch(()=>null) as NftEquipShop&{error?:string}|null;
  if(!response.ok||!payload||!Array.isArray(payload.items))throw new Error(nftError(payload?.error||'','Não foi possível carregar a loja de equipamentos NFT.'));
  return payload;
}

/** Buys with the internal withdrawable TON balance (atomic; 1/1 supply guaranteed server-side). */
export async function buyNftEquipmentWithBalance(telegramInitData:string,nftId:string,idempotencyKey:string){
  const response=await forgeFetch('nft-equip',{initData:telegramInitData,action:'buy-balance',nftId,idempotencyKey});
  const payload=await response.json().catch(()=>null) as {status?:string;instanceId?:string;serial?:number;itemName?:string;error?:string}|null;
  if(!response.ok||!payload)throw new Error(NFT_SHOP_ERRORS[payload?.error||'']??nftError(payload?.error||'','Não foi possível concluir a compra.'));
  return payload;
}

/** Creates the on-chain order for TON Connect (unique comment binds payment ↔ NFT equipment). */
export async function createNftEquipmentTonOrder(telegramInitData:string,nftId:string,idempotencyKey:string){
  const response=await forgeFetch('nft-equip',{initData:telegramInitData,action:'order',nftId,idempotencyKey});
  const payload=await response.json().catch(()=>null) as {id:string;paymentAddress:string;amountNano:string;amountTon:number;paymentComment:string;expiresAt:string;error?:string}|null;
  if(!response.ok||!payload)throw new Error(NFT_SHOP_ERRORS[payload?.error||'']??nftError(payload?.error||'','Não foi possível iniciar o pagamento.'));
  return payload;
}

export async function verifyNftEquipmentPurchases(telegramInitData:string):Promise<NftPurchaseVerification>{
  const response=await forgeFetch('nft-equip',{initData:telegramInitData,action:'verify-purchases'});
  const payload=await response.json().catch(()=>null) as NftPurchaseVerification&{error?:string}|null;
  if(!response.ok||!payload)throw new Error(nftError(payload?.error||'','Não foi possível verificar o pagamento.'));
  return {checked:payload.checked??0,completed:payload.completed??[],alreadyDelivered:payload.alreadyDelivered??[],pending:payload.pending??[],results:payload.results??[]};
}





/**
 * Hero TON mining. Rates, elapsed time and claimable amount are ALL server-side;
 * the client only reads the state and asks for a claim.
 */
export async function miningRequest<T=HeroMiningState>(initData:string,action:'status'|'claim'):Promise<T>{
  const response=await forgeFetch('mining',{initData,action});
  if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar a mineração.');
  const payload=await response.json().catch(()=>null)as(T&{error?:string})|null;
  if(!response.ok||!payload){
    const raw=payload?.error||'';
    const friendly:Record<string,string>={MINING_DISABLED:'A mineração está temporariamente pausada.',NOTHING_TO_CLAIM:'Nada para coletar ainda.',NO_TON_INVESTMENT:'Mineração inativa no momento.',ROI_LIMIT_REACHED:'Mineração inativa no momento.',PLAYER_NOT_FOUND:'Jogador não encontrado.'};
    throw new Error(friendly[raw]||raw||'Não foi possível processar a mineração.');
  }
  return payload;
}
export const fetchHeroMining=(initData:string)=>miningRequest<HeroMiningState>(initData,'status');
export const claimHeroMining=(initData:string)=>miningRequest<HeroMiningClaimResult>(initData,'claim');


/**
 * NFT BREEDING / SUB-NFT. Costs, breed counters, cooldowns and egg minting are all
 * server-side; the client only sends the chosen NFTs and confirms its own payment.
 */
const BREEDING_ERRORS: Record<string, string> = {
  BREEDING_DISABLED: 'O breeding está temporariamente desativado.',
  SAME_NFT_NOT_ALLOWED: 'Você não pode cruzar o mesmo NFT com ele mesmo.',
  NOT_YOUR_NFT: 'Este NFT não é seu.',
  NFT_NOT_OWNED: 'Este NFT não tem proprietário válido.',
  NFT_LOCKED: 'Este NFT está bloqueado pelo administrador.',
  MAX_BREEDING_REACHED: 'MAX BREEDING REACHED — este NFT já reproduziu 3 vezes.',
  BREEDING_COOLDOWN: 'Este NFT ainda está em cooldown de breeding.',
  NFT_IN_BREEDING: 'Este NFT já está em outro breeding.',
  REQUEST_NOT_FOUND: 'Pedido de breeding não encontrado.',
  REQUEST_NOT_OPEN: 'Este pedido não está mais aberto.',
  REQUEST_NOT_PENDING: 'Este pedido já foi respondido.',
  NOT_YOUR_REQUEST: 'Este pedido não é seu.',
  BREEDING_EXPIRED: 'BREEDING EXPIRED — o pedido venceu.',
  INSUFFICIENT_TON_BALANCE: 'Saldo TON insuficiente. Deposite TON para pagar sua parte.',
  CLAIM_BELOW_MINIMUM: 'Valor abaixo do mínimo para coletar.',
  QUERY_TOO_SHORT: 'Digite ao menos 2 caracteres para buscar.',
  NO_SUB_NFT_TEMPLATE: 'Nenhum modelo de Sub-NFT disponível.',
  PLAYER_NOT_FOUND: 'Jogador não encontrado.',
};

async function breedingCall<T>(initData: string, body: Record<string, unknown>): Promise<T> {
  const response = await forgeFetch('breeding', { initData, ...body });
  if (response.status === 404) throw new Error('Backend indisponível: não foi possível contatar o breeding.');
  const payload = await response.json().catch(() => null) as (T & { error?: string }) | null;
  if (!response.ok || !payload) {
    const raw = payload?.error || '';
    throw new Error(BREEDING_ERRORS[raw] || raw || 'Não foi possível processar o breeding.');
  }
  return payload;
}

export const fetchBreedingState = (initData: string) => breedingCall<import('./breeding').BreedingState>(initData, { action: 'state' });
export const searchBreedingPartners = (initData: string, query: string) =>
  breedingCall<import('./breeding').PartnerNft[]>(initData, { action: 'search', query });
export const createBreedingRequest = (initData: string, myNftId: string, partnerNftId: string) =>
  breedingCall<{ requestId: string; status: string; costA: number; costB: number; selfBreed: boolean }>(initData, { action: 'request', myNftId, partnerNftId });
export const respondBreedingRequest = (initData: string, requestId: string, accept: boolean) =>
  breedingCall<{ ok: boolean; status: string }>(initData, { action: 'respond', requestId, accept });
export const payBreedingShare = (initData: string, requestId: string, idempotencyKey: string) =>
  breedingCall<{ ok: boolean; status: string; eggA?: string; eggB?: string }>(initData, { action: 'pay', requestId, idempotencyKey });
export const claimSubNftMining = (initData: string) =>
  breedingCall<{ ok: boolean; claimedTon: number }>(initData, { action: 'claim-mining' });

/** PET EXPEDITIONS (AFK). Timers live on the server; the client only reads timestamps. */
const EXPEDITION_ERRORS: Record<string, string> = {
  MISSION_NOT_FOUND: 'Missão indisponível.',
  TEAM_MUST_HAVE_3_PETS: 'Selecione exatamente 3 pets.',
  DUPLICATED_PET: 'Não repita o mesmo pet na equipe.',
  PET_NOT_YOURS: 'Este pet não é seu.',
  PET_ON_EXPEDITION: 'Este pet já está em expedição.',
  SUB_NFT_NOT_ADULT: 'Sub-NFTs só podem ir em expedição quando adultos.',
  EXPEDITION_NOT_FOUND: 'Expedição não encontrada.',
  EXPEDITION_IN_PROGRESS: 'A expedição ainda está em andamento.',
  ALREADY_CLAIMED: 'Recompensa já coletada.',
  PLAYER_NOT_FOUND: 'Jogador não encontrado.',
};

async function expeditionCall<T>(initData: string, body: Record<string, unknown>): Promise<T> {
  const response = await forgeFetch('expeditions', { initData, ...body });
  if (response.status === 404) throw new Error('Backend indisponível: não foi possível contatar as expedições.');
  const payload = await response.json().catch(() => null) as (T & { error?: string }) | null;
  if (!response.ok || !payload) {
    const raw = payload?.error || '';
    throw new Error(EXPEDITION_ERRORS[raw] || raw || 'Não foi possível processar a expedição.');
  }
  return payload;
}

export const fetchExpeditionState = (initData: string) => expeditionCall<import('./breeding').ExpeditionState>(initData, { action: 'state' });
export const startExpedition = (initData: string, missionId: string, petIds: string[]) =>
  expeditionCall<{ ok: boolean; expeditionId: string; teamPower: number; successChance: number; finishesAt: string }>(initData, { action: 'start', missionId, petIds });
export const claimExpedition = (initData: string, expeditionId: string) =>
  expeditionCall<{ ok: boolean; success: boolean; rewards: import('./breeding').ExpeditionReward[] }>(initData, { action: 'claim', expeditionId });

/**
 * Extra attempts are ALWAYS scoped to one mission and one game day: 5 via rewarded ads
 * and 5 via FC, counted separately per mission (never a global expedition limit).
 */
export const beginExpeditionAd = (initData: string, missionId: string) =>
  expeditionCall<{ viewId: string; blockId: string | null; attempts: import('./breeding').ExpeditionAttempts }>(initData, { action: 'ad-begin', missionId });
export const claimExpeditionAd = (initData: string, viewId: string) =>
  expeditionCall<{ granted: boolean; reason?: string; attempts: import('./breeding').ExpeditionAttempts }>(initData, { action: 'ad-claim', viewId });
/**
 * AD BOOST: rewarded ad that cuts 20% of the remaining time of ONE active expedition
 * (max 5 per expedition, resolved and persisted server-side).
 */
export const beginExpeditionBoostAd = (initData: string, expeditionId: string) =>
  expeditionCall<{ viewId: string; blockId: string | null; adBoostsUsed: number; maxAdBoosts: number }>(initData, { action: 'boost-ad-begin', expeditionId });
export const claimExpeditionBoostAd = (initData: string, viewId: string) =>
  expeditionCall<{ granted: boolean; reason?: string; finishesAt: string; secondsSaved: number; adBoostsUsed: number; maxAdBoosts: number }>(initData, { action: 'boost-ad-claim', viewId });
export const buyExpeditionExtra = (initData: string, missionId: string, idempotencyKey: string) =>
  expeditionCall<{ ok: boolean; duplicate?: boolean; spentFc?: number; attempts: import('./breeding').ExpeditionAttempts }>(initData, { action: 'buy-extra', missionId, idempotencyKey });


/* ===================== TACTICAL ARENA (PVP 3V3) ===================== */
export type TacticalAction=
 |{action:'dashboard'}
 |{action:'save-team';slot:number;heroId:string}
 |{action:'remove-team';slot:number}
 |{action:'save-deck';skillKeys:string[]}
 |{action:'queue-join';practice?:boolean}
 |{action:'queue-cancel'}
 |{action:'queue-status'}
 |{action:'match';matchId:string}
 |{action:'action';matchId:string;skillKey:string;targetUid?:string|null;clientKey?:string}
 |{action:'history';limit?:number}
 |{action:'ranking';limit?:number};
/**
 * Single bridge to the tactical engine. Errors keep their backend code so
 * `tError` can localize them (TACTICAL_*, SKILL_*, DUPLICATED_HERO_TEMPLATE...).
 */
export async function tacticalRequest<T>(telegramInitData:string,input:TacticalAction):Promise<T>{
  const response=await forgeFetch('tactical',{initData:telegramInitData,...input});
  if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar a Arena Tática.');
  const payload=await response.json().catch(()=>null) as (T&{error?:string})|null;
  if(!response.ok||!payload){const raw=(payload as {error?:string}|null)?.error||'';if(raw)console.error('[MYTHREON TACTICAL]',input.action,raw);throw new Error(raw||'TACTICAL_ERROR')}
  return payload;
}
export const fetchTacticalDashboard=(initData:string)=>tacticalRequest<import('./tactical').TacticalDashboard>(initData,{action:'dashboard'});
export const saveTacticalTeamSlot=(initData:string,slot:number,heroId:string)=>tacticalRequest<import('./tactical').TacticalDashboard>(initData,{action:'save-team',slot,heroId});
export const removeTacticalTeamSlot=(initData:string,slot:number)=>tacticalRequest<import('./tactical').TacticalDashboard>(initData,{action:'remove-team',slot});
export const saveTacticalDeck=(initData:string,skillKeys:string[])=>tacticalRequest<import('./tactical').TacticalDashboard>(initData,{action:'save-deck',skillKeys});
export const joinTacticalQueue=(initData:string,practice=false)=>tacticalRequest<import('./tactical').TacticalQueueState>(initData,{action:'queue-join',practice});
export const cancelTacticalQueue=(initData:string)=>tacticalRequest<import('./tactical').TacticalQueueState>(initData,{action:'queue-cancel'});
export const pollTacticalQueue=(initData:string)=>tacticalRequest<import('./tactical').TacticalQueueState>(initData,{action:'queue-status'});
export const fetchTacticalMatch=(initData:string,matchId:string)=>tacticalRequest<import('./tactical').TacticalMatch>(initData,{action:'match',matchId});
export const submitTacticalAction=(initData:string,matchId:string,skillKey:string,targetUid?:string|null,clientKey?:string)=>tacticalRequest<import('./tactical').TacticalMatch>(initData,{action:'action',matchId,skillKey,targetUid,clientKey});
export const fetchTacticalHistory=(initData:string,limit=20)=>tacticalRequest<import('./tactical').TacticalHistoryEntry[]>(initData,{action:'history',limit});
export const fetchTacticalRanking=(initData:string,limit=50)=>tacticalRequest<import('./tactical').TacticalRanking>(initData,{action:'ranking',limit});

// ------------------------------------------------------------- auction (TON interno apenas)
/**
 * Leilão: nunca envolve FC nem TonConnect. Os lances reservam o saldo TON interno
 * do jogador; o backend é a única autoridade sobre reserva, liberação, taxa e entrega.
 */
const AUCTION_ERRORS:Record<string,string>={
  AUCTION_DISABLED:'O Leilão está temporariamente desativado.',
  AUCTION_NOT_FOUND:'Leilão não encontrado.',
  AUCTION_NOT_ACTIVE:'Este leilão não está mais ativo.',
  AUCTION_ENDED:'Este leilão já terminou.',
  AUCTION_HAS_BIDS:'Não é possível cancelar um leilão que já recebeu lances.',
  NOT_AUCTION_OWNER:'Este leilão não é seu.',
  CANNOT_BID_OWN_AUCTION:'Você não pode dar lance no seu próprio leilão.',
  BID_TOO_LOW:'Lance abaixo do mínimo permitido.',
  INVALID_BID:'Lance inválido.',
  INVALID_DURATION:'Duração inválida.',
  INVALID_PRICE:'Lance inicial inválido.',
  PRICE_BELOW_MINIMUM:'Lance inicial abaixo do mínimo.',
  PRICE_ABOVE_MAXIMUM:'Lance inicial acima do máximo.',
  INSUFFICIENT_TON_BALANCE:'Saldo TON interno insuficiente. Deposite TON antes de dar o lance.',
  NOT_AUCTION_ITEM:'Este item não é elegível ao leilão.',
  AUCTION_ONLY_ITEM:'Este item só pode ser negociado no Leilão.',
  ITEM_NOT_OWNED:'Este item não pertence a você.',
  ALREADY_LISTED:'Este item já está anunciado.',
  ITEM_EQUIPPED:'Desequipe o item antes de leiloar.',
  ITEM_LOCKED:'Remova o bloqueio do item antes de leiloar.',
  HERO_LOCKED:'Remova o bloqueio do herói antes de leiloar.',
  HERO_NOT_TRADABLE:'Este herói não pode ser negociado.',
  HERO_IN_PVP_TEAM:'Retire o herói da equipe de PvP antes de leiloar.',
  HERO_IN_BOSS_TEAM:'Retire o herói da equipe do Chefe antes de leiloar.',
  PET_IS_ACTIVE:'Desative o pet antes de leiloar.',
  PET_NOT_TRADABLE:'Este pet não pode ser negociado.',
  PLAYER_NOT_FOUND:'Jogador não encontrado.',
};
export type AuctionApiAction=
  |{action:'browse';itemType?:string;sort?:string;limit?:number;offset?:number}
  |{action:'sellable'}
  |{action:'mine'}
  |{action:'create';itemType:string;itemInstanceId:string;startingBidTon:number;durationHours:number}
  |{action:'bid';auctionId:string;amountTon:number;idempotencyKey?:string}
  |{action:'cancel';auctionId:string};
export async function auctionRequest<T>(initData:string,input:AuctionApiAction):Promise<T>{
  const response=await forgeFetch('auction',{initData,...input});
  if(response.status===404)throw new Error('Backend indisponível: não foi possível contatar o leilão.');
  const payload=await response.json().catch(()=>null) as (T&{error?:string})|null;
  if(!response.ok||!payload){
    const raw=payload?.error||'';
    const known=AUCTION_ERRORS[raw];
    if(!known)console.error('[AUCTION]',raw);
    const isBusinessCode=/^[A-Z][A-Z0-9_]{2,48}$/.test(raw);
    throw new Error(known||(isBusinessCode?`Leilão: ${raw.replace(/_/g,' ').toLowerCase()}.`:'Não foi possível processar o leilão. Tente novamente.'));
  }
  return payload;
}
export const fetchAuctionBrowse=(initData:string,itemType:string='all',sort:string='ending')=>auctionRequest<import('./auction').AuctionBrowse>(initData,{action:'browse',itemType,sort,limit:60});
export const fetchAuctionSellable=(initData:string)=>auctionRequest<import('./auction').AuctionSellable>(initData,{action:'sellable'});
export const fetchAuctionMine=(initData:string)=>auctionRequest<import('./auction').AuctionMine>(initData,{action:'mine'});
export const createAuction=(initData:string,input:{itemType:string;itemInstanceId:string;startingBidTon:number;durationHours:number})=>auctionRequest<{ok:boolean;auctionId:string}>(initData,{action:'create',...input});
export const placeAuctionBid=(initData:string,auctionId:string,amountTon:number,idempotencyKey?:string)=>auctionRequest<{ok:boolean;bidTon:number;availableTon?:number}>(initData,{action:'bid',auctionId,amountTon,idempotencyKey});
export const cancelAuction=(initData:string,auctionId:string)=>auctionRequest<{ok:boolean}>(initData,{action:'cancel',auctionId});
