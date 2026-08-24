import { useEffect, useMemo, useRef, useState } from 'react';
import { useTonConnectUI, useTonWallet } from '@tonconnect/ui-react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { hatchedPurchase, reconcilePendingEggPurchases } from './eggPurchase';
import { activatedPass, passTierLabel, reconcilePendingPassPurchases } from './passPurchase';
import { Bell, ChevronRight, Settings, Sparkles, X } from 'lucide-react';
import type { GameState, LanguageStrings, TabKey } from './types';
import { LANGUAGES, formatCurrency, locales } from './utils';
import { useBossCombat, useCalendarDashboard, useDailyQuests, useGameState, usePlayerInventory, usePetDashboard, usePlayerHeroes, useReferralDashboard, useTelegramProfile, useTonWallet as useTonRewardWallet, useWalletSummary } from './hooks';
import { VillagePage } from './pages/VillagePage';
import { ClanHubPage, CommunityPoolPage, DiagnosticsPage, HeroesPage, PetsPage, PvpPage, ReferralPage, SeasonPassPage } from './lazyPages';
import { QuestsPage } from './pages/QuestsPage';
import { BossPage } from './pages/BossPage';
import { WalletPage } from './pages/WalletPage';
import { ProfilePage } from './pages/ProfilePage';
import {ClanHall}from'./components/ClanHall';
import {PartnersModal}from'./components/PartnersModal';
import {RewardsModal}from'./components/RewardsModal';
import {useClanDashboard}from'./hooks';
import {PlayerHeader}from'./components/PlayerHeader';
import {MythreonLoadingScreen}from'./components/MythreonLoadingScreen';
import {HeroShopPanel}from'./components/HeroShopPanel';

import {StarterPackPopup}from'./components/StarterPackPopup';
import {GiveawayPopup}from'./components/GiveawayPopup';
import {PremiumOffersPopups}from'./components/PremiumOffersPopups';
import {PremiumOffersModal}from'./components/PremiumOffersModal';
import { backgrounds, characters, chests, coin, logo, mainScreenArt, navigationIcons } from './gameAssets';
import { isDemoMode, isProduction, TELEGRAM_APP_LINK } from './config';
import { getTelegramStartParam, getTelegramUser, validateTelegramSession, waitForTelegramInitData, type TelegramUser } from './telegram';
import { attackBossOnServer, bindReferral, bossRequest, buildLocalGameState, claimCalendarDay, equipCombatHeroOnServer, fetchHeroShopConfig, markNotificationsRead, openCalendarChest, recruitHeroesOnServer, saveDemoState, campaignPopupRequest, markCampaignPopup, starterPackStatusRequest,claimStarterPackRequest, unequipCombatHeroOnServer } from './services';
import { type LanguageCode } from './i18n';
import { useLanguage } from './LanguageContext';
import { PassXpToasts } from './PassXpToasts';
import { HeroXpToasts } from './HeroXpToasts';
import AccessDeniedScreen from './components/AccessDeniedScreen';
import { checkDeviceAccess, type DeviceAccess, type DeviceIdentity } from './antiFake';
import { HERO_CATALOG, RARITY_COLORS, RARITY_ODDS, type HeroRarity, type ShopHero } from './heroCatalog';
import type {TelegramPlayerProfile} from './playerProfile';
import {CALENDAR_REWARDS,CHEST_LABELS,calendarDayStatus,nextResetCountdown,type CalendarClaimResult,type ChestOpenResult} from './calendarRewards';

import { toFriendlyTonAddress } from './tonAddress';

const tabs: TabKey[] = ['village', 'missions', 'boss', 'wallet', 'profile'];
const PENDING_INVITER_KEY='forge-village-pending-inviter';
type InternalPage='invites'|'pvp'|'pets'|'pool'|'hero-shop'|'market'|'calendar'|'season-pass'|'heroes'|'clan';
const internalPaths:Record<InternalPage,string>={invites:'/invites',pvp:'/pvp',pets:'/pets',pool:'/pool','hero-shop':'/hero-shop',market:'/market',calendar:'/calendar','season-pass':'/season-pass',heroes:'/heroes',clan:'/clan'};
const internalFromPath=():InternalPage|null=>(Object.entries(internalPaths).find(([,path])=>path===window.location.pathname)?.[0] as InternalPage|undefined)??null;

const tabFromPath = (): TabKey => {
  const candidate = window.location.pathname.slice(1) as TabKey;
  return tabs.includes(candidate) ? candidate : 'village';
};

function StatusScreen({ title, message, details }: { title: string; message: string; details?: string[] }) {
  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-forge-black px-6 text-white">
      <img src={backgrounds.loading} alt="" className="absolute inset-0 h-full w-full object-cover" />
      <div className="absolute inset-0 bg-[#07090d]/85" />
      <div className="relative w-full max-w-sm rounded-3xl border border-amber-400/20 bg-forge-black/90 p-7 shadow-card">
        <img src={logo.icon} alt="" className="mx-auto h-20 w-20 object-contain" />
        <h1 className="mt-4 text-center text-xl font-semibold">{title}</h1>
        <p className="mt-3 text-center text-sm leading-6 text-slate-300">{message}</p>
        {details?.length ? <ul className="mt-4 space-y-2 rounded-2xl bg-black/30 p-4 text-sm text-amber-200">{details.map((detail) => <li key={detail}><code>{detail}</code></li>)}</ul> : null}
      </div>
    </div>
  );
}

function OpenInTelegramGate() {
  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-forge-black px-6 text-white">
      <img src={backgrounds.loading} alt="" className="absolute inset-0 h-full w-full object-cover" />
      <div className="absolute inset-0 bg-[#07090d]/90" />
      <main className="relative w-full max-w-sm text-center">
        <img src={logo.icon} alt="MYTHREON" className="mx-auto h-24 w-24 object-contain" />
        <a
          href={TELEGRAM_APP_LINK}
          className="mt-8 block w-full rounded-2xl border border-amber-300/50 bg-gradient-to-b from-amber-400 to-amber-600 px-6 py-4 text-base font-black uppercase tracking-[.12em] text-forge-black shadow-[0_14px_30px_rgba(0,0,0,.6)] transition active:scale-95"
        >
          Abrir no Telegram
        </a>
      </main>
    </div>
  );
}

function HomeFeature({image,label,subtitle,onClick}:{image:string;label:string;subtitle?:string;onClick:()=>void}){
  return <button type="button" onClick={onClick} className="home-feature forge-golden-tile group relative flex h-[112px] w-[108px] shrink-0 flex-col items-center justify-center overflow-hidden rounded-2xl border border-amber-300/35 bg-[#080c13]/90 px-2 shadow-[0_12px_28px_rgba(0,0,0,.58)] backdrop-blur-sm transition active:scale-95"><div className="absolute inset-0 bg-gradient-to-b from-sky-950/10 to-amber-950/20"/><img src={image} alt={label} className="home-feature-image relative h-[68px] w-[68px] object-contain drop-shadow-[0_7px_10px_rgba(0,0,0,.7)] transition group-hover:scale-105"/><span className="home-feature-label relative mt-1 text-center text-[10px] font-black uppercase tracking-[.11em] text-amber-200">{label}</span>{subtitle&&<span className="home-feature-subtitle relative mt-0.5 text-[7px] font-bold uppercase text-emerald-300">{subtitle}</span>}</button>;
}


/** In-memory only: resets on every real app launch (Mini App reopen). */

function App() {
  const [tab, setTab] = useState<TabKey>(tabFromPath);
  // Global language: single source of truth (backend-persisted per player).
  const { language: languageCode, setLanguage, applyRemoteLanguage, t, tError } = useLanguage();
  const [lang, setLang] = useState<LanguageStrings>(locales[languageCode] ?? LANGUAGES.en);
  const [loadingMessage, setLoadingMessage] = useState('Loading game data...');
  const [isReady, setIsReady] = useState(false);
  const [game, setGame] = useState<GameState | null>(null);
  const [telegramInitData, setTelegramInitData] = useState<string | null>(null);
  const eggRecoveryRef = useRef(false);
  const passRecoveryRef = useRef(false);

  const [telegramUser, setTelegramUser] = useState<TelegramUser | null>(null);
  const [activePage,setActivePage]=useState<InternalPage|null>(internalFromPath);
  const [calendarResult,setCalendarResult]=useState<CalendarClaimResult|null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const [telegramStartParam,setTelegramStartParam]=useState<string|null>(null);
  const [shopResults, setShopResults] = useState<ShopHero[]>([]);
  const [bootstrapError, setBootstrapError] = useState<string | null>(null);
  const [outsideTelegram, setOutsideTelegram] = useState(false);
  // ANTI-FAKE: the backend decides; the client only renders the resulting screen.
  const [deviceAccess, setDeviceAccess] = useState<DeviceAccess | null>(null);
  const [deviceIdentity, setDeviceIdentity] = useState<DeviceIdentity | null>(null);
  const deviceCheckedRef = useRef(false);
  const [telegramBooting, setTelegramBooting] = useState(true);
  const [bootStage, setBootStage] = useState(5);
  const [bootFading, setBootFading] = useState(false);
  const [bootDone, setBootDone] = useState(false);
  const [tonConnectUI] = useTonConnectUI();
  const wallet = useTonWallet();
  const queryClient = useQueryClient();
  const clanDashboard=useClanDashboard(telegramInitData,Boolean(telegramInitData)).data;
  const referralBound=useRef(false);
  const lastCommissionNotification=useRef<string|null>(null);

  const totalProduction = useMemo(
    () => game?.buildings.reduce((sum, building) => sum + building.productionPerHour, 0) ?? 0,
    [game?.buildings]
  );

  const storageCapacity = useMemo(
    () => game?.buildings.reduce((sum, building) => sum + building.storage, 0) ?? 0,
    [game?.buildings]
  );

  const canLoadGame = Boolean(telegramInitData);
  const { data, isLoading, error, refetch: refetchGame } = useGameState(telegramInitData, canLoadGame);
  const backendEnabled = Boolean(telegramInitData) && isProduction && !isDemoMode;
  const bossBackendEnabled = backendEnabled && tab === 'boss';
  const { data: bossCombat, isFetching: bossSyncing, refetch: refetchBoss } = useBossCombat(telegramInitData, bossBackendEnabled);
  // Single hero collection source (player_heroes) shared by Coleção, PvP and Boss.
  const heroCollection = usePlayerHeroes(telegramInitData, backendEnabled);
  // Hero shop pricing and summon odds are admin-controlled (game_settings), refreshed on open.
  const {data:heroShopConfig}=useQuery({
    queryKey:['hero-shop-config',telegramInitData],
    enabled:backendEnabled&&Boolean(telegramInitData),
    queryFn:()=>fetchHeroShopConfig(telegramInitData??''),
    staleTime:15_000,
    // Admin can disable a rarity at any time; keep the shop odds close to live.
    refetchInterval:30_000,
  });
  const recruitPrice=(count:number)=>Number(heroShopConfig?.prices?.[String(count)]??25_000*count);
  const summonOdds=useMemo(()=>{
    // Canonical order (common -> mythic). Ancestral is event/admin exclusive and never shown.
    const order:HeroRarity[]=['common','uncommon','rare','epic','legendary','mythic'];
    const odds=heroShopConfig?.odds;
    const base=odds
      ?(Object.entries(odds) as Array<[HeroRarity,number]>).map(([rarity,chance])=>({rarity,chance:Number(chance)}))
      :RARITY_ODDS;
    return base
      // The backend only returns rarities that are enabled in the shop: a disabled
      // rarity simply disappears from SUMMON ODDS (never shown as 0%).
      .filter(entry=>entry.rarity!=='ancestral'&&order.includes(entry.rarity)&&entry.chance>0)
      .sort((a,b)=>order.indexOf(a.rarity)-order.indexOf(b.rarity));
  },[heroShopConfig?.odds]);
  const {data:referralDashboard}=useReferralDashboard(telegramInitData,backendEnabled);
  const {data:petDashboard}=usePetDashboard(telegramInitData,backendEnabled);
  const {data:calendarDashboard,refetch:refetchCalendar}=useCalendarDashboard(telegramInitData,backendEnabled);
  // Ticks only to refresh the countdown label; the boundary itself is server-owned.
  const [nowTick,setNowTick]=useState(()=>Date.now());
  useEffect(()=>{const id=window.setInterval(()=>setNowTick(Date.now()),30_000);return()=>window.clearInterval(id)},[]);

  const dailyQuests=useDailyQuests(telegramInitData,backendEnabled);
  const calendarClaimMutation=useMutation({mutationFn:(day:number)=>claimCalendarDay(telegramInitData??'',day),onSuccess:async result=>{setCalendarResult(result);queryClient.setQueryData(['calendar-dashboard',telegramInitData],result.dashboard);await Promise.all([refetchGame(),refetchCalendar(),queryClient.invalidateQueries({queryKey:['pet-dashboard']}),queryClient.invalidateQueries({queryKey:['player-inventory']}),queryClient.invalidateQueries({queryKey:['boss-combat']})]);toast.success('Recompensa coletada!')},onError:error=>toast.error(error instanceof Error?error.message:'Não foi possível coletar a recompensa.')});
  const [chestResult,setChestResult]=useState<ChestOpenResult|null>(null);
  const openingChestRef=useRef(false);
  const calendarChestMutation=useMutation({mutationFn:(id:string)=>openCalendarChest(telegramInitData??'',id),onSuccess:async result=>{setChestResult(result);setCalendarResult(null);await Promise.all([refetchBoss(),queryClient.invalidateQueries({queryKey:['player-inventory']}),queryClient.invalidateQueries({queryKey:['player-heroes']}),queryClient.invalidateQueries({queryKey:['community-pool']}),queryClient.invalidateQueries({queryKey:['game-state']}),queryClient.invalidateQueries({queryKey:['daily-quests']}),queryClient.invalidateQueries({queryKey:['season-pass']})])},onError:error=>toast.error(error instanceof Error?error.message:'Não foi possível abrir o baú. Tente novamente.'),onSettled:()=>{openingChestRef.current=false}});
  /** One click = one chest: the ref blocks a second request before React re-renders. */
  const openChest=(id:string)=>{if(openingChestRef.current||calendarChestMutation.isPending)return;openingChestRef.current=true;calendarChestMutation.mutate(id)};

  /**
   * SPENDING EVENT: the automatic entry popup was REMOVED on purpose. The event,
   * its ranking, points and rewards stay untouched inside the EVENTS tab.
   * The single automatic popup is now the MYTHREON GIVEAWAY campaign below.
   */
  const [poolInitialTab,setPoolInitialTab]=useState<'weekly'|'events'|'spending'>('weekly');
  const homeQuiet=bootDone&&Boolean(game)&&tab==='village'&&!activePage&&!settingsOpen&&!notificationsOpen&&!calendarResult&&!chestResult&&shopResults.length===0;

  /**
   * MYTHREON GIVEAWAY popup. The backend decides visibility once per
   * (player, campaign_id), so it never reappears after a dismiss/join, on page
   * changes, refreshes or on another device. It never grants rewards.
   */
  const [giveawayClosed,setGiveawayClosed]=useState(false);
  const {data:giveawayCampaign}=useQuery({
    queryKey:['campaign-popup',telegramInitData],
    enabled:backendEnabled&&homeQuiet&&!giveawayClosed,
    queryFn:()=>campaignPopupRequest(telegramInitData??''),
    staleTime:Infinity,gcTime:Infinity,retry:0,refetchOnWindowFocus:false,refetchOnMount:false,
  });
  const showGiveaway=Boolean(homeQuiet&&!giveawayClosed&&giveawayCampaign?.show);
  useEffect(()=>{
    if(!showGiveaway||!giveawayCampaign?.campaignId)return;
    void markCampaignPopup(telegramInitData??'',giveawayCampaign.campaignId,'shown');
  },[showGiveaway,giveawayCampaign?.campaignId,telegramInitData]);

  /**
   * Starter Pack: the backend decides who is eligible (accounts created on/after
   * 2026-08-13, UTC-3) and whether it was already claimed. Delivery is atomic and
   * idempotent server-side, so retries can never duplicate rewards.
   */
  const {data:starterPackStatus,refetch:refetchStarterPack}=useQuery({
    queryKey:['starter-pack',telegramInitData],
    enabled:backendEnabled&&homeQuiet,
    queryFn:()=>starterPackStatusRequest(telegramInitData??''),
    staleTime:Infinity,gcTime:Infinity,retry:0,refetchOnWindowFocus:false,refetchOnMount:false,
  });
  const [starterPackClosed,setStarterPackClosed]=useState(false);
  const showStarterPack=Boolean(homeQuiet&&!starterPackClosed&&starterPackStatus?.show&&!starterPackStatus?.claimed);

  const {data:officialProfile,isLoading:profileLoading,error:profileError,refetch:refetchProfile}=useTelegramProfile(telegramInitData,backendEnabled);
  const playerProfile:TelegramPlayerProfile|null=officialProfile??(telegramUser?{telegramId:String(telegramUser.id),firstName:telegramUser.first_name,lastName:telegramUser.last_name??null,username:telegramUser.username??null,photoUrl:telegramUser.photo_url??null}:null);
  useEffect(()=>{if(profileError)console.error('[telegram-profile] Falha ao carregar perfil',profileError)},[profileError]);
  // The backend profile is the persistent source for the player's language.
  useEffect(()=>{
    const remote=officialProfile as unknown as {language?:string|null;languageLocked?:boolean;language_locked?:boolean}|null|undefined;
    if(!remote?.language)return;
    applyRemoteLanguage(remote.language,Boolean(remote.languageLocked??remote.language_locked));
  },[officialProfile,applyRemoteLanguage]);
  const equipHeroMutation=useMutation({
    mutationFn:async({heroId,slot}:{heroId:string;slot:1|2|3|4|5})=>{
      if(!backendEnabled||!telegramInitData)throw new Error(t('backendRequired'));
      return equipCombatHeroOnServer(telegramInitData,heroId,slot);
    },
    onSuccess:async(result)=>{
      queryClient.setQueryData(['boss-combat',telegramInitData],result);
      await Promise.all([
        queryClient.invalidateQueries({queryKey:['boss-combat',telegramInitData]}),
        queryClient.invalidateQueries({queryKey:['game-state',telegramInitData]})
      ]);
      toast.success(t('heroEquipped'));
    },
    onError:(mutationError)=>toast.error(mutationError instanceof Error?mutationError.message:t('equipFailed'))
  });
  // Removing a hero from a Boss slot is also independent from an active boss.
  const unequipHeroMutation=useMutation({
    mutationFn:async(slot:1|2|3|4|5)=>{
      if(!backendEnabled||!telegramInitData)throw new Error(t('backendRequired'));
      return unequipCombatHeroOnServer(telegramInitData,slot);
    },
    onSuccess:async(result)=>{
      queryClient.setQueryData(['boss-combat',telegramInitData],result);
      await queryClient.invalidateQueries({queryKey:['boss-combat',telegramInitData]});
      toast.success('Herói removido do slot.');
    },
    onError:(mutationError)=>toast.error(mutationError instanceof Error?mutationError.message:'Não foi possível remover o herói.')
  });
  // Only the attack action requires an active boss (backend raises BOSS_NOT_ACTIVE).
  const attackBossMutation=useMutation({
    mutationFn:async()=>{
      if(!backendEnabled||!telegramInitData)throw new Error(t('backendRequired'));
      return attackBossOnServer(telegramInitData);
    },
    onSuccess:async(result)=>{
      queryClient.setQueryData(['boss-combat',telegramInitData],result);
      await Promise.all([
        queryClient.invalidateQueries({queryKey:['boss-combat',telegramInitData]}),
        queryClient.invalidateQueries({queryKey:['daily-quests']}),queryClient.invalidateQueries({queryKey:['season-pass']})
      ]);
    },
    onError:(mutationError)=>toast.error(mutationError instanceof Error?mutationError.message:'Não foi possível atacar o chefe.')
  });

  // Keeps the legacy `lang` strings in sync with the global language.
  useEffect(() => {
    setLang(locales[languageCode] ?? LANGUAGES.en);
    setLoadingMessage(locales[languageCode]?.loading ?? LANGUAGES.en.loading);
  }, [languageCode]);

  useEffect(() => {
    const onPopState = () => {setTab(tabFromPath());setActivePage(internalFromPath())};
    window.addEventListener('popstate', onPopState);
    return () => window.removeEventListener('popstate', onPopState);
  }, []);

  // Lets nested panels jump to a main tab (e.g. Tower -> Wallet for a TON deposit).
  useEffect(() => {
    const onNavigate = (event: Event) => {
      const target = String((event as CustomEvent<string>).detail ?? '') as TabKey;
      if (!tabs.includes(target)) return;
      setActivePage(null);
      setTab(target);
    };
    window.addEventListener('mythreon:navigate', onNavigate);
    return () => window.removeEventListener('mythreon:navigate', onNavigate);
  }, []);

  useEffect(() => {
    window.scrollTo(0, 0);
  }, []);



  // Premium egg purchases paid earlier (even with the app closed) are finished here — a single
  // reconciliation per session, always idempotent: one payment can only ever deliver one pet.
  useEffect(() => {
    if (!backendEnabled || !telegramInitData || eggRecoveryRef.current) return;
    eggRecoveryRef.current = true;
    reconcilePendingEggPurchases(telegramInitData)
      .then(async (verification) => {
        const delivered = hatchedPurchase(verification);
        if (!delivered?.result) return;
        await Promise.all([
          queryClient.invalidateQueries({ queryKey: ['pet-dashboard'] }),
          queryClient.invalidateQueries({ queryKey: ['wallet-summary'] }),
          queryClient.invalidateQueries({ queryKey: ['wallet-history'] }),
        ]);
        toast.success(`Compra concluída: ${delivered.result.name} entregue!`);
      })
      .catch(() => undefined);
  }, [backendEnabled, telegramInitData, queryClient]);

  // Battle pass payments made with the app closed are activated here, exactly once per session.
  useEffect(() => {
    if (!backendEnabled || !telegramInitData || passRecoveryRef.current) return;
    passRecoveryRef.current = true;
    reconcilePendingPassPurchases(telegramInitData)
      .then(async (verification) => {
        const activated = activatedPass(verification);
        if (!activated) return;
        await Promise.all([
          queryClient.invalidateQueries({ queryKey: ['season-pass'] }),
          queryClient.invalidateQueries({ queryKey: ['season-pass-profile'] }),
          queryClient.invalidateQueries({ queryKey: ['community-pool'] }),
          queryClient.invalidateQueries({ queryKey: ['wallet-history'] }),
        ]);
        toast.success(`${passTierLabel(activated.tier)} ATIVO!`);
      })
      .catch(() => undefined);
  }, [backendEnabled, telegramInitData, queryClient]);



  useEffect(() => {
    let cancelled = false;
    // Telegram can deliver initData a few frames after mount; wait for it before any auth call.
    (async () => {
      if (window.Telegram?.WebApp) setBootStage(10);
      const webApp = await waitForTelegramInitData();
      if (cancelled) return;
      setBootStage((current) => Math.max(current, 20));
      const initData = webApp?.initData ?? '';
      setTelegramUser(getTelegramUser(webApp));
      setTelegramStartParam(getTelegramStartParam(webApp));
      console.log('[TELEGRAM AUTH]', {
        hasTelegram: Boolean(window.Telegram?.WebApp),
        hasInitData: Boolean(initData),
        initDataLength: initData.length,
        userId: webApp?.initDataUnsafe?.user?.id ?? null,
      });
      if (!isProduction || isDemoMode) {
        setBootStage(50);
        setTelegramInitData(initData || 'development-browser-session');
        setTelegramBooting(false);
        return;
      }
      if (!initData) {
        setOutsideTelegram(true);
        setTelegramBooting(false);
        return;
      }
      // Fast boot: the signed initData goes straight to the data layer. Every backend
      // endpoint (RPC + edge function) validates it again server-side, so waiting for a
      // dedicated /auth round-trip here only added a cold-start round-trip to the splash.
      setBootStage((current) => Math.max(current, 50));
      setTelegramInitData(initData);
      setBootstrapError(null);
      setTelegramBooting(false);
      // Background sanity check: only a real signature/expiry rejection shows the auth error.
      void validateTelegramSession(initData).catch((validationError: unknown) => {
        if (cancelled) return;
        const reason = (validationError as { reason?: string } | null)?.reason ?? '';
        const message = validationError instanceof Error ? validationError.message : 'Falha na autenticação do Telegram.';
        console.error('[TELEGRAM AUTH] background validation failed', { reason, message });
        if (reason === 'invalid_hash' || reason === 'expired' || reason === 'init_data_missing') setBootstrapError(message);
      });

    })();
    return () => { cancelled = true; };
  }, []);

  // ANTI-FAKE / ANTI-MULTIACCOUNT: single fast RPC at boot. Up to 3 distinct Telegram
  // accounts per device are allowed; the 4th+ gets a server-side block (never a ban).
  useEffect(() => {
    if (!telegramInitData || deviceCheckedRef.current) return;
    deviceCheckedRef.current = true;
    let cancelled = false;
    checkDeviceAccess(telegramInitData).then(({ result, identity }) => {
      if (cancelled) return;
      setDeviceIdentity(identity);
      setDeviceAccess(result);
      if (result.access === 'blocked') console.error('[ANTI FAKE] access blocked', { code: result.code });
    });
    return () => { cancelled = true; };
  }, [telegramInitData]);

  // Real boot progress: each resolved dependency advances the single Mythreon loading screen.
  const playerProfileReady = Boolean(playerProfile);
  const heroesReady = !backendEnabled || Boolean(heroCollection.data) || Boolean(heroCollection.error);
  useEffect(() => {
    if (telegramInitData) { console.info('[BOOT] Telegram initialized + auth validated'); setBootStage((current) => Math.max(current, 50)); }
    if (playerProfileReady) { console.info('[BOOT] Player profile loaded'); setBootStage((current) => Math.max(current, 65)); }
    if (game) { console.info('[BOOT] Game state ready'); setBootStage((current) => Math.max(current, 80)); }
    if (heroesReady) { console.info('[BOOT] Hero collection settled'); setBootStage((current) => Math.max(current, 95)); }
  }, [telegramInitData, playerProfileReady, game, heroesReady]);

  // Only identity + game state are critical. Heroes, pets, pool, pass and events are
  // secondary systems: each screen shows its own loading/error state instead of
  // blocking the whole Mini App behind the splash.
  const appReady = !telegramBooting && Boolean(telegramInitData) && isReady && Boolean(game);
  const bootProgress = appReady ? 100 : Math.min(bootStage, 95);
  useEffect(() => {
    if (!appReady || bootDone) return;
    console.info('[BOOT] App ready');
    const fadeTimer = setTimeout(() => setBootFading(true), 120);
    const doneTimer = setTimeout(() => setBootDone(true), 480);
    return () => { clearTimeout(fadeTimer); clearTimeout(doneTimer); };
  }, [appReady, bootDone]);





  // The inviter id survives reloads: Telegram only delivers start_param on the first launch.
  useEffect(()=>{
    const inviter=Number(telegramStartParam);
    if(Number.isSafeInteger(inviter)&&inviter>0)localStorage.setItem(PENDING_INVITER_KEY,String(inviter));
  },[telegramStartParam]);

  useEffect(()=>{
    if(!backendEnabled||!telegramInitData||referralBound.current)return;
    const stored=Number(localStorage.getItem(PENDING_INVITER_KEY)??telegramStartParam??'');
    if(!Number.isSafeInteger(stored)||stored<=0)return;
    referralBound.current=true;
    bindReferral(telegramInitData,stored)
      .then(()=>{localStorage.removeItem(PENDING_INVITER_KEY);queryClient.invalidateQueries({queryKey:['referral-dashboard']})})
      .catch(error=>{
        const message=error instanceof Error?error.message:String(error);
        // Permanent outcomes clear the pending inviter; transient failures retry on the next launch.
        if(/SELF_REFERRAL_BLOCKED|SPONSOR_IMMUTABLE|REFERRAL_CYCLE_BLOCKED|Indicador inválido/.test(message))localStorage.removeItem(PENDING_INVITER_KEY);
        else referralBound.current=false;
        console.error('[REFERRAL BIND]',message);
      });
  },[backendEnabled,telegramInitData,telegramStartParam,queryClient]);

  // FC have a single source of truth: the server balance (game_players.forge_coins).
  const {data:serverWallet}=useWalletSummary(telegramInitData,backendEnabled);
  // Withdrawable TON lives on its own ledger (rewards only) and is shown beside FC.
  const {data:tonRewardWallet}=useTonRewardWallet(telegramInitData,backendEnabled);
  // A falha temporária de uma request NUNCA deve mostrar 0: mantemos o último valor conhecido do servidor.
  const lastTon=useRef(0);
  if(Number.isFinite(tonRewardWallet?.availableTon))lastTon.current=Number(tonRewardWallet?.availableTon);
  const tonBalance=Number.isFinite(tonRewardWallet?.availableTon)?Number(tonRewardWallet?.availableTon):lastTon.current;
  const serverBalance=typeof serverWallet?.balanceFc==='number'&&Number.isFinite(serverWallet.balanceFc)?serverWallet.balanceFc:null;
  // Header, shop, pets and every other screen read this value — never a local or default amount.
  const fcBalance=backendEnabled?(serverBalance??game?.balance??0):(game?.balance??0);
  useEffect(()=>{
    if(serverBalance===null)return;
    setGame(current=>current&&current.balance!==serverBalance?{...current,balance:serverBalance}:current);
  },[serverBalance]);

  // Notifications are silently marked as read ON THE SERVER: commissions are TON-only now
  // and must NEVER pop a toast/modal when the player opens the Mini App.
  useEffect(()=>{
    const unread=referralDashboard?.notifications??[];
    if(!unread.length||!telegramInitData)return;
    lastCommissionNotification.current=unread[0].id;
    markNotificationsRead(telegramInitData,unread.map(item=>item.id))
      .then(()=>queryClient.invalidateQueries({queryKey:['referral-dashboard']}))
      .catch((error:unknown)=>console.error('[NOTIFICATIONS]',error instanceof Error?error.message:error));
  },[referralDashboard?.notifications,telegramInitData,queryClient]);


  useEffect(() => {
    if (data) {
      setGame(data as GameState);
      setIsReady(true);
    }
  }, [data]);

  // Boot watchdog: the loading screen never stays stuck — after 12s the local village state opens the game.
  useEffect(() => {
    if (!telegramInitData || game) return;
    const timer = window.setTimeout(() => {
      console.error('[BOOT] game state unavailable, opening with local village state', {
        hasError: Boolean(error), isLoading
      });
      setGame(buildLocalGameState(telegramInitData));
      setIsReady(true);
    }, 7_000);
    return () => window.clearTimeout(timer);
  }, [telegramInitData, game, error, isLoading]);


  useEffect(() => {
    if (!game || !isDemoMode || !telegramInitData) return;
    saveDemoState(game, telegramInitData);
  }, [game, telegramInitData]);

  useEffect(() => {
    if (!isReady || !totalProduction || !storageCapacity) return;
    const timer = window.setInterval(() => {
      setGame((current) => current ? {
        ...current,
        offlineProduction: Math.min(storageCapacity, current.offlineProduction + totalProduction / 3600)
      } : current);
    }, 1000);
    return () => window.clearInterval(timer);
  }, [isReady, storageCapacity, totalProduction]);

  const collect = () => {
    if (!game) return;
    const collectedAmount = Math.floor(game.offlineProduction);
    if (collectedAmount <= 0) return;
    const newBalance = game.balance + collectedAmount;
    const entry = {
      id: crypto.randomUUID(),
      type: 'collect' as const,
      amount: collectedAmount,
      previousBalance: game.balance,
      newBalance,
      reference: 'collect-production',
      createdAt: new Date().toISOString(),
      metadata: { source: 'offline' }
    };
    setGame({
      ...game,
      balance: newBalance,
      offlineProduction: 0,
      lastCollectedAt: new Date().toISOString(),
      missions: game.missions.map((mission) => mission.id === 'mission-2' ? { ...mission, complete: true } : mission),
      ledger: [entry, ...game.ledger]
    });
    toast.success(lang.collected.replace('{amount}', formatCurrency(collectedAmount)));
  };

  const connectWallet = async () => { await tonConnectUI.openModal(); };

  const disconnectWallet = async () => {
    try {
      await tonConnectUI.disconnect();
      toast.success(t('walletDisconnected'));
    } catch (error) {
      console.error('TON disconnect error', error);
      toast.error(t('walletError'));
    }
  };

  const navigateTo = (nextTab: TabKey) => {
    setTab(nextTab);
    window.history.pushState({}, '', `/${nextTab}`);
    window.scrollTo({ top: 0, behavior: 'instant' });
  };
  const openInternal=(page:InternalPage)=>{const method=activePage?'replaceState':'pushState';setActivePage(page);window.history[method]({},'',internalPaths[page]);window.scrollTo(0,0)};
  const closeInternal=()=>{setActivePage(null);if(internalFromPath())window.history.back();else window.history.replaceState({},'','/village');window.scrollTo(0,0)};
  const [partnersOpen,setPartnersOpen]=useState(false);
  const [premiumOffersOpen,setPremiumOffersOpen]=useState(false);
  const [rewardsOpen,setRewardsOpen]=useState(false);
  const calendarOpen=activePage==='calendar',shopOpen=activePage==='hero-shop',marketOpen=activePage==='market';
  const {data:playerInventory}=usePlayerInventory(telegramInitData,backendEnabled&&calendarOpen);
  const setCalendarOpen=(open:boolean)=>open?openInternal('calendar'):closeInternal();const setShopOpen=(open:boolean)=>open?openInternal('hero-shop'):closeInternal();
  const setPetsOpen=(open:boolean)=>open?openInternal('pets'):closeInternal();
  useEffect(()=>{if(!activePage)return;const back=window.Telegram?.WebApp?.BackButton;const handle=()=>closeInternal();back?.show();back?.onClick(handle);const previous=document.body.style.overflow;document.body.style.overflow='hidden';return()=>{back?.offClick(handle);back?.hide();document.body.style.overflow=previous}},[activePage]);

  const upgradeBuilding = (id: string) => {
    setGame((prev) => {
      if (!prev) return prev;
      const selected = prev.buildings.find((b) => b.id === id);
      if (selected?.locked) {
        toast.error(t('buildingLocked'));
        return prev;
      }
      if (!selected || prev.balance < selected.upgradeCost) {
        toast.error(lang.notEnoughFunds);
        return prev;
      }
      const buildings = prev.buildings.map((building) => {
        if (building.id !== id) return building;
        return {
          ...building,
          level: building.level + 1,
          upgradeCost: Math.round(building.upgradeCost * 1.35),
          productionPerHour: Math.round(building.productionPerHour * 1.18),
          storage: Math.round(building.storage * 1.12)
        };
      });
      const totalLevels = buildings.reduce((sum, building) => sum + building.level, 0);
      const nextVillageLevel = Math.max(prev.level, Math.floor(totalLevels / 3));
      const unlockedBuildings = buildings.map((building) => ({
        ...building,
        locked: building.id === 'dragon-foundry' ? nextVillageLevel < 8 : building.locked
      }));
      const newBalance = prev.balance - selected.upgradeCost;
      return {
        ...prev,
        level: nextVillageLevel,
        balance: newBalance,
        buildings: unlockedBuildings,
        missions: prev.missions.map((mission) => mission.id === 'mission-3' ? { ...mission, complete: true } : mission),
        ledger: [{
          id: crypto.randomUUID(), type: 'upgrade', amount: -selected.upgradeCost,
          previousBalance: prev.balance, newBalance, reference: selected.id,
          createdAt: new Date().toISOString(), metadata: { level: selected.level + 1 }
        }, ...prev.ledger]
      };
    });
  };

  const claimMission = (id: string) => {
    setGame((current) => {
      if (!current) return current;
      const mission = current.missions.find((item) => item.id === id);
      if (!mission?.complete || mission.claimed) return current;
      toast.success(`+${formatCurrency(mission.reward)} FC`);
      return {
        ...current,
        balance: current.balance + mission.reward,
        missions: current.missions.map((item) => item.id === id ? { ...item, claimed: true } : item),
        ledger: [{
          id: crypto.randomUUID(), type: 'mission', amount: mission.reward,
          previousBalance: current.balance, newBalance: current.balance + mission.reward,
          reference: mission.id, createdAt: new Date().toISOString()
        }, ...current.ledger]
      };
    });
  };

  // Bottom nav: MARKET took over the old MISSIONS slot (Missions now lives on the Village home).
  const navItems = [
    { key: 'village', label: lang.tabs.village },
    { key: 'market', label: t('nav.market') },
    { key: 'boss', label: lang.tabs.boss },
    { key: 'wallet', label: lang.tabs.wallet },
    { key: 'profile', label: lang.tabs.profile }
  ] as const;


  // Admin-only diagnostics screen (Telegram id checked against the super admin).
  if (window.location.pathname === '/admin/diagnostics' && !telegramBooting) {
    if (telegramUser?.id !== 8118569391) {
      return <StatusScreen title="Acesso restrito" message="Esta área é exclusiva do administrador." />;
    }
    return (
      <DiagnosticsPage
        telegramInitData={telegramInitData ?? ''}
        telegramId={telegramUser?.id ?? null}
        onClose={() => {window.history.replaceState({}, '', '/village'); setActivePage(null); setTab('village')}}
      />
    );
  }

  if (outsideTelegram) {
    return <OpenInTelegramGate />;
  }

  // Blocked device: no Village, Wallet, PvP or Market is ever rendered/loaded.
  if (deviceAccess?.access === 'blocked') {
    return (
      <AccessDeniedScreen
        language={languageCode}
        initData={telegramInitData ?? ''}
        identity={deviceIdentity}
        pendingReview={Boolean(deviceAccess.pendingReview)}
      />
    );
  }



  // One single boot screen: Telegram init, session validation and game data all live behind it.
  if (!bootDone || !game) {
    const failure = bootstrapError ?? (error ? (error instanceof Error ? error.message : 'Erro inesperado ao consultar o backend.') : null);
    // Critical failure (session/identity): never leave the player on an endless bar.
    if (bootstrapError && !game) {
      console.error('[BOOT ERROR] critical_bootstrap', bootstrapError);
      return (
        <div className="relative flex min-h-screen flex-col items-center justify-center gap-4 bg-[#03060f] px-6 text-center text-white">
          <h1 className="text-xl font-black tracking-wide">Unable to load Mythreon</h1>
          <p className="max-w-xs text-sm text-slate-300">{bootstrapError}</p>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="rounded-full border border-sky-300/50 bg-sky-500/20 px-6 py-3 text-sm font-black uppercase tracking-[.18em] text-sky-100"
          >
            Try again
          </button>
        </div>
      );
    }
    return <MythreonLoadingScreen progress={bootProgress} note={failure} fading={bootFading} />;
  }





  const tabContent = {
    village: <VillagePage game={game} onUpgrade={upgradeBuilding} lang={lang} telegramInitData={telegramInitData ?? undefined} />,
    missions: <QuestsPage telegramInitData={telegramInitData} dashboard={dailyQuests.data} loading={dailyQuests.isLoading} error={dailyQuests.error instanceof Error?dailyQuests.error.message:null} />,
    boss: <BossPage
      game={game}
      lang={lang}
      languageCode={languageCode}
      combat={bossCombat}
      collection={heroCollection.data?.heroes}
      collectionLoading={heroCollection.isLoading}
      collectionError={heroCollection.error instanceof Error?heroCollection.error.message:heroCollection.error?'Não foi possível carregar sua coleção de heróis.':null}
      syncing={bossSyncing}
      backendOfficial={backendEnabled}
      telegramInitData={telegramInitData}
      onOpenSeasonPass={()=>openInternal('season-pass')}
      onEquipHero={async(heroId,slot)=>{
        if(backendEnabled)return equipHeroMutation.mutateAsync({heroId,slot});
        setGame(current=>{
          if(!current)return current;
          const next=current.bossTeam?.length===5?[...current.bossTeam]:['','','','',''];
          next.forEach((equipped,index)=>{if(equipped===heroId)next[index]='';});
          next[slot-1]=heroId;
          return {...current,bossTeam:next};
        });
        toast.success(t('heroEquipped'));
      }}
      isEquipping={equipHeroMutation.isPending}
      onRemoveHero={async(slot)=>{
        if(backendEnabled)return void await unequipHeroMutation.mutateAsync(slot);
        setGame(current=>{
          if(!current)return current;
          const next=current.bossTeam?.length===5?[...current.bossTeam]:['','','','',''];
          next[slot-1]='';
          return {...current,bossTeam:next};
        });
      }}
      onAttack={async()=>{await attackBossMutation.mutateAsync()}}
      isAttacking={attackBossMutation.isPending}
      onClaimReward={async () => {
        if (!telegramInitData || !backendEnabled) return;
        await bossRequest(telegramInitData,'claim'); await refetchBoss(); toast.success(t('bossDefeated'));
      }}
    />,
    wallet: (
      <WalletPage
        game={game}
        lang={lang}
        telegramInitData={telegramInitData}
        connected={Boolean(wallet)}
        address={toFriendlyTonAddress(wallet?.account.address) ?? null}
        onConnect={connectWallet}
        onDisconnect={disconnectWallet}
        isConnecting={tonConnectUI.modalState.status === 'opened'}
        languageCode={languageCode}
      />
    ),
    profile: <ProfilePage game={game} profile={playerProfile} telegramInitData={telegramInitData} backendEnabled={backendEnabled} onOpenBattlePass={()=>openInternal('season-pass')} />
  };
  const featuredMission = game.missions.find((mission) => !mission.claimed) ?? game.missions[0];
  const dailyReward = game.missions.find((mission) => mission.id === 'mission-1');
  /** Presentation-only counter: reuses the existing notification sources (no new system). */
  const unreadNotifications = (referralDashboard?.notifications?.length ?? 0) + (dailyReward?.claimed ? 0 : 1);
  const calendarDay = calendarDashboard?.currentDay??((Math.max(1, game.loginStreak) - 1) % 30) + 1;
  const calendarRewards=calendarDashboard?.rewards??CALENDAR_REWARDS;
  // Streak counts one presence per official game day: the server claim history is the authority.
  const loginStreak = calendarDashboard?calendarDashboard.claimedDays.length:game.loginStreak;


  const changeLanguage = (code: string) => {
    if (!(code in locales)) return;
    setSettingsOpen(false);
    setLanguage(code as LanguageCode)
      .then(() => toast.success(t('settings.languageSaved')))
      .catch(() => toast.error(t('settings.languageError')));
  };


  const collectCalendarDay = (day: number) => {
    if(calendarClaimMutation.isPending)return;
    if(calendarDashboard?(day!==(calendarDashboard.availableDay??-1)||!calendarDashboard.canClaim):day!==calendarDay)return;
    if(backendEnabled){calendarClaimMutation.mutate(day);return}
    if (!dailyReward?.complete || dailyReward.claimed) return;claimMission(dailyReward.id);
  };

  const drawHero = () => {
    const roll = Math.random() * 100;
    let accumulated = 0;
    let rarity: HeroRarity = 'common';
    for (const entry of summonOdds) {
      accumulated += entry.chance;
      if (roll < accumulated) {
        rarity = entry.rarity;
        break;
      }
    }
    const pool = HERO_CATALOG.filter((hero) => hero.rarity === rarity);
    return pool[Math.floor(Math.random() * pool.length)];
  };

  const recruitHeroes = async (count: number, payWith: 'FC' | 'MYTH' = 'FC') => {
    if (backendEnabled && telegramInitData && (count === 1 || count === 5 || count === 10)) {
      try {
        const result = await recruitHeroesOnServer(telegramInitData, count, payWith);
        // Server catalog wins (heroes created in the admin bot exist only there); local art is a fallback.
        setShopResults(result.heroes.map((item) => {
          const local = HERO_CATALOG.find((hero) => hero.id === item.heroKey);
          const raw = item as unknown as { name?: string; image?: string; rarity?: string };
          const image = raw.image || local?.image;
          if (!image) return null;
          return { id: item.heroKey, name: raw.name || local?.name || item.heroKey, rarity: (raw.rarity || local?.rarity || 'common') as HeroRarity, image } satisfies ShopHero;
        }).filter((hero): hero is ShopHero => Boolean(hero)));

        await Promise.all([refetchBoss(), refetchGame(), queryClient.invalidateQueries({ queryKey: ['player-heroes'] }), queryClient.invalidateQueries({ queryKey: ['community-pool'] }), queryClient.invalidateQueries({ queryKey: ['pvp-dashboard'] }), queryClient.invalidateQueries({ queryKey: ['market-sellable'] }), queryClient.invalidateQueries({ queryKey: ['hero-fusion'] }), queryClient.invalidateQueries({ queryKey: ['rarity-fusion'] }), queryClient.invalidateQueries({ queryKey: ['myth-utility'] }), queryClient.invalidateQueries({ queryKey: ['myth-wallet'] })]);
      } catch (recruitError) {
        const message = recruitError instanceof Error ? recruitError.message : String(recruitError);
        toast.error(message === 'NOT_ENOUGH_FC' ? t('notEnoughFc')
          : message.includes('INSUFFICIENT_MYTH') ? 'Saldo de MYTH insuficiente.'
          : message.includes('MYTH_PAYMENT_NOT_ENABLED') || message.includes('MYTH_UTILITY_DISABLED') ? 'Pagamento com MYTH indisponível agora.'
          : message);
      }
      return;
    }
    const cost = recruitPrice(count);
    if (fcBalance < cost) {
      toast.error(t('notEnoughFc'));
      return;
    }
    const results = Array.from({ length: count }, drawHero);
    setGame((current) => {
      if (!current) return current;
      const inventory = { ...(current.heroInventory ?? {}) };
      results.forEach((hero) => { inventory[hero.id] = (inventory[hero.id] ?? 0) + 1; });
      return {
        ...current,
        balance: current.balance - cost,
        heroInventory: inventory,
        ledger: [{ id: crypto.randomUUID(), type: 'shop', amount: -cost, previousBalance: current.balance, newBalance: current.balance - cost, reference: `recruit-${count}x`, createdAt: new Date().toISOString() }, ...current.ledger]
      };
    });
    setShopResults(results);
  };

  if(activePage==='invites'&&telegramInitData)return <><PassXpToasts telegramInitData={telegramInitData}/><HeroXpToasts/><ReferralPage telegramInitData={telegramInitData} languageCode={languageCode} onClose={closeInternal}/></>;
  if(activePage==='pets'&&telegramInitData)return <><PassXpToasts telegramInitData={telegramInitData}/><HeroXpToasts/><PetsPage telegramInitData={telegramInitData} onClose={closeInternal} onWallet={()=>{closeInternal();setTab('wallet')}}/></>;
  if(activePage==='pvp'&&telegramInitData)return <><PassXpToasts telegramInitData={telegramInitData}/><HeroXpToasts/><PvpPage telegramInitData={telegramInitData} onClose={closeInternal}/></>;
  if(activePage==='season-pass'&&telegramInitData)return <><PassXpToasts telegramInitData={telegramInitData}/><HeroXpToasts/><SeasonPassPage telegramInitData={telegramInitData} onClose={closeInternal} onMissions={()=>{setActivePage(null);navigateTo('missions')}}/></>;
  if(activePage==='heroes'&&telegramInitData)return <><PassXpToasts telegramInitData={telegramInitData}/><HeroXpToasts/><HeroesPage telegramInitData={telegramInitData} onClose={closeInternal}/></>;
  if(activePage==='clan'&&telegramInitData)return <><PassXpToasts telegramInitData={telegramInitData}/><HeroXpToasts/><ClanHubPage telegramInitData={telegramInitData} onClose={closeInternal}/></>;
  if(activePage==='pool'&&telegramInitData)return <><PassXpToasts telegramInitData={telegramInitData}/><HeroXpToasts/><CommunityPoolPage telegramInitData={telegramInitData} onClose={closeInternal} onInvite={()=>setActivePage('invites')} onWallet={()=>{closeInternal();setTab('wallet')}} initialTab={poolInitialTab}/></>;

  return (
    <div className={`telegram-safe-page relative min-h-screen overflow-x-hidden bg-black text-white ${tab === 'village' ? 'h-[100dvh] overflow-y-hidden' : ''}`}>
      <PassXpToasts telegramInitData={telegramInitData}/><HeroXpToasts/>
      {showStarterPack?<StarterPackPopup
        onClaim={async()=>{
          await claimStarterPackRequest(telegramInitData??'');
          await Promise.all([
            refetchGame(),
            refetchStarterPack(),
            queryClient.invalidateQueries({queryKey:['player-inventory']}),
            queryClient.invalidateQueries({queryKey:['pet-dashboard']}),
          ]);
        }}
        onDone={()=>setStarterPackClosed(true)}
      />:null}
      {showGiveaway?<GiveawayPopup
        onClose={()=>{setGiveawayClosed(true);void markCampaignPopup(telegramInitData??'',giveawayCampaign?.campaignId??'','dismiss')}}
        onJoin={()=>{
          const url=giveawayCampaign?.groupUrl??'https://t.me/+sy4Y6cd7cuIyNmEx';
          setGiveawayClosed(true);
          void markCampaignPopup(telegramInitData??'',giveawayCampaign?.campaignId??'','join');
          const webApp=window.Telegram?.WebApp;
          if(webApp?.openTelegramLink)webApp.openTelegramLink(url);
          else window.open(url,'_blank','noopener,noreferrer');
        }}
      />:null}
      {telegramInitData&&!showStarterPack&&!showGiveaway?<PremiumOffersPopups telegramInitData={telegramInitData}/>:null}
      <div className="fixed inset-y-0 left-1/2 w-full max-w-[480px] -translate-x-1/2 bg-cover bg-center" style={{ backgroundImage: `url(${backgrounds.village})` }} />
      <div className={`fixed inset-y-0 left-1/2 w-full max-w-[480px] -translate-x-1/2 bg-gradient-to-b ${tab === 'village' ? 'from-[#06101f]/20 via-transparent to-[#07090d]/90' : 'from-[#06101f]/55 via-[#07090d]/72 to-[#07090d]/95'}`} />
      <div className={`telegram-safe-body relative mx-auto flex min-h-screen max-w-[480px] flex-col px-3 pt-3 shadow-[0_0_80px_rgba(0,0,0,.95)] ${tab === 'village' ? 'h-[100dvh] overflow-hidden' : ''}`}>
        <header className={`main-player-header mb-2 shrink-0 border-b border-white/10 bg-[#080b10]/75 px-2 py-2.5 backdrop-blur-md ${tab === 'village' || tab === 'profile' ? 'hidden' : 'block'}`}>
          <PlayerHeader profile={playerProfile} loading={profileLoading} onRetry={()=>void refetchProfile()} balance={fcBalance} tonBalance={tonBalance} onBalanceClick={()=>setTab('wallet')} />
        </header>



        {tab === 'village' ? <div className="village-home relative flex min-h-0 flex-1 flex-col items-start gap-2 pb-2 pt-2">
          <div className="relative z-30 w-full">
            <section className="telegram-profile-card village-profile-card relative w-full overflow-hidden rounded-2xl border border-amber-300/25 px-2 py-2 shadow-[0_12px_35px_rgba(0,0,0,.55)]">
              <div className="absolute inset-0 bg-gradient-to-br from-[#101d35]/95 via-[#080d17]/90 to-[#2a1609]/90" />
              <div className="absolute -right-16 -top-16 h-52 w-52 rounded-full bg-amber-500/15 blur-3xl" />
              <PlayerHeader
                className="relative"
                profile={playerProfile}
                loading={profileLoading}
                onRetry={()=>void refetchProfile()}
                balance={fcBalance}
                tonBalance={tonBalance}
                onBalanceClick={()=>setTab('wallet')}
                tonChipVariant="villageCompact"
                actions={
                  <button onClick={() => setSettingsOpen(true)} aria-label="Configurações" className="player-header-icon relative rounded-xl border border-white/10 bg-[#080c13]/90 text-slate-200 shadow-lg backdrop-blur-md">
                    <Settings />
                    {unreadNotifications > 0 ? <span className="absolute right-0.5 top-0.5 h-2 w-2 rounded-full border border-black bg-rose-500" /> : null}
                  </button>
                }
              />

            </section>
          </div>


          <ClanHall clan={clanDashboard?.clan??null} onOpen={()=>openInternal('clan')}/>


          <div className="flex w-full items-start justify-between">
            <HomeFeature image={mainScreenArt.dailyStreak} label={t('calendar')} subtitle={(calendarDashboard?calendarDashboard.claimedToday:dailyReward?.claimed)?t('collectedToday'):`${t('day')} ${calendarDay}`} onClick={()=>setCalendarOpen(true)}/>
            <HomeFeature image={mainScreenArt.pool} label="POOL" subtitle="COMUNIDADE" onClick={()=>{setPoolInitialTab('weekly');openInternal('pool')}}/>
          </div>
          <div className="flex w-full items-start justify-between">
            <HomeFeature image={mainScreenArt.heroShop} label={t('shop')} onClick={()=>setShopOpen(true)}/>
            <HomeFeature image={mainScreenArt.seasonPass} label="PASSE" subtitle="TEMPORADA" onClick={()=>openInternal('season-pass')}/>
          </div>
          <div className="flex w-full items-start justify-between">
            <HomeFeature image={mainScreenArt.invite} label={t('invite')} onClick={()=>openInternal('invites')}/>
            <HomeFeature image={mainScreenArt.pvp} label={t('pvp')} onClick={()=>openInternal('pvp')}/>
          </div>

          <div className="flex w-full items-start justify-between">
            <div className="flex flex-col items-center gap-2">
              <HomeFeature image={petDashboard?.activePet?.image||mainScreenArt.pet} label="PET" subtitle={petDashboard?.activePet?`${petDashboard.activePet.name} · Nv. ${petDashboard.activePet.level}`:'Nenhum ativo'} onClick={()=>openInternal('pets')}/>
              <button
                onClick={()=>setPartnersOpen(true)}
                className="flex items-center gap-1.5 rounded-full border border-amber-300/30 bg-black/40 px-4 py-2 text-[10px] font-black uppercase tracking-[0.18em] text-amber-200 transition active:scale-95"
              >🤝 {t('partners.button')}</button>
              <button
                onClick={()=>{setActivePage(null);navigateTo('missions')}}
                className="flex items-center gap-1.5 rounded-full border border-amber-300/30 bg-black/40 px-4 py-2 text-[10px] font-black uppercase tracking-[0.18em] text-amber-200 transition active:scale-95"
              >📜 MISSIONS</button>
            </div>
            <div className="flex flex-col items-center gap-2">
              <HomeFeature image={characters.knight} label="HEROES" subtitle="COLEÇÃO" onClick={()=>openInternal('heroes')}/>
              <button
                onClick={()=>setRewardsOpen(true)}
                className="flex items-center gap-1.5 rounded-full border border-sky-400/40 bg-black/60 px-3.5 py-2 text-[10px] font-black uppercase tracking-[0.14em] text-sky-200 shadow-[0_0_18px_rgba(56,189,248,.15)] transition active:scale-95"
              >
                <Sparkles className="h-3.5 w-3.5" /> {t('adRewards.button')}
              </button>
              <button
                onClick={()=>setPremiumOffersOpen(true)}
                className="flex items-center gap-1.5 rounded-full border border-amber-300/50 bg-black/60 px-3.5 py-2 text-[10px] font-black uppercase tracking-[0.14em] text-amber-200 shadow-[0_0_18px_rgba(251,191,36,.18)] transition active:scale-95"
              >💎 OFERTAS</button>
            </div>
          </div>



          {partnersOpen&&telegramInitData?<PartnersModal telegramInitData={telegramInitData} onClose={()=>setPartnersOpen(false)}/>:null}
          {rewardsOpen&&telegramInitData?<RewardsModal telegramInitData={telegramInitData} onClose={()=>setRewardsOpen(false)}/>:null}
          {premiumOffersOpen&&telegramInitData?<PremiumOffersModal telegramInitData={telegramInitData} onClose={()=>setPremiumOffersOpen(false)}/>:null}


          {shopOpen||marketOpen ? (
            <HeroShopPanel
              mode={marketOpen?'market':'recruit'}
              telegramInitData={telegramInitData}
              fcBalance={fcBalance}
              tonBalance={tonBalance}
              summonOdds={summonOdds}
              recruitPrice={recruitPrice}
              shopResults={shopResults}
              onRecruit={(count: 1 | 5 | 10, payWith: 'FC' | 'MYTH' = 'FC') => void recruitHeroes(count, payWith)}
              onClose={closeInternal}
            />
          ) : null}


          {calendarOpen ? (
            <div className="fullscreen-page flex items-center justify-center p-4">
              <div className="w-full max-w-[440px] rounded-[2rem] border border-amber-300/25 bg-[#090d15] p-4 shadow-2xl">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-[10px] uppercase tracking-[0.28em] text-amber-300">{t('dailyRewards')}</p>
                    <h2 className="text-xl font-black text-white">{t('calendar30')}</h2>
                  </div>
                  <button onClick={() => setCalendarOpen(false)} className="grid h-9 w-9 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
                </div>
                {/* Official server day and next 21:00 rollover come from the backend only. */}
                <div className="mt-3 flex items-center justify-between rounded-2xl border border-white/10 bg-white/[.03] px-3 py-2">
                  <p className="text-[10px] font-black text-amber-200">DIA OFICIAL {calendarDashboard?.gameDayNumber??calendarDay}</p>
                  <p className="text-[9px] uppercase tracking-[.18em] text-slate-400">PRÓXIMO DIA EM <b className="text-white">{nextResetCountdown(calendarDashboard?.nextResetAt,nowTick)}</b></p>
                </div>

                <div className="mt-4 grid grid-cols-5 gap-2">
                  {Array.from({ length: 30 }, (_, index) => {
                    const day = index + 1;
                    const reward=calendarRewards.find(item=>item.day===day);
                    // CLAIMED / AVAILABLE / LOCKED come from the server: only one day is ever AVAILABLE.
                    const status = calendarDayStatus(calendarDashboard, day, calendarDay, Boolean(dailyReward?.claimed));
                    const collected = status === 'CLAIMED';
                    const current = status === 'AVAILABLE';
                    const claiming = current && calendarClaimMutation.isPending;
                    const chestIndex=reward?.itemCode==='epic_chest'||reward?.itemCode==='legendary_chest'?2:reward?.itemCode==='rare_chest'?1:0;
                    return (
                      <button
                        key={day}
                        onClick={() => collectCalendarDay(day)}
                        disabled={!current || Boolean(collected)||calendarClaimMutation.isPending}
                        className={`aspect-square rounded-xl border p-1 text-center transition ${collected ? 'border-emerald-400/25 bg-emerald-500/10 text-emerald-300' : current ? 'border-amber-300 bg-amber-400/15 text-amber-200 shadow-[0_0_15px_rgba(251,191,36,.2)]' : 'border-white/5 bg-white/[.03] text-slate-600'}`}
                      >
                        <span className="block text-[8px] font-black">DIA {day}</span>
                        {reward?.type==='fc'?<img src={coin} alt="FC" className="mx-auto h-5 w-5 object-contain"/>:reward?.type==='hero_chest'?<img src={chests[chestIndex]} alt="Baú" className="mx-auto h-5 w-5 object-contain"/>:<img src={`/assets/game/pet-eggs/${reward?.itemCode}.webp`} alt="Ovo" className="mx-auto h-5 w-5 object-contain"/>}
                        <span className="block truncate text-[6px]">{collected?'OK':claiming?'...':!current?'🔒':reward?.type==='fc'?`${(reward.amountFc??0)/1000}K FC`:reward?.type==='hero_chest'?'BAÚ':'OVO'}</span>
                      </button>
                    );
                  })}
                </div>
                <p className="mt-3 text-center text-[10px] text-slate-400">{t('selectDay')}</p>
                {/* Stored rewards stay openable later: nothing is lost when the player closes the modal. */}
                <section className="mt-4 rounded-2xl border border-white/10 bg-white/[.03] p-3">
                  <h3 className="text-[10px] font-black uppercase tracking-[0.22em] text-amber-300">MEU INVENTÁRIO</h3>
                  {(playerInventory?.chests.length??0)+(playerInventory?.eggs.length??0)===0?(
                    <p className="mt-2 text-[10px] text-slate-500">Nenhum baú ou ovo guardado.</p>
                  ):(
                    <ul className="mt-2 space-y-2">
                      {playerInventory?.chests.map(chest=>(
                        <li key={chest.id} className="flex items-center gap-2 rounded-xl border border-amber-300/20 bg-black/30 p-2">
                          <img src={chests[chest.itemCode==='epic_chest'||chest.itemCode==='legendary_chest'?2:chest.itemCode==='rare_chest'?1:0]} alt="Baú" className="h-8 w-8 object-contain"/>
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-[11px] font-bold text-white">{chest.name||CHEST_LABELS[chest.itemCode]||'Baú de Herói'}</p>
                            <p className="text-[9px] text-slate-400">x{chest.quantity} · {chest.subtitle}</p>
                          </div>
                          <button type="button" disabled={calendarChestMutation.isPending} onClick={()=>openChest(chest.id)} className="rounded-lg bg-amber-400 px-3 py-2 text-[10px] font-black text-black disabled:opacity-50">{calendarChestMutation.isPending?'ABRINDO...':'ABRIR'}</button>
                        </li>
                      ))}
                      {playerInventory?.eggs.map(egg=>(
                        <li key={egg.id} className="flex items-center gap-2 rounded-xl border border-white/10 bg-black/30 p-2">
                          <img src={egg.image??`/assets/game/pet-eggs/${egg.slug}.webp`} alt={egg.name} className="h-8 w-8 object-contain"/>
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-[11px] font-bold text-white">{egg.name}</p>
                            <p className="text-[9px] text-slate-400">x{egg.quantity}</p>
                          </div>
                          <button type="button" onClick={()=>{setCalendarOpen(false);setPetsOpen(true)}} className="rounded-lg border border-amber-300/40 px-3 py-2 text-[10px] font-black text-amber-200">CHOCAR</button>
                        </li>
                      ))}
                    </ul>
                  )}
                </section>
              </div>
            </div>
          ) : null}

          {calendarResult?<div className="fixed inset-0 z-[65] grid place-items-center bg-black/80 p-5"><div className="w-full max-w-sm rounded-3xl border border-amber-300/30 bg-[#090d15] p-6 text-center"><p className="text-[10px] tracking-[.25em] text-amber-300">RECOMPENSA COLETADA</p><h2 className="mt-2 text-2xl font-black">Dia {calendarResult.reward.day}</h2><p className="mt-3 text-lg text-amber-100">{calendarResult.reward.title}{calendarResult.reward.subtitle?` · ${calendarResult.reward.subtitle}`:''}</p>{calendarResult.reward.type==='fc'?<p className="mt-2 text-emerald-300">Novo saldo: {formatCurrency(calendarResult.balance)} FC</p>:<p className="mt-2 text-slate-300">Item guardado no inventário.</p>}<div className="mt-5 grid grid-cols-2 gap-2">{calendarResult.reward.type==='pet_egg'?<button type="button" onClick={()=>{setCalendarResult(null);setCalendarOpen(false);setPetsOpen(true)}} className="rounded-xl bg-amber-400 py-3 font-black text-black">IR PARA PETS</button>:calendarResult.reward.type==='hero_chest'?<button type="button" disabled={!calendarResult.inventoryItemId||calendarChestMutation.isPending} onClick={()=>calendarResult.inventoryItemId&&openChest(calendarResult.inventoryItemId)} className="rounded-xl bg-amber-400 py-3 font-black text-black disabled:opacity-50">{calendarChestMutation.isPending?'ABRINDO...':'ABRIR AGORA'}</button>:<span/>}<button type="button" onClick={()=>setCalendarResult(null)} className="rounded-xl border border-white/15 py-3 font-bold">{calendarResult.reward.type==='fc'?'CONTINUAR':'GUARDAR'}</button></div></div></div>:null}

          {chestResult?<div className="fixed inset-0 z-[70] grid place-items-center bg-black/85 p-5"><div className="w-full max-w-sm rounded-3xl border p-6 text-center" style={{borderColor:`${RARITY_COLORS[chestResult.hero.rarity as keyof typeof RARITY_COLORS]??'#fbbf24'}55`,background:`radial-gradient(circle at 50% 0%, ${RARITY_COLORS[chestResult.hero.rarity as keyof typeof RARITY_COLORS]??'#fbbf24'}22, #090d15 65%)`}}><p className="text-[10px] tracking-[.3em] text-amber-300">BAÚ ABERTO</p><img src={chestResult.hero.image} alt={chestResult.hero.name} className="mx-auto mt-3 h-40 w-40 rounded-2xl object-contain"/><h2 className="mt-3 text-2xl font-black text-white">{chestResult.hero.name}</h2><p className="mt-1 text-[11px] font-black tracking-[.2em]" style={{color:RARITY_COLORS[chestResult.hero.rarity as keyof typeof RARITY_COLORS]??'#fbbf24'}}>{chestResult.hero.rarity.toUpperCase()}</p><p className="mt-1 text-[10px] tracking-[.2em] text-emerald-300">NOVO HERÓI</p><p className="mt-2 text-[11px] text-slate-400">ATK {chestResult.hero.baseAtk} · HP {chestResult.hero.baseHp}</p><button type="button" onClick={()=>setChestResult(null)} className="mt-5 w-full rounded-xl bg-amber-400 py-3 font-black text-black">CONTINUAR</button></div></div>:null}

          {settingsOpen ? (
            <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-sm">
              <div className="w-full max-w-sm rounded-[2rem] border border-white/10 bg-[#090d15] p-5 shadow-2xl">
                <div className="flex items-center justify-between">
                  <h2 className="text-lg font-black">{t('settings')}</h2>
                  <button onClick={() => setSettingsOpen(false)} className="grid h-9 w-9 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
                </div>
                <p className="mt-5 text-[10px] uppercase tracking-[0.25em] text-slate-400">{t('language')}</p>
                <div className="mt-2 grid grid-cols-2 gap-2">
                  {[['pt', 'Português'], ['en', 'English'], ['es', 'Español'], ['ru', 'Русский'], ['tr', 'Türkçe']].map(([code, label]) => (
                    <button key={code} onClick={() => changeLanguage(code)} className="rounded-xl border border-white/10 bg-white/5 px-3 py-3 text-sm text-white hover:border-amber-300/40 hover:bg-amber-400/10">{label}</button>
                  ))}
                </div>
                <button
                  type="button"
                  onClick={() => { setSettingsOpen(false); setNotificationsOpen(true); }}
                  className="mt-4 flex w-full items-center justify-between gap-3 rounded-xl border border-white/10 bg-white/5 px-3 py-3 text-left hover:border-amber-300/40 hover:bg-amber-400/10"
                >
                  <span className="flex items-center gap-2">
                    <Bell className="h-4 w-4 text-amber-300" />
                    <span>
                      <span className="block text-sm font-bold text-white">{t('notifications')}</span>
                      <span className="block text-[10px] text-slate-400">{t('common.notificationsHint')}</span>
                    </span>
                  </span>
                  {unreadNotifications > 0 ? (
                    <span className="shrink-0 rounded-full bg-rose-500/20 px-2 py-1 text-[10px] font-black text-rose-300">{unreadNotifications} {t('common.unread')}</span>
                  ) : (
                    <ChevronRight className="h-4 w-4 shrink-0 text-slate-500" />
                  )}
                </button>
              </div>
            </div>
          ) : null}

          {notificationsOpen ? (
            <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/75 p-4 backdrop-blur-sm">
              <div className="w-full max-w-sm rounded-[2rem] border border-white/10 bg-[#090d15] p-5 shadow-2xl">
                <div className="flex items-center justify-between">
                  <h2 className="text-lg font-black">{t('notifications')}</h2>
                  <button onClick={() => setNotificationsOpen(false)} className="grid h-9 w-9 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
                </div>
                <p className="mt-4 text-xs text-slate-300">{dailyReward?.claimed ? t('rewardCollected') : t('rewardAvailable')}</p>
                {referralDashboard?.notifications?.map(item => (
                  <div key={item.id} className="mt-3 border-t border-white/10 pt-3">
                    <p className="text-xs font-bold text-emerald-300">{item.message}</p>
                    <p className="text-[10px] text-slate-400">{item.title}</p>
                  </div>
                ))}
              </div>
            </div>
          ) : null}

          <div className="hidden">
        <img src={logo.horizontal} alt="MYTHREON" className="main-game-logo relative z-10 mx-auto -mb-3 mt-0 h-auto w-full max-w-[280px] shrink-0 drop-shadow-[0_12px_20px_rgba(0,0,0,0.8)]" />

        <section className="village-main-panel mb-2 flex min-h-0 flex-1 flex-col overflow-hidden">
          <div className="village-level-bar mx-auto flex w-full max-w-[390px] shrink-0 items-center justify-between rounded-xl border border-amber-300/30 bg-[#0a0d12]/90 px-4 py-2 shadow-card">
            <div className="flex items-center gap-2">
              <img src={mainScreenArt.villageLevel} alt="" className="h-10 w-10 object-contain" />
              <div>
                <p className="text-[10px] uppercase tracking-[0.25em] text-slate-400">{lang.villageLevel}</p>
                <p className="text-xl font-black text-amber-300">{game.level}</p>
              </div>
            </div>
            <div className="text-right">
              <p className="text-[10px] uppercase tracking-[0.25em] text-slate-400">{lang.productionPerHour}</p>
              <p className="text-base font-bold text-emerald-400">+{formatCurrency(totalProduction)} FC/h</p>
            </div>
            <img src={mainScreenArt.productionAnvil} alt="Produção" className="h-9 w-9 object-contain" />
          </div>
          <div className="village-stage relative -mx-3 min-h-[145px] flex-1 overflow-hidden">
            <div className="absolute inset-0 bg-gradient-to-b from-transparent via-transparent to-[#07090d]/90" />
            <img src={mainScreenArt.forgeTower} alt="Forja principal" className="village-forge absolute bottom-0 left-1/2 h-[325px] w-[325px] -translate-x-1/2 scale-x-110 object-contain drop-shadow-[0_18px_22px_rgba(0,0,0,.85)]" />
            <div className="village-furnace-glow pointer-events-none absolute bottom-[-12px] left-1/2 z-10 h-28 w-36 -translate-x-1/2 rounded-full" />
            <button onClick={() => upgradeBuilding('iron-mine')} title={`Melhorar Mina de Ferro: ${formatCurrency(game.buildings[0]?.upgradeCost ?? 0)} FC`} className="building-upgrade-button absolute left-[3%] top-[27%] z-20 rounded-lg border border-amber-300/40 bg-[#0a0b0e]/95 px-3 py-2 text-center shadow-lg transition active:scale-95">
              <p className="whitespace-nowrap text-[10px] font-bold uppercase text-amber-100">Mina de ferro</p>
              <p className="text-[10px] text-slate-400">Nv. {game.buildings[0]?.level}</p>
            </button>
            <button onClick={() => upgradeBuilding('coal-mine')} title={`Melhorar Mina de Carvão: ${formatCurrency(game.buildings[1]?.upgradeCost ?? 0)} FC`} className="building-upgrade-button absolute left-[2%] top-[56%] z-20 rounded-lg border border-amber-300/40 bg-[#0a0b0e]/95 px-3 py-2 text-center shadow-lg transition active:scale-95">
              <p className="whitespace-nowrap text-[10px] font-bold uppercase text-amber-100">Mina de carvão</p>
              <p className="text-[10px] text-slate-400">Nv. {game.buildings[1]?.level}</p>
            </button>
            <button onClick={() => upgradeBuilding('royal-workshop')} title={`Melhorar Oficina: ${formatCurrency(game.buildings[3]?.upgradeCost ?? 0)} FC`} className="building-upgrade-button absolute right-[2%] top-[43%] z-20 rounded-lg border border-amber-300/40 bg-[#0a0b0e]/95 px-3 py-2 text-center shadow-lg transition active:scale-95">
              <p className="whitespace-nowrap text-[10px] font-bold uppercase text-amber-100">Oficina</p>
              <p className="text-[10px] text-slate-400">Nv. {game.buildings[3]?.level}</p>
            </button>
          </div>
          <div className="village-collect shrink-0 overflow-hidden rounded-2xl border border-amber-300/30 bg-[#090c12]/92 text-center shadow-[0_12px_28px_rgba(0,0,0,.45)]">
            <div className="collect-balance-panel px-3 py-2">
              <p className="text-3xl font-black tracking-wide text-white">{formatCurrency(Math.floor(game.offlineProduction))} FC</p>
              <p className="mt-1 text-xs uppercase tracking-[0.28em] text-slate-400">{lang.offlineProduction}</p>
              <div className="mx-auto mt-2 h-1.5 w-3/4 overflow-hidden rounded-full bg-white/10">
                <div className="h-full rounded-full bg-gradient-to-r from-amber-300 to-orange-500" style={{ width: `${Math.min(100, (game.offlineProduction / storageCapacity) * 100)}%` }} />
              </div>
            </div>
            <button
              onClick={collect}
              disabled={game.offlineProduction < 1}
              className="w-full border-x-0 border-b-0 border-t border-amber-100/70 bg-gradient-to-b from-amber-300 via-amber-500 to-orange-600 px-4 py-4 text-xl font-black text-[#241307] shadow-[inset_0_2px_0_rgba(255,255,255,.3)] transition disabled:cursor-not-allowed disabled:opacity-50"
            >
              {lang.collect.toUpperCase()}
            </button>
            <div className="flex items-center justify-center gap-2 bg-black/45 px-2 py-1.5 text-xs text-slate-300">
              <span>🔥 {loginStreak} {lang.loginStreak.toLowerCase()}</span>
              <span className="text-slate-600">•</span>
              <span>{formatCurrency(storageCapacity)} FC max.</span>
            </div>
          </div>
        </section>

        {featuredMission ? (
          <section className="village-cards mb-1 grid h-[112px] shrink-0 grid-cols-1 gap-2">
            <div className="relative overflow-hidden rounded-3xl border border-white/10 bg-forge-black/85 p-4 shadow-card">
              <img src={mainScreenArt.dailyStreak} alt="" className="pointer-events-none absolute -right-3 -top-2 h-24 w-24 object-contain opacity-55" />
              <p className="relative text-[10px] uppercase tracking-[0.22em] text-slate-400">{lang.loginStreak}</p>
              <p className="relative mt-2 text-3xl font-black text-amber-300">{loginStreak} dias</p>
              <div className="mt-3 flex gap-1">
                {Array.from({ length: 7 }, (_, index) => (
                  <span key={index} className={`h-2 flex-1 rounded-full ${index < loginStreak ? 'bg-amber-400' : 'bg-white/10'}`} />
                ))}
              </div>
              <p className="relative mt-2 text-[11px] text-slate-400">Continue entrando todos os dias</p>
            </div>
          </section>
        ) : null}
          </div>
        </div> : null}

        {tab !== 'village' ? tabContent[tab] : null}
      </div>


      {!activePage?<nav className="telegram-safe-nav fixed bottom-0 left-0 right-0 border-t border-white/10 bg-forge-black/95 px-4 py-3 backdrop-blur-xl">
        <div className="mx-auto flex max-w-[480px] items-center justify-between">
          {navItems.map((item) => {
            const isMarket = item.key === 'market';
            const active = isMarket ? marketOpen : tab === item.key;
            const icon = isMarket ? mainScreenArt.market : (active ? navigationIcons[item.key].selected : navigationIcons[item.key].normal);
            return (
            <button
              key={item.key}
              onClick={() => isMarket ? openInternal('market') : navigateTo(item.key as TabKey)}
              className={`flex min-w-[0] flex-1 flex-col items-center justify-center rounded-3xl px-2 py-2 text-xs transition ${active ? 'bg-amber-500/15 text-amber-200' : 'text-slate-400 hover:text-white'}`}
            >
              <img
                src={icon}
                alt=""
                className="h-7 w-7 object-contain transition duration-200"
                style={active ? { filter: 'sepia(1) saturate(1.8) hue-rotate(5deg) brightness(1.15) drop-shadow(0 0 6px rgba(251,191,36,.65))' } : undefined}
              />
              <span className="mt-1">{item.label}</span>
            </button>
          );})}

        </div>
      </nav>:null}
    </div>
  );
}

export default App;
