import type{HeroRarity}from'./combat';import type{HeroArchetype}from'./pvpRules';
export type PvpHero={heroId:string;name:string;imageUrl:string;rarity:HeroRarity;level:number;archetype:HeroArchetype;finalAtk:number;finalHp:number;defense:number;speed:number;power:number;slot?:number};
export type PvpHistory={id:string;opponentName:string;result:'win'|'loss';turns:number;trophyChange:number;rewardFc:number;createdAt:string};
export type PvpRank={position:number;id:string;name:string;username?:string|null;avatarUrl:string|null;trophies:number;league:string;wins:number};
export type PvpDashboard={userId:string;trophies:number;league:string;tickets:number;wins:number;losses:number;attackTeam:PvpHero[];defenseTeam:PvpHero[];teamPower:number;ownedHeroes:PvpHero[];history:PvpHistory[];ranking:PvpRank[]};
export type PvpOpponent={userId:string;name:string;username?:string|null;avatarUrl:string|null;trophies:number;league:string;teamPower:number;wins:number;defenseTeam:PvpHero[]};
export type PvpBattleResult={battleId:string;result:'attacker_win'|'defender_win';winnerId:string;totalTurns:number;rewardFc:number;trophyChange:number;battleLog:Array<{turn:number;side:string;attackerId:string;targetId:string;damage:number;remainingHp:number}>;attackerState:PvpHero[];defenderState:PvpHero[]};
