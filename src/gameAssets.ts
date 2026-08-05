const gameAsset = (path: string) => `/assets/game/${path}`;

export const backgrounds = {
  loading: gameAsset('backgrounds/loading-background.webp'),
  village: gameAsset('backgrounds/village-background.webp'),
  boss: gameAsset('backgrounds/boss-battle-background.webp')
};

export const buildings: Record<string, string> = {
  'iron-mine': gameAsset('buildings/iron-mine.png'),
  'coal-mine': gameAsset('buildings/coal-mine.png'),
  forge: gameAsset('buildings/forge.png'),
  'royal-workshop': gameAsset('buildings/royal-workshop.png'),
  'dragon-foundry': gameAsset('buildings/dragon-foundry.png')
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
  heroShop: gameAsset('ui/hero-shop.webp'),
  pool: gameAsset('ui/pvp.webp'),
  pvp: gameAsset('ui/pool.webp'),
  invite: gameAsset('ui/invite-referral.webp'),
  pet: gameAsset('pets/pyron.webp')
  ,seasonPass: gameAsset('ui/season-pass-icon.png')
};

export const missionIcons = [
  gameAsset('icons/daily-login-icon.png'),
  gameAsset('icons/collect-production-icon.png'),
  gameAsset('icons/upgrade-building-icon.png'),
  gameAsset('icons/attack-boss-icon.png'),
  gameAsset('icons/watch-ad-icon.png'),
  gameAsset('icons/invite-friend-icon.png')
];

export const navigationIcons: Record<string, { normal: string; selected: string }> = Object.fromEntries(
  ['village', 'missions', 'boss', 'wallet', 'profile'].map((name) => [name, {
    normal: gameAsset(`icons/${name}-icon.png`),
    selected: gameAsset(`icons/${name}-icon-selected.png`)
  }])
);

export const logo = {
  horizontal: gameAsset('logo/forge-village-logo.png'),
  icon: gameAsset('logo/forge-village-icon.png')
};

export const coin = gameAsset('coins/forge-coin.png');
export const dragon = gameAsset('bosses/ancient-dragon.png');

export const bossHeroes = [
  { id: 'common', name: 'Espadachim', rarity: 'Comum', damage: 0.15, color: '#94a3b8', image: gameAsset('heroes/common-warrior.png') },
  { id: 'uncommon', name: 'Arqueira', rarity: 'Incomum', damage: 0.25, color: '#4ade80', image: gameAsset('heroes/uncommon-archer.png') },
  { id: 'rare', name: 'Guardião', rarity: 'Raro', damage: 0.4, color: '#60a5fa', image: gameAsset('heroes/rare-guardian.png') },
  { id: 'epic', name: 'Maga Rúnica', rarity: 'Épico', damage: 0.7, color: '#c084fc', image: gameAsset('heroes/epic-mage.png') },
  { id: 'legendary', name: 'Cavaleiro Dragão', rarity: 'Lendário', damage: 1.2, color: '#fbbf24', image: gameAsset('heroes/legendary-dragon-knight.png') }
] as const;

export const chests = [
  gameAsset('chests/common-chest.png'),
  gameAsset('chests/rare-chest.png'),
  gameAsset('chests/epic-chest.png'),
  gameAsset('chests/legendary-chest.png')
];
