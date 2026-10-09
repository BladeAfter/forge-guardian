import pirateHarborVillage from './assets/pirate-harbor-village.jpg';
import pirateLoading from './assets/pirate-loading.jpg';
import pirateBossArena from './assets/pirate-boss-arena.jpg';
import pirateVillageIcon from './assets/icons/pirate-village.png';
import pirateMarketIcon from './assets/icons/pirate-market.png';
import pirateBossIcon from './assets/icons/pirate-boss.png';
import pirateWalletIcon from './assets/icons/pirate-wallet.png';
import pirateProfileIcon from './assets/icons/pirate-profile.png';
import pirateRealmIcon from './assets/home-icons/pirate-realm.png';
import piratePoolIcon from './assets/home-icons/pirate-pool.png';
import pirateHeroShopIcon from './assets/home-icons/pirate-hero-shop.png';
import pirateSeasonPassIcon from './assets/home-icons/pirate-season-pass.png';
import pirateInviteIcon from './assets/home-icons/pirate-invite.png';
import piratePvpIcon from './assets/home-icons/pirate-pvp.png';
import piratePetIcon from './assets/home-icons/pirate-pet.png';
import pirateHeroesIcon from './assets/home-icons/pirate-heroes.png';
import pirateBerryCoin from './assets/pirate-berry-coin.png';
import { voyageHeroArt } from './voyageArt';
import pirateRecruitHarbor from './assets/pirate-recruit-harbor.jpg';
import pirateBerryStack from './assets/pirate-berry-stack.png';
import pirateTonCompass from './assets/pirate-ton-compass.png';
import recruitAdventurer from './assets/recruit-adventurer.jpg';
import recruitCrew from './assets/recruit-crew.jpg';
import recruitFleet from './assets/recruit-fleet.jpg';
import pirateCaptainProfile from './assets/pirate-captain-profile.jpg';
import pirateMarketPort from './assets/pirate-market-port.jpg';

export const marketArt = { port: pirateMarketPort, chest: recruitFleet, hero: voyageHeroArt.deckblade, pet: piratePetIcon };

export const profileArt = { deck: pirateCaptainProfile, captain: pirateProfileIcon, pass: pirateSeasonPassIcon, treasure: pirateBerryStack };

export const recruitmentArt = { harbor: pirateRecruitHarbor, contracts: { 1: recruitAdventurer, 5: recruitCrew, 10: recruitFleet } };
export const balanceArt = { berries: pirateBerryStack, ton: pirateTonCompass };

const gameAsset = (path: string) => `/assets/game/${path}`;

export const backgrounds = {
  loading: pirateLoading,
  village: pirateHarborVillage,
  boss: pirateBossArena
};

export const buildings: Record<string, string> = {
  'iron-mine': gameAsset('buildings/iron-mine.png'),
  'coal-mine': gameAsset('buildings/coal-mine.png'),
  forge: gameAsset('buildings/forge.png'),
  'royal-workshop': gameAsset('buildings/royal-workshop.png'),
  'dragon-foundry': gameAsset('buildings/dragon-foundry.png'),
  'clan-hall': gameAsset('buildings/mythreon-clan-hall.png')
};

export const characters = {
  novice: gameAsset('characters/novice-blacksmith.png'),
  master: gameAsset('characters/master-blacksmith.png'),
  merchant: gameAsset('characters/merchant.png'),
  knight: gameAsset('characters/knight.png'),
  king: gameAsset('characters/king.png')
};

export const mainScreenArt = {
  avatar: gameAsset('characters/blacksmith-avatar.webp'),
  villageLevel: gameAsset('ui/village-level-crest.webp'),
  dailyStreak: gameAsset('ui/daily-streak.webp'),
  missionIngots: gameAsset('ui/mission-ingots.webp'),
  productionAnvil: gameAsset('ui/production-anvil.webp'),
  forgeTower: gameAsset('buildings/main-forge-tower.webp'),
  realm: pirateRealmIcon,
  heroShop: pirateHeroShopIcon,
  pool: piratePoolIcon,
  pvp: piratePvpIcon,
  invite: pirateInviteIcon,
  pet: piratePetIcon,
  heroes: pirateHeroesIcon,
  market: gameAsset('ui/player-market.png'),
  seasonPass: pirateSeasonPassIcon
};

export const missionIcons = [
  gameAsset('icons/daily-login-icon.png'),
  gameAsset('icons/collect-production-icon.png'),
  gameAsset('icons/upgrade-building-icon.png'),
  gameAsset('icons/attack-boss-icon.png'),
  gameAsset('icons/watch-ad-icon.png'),
  gameAsset('icons/invite-friend-icon.png')
];

export const navigationIcons: Record<string, { normal: string; selected: string }> = {
  village: { normal: pirateVillageIcon, selected: pirateVillageIcon },
  market: { normal: pirateMarketIcon, selected: pirateMarketIcon },
  missions: { normal: gameAsset('icons/missions-icon.png'), selected: gameAsset('icons/missions-icon-selected.png') },
  boss: { normal: pirateBossIcon, selected: pirateBossIcon },
  wallet: { normal: pirateWalletIcon, selected: pirateWalletIcon },
  profile: { normal: pirateProfileIcon, selected: pirateProfileIcon }
};

export const logo = {
  horizontal: gameAsset('logo/forge-village-logo.png'),
  icon: gameAsset('logo/forge-village-icon.png')
};

export const coin = pirateBerryCoin;
/** MYTH Token art (decorative only — no price, no trading, no utility yet). */
export const mythToken = gameAsset('coins/myth-token.png');
export const mythTokenCard = gameAsset('ui/myth-token-card.jpg');
export const dragon = gameAsset('bosses/ancient-dragon.png');

export const bossHeroes = [
  { id: 'common', name: 'Espadachim', rarity: 'Comum', damage: 0.15, color: '#94a3b8', image: voyageHeroArt.deckblade },
  { id: 'uncommon', name: 'Arqueira', rarity: 'Incomum', damage: 0.25, color: '#4ade80', image: voyageHeroArt.starshot },
  { id: 'rare', name: 'Guardião', rarity: 'Raro', damage: 0.4, color: '#60a5fa', image: voyageHeroArt.anchorward },
  { id: 'epic', name: 'Maga Rúnica', rarity: 'Épico', damage: 0.7, color: '#c084fc', image: voyageHeroArt.tempestcall },
  { id: 'legendary', name: 'Cavaleiro Dragão', rarity: 'Lendário', damage: 1.2, color: '#fbbf24', image: voyageHeroArt.dawncaptain }
] as const;

export const chests = [
  gameAsset('chests/common-chest.png'),
  gameAsset('chests/rare-chest.png'),
  gameAsset('chests/epic-chest.png'),
  gameAsset('chests/legendary-chest.png')
];
