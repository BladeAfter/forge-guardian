export type PetRarity='common'|'uncommon'|'rare'|'epic'|'legendary';
export type PetBonusKey='boss_damage_percent'|'pvp_attack_percent'|'team_hp_percent'|'pvp_defense_percent'|'critical_chance_percent'|'pvp_speed_percent'|'reward_percent'|'revive_speed_percent'|'boss_damage_reduction_percent'|'defense_percent'|'farm_fc_percent'|'offline_production_percent'|'mission_reward_percent'|'drop_chance_percent'|'egg_luck_percent'|'random_reward_percent'|'hero_xp_percent'|'account_xp_percent'|'mission_progress_percent';
export const PET_RARITY_MULTIPLIER:Record<PetRarity,number>={common:1,uncommon:1.25,rare:1.6,epic:2.1,legendary:2.8};
export const PET_RARITY_POWER:Record<PetRarity,number>={common:500,uncommon:1000,rare:2000,epic:4000,legendary:8000};
export const PET_EVOLUTION_RARITY_MULTIPLIER:Record<PetRarity,number>={common:1,uncommon:1.25,rare:1.6,epic:2.2,legendary:3.2};
export const PET_BONUS_CAPS:Partial<Record<PetBonusKey,number>>={boss_damage_percent:20,farm_fc_percent:15,critical_chance_percent:10,pvp_speed_percent:10,team_hp_percent:20,pvp_defense_percent:20,defense_percent:20,reward_percent:10,mission_reward_percent:10,random_reward_percent:10,drop_chance_percent:10,egg_luck_percent:10,hero_xp_percent:15,account_xp_percent:15};
export function normalizePetRarity(rarity?:string|null):PetRarity{const value=String(rarity??'common').trim().toLowerCase();return ({common:'common',comum:'common',uncommon:'uncommon',incomum:'uncommon',rare:'rare',raro:'rare',rara:'rare',epic:'epic',epico:'epic','épico':'epic',epica:'epic','épica':'epic',legendary:'legendary',lendario:'legendary','lendário':'legendary',lendaria:'legendary','lendária':'legendary'} as Record<string,PetRarity>)[value]??'common'}
export function petLevelMultiplier(level:number){return 1+(Math.min(30,Math.max(1,Math.floor(Number.isFinite(level)?level:1)))-1)*.02}
export function calculatePetBonus(base:number,rarity:string,level:number,key?:PetBonusKey){if(!Number.isFinite(base)||base<0)return 0;const raw=base*PET_RARITY_MULTIPLIER[normalizePetRarity(rarity)]*petLevelMultiplier(level);const cap=key?PET_BONUS_CAPS[key]:undefined;return Number(Math.min(raw,cap??raw).toFixed(2))}
export function petPower(rarity:string,level:number,passives:Record<string,number>){const safe=Math.min(30,Math.max(1,Math.floor(level)));const total=Object.values(passives).filter(Number.isFinite).reduce((a,b)=>a+b,0);return Math.round(PET_RARITY_POWER[normalizePetRarity(rarity)]+safe*100+total*250)}
export function levelCostFc(level:number){return Math.round(1000*Math.pow(Math.max(1,level),1.45))}
export function calculatePetEvolutionCostFc(currentLevel:number,rarity:string){const level=Math.max(1,Math.floor(Number.isFinite(currentLevel)?currentLevel:1)),multiplier=PET_EVOLUTION_RARITY_MULTIPLIER[normalizePetRarity(rarity)];return Math.ceil(2500*Math.pow(level,1.45)*multiplier/100)*100}
export function canPetEvolve(level:number,currentXp:number){return level<30&&Number.isFinite(currentXp)&&currentXp>=xpRequired(level)}
export function foodCost(level:number){return Math.ceil(Math.max(1,level)/3)}
export function fragmentCost(level:number){return level>=10?Math.ceil(level/5):0}
export function xpRequired(level:number){return Math.round(250*Math.pow(Math.max(1,level),1.35))}
export function applyEligibleBonus(base:number,percent:number,eligible=true){if(!Number.isFinite(base)||base<0||!Number.isFinite(percent))return 0;return eligible?Math.floor(base*(1+Math.max(0,percent)/100)):Math.floor(base)}
export function evolutionStage(level:number){return level>=30?'ancestral':level>=20?'adult':level>=10?'young':'baby'}
export function activateOnlyPet<T extends{id:string;isActive:boolean}>(pets:T[],id:string){return pets.map(p=>({...p,isActive:p.id===id}))}
export function canTriggerPetSkill(turn:number,cooldown:number,lastTriggeredTurn:number){return Number.isInteger(turn)&&cooldown>0&&turn-lastTriggeredTurn>=cooldown}
export function canPhoenixRevive(alreadyUsed:boolean,defeatedHeroes:number){return!alreadyUsed&&defeatedHeroes>0}
export function deterministicPercent(seed:string){let hash=2166136261;for(let i=0;i<seed.length;i++){hash^=seed.charCodeAt(i);hash=Math.imul(hash,16777619)}return(hash>>>0)/4294967296*100}
