import { useEffect } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { realtimeSupabase as supabase } from './realtimeClient';

import type { ChannelRewards, RewardHistory } from './services';
import { fetchGlobalBossRanking, fetchRarityFusion, fetchHeroFusion, channelsRequest, fetchDailyQuests, fetchRewardHistory, fetchPlayerHeroes, fetchPlayerInventory, bossRequest, calendarRequest, communityPoolRequest, fetchGameState, fetchReferralDashboard, fetchTelegramProfile, petRequest, pvpRequest, seasonPassRequest, walletRequest, fetchMarketBrowse, fetchMarketMine, fetchMarketSellable, fetchMarketStatus } from './services';
import type { MarketBrowse, MarketItemType, MarketMine, MarketSellable, MarketSort, MarketStatus } from './market';

import type { GameState } from './types';
import type { BossCombat, GlobalBossRanking } from './combat';
import type { ReferralDashboard } from './referrals';
import type { PetDashboard } from './pets';
import type { PvpDashboard, PvpHero } from './pvp';
import type { TonWallet, WalletSummary } from './wallet';
import type { TelegramPlayerProfile } from './playerProfile';
import type { CalendarDashboard, PlayerInventory } from './calendarRewards';
import type{SeasonPassDashboard}from'./seasonPass';
import type{CommunityPoolDashboard}from'./communityPool';
import type{DailyQuestsDashboard}from'./quests';
import type{FusionDashboard,RarityFusionDashboard}from'./heroFusion';
import{fetchClanDashboard,type ClanDashboard}from'./clans';
import{fetchClanBoss,type ClanBossState}from'./clanBoss';
import type{SpecialEventsDashboard}from'./specialEvents';
import{specialEventsRequest,spendingEventRequest}from'./services';
import type{SpendingEventDashboard}from'./spendingEvent';

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
export const useReferralDashboard=(telegramInitData:string|null,enabled:boolean,level?:1|2|3,offset=0)=>useQuery<ReferralDashboard>({queryKey:['referral-dashboard',telegramInitData,level??'all',offset],queryFn:()=>fetchReferralDashboard(telegramInitData??'',level,offset),enabled,staleTime:60_000,refetchInterval:120_000,refetchOnWindowFocus:true,retry:1});
export const usePetDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<PetDashboard>({queryKey:['pet-dashboard',telegramInitData],queryFn:async()=>petRequest(telegramInitData??'',{action:'dashboard'}) as Promise<PetDashboard>,enabled,staleTime:20_000,refetchOnWindowFocus:true,retry:1});
export const usePvpDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<PvpDashboard>({queryKey:['pvp-dashboard',telegramInitData],queryFn:()=>pvpRequest<PvpDashboard>(telegramInitData??'',{action:'dashboard'}),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});
export const useWalletSummary=(telegramInitData:string|null,enabled:boolean)=>useQuery<WalletSummary>({queryKey:['wallet-summary',telegramInitData],queryFn:()=>walletRequest<WalletSummary>(telegramInitData??'',{action:'summary'}),enabled,staleTime:30_000,refetchInterval:60_000,refetchOnWindowFocus:true,retry:1});
/** Withdrawable TON balance (rewards only). Shared key so any credit refreshes header + wallet. */
export const useTonWallet=(telegramInitData:string|null,enabled:boolean)=>useQuery<TonWallet>({queryKey:['ton-wallet',telegramInitData],queryFn:()=>walletRequest<TonWallet>(telegramInitData??'',{action:'ton-wallet'}),enabled,staleTime:30_000,refetchInterval:60_000,refetchOnWindowFocus:true,retry:1});
export const useTelegramProfile=(telegramInitData:string|null,enabled:boolean)=>useQuery<TelegramPlayerProfile>({queryKey:['telegram-profile',telegramInitData],queryFn:()=>fetchTelegramProfile(telegramInitData??''),enabled,staleTime:60_000,refetchOnWindowFocus:true,retry:1});
/** Stored chests and eggs; shares the ['player-inventory'] key so any grant refreshes it. */
export const usePlayerInventory=(telegramInitData:string|null,enabled:boolean)=>useQuery<PlayerInventory>({queryKey:['player-inventory',telegramInitData],queryFn:()=>fetchPlayerInventory(telegramInitData??''),enabled,staleTime:10_000});
export const useCalendarDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<CalendarDashboard>({queryKey:['calendar-dashboard',telegramInitData],queryFn:()=>calendarRequest(telegramInitData??''),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});
export const useSeasonPass=(telegramInitData:string|null,enabled:boolean)=>useQuery<SeasonPassDashboard>({queryKey:['season-pass',telegramInitData],queryFn:()=>seasonPassRequest(telegramInitData??''),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});
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
      .subscribe();
    return()=>{void supabase.removeChannel(channel)};
  },[enabled,client]);
  return query;
};

export const usePlayerHeroes=(telegramInitData:string|null,enabled:boolean)=>useQuery<{heroes:PvpHero[]}>({queryKey:['player-heroes',telegramInitData],queryFn:()=>fetchPlayerHeroes(telegramInitData??''),enabled,staleTime:20_000,refetchOnWindowFocus:true,retry:1});

export const useRewardHistory=(telegramInitData:string|null,enabled:boolean,limit=5)=>useQuery<RewardHistory>({queryKey:['reward-history',telegramInitData,limit],queryFn:()=>fetchRewardHistory(telegramInitData??'',limit),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});

/** Official channel rewards for the signed-in player only (server-scoped by Telegram identity). */
export const useChannelRewards=(telegramInitData:string|null,enabled:boolean)=>useQuery<ChannelRewards>({queryKey:['channel-rewards',telegramInitData],queryFn:()=>channelsRequest(telegramInitData??'',{action:'dashboard'}),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});

/** Daily quests: server is the only source of progress, so refetch on focus. */
export const useDailyQuests=(telegramInitData:string|null,enabled:boolean)=>useQuery<DailyQuestsDashboard>({queryKey:['daily-quests',telegramInitData],queryFn:()=>fetchDailyQuests(telegramInitData??''),enabled,staleTime:10_000,refetchOnWindowFocus:true,retry:1});

/** Hero ascension state (stars, duplicates, costs) — server is the only source of truth. */
export const useHeroFusion=(telegramInitData:string|null,enabled:boolean)=>useQuery<FusionDashboard>({queryKey:['hero-fusion',telegramInitData],queryFn:()=>fetchHeroFusion(telegramInitData??''),enabled,staleTime:10_000,refetchOnWindowFocus:true,retry:1});

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

/** Player market listings (FC only). Filters/sort are applied server-side. */
export const useMarketBrowse=(telegramInitData:string|null,enabled:boolean,itemType:MarketItemType|'all',rarity:string,sort:MarketSort)=>useQuery<MarketBrowse>({
  queryKey:['market-browse',telegramInitData,itemType,rarity,sort],
  queryFn:()=>fetchMarketBrowse(telegramInitData??'',itemType,rarity,sort),
  enabled,staleTime:5_000,refetchOnWindowFocus:true,retry:1
});

/** Items the player may list right now — the server decides eligibility. */
export const useMarketSellable=(telegramInitData:string|null,enabled:boolean)=>useQuery<MarketSellable>({
  queryKey:['market-sellable',telegramInitData],queryFn:()=>fetchMarketSellable(telegramInitData??''),
  enabled,staleTime:5_000,retry:1
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
