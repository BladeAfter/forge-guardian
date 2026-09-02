import { useEffect } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { realtimeSupabase as supabase } from './realtimeClient';

import type { ActivityProgress, ChannelRewards, RewardHistory } from './services';
import { fetchGlobalBossRanking, fetchGlobalBossHistory, fetchRarityFusion, fetchHeroFusion, channelsRequest, fetchDailyQuests, fetchRewardHistory, fetchPlayerHeroes, fetchPlayerInventory, bossRequest, calendarRequest, activityProgressRequest,communityPoolRequest, fetchGameState, fetchReferralDashboard, fetchTelegramProfile, petRequest, pvpRequest, seasonPassRequest, walletRequest, fetchMarketBrowse, fetchMarketItemDetails, fetchMarketMine, fetchMarketQuote, fetchMarketSellable, fetchMarketStatus } from './services';
import type { MarketBrowse, MarketCurrency, MarketItemDetailsResult, MarketItemType, MarketMine, MarketQuote, MarketSellable, MarketSort, MarketStatus } from './market';

import type { GameState } from './types';
import type { BossCombat, GlobalBossRanking, GlobalBossHistoryRow } from './combat';
import type { ReferralDashboard } from './referrals';
import type { PetDashboard } from './pets';
import type { MythUtilityState } from './mythUtility';
import { fetchMythUtility } from './services';
import type { TowerDashboard as TowerDashboardType, TowerRanking } from './tower';
import { fetchTowerDashboard, fetchTowerRanking } from './services';
import type { PvpDashboard, PvpHero } from './pvp';
import type { TonWallet, WalletSummary ,MythWallet} from './wallet';
import type { TelegramPlayerProfile } from './playerProfile';
import type { FounderPackState } from './founderPack';
import type { VeteranVaultState } from './veteranVault';
import type { VeteranV2State } from './veteranVaultV2';
import type { CelestialPackState } from './celestialPack';
import type { VanguardPackState } from './vanguardPack';
import type { PremiumOffersState } from './premiumOffers';
import type { CalendarDashboard, PlayerInventory } from './calendarRewards';
import type{SeasonPassDashboard}from'./seasonPass';
import type{CommunityPoolDashboard}from'./communityPool';
import type{DailyQuestsDashboard}from'./quests';
import type{FusionDashboard,RarityFusionDashboard}from'./heroFusion';
import{fetchClanDashboard,type ClanDashboard}from'./clans';
import{fetchClanWarDashboard,type ClanWarDashboard}from'./clanWar';
import{fetchClanBoss,type ClanBossState}from'./clanBoss';
import type{SpecialEventsDashboard}from'./specialEvents';
import{specialEventsRequest,spendingEventRequest}from'./services';
import type{SpendingEventDashboard}from'./spendingEvent';
import type{MarketingPoolDashboard}from'./marketingPool';
import{marketingPoolRequest}from'./services';
import type{MythSaleDashboard}from'./mythSale';
import type{MythStakingDashboard}from'./mythStaking';
import{fetchMythSale}from'./services';
import type{HeroMiningState}from'./heroMining';
import{fetchHeroMining}from'./services';

export const useGameState = (telegramInitData: string | null, enabled: boolean) => {
  return useQuery<GameState>({
    queryKey: ['game-state', telegramInitData],
    queryFn: () => fetchGameState(telegramInitData ?? ''),
    enabled,
    retry: 1,
    staleTime: 1000 * 60
  });
};

export const useBossCombat = (telegramInitData: string | null, enabled: boolean) => useQuery<BossCombat>({
  queryKey:['boss-combat',telegramInitData],queryFn:()=>bossRequest(telegramInitData ?? '','process'),enabled,
  refetchInterval:8_000,refetchOnWindowFocus:true,staleTime:6_000,retry:1
});

/** Global boss ranking; only polled while the ranking sheet is open. */
export const useGlobalBossRanking=(telegramInitData:string|null,enabled:boolean,limit=50)=>useQuery<GlobalBossRanking>({
  queryKey:['global-boss-ranking',telegramInitData,limit],queryFn:()=>fetchGlobalBossRanking(telegramInitData??'',limit),
  enabled,refetchInterval:enabled?10_000:false,staleTime:8_000,retry:1
});
/** Global boss history (past cycles); one row per finished boss cycle. */
export const useGlobalBossHistory=(telegramInitData:string|null,enabled:boolean,limit=10)=>useQuery<GlobalBossHistoryRow[]>({
  queryKey:['global-boss-history',telegramInitData,limit],queryFn:()=>fetchGlobalBossHistory(telegramInitData??'',limit),
  enabled,staleTime:30_000,retry:1
});
export const useReferralDashboard=(telegramInitData:string|null,enabled:boolean,level?:1|2|3,offset=0)=>useQuery<ReferralDashboard>({queryKey:['referral-dashboard',telegramInitData,level??'all',offset],queryFn:()=>fetchReferralDashboard(telegramInitData??'',level,offset),enabled,staleTime:60_000,refetchInterval:120_000,refetchOnWindowFocus:true,retry:1});
/** MYTH utility (rates, discount, per-feature switches, spendable balance). Shared by every screen that offers MYTH. */
export const useMythUtility=(telegramInitData:string|null,enabled=true)=>useQuery<MythUtilityState>({queryKey:['myth-utility',telegramInitData],queryFn:()=>fetchMythUtility(telegramInitData??''),enabled:enabled&&!!telegramInitData,staleTime:30_000,retry:1});
export const usePetDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<PetDashboard>({queryKey:['pet-dashboard',telegramInitData],queryFn:async()=>petRequest(telegramInitData??'',{action:'dashboard'}) as Promise<PetDashboard>,enabled,staleTime:20_000,refetchOnWindowFocus:true,retry:1});
export const usePvpDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<PvpDashboard>({queryKey:['pvp-dashboard',telegramInitData],queryFn:()=>pvpRequest<PvpDashboard>(telegramInitData??'',{action:'dashboard'}),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});
export const useWalletSummary=(telegramInitData:string|null,enabled:boolean)=>useQuery<WalletSummary>({queryKey:['wallet-summary',telegramInitData],queryFn:()=>walletRequest<WalletSummary>(telegramInitData??'',{action:'summary'}),enabled,staleTime:30_000,refetchInterval:60_000,refetchOnWindowFocus:true,retry:3,retryDelay:a=>Math.min(1200*2**a,6000)});
/** Withdrawable TON balance (rewards only). Shared key so any credit refreshes header + wallet. */
export const useTonWallet=(telegramInitData:string|null,enabled:boolean)=>useQuery<TonWallet>({queryKey:['ton-wallet',telegramInitData],queryFn:()=>walletRequest<TonWallet>(telegramInitData??'',{action:'ton-wallet'}),enabled,staleTime:30_000,refetchInterval:60_000,refetchOnWindowFocus:true,retry:3,retryDelay:a=>Math.min(1200*2**a,6000)});
/** MYTH Token balance (decorative). Read-only: nothing in the app can spend or convert it. */
export const useMythWallet=(telegramInitData:string|null,enabled:boolean)=>useQuery<MythWallet>({queryKey:['myth-wallet',telegramInitData],queryFn:()=>walletRequest<MythWallet>(telegramInitData??'',{action:'myth'}),enabled,staleTime:60_000,refetchOnWindowFocus:true,retry:1});
/** Internal MYTH staking dashboard: settings, plans, positions and accrued rewards are server-owned. */
export const useMythStaking=(telegramInitData:string|null,enabled:boolean)=>useQuery<MythStakingDashboard>({queryKey:['myth-staking',telegramInitData],queryFn:()=>walletRequest<MythStakingDashboard>(telegramInitData??'',{action:'myth-staking'}),enabled,staleTime:15_000,refetchInterval:enabled?60_000:false,refetchOnWindowFocus:true,retry:1});
/** 👑 FOUNDER PACK: server-owned visibility. Short polling keeps the 7-day countdown honest. */
export const useFounderPack=(telegramInitData:string|null,enabled:boolean)=>useQuery<FounderPackState>({queryKey:['founder-pack',telegramInitData],queryFn:()=>walletRequest<FounderPackState>(telegramInitData??'',{action:'founder-pack'}),enabled,staleTime:30_000,refetchOnWindowFocus:true,retry:1});
export const useVeteranVault=(telegramInitData:string|null,enabled:boolean)=>useQuery<VeteranVaultState>({queryKey:['veteran-vault',telegramInitData],queryFn:()=>walletRequest<VeteranVaultState>(telegramInitData??'',{action:'veteran-vault'}),enabled,staleTime:30_000,refetchOnWindowFocus:true,retry:1});
/** ⚔️ VETERAN VAULT V2: visibilidade, preço e estoque são do servidor. */
export const useVeteranV2=(telegramInitData:string|null,enabled:boolean)=>useQuery<VeteranV2State>({queryKey:['veteran-v2',telegramInitData],queryFn:()=>walletRequest<VeteranV2State>(telegramInitData??'',{action:'veteran-v2'}),enabled,staleTime:30_000,refetchOnWindowFocus:true,retry:1});
/** 💫 CELESTIAL MYSTERY PACK: visibilidade, preço, estoque e status de revelação são do servidor. */
export const useCelestialPack=(telegramInitData:string|null,enabled:boolean)=>useQuery<CelestialPackState>({queryKey:['celestial-pack',telegramInitData],queryFn:()=>walletRequest<CelestialPackState>(telegramInitData??'',{action:'celestial-pack'}),enabled,staleTime:30_000,refetchOnWindowFocus:true,retry:1});
/** ⚔️ MYTHIC VANGUARD PACK: visibilidade, preço, estoque e status de revelação são do servidor. */
export const useVanguardPack=(telegramInitData:string|null,enabled:boolean)=>useQuery<VanguardPackState>({queryKey:['vanguard-pack',telegramInitData],queryFn:()=>walletRequest<VanguardPackState>(telegramInitData??'',{action:'vanguard-pack'}),enabled,staleTime:30_000,refetchOnWindowFocus:true,retry:1});
/** 🎁 PREMIUM OFFERS: fila de popups (Founder → Veteran) decidida 100% pelo servidor, 1x por dia. */
export const usePremiumOffers=(telegramInitData:string|null,enabled:boolean)=>useQuery<PremiumOffersState>({queryKey:['premium-offers',telegramInitData],queryFn:()=>walletRequest<PremiumOffersState>(telegramInitData??'',{action:'premium-offers'}),enabled,staleTime:60_000,refetchOnWindowFocus:false,retry:1});
export const useTelegramProfile=(telegramInitData:string|null,enabled:boolean)=>useQuery<TelegramPlayerProfile>({queryKey:['telegram-profile',telegramInitData],queryFn:()=>fetchTelegramProfile(telegramInitData??''),enabled,staleTime:60_000,refetchOnWindowFocus:true,retry:1});
/** Stored chests and eggs; shares the ['player-inventory'] key so any grant refreshes it. */
export const usePlayerInventory=(telegramInitData:string|null,enabled:boolean)=>useQuery<PlayerInventory>({queryKey:['player-inventory',telegramInitData],queryFn:()=>fetchPlayerInventory(telegramInitData??''),enabled,staleTime:5_000,refetchOnMount:'always',refetchOnWindowFocus:true});
export const useCalendarDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<CalendarDashboard>({queryKey:['calendar-dashboard',telegramInitData],queryFn:()=>calendarRequest(telegramInitData??''),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});
export const useSeasonPass=(telegramInitData:string|null,enabled:boolean)=>useQuery<SeasonPassDashboard>({queryKey:['season-pass',telegramInitData],queryFn:()=>seasonPassRequest(telegramInitData??''),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});
export const useActivityProgress=(telegramInitData:string|null,enabled:boolean)=>useQuery<ActivityProgress>({queryKey:['activity-progress',telegramInitData],queryFn:()=>activityProgressRequest(telegramInitData??''),enabled,staleTime:15_000,refetchOnMount:'always',refetchOnWindowFocus:true,retry:1});
export const useCommunityPool=(telegramInitData:string|null,enabled:boolean)=>useQuery<CommunityPoolDashboard>({queryKey:['community-pool',telegramInitData],queryFn:()=>communityPoolRequest(telegramInitData??''),enabled,staleTime:15_000,refetchOnMount:'always',refetchInterval:60_000,refetchOnWindowFocus:true,retry:1});

/** Special events tab: short refetch keeps the referral ranking live without a reload. */
export const useSpecialEvents=(telegramInitData:string|null,enabled:boolean)=>useQuery<SpecialEventsDashboard>({queryKey:['special-events',telegramInitData],queryFn:()=>specialEventsRequest(telegramInitData??''),enabled,staleTime:15_000,refetchOnMount:'always',refetchInterval:60_000,refetchOnWindowFocus:true,retry:1});

/**
 * Spending Event: realtime reacts to the public aggregate ticker only, so a
 * change never triggers another write (no realtime -> refetch -> realtime loop).
 * A moderate 25s refetch is the fallback when realtime is unavailable.
 */
export const useSpendingEvent=(telegramInitData:string|null,enabled:boolean,limit=20)=>{
  const client=useQueryClient();
  const query=useQuery<SpendingEventDashboard>({queryKey:['spending-event',telegramInitData,limit],queryFn:()=>spendingEventRequest(telegramInitData??'',limit),enabled,staleTime:10_000,refetchInterval:enabled?25_000:false,refetchOnWindowFocus:true,retry:1});
  useEffect(()=>{
    if(!enabled)return;
    const channel=supabase.channel('spending-event-ticker')
      .on('postgres_changes',{event:'*',schema:'public',table:'spending_event_ticker'},()=>{void client.invalidateQueries({queryKey:['spending-event']})})
      .on('postgres_changes',{event:'*',schema:'public',table:'spending_event_scores'},()=>{void client.invalidateQueries({queryKey:['spending-event']})})
      .subscribe();
    return()=>{void supabase.removeChannel(channel)};
  },[enabled,client]);
  return query;
};

/**
 * Live MYTH state: balances, staking positions and token settings stream from the
 * backend, so the wallet card, the staking panel and the TON withdrawal fee
 * (15% while >= 100k MYTH is staked) update without a reload.
 */
export const useMythRealtime=(enabled:boolean)=>{
  const client=useQueryClient();
  useEffect(()=>{
    if(!enabled)return;
    const refresh=()=>{
      void client.invalidateQueries({queryKey:['myth-wallet']});
      void client.invalidateQueries({queryKey:['myth-staking']});
      void client.invalidateQueries({queryKey:['myth-sale']});
      void client.invalidateQueries({queryKey:['ton-wallet']});
      void client.invalidateQueries({queryKey:['wallet-summary']});
    };
    const channel=supabase.channel('myth-live')
      .on('postgres_changes',{event:'*',schema:'public',table:'myth_balances'},refresh)
      .on('postgres_changes',{event:'*',schema:'public',table:'myth_staking_positions'},refresh)
      .on('postgres_changes',{event:'*',schema:'public',table:'myth_token_settings'},refresh)
      .subscribe();
    return()=>{void supabase.removeChannel(channel)};
  },[enabled,client]);
};



export const usePlayerHeroes=(telegramInitData:string|null,enabled:boolean)=>useQuery<{heroes:PvpHero[]}>({queryKey:['player-heroes',telegramInitData],queryFn:()=>fetchPlayerHeroes(telegramInitData??''),enabled,staleTime:20_000,refetchOnWindowFocus:true,retry:1});

export const useRewardHistory=(telegramInitData:string|null,enabled:boolean,limit=5)=>useQuery<RewardHistory>({queryKey:['reward-history',telegramInitData,limit],queryFn:()=>fetchRewardHistory(telegramInitData??'',limit),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});

/** Official channel rewards for the signed-in player only (server-scoped by Telegram identity). */
export const useChannelRewards=(telegramInitData:string|null,enabled:boolean)=>useQuery<ChannelRewards>({queryKey:['channel-rewards',telegramInitData],queryFn:()=>channelsRequest(telegramInitData??'',{action:'dashboard'}),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});

/** Daily quests: server is the only source of progress, so refetch on focus. */
export const useDailyQuests=(telegramInitData:string|null,enabled:boolean)=>useQuery<DailyQuestsDashboard>({queryKey:['daily-quests',telegramInitData],queryFn:()=>fetchDailyQuests(telegramInitData??''),enabled,staleTime:10_000,refetchOnWindowFocus:true,retry:1});

/** Hero ascension state (stars, duplicates, costs) — server is the only source of truth. */
export const useHeroFusion=(telegramInitData:string|null,enabled:boolean)=>useQuery<FusionDashboard>({queryKey:['hero-fusion',telegramInitData],queryFn:()=>fetchHeroFusion(telegramInitData??''),enabled,staleTime:10_000,refetchOnWindowFocus:true,retry:3,retryDelay:800});

/** Rarity fusion state (config, odds, eligible heroes) — the server owns every rule. */
export const useRarityFusion=(telegramInitData:string|null,enabled:boolean)=>useQuery<RarityFusionDashboard>({queryKey:['rarity-fusion',telegramInitData],queryFn:()=>fetchRarityFusion(telegramInitData??''),enabled,staleTime:10_000,refetchOnWindowFocus:true,retry:1});

/** Clan dashboard: membership, members, missions, clan boss and ranking (server-owned). */
/**
 * Clan boss state. Never shares a query key or a channel with the global boss,
 * so both bosses can be open in the same session without cross-invalidation.
 */
export const useClanBoss=(telegramInitData:string|null,enabled:boolean)=>useQuery<ClanBossState>({
  queryKey:['clan-boss',telegramInitData],
  queryFn:()=>fetchClanBoss(telegramInitData??''),
  enabled,staleTime:5_000,refetchInterval:enabled?20_000:false,refetchOnWindowFocus:true,retry:1
});

/** Realtime HP + internal ranking, filtered to this clan's own instance only. */
export const useClanBossRealtime=(instanceId:string|null|undefined,clanId:string|null|undefined,enabled:boolean)=>{
  const queryClient=useQueryClient();
  useEffect(()=>{
    if(!enabled||!clanId)return;
    let timer:number|undefined;
    const refresh=()=>{
      window.clearTimeout(timer);
      timer=window.setTimeout(()=>{void queryClient.invalidateQueries({queryKey:['clan-boss']})},250);
    };
    const channel=supabase.channel(`clan-boss-${clanId}`)
      .on('postgres_changes',{event:'*',schema:'public',table:'clan_boss_instances',filter:`clan_id=eq.${clanId}`},refresh)
      .on('postgres_changes',{event:'*',schema:'public',table:'clan_boss_damage',
        ...(instanceId?{filter:`instance_id=eq.${instanceId}`}:{filter:`clan_id=eq.${clanId}`})},refresh)
      .subscribe();
    return()=>{window.clearTimeout(timer);void supabase.removeChannel(channel)};
  },[instanceId,clanId,enabled,queryClient]);
};

export const useClanDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<ClanDashboard>({queryKey:['clan-dashboard',telegramInitData],queryFn:()=>fetchClanDashboard(telegramInitData??''),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});

/** Clan War dashboard. Polls while a war is live so scores, sectors and the feed stay fresh. */
export const useClanWarDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<ClanWarDashboard>({queryKey:['clan-war',telegramInitData],queryFn:()=>fetchClanWarDashboard(telegramInitData??''),enabled,staleTime:10_000,refetchInterval:(query)=>{const status=query.state.data?.war?.status;return status==='battle'||status==='preparation'||status==='searching'?15_000:false},refetchOnWindowFocus:true,retry:1});


/**
 * Live global boss. Any change the admin makes to the ACTIVE cycle (reward pool, HP, ends_at,
 * boss swap, status) and any damage from any player arrives through Supabase Realtime and
 * refreshes the boss + ranking caches in place — no reload, no modal reopen.
 * The cycle table is watched without a filter on purpose, so a brand new active cycle
 * (#2 → #3) is detected while the player keeps the screen open.
 */
export const useGlobalBossRealtime=(cycleId:string|null|undefined,enabled:boolean)=>{
  const queryClient=useQueryClient();
  useEffect(()=>{
    if(!enabled)return;
    let timer:number|undefined;
    const refresh=()=>{
      window.clearTimeout(timer);
      timer=window.setTimeout(()=>{
        void queryClient.invalidateQueries({queryKey:['boss-combat']});
        void queryClient.invalidateQueries({queryKey:['global-boss-ranking']});
      },250);
    };
    const channel=supabase.channel(`global-boss-${cycleId??'pending'}`)
      .on('postgres_changes',{event:'*',schema:'public',table:'global_boss_cycles'},refresh)
      .on('postgres_changes',{event:'*',schema:'public',table:'global_boss_participants',
        ...(cycleId?{filter:`boss_cycle_id=eq.${cycleId}`}:{})},refresh)
      .subscribe();
    return()=>{window.clearTimeout(timer);void supabase.removeChannel(channel)};
  },[cycleId,enabled,queryClient]);
};


/**
 * Marketplace maintenance status. Short polling keeps players in sync when an admin
 * flips the switch while the Mini App is open (no reload required).
 */
export const useMarketStatus=(telegramInitData:string|null,enabled:boolean)=>useQuery<MarketStatus>({
  queryKey:['market-status',telegramInitData],queryFn:()=>fetchMarketStatus(telegramInitData??''),
  enabled,staleTime:5_000,refetchInterval:enabled?15_000:false,refetchOnWindowFocus:true,retry:1
});

/** Player market listings (FC or TON). Filters/sort/currency are applied server-side. */
export const useMarketBrowse=(telegramInitData:string|null,enabled:boolean,itemType:MarketItemType|'all',rarity:string,sort:MarketSort,currency:MarketCurrency|'all'='all')=>useQuery<MarketBrowse>({
  queryKey:['market-browse',telegramInitData,itemType,rarity,sort,currency],
  queryFn:()=>fetchMarketBrowse(telegramInitData??'',itemType,rarity,sort,currency),
  enabled,staleTime:5_000,refetchOnWindowFocus:true,retry:1
});


/** Items the player may list right now — the server decides eligibility. */
export const useMarketSellable=(telegramInitData:string|null,enabled:boolean)=>useQuery<MarketSellable>({
  queryKey:['market-sellable',telegramInitData],queryFn:()=>fetchMarketSellable(telegramInitData??''),
  enabled,staleTime:5_000,retry:1
});

/**
 * Live price quote for the item being listed. The band (min/max/recommended) is
 * computed server-side from the median of recent settled sales — the client only shows it.
 */
export const useMarketQuote=(telegramInitData:string|null,enabled:boolean,input:{itemType:MarketItemType;itemInstanceId?:string;itemCode?:string})=>useQuery<MarketQuote>({
  queryKey:['market-quote',telegramInitData,input.itemType,input.itemInstanceId??input.itemCode??''],
  queryFn:()=>fetchMarketQuote(telegramInitData??'',input),
  enabled,staleTime:15_000,retry:1
});

/**
 * Full attribute preview for one listing / auction lot. Read-only: the data comes
 * straight from the backend instance (no client-side recomputation).
 */
export const useMarketItemDetails=(telegramInitData:string|null,source:'market'|'auction',id:string|null)=>useQuery<MarketItemDetailsResult>({
  queryKey:['market-item-details',telegramInitData,source,id],
  queryFn:()=>fetchMarketItemDetails(telegramInitData??'',source,id??''),
  enabled:Boolean(telegramInitData&&id),staleTime:15_000,retry:1
});

export const useMarketMine=(telegramInitData:string|null,enabled:boolean)=>useQuery<MarketMine>({
  queryKey:['market-mine',telegramInitData],queryFn:()=>fetchMarketMine(telegramInitData??''),
  enabled,staleTime:5_000,refetchOnWindowFocus:true,retry:1
});

/**
 * Live market. Any listing created, sold or cancelled by any player refreshes the
 * browse/my-listings caches (and balances/inventories) in place — no reload needed.
 */
export const useMarketRealtime=(enabled:boolean)=>{
  const queryClient=useQueryClient();
  useEffect(()=>{
    if(!enabled)return;
    let timer:number|undefined;
    const refresh=()=>{
      window.clearTimeout(timer);
      timer=window.setTimeout(()=>{
        void queryClient.invalidateQueries({queryKey:['market-browse']});
        void queryClient.invalidateQueries({queryKey:['market-mine']});
        void queryClient.invalidateQueries({queryKey:['market-sellable']});
        void queryClient.invalidateQueries({queryKey:['game-state']});
        void queryClient.invalidateQueries({queryKey:['player-heroes']});
        void queryClient.invalidateQueries({queryKey:['pet-dashboard']});
        void queryClient.invalidateQueries({queryKey:['player-inventory']});
      },250);
    };
    const channel=supabase.channel('market-listings')
      .on('postgres_changes',{event:'*',schema:'public',table:'market_listings'},refresh)
      .subscribe();
    return()=>{window.clearTimeout(timer);void supabase.removeChannel(channel)};
  },[enabled,queryClient]);
};

/** Tower of Eternity: individual progress, always resolved server-side. */
export const useTowerDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<TowerDashboardType>({
  queryKey:['tower-dashboard',telegramInitData],
  queryFn:()=>fetchTowerDashboard(telegramInitData??''),
  enabled:enabled&&Boolean(telegramInitData),staleTime:15_000,refetchOnWindowFocus:true,retry:1,
});

/** Tower ranking; only polled while the ranking sheet is open (same pattern as the Global Boss). */
export const useTowerRanking=(telegramInitData:string|null,enabled:boolean,limit=50)=>useQuery<TowerRanking>({
  queryKey:['tower-ranking',telegramInitData,limit],
  queryFn:()=>fetchTowerRanking(telegramInitData??'',limit),
  enabled:enabled&&Boolean(telegramInitData),refetchInterval:enabled?15_000:false,staleTime:10_000,retry:1,
});

/**
 * Hero TON mining state. The server owns the accrual; a moderate refetch keeps
 * the panel in sync while the player is on the Heroes screen.
 */
export const useHeroMining=(telegramInitData:string|null,enabled:boolean)=>useQuery<HeroMiningState>({
  queryKey:['hero-mining',telegramInitData],
  queryFn:()=>fetchHeroMining(telegramInitData??''),
  enabled:enabled&&Boolean(telegramInitData),staleTime:10_000,refetchInterval:enabled?30_000:false,refetchOnWindowFocus:true,retry:1,
});

/** POOL MARKETING: read-only; a 30s refetch keeps admin-bot edits live without a reload. */
export const useMarketingPool=(telegramInitData:string|null,enabled:boolean,limit=50)=>useQuery<MarketingPoolDashboard>({queryKey:['marketing-pool',telegramInitData,limit],queryFn:()=>marketingPoolRequest(telegramInitData??'',limit),enabled,staleTime:10_000,refetchInterval:enabled?30_000:false,refetchOnMount:'always',refetchOnWindowFocus:true,retry:1});

/**
 * MYTH TOKEN SALE dashboard. The aggregated public stats table is broadcast over Realtime, so the
 * SOLD/BURNED/AVAILABLE cards move for everyone the moment a purchase or a burn is confirmed —
 * without exposing who bought what (the public table carries aggregates only).
 */
export const useMythSale=(telegramInitData:string|null,enabled:boolean)=>{
  const client=useQueryClient();
  const query=useQuery<MythSaleDashboard>({queryKey:['myth-sale',telegramInitData],queryFn:()=>fetchMythSale(telegramInitData??''),enabled,staleTime:10_000,refetchInterval:enabled?30_000:false,refetchOnMount:'always',refetchOnWindowFocus:true,retry:1});
  useEffect(()=>{
    if(!enabled)return;
    // Unique channel name per mount: two components may read this hook at the same time
    // (sale panel + milestone ladder) and a duplicated channel name breaks the subscription.
    const channel=supabase.channel(`myth-sale-stats-${Math.random().toString(36).slice(2)}`).on('postgres_changes',{event:'*',schema:'public',table:'myth_sale_public_stats'},()=>{void client.invalidateQueries({queryKey:['myth-sale']})}).subscribe();
    return ()=>{void supabase.removeChannel(channel)};
  },[enabled,client]);
  return query;
};
