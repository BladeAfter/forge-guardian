import { useQuery } from '@tanstack/react-query';
import type { ChannelRewards, RewardHistory } from './services';
import { channelsRequest, fetchDailyQuests, fetchRewardHistory, fetchPlayerHeroes, fetchPlayerInventory, bossRequest, calendarRequest, communityPoolRequest, fetchGameState, fetchReferralDashboard, fetchTelegramProfile, petRequest, pvpRequest, seasonPassRequest, walletRequest } from './services';
import type { GameState } from './types';
import type { BossCombat } from './combat';
import type { ReferralDashboard } from './referrals';
import type { PetDashboard } from './pets';
import type { PvpDashboard, PvpHero } from './pvp';
import type { WalletSummary } from './wallet';
import type { TelegramPlayerProfile } from './playerProfile';
import type { CalendarDashboard, PlayerInventory } from './calendarRewards';
import type{SeasonPassDashboard}from'./seasonPass';
import type{CommunityPoolDashboard}from'./communityPool';
import type{DailyQuestsDashboard}from'./quests';

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
  refetchInterval:15_000,refetchOnWindowFocus:true,staleTime:9_000,retry:1
});
export const useReferralDashboard=(telegramInitData:string|null,enabled:boolean,level?:1|2|3,offset=0)=>useQuery<ReferralDashboard>({queryKey:['referral-dashboard',telegramInitData,level??'all',offset],queryFn:()=>fetchReferralDashboard(telegramInitData??'',level,offset),enabled,staleTime:30_000,refetchInterval:60_000,refetchOnWindowFocus:true,retry:1});
export const usePetDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<PetDashboard>({queryKey:['pet-dashboard',telegramInitData],queryFn:async()=>petRequest(telegramInitData??'',{action:'dashboard'}) as Promise<PetDashboard>,enabled,staleTime:20_000,refetchOnWindowFocus:true,retry:1});
export const usePvpDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<PvpDashboard>({queryKey:['pvp-dashboard',telegramInitData],queryFn:()=>pvpRequest<PvpDashboard>(telegramInitData??'',{action:'dashboard'}),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});
export const useWalletSummary=(telegramInitData:string|null,enabled:boolean)=>useQuery<WalletSummary>({queryKey:['wallet-summary',telegramInitData],queryFn:()=>walletRequest<WalletSummary>(telegramInitData??'',{action:'summary'}),enabled,staleTime:10_000,refetchInterval:20_000,refetchOnWindowFocus:true,retry:1});
export const useTelegramProfile=(telegramInitData:string|null,enabled:boolean)=>useQuery<TelegramPlayerProfile>({queryKey:['telegram-profile',telegramInitData],queryFn:()=>fetchTelegramProfile(telegramInitData??''),enabled,staleTime:60_000,refetchOnWindowFocus:true,retry:1});
/** Stored chests and eggs; shares the ['player-inventory'] key so any grant refreshes it. */
export const usePlayerInventory=(telegramInitData:string|null,enabled:boolean)=>useQuery<PlayerInventory>({queryKey:['player-inventory',telegramInitData],queryFn:()=>fetchPlayerInventory(telegramInitData??''),enabled,staleTime:10_000});
export const useCalendarDashboard=(telegramInitData:string|null,enabled:boolean)=>useQuery<CalendarDashboard>({queryKey:['calendar-dashboard',telegramInitData],queryFn:()=>calendarRequest(telegramInitData??''),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});
export const useSeasonPass=(telegramInitData:string|null,enabled:boolean)=>useQuery<SeasonPassDashboard>({queryKey:['season-pass',telegramInitData],queryFn:()=>seasonPassRequest(telegramInitData??''),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});
export const useCommunityPool=(telegramInitData:string|null,enabled:boolean)=>useQuery<CommunityPoolDashboard>({queryKey:['community-pool',telegramInitData],queryFn:()=>communityPoolRequest(telegramInitData??''),enabled,staleTime:15_000,refetchInterval:30_000,refetchOnWindowFocus:true,retry:1});

export const usePlayerHeroes=(telegramInitData:string|null,enabled:boolean)=>useQuery<{heroes:PvpHero[]}>({queryKey:['player-heroes',telegramInitData],queryFn:()=>fetchPlayerHeroes(telegramInitData??''),enabled,staleTime:20_000,refetchOnWindowFocus:true,retry:1});

export const useRewardHistory=(telegramInitData:string|null,enabled:boolean,limit=5)=>useQuery<RewardHistory>({queryKey:['reward-history',telegramInitData,limit],queryFn:()=>fetchRewardHistory(telegramInitData??'',limit),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});

/** Official channel rewards for the signed-in player only (server-scoped by Telegram identity). */
export const useChannelRewards=(telegramInitData:string|null,enabled:boolean)=>useQuery<ChannelRewards>({queryKey:['channel-rewards',telegramInitData],queryFn:()=>channelsRequest(telegramInitData??'',{action:'dashboard'}),enabled,staleTime:15_000,refetchOnWindowFocus:true,retry:1});

/** Daily quests: server is the only source of progress, so refetch on focus. */
export const useDailyQuests=(telegramInitData:string|null,enabled:boolean)=>useQuery<DailyQuestsDashboard>({queryKey:['daily-quests',telegramInitData],queryFn:()=>fetchDailyQuests(telegramInitData??''),enabled,staleTime:10_000,refetchOnWindowFocus:true,retry:1});
