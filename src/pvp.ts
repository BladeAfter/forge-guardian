import type{HeroRarity}from'./combat';import type{HeroArchetype}from'./pvpRules';
export type PvpHero={heroId:string;name:string;imageUrl:string;rarity:HeroRarity;level:number;archetype:HeroArchetype;finalAtk:number;finalHp:number;defense:number;speed:number;power:number;stars?:number;locked?:boolean;heroKey?:string;slot?:number};
export type PvpHistory={id:string;opponentName:string;isBot?:boolean;result:'win'|'loss';turns:number;trophyChange:number;rewardFc:number;createdAt:string};
export type PvpRank={position:number;id:string;name:string;username?:string|null;avatarUrl:string|null;trophies:number;league:string;wins:number};
export type PvpTicketPack={tickets:number;priceFc:number};
export type PvpAdsState={enabled:boolean;blockId:string|null;dailyLimit:number;watchedToday:number;remaining:number;cycleDate?:string;interstitialEnabled:boolean;interstitialBlockId:string|null};
export type PvpTicketShop={dailyLimit:number;boughtToday:number;remaining:number;passTier:string|null;hasPass:boolean;freeLimit:number;passLimit:number;packs:PvpTicketPack[]};
export type PvpDashboard={userId:string;trophies:number;league:string;tickets:number;wins:number;losses:number;attackTeam:PvpHero[];defenseTeam:PvpHero[];teamPower:number;ownedHeroes:PvpHero[];history:PvpHistory[];ranking:PvpRank[];ticketShop?:PvpTicketShop;adsShop?:PvpAdsState};

export type PvpOpponent={userId:string;name:string;username?:string|null;avatarUrl:string|null;isBot?:boolean;avatarLetter?:string;avatarColor?:string;strategy?:string;trophies:number;league:string;teamPower:number;wins:number;defenseTeam:PvpHero[]};
export type PvpBattleResult={battleId:string;result:'attacker_win'|'defender_win';winnerId:string|null;isBotBattle?:boolean;totalTurns:number;rewardFc:number;trophyChange:number;battleLog:Array<{turn:number;side:string;attackerId:string;targetId:string;damage:number;remainingHp:number}>;attackerState:PvpHero[];defenderState:PvpHero[]};
