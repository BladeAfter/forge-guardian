import { useEffect, useMemo, useRef, useState } from 'react';
import { useTonConnectUI, useTonWallet } from '@tonconnect/ui-react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { Bell, Settings, X } from 'lucide-react';
import type { GameState, LanguageStrings, TabKey } from './types';
import { LANGUAGES, formatCurrency, getLocale, locales } from './utils';
import { useBossCombat, useCalendarDashboard, useGameState, usePetDashboard, useReferralDashboard, useTelegramProfile } from './hooks';
import { VillagePage } from './pages/VillagePage';
import { MissionsPage } from './pages/MissionsPage';
import { BossPage } from './pages/BossPage';
import { WalletPage } from './pages/WalletPage';
import { ProfilePage } from './pages/ProfilePage';
import { ReferralPage } from './pages/ReferralPage';
import { PetsPage } from './pages/PetsPage';
import { PvpPage } from './pages/PvpPage';
import {SeasonPassPage}from'./pages/SeasonPassPage';
import {CommunityPoolPage}from'./pages/CommunityPoolPage';
import { backgrounds, chests, coin, logo, mainScreenArt, navigationIcons } from './gameAssets';
import { isDemoMode, isProduction } from './config';
import { getTelegramStartParam, getTelegramUser, initializeTelegram, validateTelegramSession, type TelegramUser } from './telegram';
import { bindReferral, bossRequest, claimCalendarDay, equipCombatHeroOnServer, openCalendarChest, recruitHeroesOnServer, saveDemoState } from './services';
import { translate, type LanguageCode } from './i18n';
import { HERO_CATALOG, RARITY_COLORS, RARITY_ODDS, type HeroRarity, type ShopHero } from './heroCatalog';
import {getDisplayName,getInitials,type TelegramPlayerProfile} from './playerProfile';
import {CALENDAR_REWARDS,type CalendarClaimResult} from './calendarRewards';

const tabs: TabKey[] = ['village', 'missions', 'boss', 'wallet', 'profile'];
type InternalPage='invites'|'pvp'|'pets'|'pool'|'hero-shop'|'calendar'|'season-pass';
const internalPaths:Record<InternalPage,string>={invites:'/invites',pvp:'/pvp',pets:'/pets',pool:'/pool','hero-shop':'/hero-shop',calendar:'/calendar','season-pass':'/season-pass'};
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

function HomeFeature({image,label,subtitle,onClick}:{image:string;label:string;subtitle?:string;onClick:()=>void}){
  return <button type="button" onClick={onClick} className="home-feature group relative flex h-[112px] w-[108px] shrink-0 flex-col items-center justify-center overflow-hidden rounded-2xl border border-amber-300/35 bg-[#080c13]/90 px-2 shadow-[0_12px_28px_rgba(0,0,0,.58)] backdrop-blur-sm transition active:scale-95"><div className="absolute inset-0 bg-gradient-to-b from-sky-950/10 to-amber-950/20"/><img src={image} alt={label} className="home-feature-image relative h-[68px] w-[68px] object-contain drop-shadow-[0_7px_10px_rgba(0,0,0,.7)] transition group-hover:scale-105"/><span className="home-feature-label relative mt-1 text-center text-[10px] font-black uppercase tracking-[.11em] text-amber-200">{label}</span>{subtitle&&<span className="home-feature-subtitle relative mt-0.5 text-[7px] font-bold uppercase text-emerald-300">{subtitle}</span>}</button>;
}

function TelegramAvatar({profile}:{profile:TelegramPlayerProfile|null}){
  const [failed,setFailed]=useState(false);const name=profile?getDisplayName(profile):'Jogador';
  useEffect(()=>setFailed(false),[profile?.photoUrl]);
  return profile?.photoUrl&&!failed?<img src={profile.photoUrl} onError={()=>setFailed(true)} alt={name} className="h-11 w-11 shrink-0 rounded-full border-2 border-amber-400/60 bg-black object-cover"/>:<div className="grid h-11 w-11 shrink-0 place-items-center rounded-full border-2 border-amber-400/60 bg-slate-900 text-xs font-black text-amber-100">{getInitials(name)}</div>;
}

function App() {
  const [tab, setTab] = useState<TabKey>(tabFromPath);
  const [lang, setLang] = useState<LanguageStrings>(LANGUAGES.en);
  const [languageCode, setLanguageCode] = useState<LanguageCode>('en');
  const [loadingMessage, setLoadingMessage] = useState('Loading game data...');
  const [isReady, setIsReady] = useState(false);
  const [game, setGame] = useState<GameState | null>(null);
  const [telegramInitData, setTelegramInitData] = useState<string | null>(null);
  const [telegramUser, setTelegramUser] = useState<TelegramUser | null>(null);
  const [activePage,setActivePage]=useState<InternalPage|null>(internalFromPath);
  const [calendarResult,setCalendarResult]=useState<CalendarClaimResult|null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const [telegramStartParam,setTelegramStartParam]=useState<string|null>(null);
  const [shopResults, setShopResults] = useState<ShopHero[]>([]);
  const [bootstrapError, setBootstrapError] = useState<string | null>(null);
  const [outsideTelegram, setOutsideTelegram] = useState(false);
  const [tonConnectUI] = useTonConnectUI();
  const wallet = useTonWallet();
  const queryClient = useQueryClient();
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
  const {data:referralDashboard}=useReferralDashboard(telegramInitData,backendEnabled);
  const {data:petDashboard}=usePetDashboard(telegramInitData,backendEnabled);
  const {data:calendarDashboard,refetch:refetchCalendar}=useCalendarDashboard(telegramInitData,backendEnabled);
  const calendarClaimMutation=useMutation({mutationFn:(day:number)=>claimCalendarDay(telegramInitData??'',day),onSuccess:async result=>{setCalendarResult(result);queryClient.setQueryData(['calendar-dashboard',telegramInitData],result.dashboard);await Promise.all([refetchGame(),refetchCalendar(),queryClient.invalidateQueries({queryKey:['pet-dashboard']}),queryClient.invalidateQueries({queryKey:['boss-combat']})]);toast.success('Recompensa coletada!')},onError:error=>toast.error(error instanceof Error?error.message:'Não foi possível coletar a recompensa.')});
  const calendarChestMutation=useMutation({mutationFn:(id:string)=>openCalendarChest(telegramInitData??'',id),onSuccess:async result=>{toast.success(`${result.hero.name} · ${result.hero.rarity}`);setCalendarResult(null);await Promise.all([refetchBoss(),queryClient.invalidateQueries({queryKey:['game-state']})])},onError:error=>toast.error(error instanceof Error?error.message:'Não foi possível abrir o baú.')});
  const {data:officialProfile,isLoading:profileLoading,error:profileError,refetch:refetchProfile}=useTelegramProfile(telegramInitData,backendEnabled);
  const playerProfile:TelegramPlayerProfile|null=officialProfile??(telegramUser?{telegramId:String(telegramUser.id),firstName:telegramUser.first_name,lastName:telegramUser.last_name??null,username:telegramUser.username??null,photoUrl:telegramUser.photo_url??null}:null);
  useEffect(()=>{if(profileError)console.error('[telegram-profile] Falha ao carregar perfil',profileError)},[profileError]);
  const equipHeroMutation=useMutation({
    mutationFn:async({heroId,slot}:{heroId:string;slot:1|2|3|4|5})=>{
      if(!backendEnabled||!telegramInitData)throw new Error(translate(languageCode,'backendRequired'));
      return equipCombatHeroOnServer(telegramInitData,heroId,slot);
    },
    onSuccess:async(result)=>{
      queryClient.setQueryData(['boss-combat',telegramInitData],result);
      await Promise.all([
        queryClient.invalidateQueries({queryKey:['boss-combat',telegramInitData]}),
        queryClient.invalidateQueries({queryKey:['game-state',telegramInitData]})
      ]);
      toast.success(translate(languageCode,'heroEquipped'));
    },
    onError:(mutationError)=>toast.error(mutationError instanceof Error?mutationError.message:translate(languageCode,'equipFailed'))
  });

  useEffect(() => {
    const locale = localStorage.getItem('forge-village-language') || getLocale();
    const code = (locale in locales ? locale : 'en') as LanguageCode;
    setLanguageCode(code);
    setLang(locales[code] ?? LANGUAGES.en);
    setLoadingMessage(locales[locale]?.loading ?? LANGUAGES.en.loading);
  }, []);

  useEffect(() => {
    const onPopState = () => {setTab(tabFromPath());setActivePage(internalFromPath())};
    window.addEventListener('popstate', onPopState);
    return () => window.removeEventListener('popstate', onPopState);
  }, []);

  useEffect(() => {
    window.scrollTo(0, 0);
  }, []);

  useEffect(() => {
    const webApp = initializeTelegram();
    setTelegramUser(getTelegramUser(webApp));
    setTelegramStartParam(getTelegramStartParam(webApp));
    if (!isProduction || isDemoMode) {
      setTelegramInitData(webApp?.initData || 'development-browser-session');
      return;
    }
    if (!webApp?.initData) {
      setOutsideTelegram(true);
      return;
    }
    validateTelegramSession(webApp.initData)
      .then(() => setTelegramInitData(webApp.initData))
      .catch((validationError: unknown) => setBootstrapError(validationError instanceof Error ? validationError.message : 'Telegram authentication failed.'));
  }, []);

  useEffect(()=>{
    if(!backendEnabled||!telegramInitData||referralBound.current)return;
    const inviter=Number(telegramStartParam);
    if(!Number.isSafeInteger(inviter)||inviter<=0)return;
    referralBound.current=true;
    bindReferral(telegramInitData,inviter).then(()=>queryClient.invalidateQueries({queryKey:['referral-dashboard']})).catch(error=>toast.error(error instanceof Error?error.message:String(error)));
  },[backendEnabled,telegramInitData,telegramStartParam,queryClient]);

  useEffect(()=>{
    const latest=referralDashboard?.notifications?.[0];if(!latest||latest.id===lastCommissionNotification.current)return;
    lastCommissionNotification.current=latest.id;
    if(latest.amountFc)toast.success(`${latest.message} · ${latest.title}`);
  },[referralDashboard?.notifications]);

  useEffect(() => {
    if (data) {
      setGame(data as GameState);
      setIsReady(true);
    }
  }, [data]);

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
      toast.success(translate(languageCode, 'walletDisconnected'));
    } catch (error) {
      console.error('TON disconnect error', error);
      toast.error(translate(languageCode, 'walletError'));
    }
  };

  const navigateTo = (nextTab: TabKey) => {
    setTab(nextTab);
    window.history.pushState({}, '', `/${nextTab}`);
    window.scrollTo({ top: 0, behavior: 'instant' });
  };
  const openInternal=(page:InternalPage)=>{const method=activePage?'replaceState':'pushState';setActivePage(page);window.history[method]({},'',internalPaths[page]);window.scrollTo(0,0)};
  const closeInternal=()=>{setActivePage(null);if(internalFromPath())window.history.back();else window.history.replaceState({},'','/village');window.scrollTo(0,0)};
  const calendarOpen=activePage==='calendar',shopOpen=activePage==='hero-shop';
  const setCalendarOpen=(open:boolean)=>open?openInternal('calendar'):closeInternal();const setShopOpen=(open:boolean)=>open?openInternal('hero-shop'):closeInternal();
  const setPetsOpen=(open:boolean)=>open?openInternal('pets'):closeInternal();
  useEffect(()=>{if(!activePage)return;const back=window.Telegram?.WebApp?.BackButton;const handle=()=>closeInternal();back?.show();back?.onClick(handle);const previous=document.body.style.overflow;document.body.style.overflow='hidden';return()=>{back?.offClick(handle);back?.hide();document.body.style.overflow=previous}},[activePage]);

  const upgradeBuilding = (id: string) => {
    setGame((prev) => {
      if (!prev) return prev;
      const selected = prev.buildings.find((b) => b.id === id);
      if (selected?.locked) {
        toast.error(translate(languageCode, 'buildingLocked'));
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

  const navItems = [
    { key: 'village', label: lang.tabs.village },
    { key: 'missions', label: lang.tabs.missions },
    { key: 'boss', label: lang.tabs.boss },
    { key: 'wallet', label: lang.tabs.wallet },
    { key: 'profile', label: lang.tabs.profile }
  ] as const;

  if (outsideTelegram) {
    return <OpenInTelegramGate />;
  }

  if (bootstrapError) {
    return <StatusScreen title="Telegram necessário" message={bootstrapError} />;
  }

  if (error) {
    return <StatusScreen title="Não foi possível carregar o jogo" message={error instanceof Error ? error.message : 'Erro inesperado ao consultar o backend.'} />;
  }

  if (isLoading || !isReady || !game) {
    return (
      <div className="relative min-h-screen overflow-hidden bg-forge-black text-white">
        <img src={backgrounds.loading} alt="" className="absolute inset-0 h-full w-full object-cover object-center" fetchPriority="high" />
        <div className="absolute inset-0 bg-gradient-to-b from-[#06101f]/45 via-[#07090d]/45 to-[#07090d]/90" />
        <div className="relative flex min-h-screen flex-col items-center justify-center px-6 py-12 text-center">
          <div className="mb-10 w-full max-w-sm rounded-3xl border border-white/10 bg-[#07090d]/70 p-8 shadow-card backdrop-blur-xl">
            <img src={logo.horizontal} alt="Forge Village" className="mx-auto mb-6 h-auto w-full max-w-[280px] object-contain" />
            <p className="mt-3 text-sm text-slate-300">{loadingMessage}</p>
            <div className="mt-8 h-4 w-full overflow-hidden rounded-full bg-white/10">
              <div className="h-full w-3/4 animate-pulse rounded-full bg-gradient-to-r from-amber-400 via-orange-500 to-rose-500" />
            </div>
          </div>
        </div>
      </div>
    );
  }

  const tabContent = {
    village: <VillagePage game={game} onUpgrade={upgradeBuilding} lang={lang} />,
    missions: <MissionsPage game={game} lang={lang} onClaim={claimMission} languageCode={languageCode} />,
    boss: <BossPage
      game={game}
      lang={lang}
      languageCode={languageCode}
      combat={bossCombat}
      syncing={bossSyncing}
      backendOfficial={backendEnabled}
      onEquipHero={async(heroId,slot)=>{
        if(backendEnabled)return equipHeroMutation.mutateAsync({heroId,slot});
        setGame(current=>{
          if(!current)return current;
          const next=current.bossTeam?.length===5?[...current.bossTeam]:['','','','',''];
          next.forEach((equipped,index)=>{if(equipped===heroId)next[index]='';});
          next[slot-1]=heroId;
          return {...current,bossTeam:next};
        });
        toast.success(translate(languageCode,'heroEquipped'));
      }}
      isEquipping={equipHeroMutation.isPending}
      onClaimReward={async () => {
        if (!telegramInitData || !backendEnabled) return;
        await bossRequest(telegramInitData,'claim'); await refetchBoss(); toast.success(translate(languageCode,'bossDefeated'));
      }}
    />,
    wallet: (
      <WalletPage
        game={game}
        lang={lang}
        telegramInitData={telegramInitData}
        connected={Boolean(wallet)}
        address={wallet?.account.address ?? null}
        onConnect={connectWallet}
        onDisconnect={disconnectWallet}
        isConnecting={tonConnectUI.modalState.status === 'opened'}
        languageCode={languageCode}
      />
    ),
    profile: <ProfilePage game={game} lang={lang} profile={playerProfile} />
  };
  const featuredMission = game.missions.find((mission) => !mission.claimed) ?? game.missions[0];
  const dailyReward = game.missions.find((mission) => mission.id === 'mission-1');
  const calendarDay = calendarDashboard?.currentDay??((Math.max(1, game.loginStreak) - 1) % 30) + 1;
  const calendarRewards=calendarDashboard?.rewards??CALENDAR_REWARDS;

  const changeLanguage = (code: string) => {
    const language = locales[code];
    if (!language) return;
    setLang(language);
    setLanguageCode(code as LanguageCode);
    localStorage.setItem('forge-village-language', code);
    setSettingsOpen(false);
  };
  const t = (key: string) => translate(languageCode, key);

  const collectCalendarDay = (day: number) => {
    if(day!==calendarDay)return;if(backendEnabled){calendarClaimMutation.mutate(day);return}
    if (!dailyReward?.complete || dailyReward.claimed) return;claimMission(dailyReward.id);
  };

  const drawHero = () => {
    const roll = Math.random() * 100;
    let accumulated = 0;
    let rarity: HeroRarity = 'common';
    for (const entry of RARITY_ODDS) {
      accumulated += entry.chance;
      if (roll < accumulated) {
        rarity = entry.rarity;
        break;
      }
    }
    const pool = HERO_CATALOG.filter((hero) => hero.rarity === rarity);
    return pool[Math.floor(Math.random() * pool.length)];
  };

  const recruitHeroes = async (count: number) => {
    if (backendEnabled && telegramInitData && (count === 1 || count === 5 || count === 10)) {
      try {
        const result = await recruitHeroesOnServer(telegramInitData, count);
        setShopResults(result.heroes.map((item) => HERO_CATALOG.find((hero) => hero.id === item.heroKey)).filter((hero): hero is ShopHero => Boolean(hero)));
        await Promise.all([refetchBoss(), refetchGame()]);
      } catch (recruitError) { toast.error(recruitError instanceof Error && recruitError.message === 'NOT_ENOUGH_FC' ? t('notEnoughFc') : String(recruitError)); }
      return;
    }
    const unitPrice = 25_000;
    const cost = unitPrice * count;
    if (game.balance < cost) {
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

  if(activePage==='invites'&&telegramInitData)return <ReferralPage telegramInitData={telegramInitData} languageCode={languageCode} onClose={closeInternal}/>;
  if(activePage==='pets'&&telegramInitData)return <PetsPage telegramInitData={telegramInitData} onClose={closeInternal}/>;
  if(activePage==='pvp'&&telegramInitData)return <PvpPage telegramInitData={telegramInitData} onClose={closeInternal}/>;
  if(activePage==='season-pass'&&telegramInitData)return <SeasonPassPage telegramInitData={telegramInitData} onClose={closeInternal} onMissions={()=>{setActivePage(null);navigateTo('missions')}}/>;
  if(activePage==='pool'&&telegramInitData)return <CommunityPoolPage telegramInitData={telegramInitData} onClose={closeInternal}/>;

  return (
    <div className={`telegram-safe-page relative min-h-screen overflow-x-hidden bg-black text-white ${tab === 'village' ? 'h-[100dvh] overflow-y-hidden' : ''}`}>
      <div className="fixed inset-y-0 left-1/2 w-full max-w-[480px] -translate-x-1/2 bg-cover bg-center" style={{ backgroundImage: `url(${backgrounds.village})` }} />
      <div className={`fixed inset-y-0 left-1/2 w-full max-w-[480px] -translate-x-1/2 bg-gradient-to-b ${tab === 'village' ? 'from-[#06101f]/20 via-transparent to-[#07090d]/90' : 'from-[#06101f]/55 via-[#07090d]/72 to-[#07090d]/95'}`} />
      <div className={`relative mx-auto flex min-h-screen max-w-[480px] flex-col px-3 pb-24 pt-3 shadow-[0_0_80px_rgba(0,0,0,.95)] ${tab === 'village' ? 'h-[100dvh] overflow-hidden' : ''}`}>
        <header className={`main-player-header mb-2 shrink-0 items-center justify-between border-b border-white/10 bg-[#080b10]/75 px-2 py-3 backdrop-blur-md ${tab === 'village' ? 'hidden' : 'flex'}`}>
          <div className="flex min-w-0 items-center gap-2.5">{profileLoading&&!playerProfile?<div className="h-11 w-11 animate-pulse rounded-full bg-white/10"/>:<TelegramAvatar profile={playerProfile}/>}<div className="min-w-0">{playerProfile?<><p className="truncate text-sm font-bold text-white">{getDisplayName(playerProfile)}</p><p className="truncate text-[10px] text-sky-300">{playerProfile.username?`@${playerProfile.username}`:'Sem username'}</p><p className="text-[9px] text-slate-400">ID: {playerProfile.telegramId}</p></>:<><p className="text-sm font-bold">Jogador</p><button type="button" onClick={()=>void refetchProfile()} className="text-[9px] text-amber-300">Tentar novamente</button></>}</div></div>
          <div className="flex items-center gap-2 rounded-xl border border-amber-400/40 bg-black/80 px-3 py-2 text-amber-200 shadow-[inset_0_0_18px_rgba(245,158,11,.08)]">
            <img src={coin} alt="Forge Coin" className="h-9 w-9 object-contain drop-shadow-[0_0_7px_rgba(251,191,36,.45)]" />
            <div className="text-right text-sm">
              <p className="text-base font-bold">{formatCurrency(game.balance)}</p>
              <p className="text-[9px] uppercase tracking-widest text-slate-400">Forge Coins</p>
            </div>
          </div>
        </header>

        {tab === 'village' ? <div className="village-home relative flex min-h-0 flex-1 flex-col items-start gap-2 pb-2 pt-2">
          <div className="absolute right-0 top-2 z-30 flex gap-1.5">
            <div className="flex h-9 items-center gap-1.5 rounded-xl border border-amber-400/25 bg-[#080c13]/90 px-2 text-amber-200 shadow-lg backdrop-blur-md" aria-label={`Saldo: ${formatCurrency(game.balance)} FC`}>
              <img src={coin} alt="FC" className="h-5 w-5 object-contain drop-shadow-[0_0_5px_rgba(251,191,36,.45)]" />
              <span className="max-w-[72px] truncate text-[10px] font-black">{formatCurrency(game.balance)}</span>
            </div>
            <button onClick={() => setNotificationsOpen((open) => !open)} aria-label="Notificações" className="relative grid h-9 w-9 place-items-center rounded-xl border border-white/10 bg-[#080c13]/90 text-amber-200 shadow-lg backdrop-blur-md">
              <Bell className="h-4 w-4" />
              {!dailyReward?.claimed || referralDashboard?.notifications?.length ? <span className="absolute right-1 top-1 h-2 w-2 rounded-full border border-black bg-rose-500" /> : null}
            </button>
            <button onClick={() => setSettingsOpen(true)} aria-label="Configurações" className="grid h-9 w-9 place-items-center rounded-xl border border-white/10 bg-[#080c13]/90 text-slate-200 shadow-lg backdrop-blur-md">
              <Settings className="h-4 w-4" />
            </button>
          </div>
          {notificationsOpen ? (
            <div className="absolute right-0 top-12 z-40 w-56 rounded-2xl border border-white/10 bg-[#080c13]/95 p-3 text-xs shadow-2xl backdrop-blur-xl">
              <p className="font-bold text-white">{t('notifications')}</p>
              <p className="mt-2 text-slate-300">{dailyReward?.claimed ? t('rewardCollected') : t('rewardAvailable')}</p>
              {referralDashboard?.notifications?.slice(0,3).map(item=><div key={item.id} className="mt-2 border-t border-white/10 pt-2"><p className="font-bold text-emerald-300">{item.message}</p><p className="text-[9px] text-slate-400">{item.title}</p></div>)}
            </div>
          ) : null}
          <section className="telegram-profile-card village-profile-card relative w-fit max-w-[285px] overflow-hidden rounded-2xl border border-amber-300/25 px-3 py-2.5 shadow-[0_12px_35px_rgba(0,0,0,.55)]">
            <div className="absolute inset-0 bg-gradient-to-br from-[#101d35]/95 via-[#080d17]/90 to-[#2a1609]/90" />
            <div className="absolute -right-16 -top-16 h-52 w-52 rounded-full bg-amber-500/15 blur-3xl" />
            <div className="relative flex items-center gap-2.5">
              {profileLoading&&!playerProfile?<div className="h-11 w-11 animate-pulse rounded-full bg-white/10"/>:<TelegramAvatar profile={playerProfile}/>}
              <div className="min-w-0">
                <h1 className="truncate text-sm font-black leading-5 text-white">
                  {playerProfile?getDisplayName(playerProfile):'Jogador'}
                </h1>
                <p className="truncate text-[9px] text-sky-300">{playerProfile?.username?`@${playerProfile.username}`:'Sem username'}</p>
                <p className="text-[9px] text-slate-400">ID: {playerProfile?.telegramId??'--'}</p>
                {!playerProfile&&!profileLoading?<button type="button" onClick={()=>void refetchProfile()} className="text-[8px] text-amber-300">Tentar novamente</button>:null}
              </div>
            </div>
          </section>

          <div className="flex w-full items-start justify-between">
            <HomeFeature image={mainScreenArt.dailyStreak} label={t('calendar')} subtitle={dailyReward?.claimed?t('collectedToday'):`${t('day')} ${calendarDay}`} onClick={()=>setCalendarOpen(true)}/>
            <HomeFeature image={mainScreenArt.pool} label="POOL" subtitle="COMUNIDADE" onClick={()=>openInternal('pool')}/>
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
            <HomeFeature image={petDashboard?.activePet?.image||mainScreenArt.pet} label="PET" subtitle={petDashboard?.activePet?`${petDashboard.activePet.name} · Nv. ${petDashboard.activePet.level}`:'Nenhum ativo'} onClick={()=>openInternal('pets')}/>
            <div className="home-feature-placeholder h-[112px] w-[108px]" aria-hidden="true" />
          </div>

          {shopOpen ? (
            <div className="fullscreen-page flex items-center justify-center p-3">
              <div className="max-h-[92dvh] w-full max-w-[450px] overflow-y-auto rounded-[2rem] border border-amber-300/25 bg-[#090d15] p-4 shadow-2xl">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-[10px] uppercase tracking-[0.25em] text-amber-300">{t('shop')}</p>
                    <h2 className="text-xl font-black text-white">{t('recruitment')}</h2>
                  </div>
                  <button onClick={() => setShopOpen(false)} className="grid h-9 w-9 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
                </div>
                <div className="mt-3 flex items-center justify-between rounded-2xl border border-amber-300/15 bg-black/30 px-3 py-2">
                  <span className="text-xs text-slate-400">FC</span>
                  <span className="font-black text-amber-300">{formatCurrency(game.balance)}</span>
                </div>
                <p className="mt-4 text-[10px] uppercase tracking-[0.2em] text-slate-400">{t('odds')}</p>
                <div className="mt-2 grid grid-cols-5 gap-1">
                  {RARITY_ODDS.slice().reverse().map((entry) => (
                    <div key={entry.rarity} className="rounded-xl border border-white/5 bg-white/[.03] px-1 py-2 text-center">
                      <p className="truncate text-[8px] font-bold" style={{ color: RARITY_COLORS[entry.rarity] }}>{t(entry.rarity)}</p>
                      <p className="mt-1 text-[10px] text-white">{entry.chance}%</p>
                    </div>
                  ))}
                </div>
                <div className="mt-4 grid grid-cols-3 gap-2">
                  {[1, 5, 10].map((count) => (
                    <button key={count} onClick={() => recruitHeroes(count)} className="rounded-2xl border border-amber-300/30 bg-gradient-to-b from-amber-400/20 to-orange-600/10 px-2 py-3 text-center">
                      <span className="block text-lg font-black text-white">{count}×</span>
                      <span className="block text-[9px] text-amber-300">{formatCurrency(25_000 * count)} FC</span>
                    </button>
                  ))}
                </div>
                {shopResults.length ? (
                  <div className="mt-4">
                    <p className="text-[10px] uppercase tracking-[0.2em] text-slate-400">{t('latestHeroes')}</p>
                    <div className="mt-2 grid grid-cols-5 gap-1.5">
                      {shopResults.map((hero, index) => (
                        <div key={`${hero.id}-${index}`} className="overflow-hidden rounded-xl border bg-black/50" style={{ borderColor: `${RARITY_COLORS[hero.rarity]}99` }}>
                          <img src={hero.image} alt={hero.name} className="aspect-square w-full object-cover" />
                          <p className="truncate px-1 py-1 text-center text-[7px] font-bold" style={{ color: RARITY_COLORS[hero.rarity] }}>{t(hero.rarity)}</p>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : null}
              </div>
            </div>
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
                <div className="mt-4 grid grid-cols-5 gap-2">
                  {Array.from({ length: 30 }, (_, index) => {
                    const day = index + 1;
                    const reward=calendarRewards.find(item=>item.day===day);const past = calendarDashboard?.claimedDays.includes(day)??day < calendarDay;
                    const current = day === calendarDay;
                    const collected = past||(current&&(calendarDashboard?!calendarDashboard.canClaim:Boolean(dailyReward?.claimed)));
                    const chestIndex=reward?.itemCode==='hero_chest_special'?2:reward?.itemCode==='hero_chest_improved'?1:0;
                    return (
                      <button
                        key={day}
                        onClick={() => collectCalendarDay(day)}
                        disabled={!current || Boolean(collected)||calendarClaimMutation.isPending}
                        className={`aspect-square rounded-xl border p-1 text-center transition ${past || collected ? 'border-emerald-400/25 bg-emerald-500/10 text-emerald-300' : current ? 'border-amber-300 bg-amber-400/15 text-amber-200 shadow-[0_0_15px_rgba(251,191,36,.2)]' : 'border-white/5 bg-white/[.03] text-slate-600'}`}
                      >
                        <span className="block text-[8px] font-black">DIA {day}</span>
                        {reward?.type==='fc'?<img src={coin} alt="FC" className="mx-auto h-5 w-5 object-contain"/>:reward?.type==='hero_chest'?<img src={chests[chestIndex]} alt="Baú" className="mx-auto h-5 w-5 object-contain"/>:<img src={`/assets/game/pet-eggs/${reward?.itemCode}.webp`} alt="Ovo" className="mx-auto h-5 w-5 object-contain"/>}
                        <span className="block truncate text-[6px]">{collected?'OK':!current?'🔒':reward?.type==='fc'?`${(reward.amountFc??0)/1000}K FC`:reward?.type==='hero_chest'?'BAÚ':'OVO'}</span>
                      </button>
                    );
                  })}
                </div>
                <p className="mt-3 text-center text-[10px] text-slate-400">{t('selectDay')}</p>
              </div>
            </div>
          ) : null}

          {calendarResult?<div className="fixed inset-0 z-[65] grid place-items-center bg-black/80 p-5"><div className="w-full max-w-sm rounded-3xl border border-amber-300/30 bg-[#090d15] p-6 text-center"><p className="text-[10px] tracking-[.25em] text-amber-300">RECOMPENSA COLETADA</p><h2 className="mt-2 text-2xl font-black">Dia {calendarResult.reward.day}</h2><p className="mt-3 text-lg text-amber-100">{calendarResult.reward.title}{calendarResult.reward.subtitle?` · ${calendarResult.reward.subtitle}`:''}</p>{calendarResult.reward.type==='fc'?<p className="mt-2 text-emerald-300">Novo saldo: {formatCurrency(calendarResult.balance)} FC</p>:<p className="mt-2 text-slate-300">Item guardado no inventário.</p>}<div className="mt-5 grid grid-cols-2 gap-2">{calendarResult.reward.type==='pet_egg'?<button type="button" onClick={()=>{setCalendarResult(null);setCalendarOpen(false);setPetsOpen(true)}} className="rounded-xl bg-amber-400 py-3 font-black text-black">IR PARA PETS</button>:calendarResult.reward.type==='hero_chest'?<button type="button" disabled={!calendarResult.inventoryItemId||calendarChestMutation.isPending} onClick={()=>calendarResult.inventoryItemId&&calendarChestMutation.mutate(calendarResult.inventoryItemId)} className="rounded-xl bg-amber-400 py-3 font-black text-black disabled:opacity-50">{calendarChestMutation.isPending?'ABRINDO...':'ABRIR AGORA'}</button>:<span/>}<button type="button" onClick={()=>setCalendarResult(null)} className="rounded-xl border border-white/15 py-3 font-bold">{calendarResult.reward.type==='fc'?'CONTINUAR':'GUARDAR'}</button></div></div></div>:null}

          {settingsOpen ? (
            <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-sm">
              <div className="w-full max-w-sm rounded-[2rem] border border-white/10 bg-[#090d15] p-5 shadow-2xl">
                <div className="flex items-center justify-between">
                  <h2 className="text-lg font-black">{t('settings')}</h2>
                  <button onClick={() => setSettingsOpen(false)} className="grid h-9 w-9 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
                </div>
                <p className="mt-5 text-[10px] uppercase tracking-[0.25em] text-slate-400">{t('language')}</p>
                <div className="mt-2 grid grid-cols-2 gap-2">
                  {[['pt', 'Português'], ['en', 'English'], ['es', 'Español'], ['ru', 'Русский']].map(([code, label]) => (
                    <button key={code} onClick={() => changeLanguage(code)} className="rounded-xl border border-white/10 bg-white/5 px-3 py-3 text-sm text-white hover:border-amber-300/40 hover:bg-amber-400/10">{label}</button>
                  ))}
                </div>
              </div>
            </div>
          ) : null}

          <div className="hidden">
        <img src={logo.horizontal} alt="Forge Village" className="main-game-logo relative z-10 mx-auto -mb-3 mt-0 h-auto w-full max-w-[280px] shrink-0 drop-shadow-[0_12px_20px_rgba(0,0,0,0.8)]" />

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
              <span>🔥 {game.loginStreak} {lang.loginStreak.toLowerCase()}</span>
              <span className="text-slate-600">•</span>
              <span>{formatCurrency(storageCapacity)} FC max.</span>
            </div>
          </div>
        </section>

        {featuredMission ? (
          <section className="village-cards mb-1 grid h-[112px] shrink-0 grid-cols-2 gap-2">
            <div className="relative overflow-hidden rounded-3xl border border-white/10 bg-forge-black/85 p-4 shadow-card">
              <img src={mainScreenArt.dailyStreak} alt="" className="pointer-events-none absolute -right-3 -top-2 h-24 w-24 object-contain opacity-55" />
              <p className="relative text-[10px] uppercase tracking-[0.22em] text-slate-400">{lang.loginStreak}</p>
              <p className="relative mt-2 text-3xl font-black text-amber-300">{game.loginStreak} dias</p>
              <div className="mt-3 flex gap-1">
                {Array.from({ length: 7 }, (_, index) => (
                  <span key={index} className={`h-2 flex-1 rounded-full ${index < game.loginStreak ? 'bg-amber-400' : 'bg-white/10'}`} />
                ))}
              </div>
              <p className="relative mt-2 text-[11px] text-slate-400">Continue entrando todos os dias</p>
            </div>
            <button
              onClick={() => featuredMission.complete ? claimMission(featuredMission.id) : navigateTo('missions')}
              className="relative overflow-hidden rounded-3xl border border-white/10 bg-forge-black/85 p-4 text-left shadow-card"
            >
              <img src={mainScreenArt.missionIngots} alt="" className="pointer-events-none absolute -bottom-2 -right-4 h-24 w-24 object-contain opacity-55" />
              <p className="relative text-[10px] uppercase tracking-[0.18em] text-slate-300">Missão em destaque</p>
              <p className="relative mt-2 line-clamp-2 pr-9 text-sm font-bold text-white">{featuredMission.title}</p>
              <p className="relative mt-3 text-xs font-bold text-emerald-400">+{formatCurrency(featuredMission.reward)} FC</p>
              <p className="relative mt-1 text-[10px] text-amber-300">{featuredMission.complete ? 'TOQUE PARA RESGATAR' : 'VER MISSÕES →'}</p>
            </button>
          </section>
        ) : null}
          </div>
        </div> : null}

        {tab !== 'village' ? tabContent[tab] : null}
      </div>


      {!activePage?<nav className="telegram-safe-nav fixed bottom-0 left-0 right-0 border-t border-white/10 bg-forge-black/95 px-4 py-3 backdrop-blur-xl">
        <div className="mx-auto flex max-w-[480px] items-center justify-between">
          {navItems.map((item) => (
            <button
              key={item.key}
              onClick={() => navigateTo(item.key)}
              className={`flex min-w-[0] flex-1 flex-col items-center justify-center rounded-3xl px-2 py-2 text-xs transition ${tab === item.key ? 'bg-amber-500/15 text-amber-200' : 'text-slate-400 hover:text-white'}`}
            >
              <img src={tab === item.key ? navigationIcons[item.key].selected : navigationIcons[item.key].normal} alt="" className="h-7 w-7 object-contain" />
              <span className="mt-1">{item.label}</span>
            </button>
          ))}
        </div>
      </nav>:null}
    </div>
  );
}

export default App;
