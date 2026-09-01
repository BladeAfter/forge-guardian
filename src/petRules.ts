export type PetRarity='common'|'uncommon'|'rare'|'epic'|'legendary'|'mythic'|'ancestral'|'exclusive'|'nft_exclusive';
export type PetBonusKey='boss_damage_percent'|'pvp_attack_percent'|'team_hp_percent'|'pvp_defense_percent'|'critical_chance_percent'|'pvp_speed_percent'|'reward_percent'|'revive_speed_percent'|'boss_damage_reduction_percent'|'defense_percent'|'farm_fc_percent'|'offline_production_percent'|'mission_reward_percent'|'drop_chance_percent'|'egg_luck_percent'|'random_reward_percent'|'hero_xp_percent'|'account_xp_percent'|'mission_progress_percent';
/** Official rarity hierarchy — mirrors public.pet_rarity_config (single source of truth is the backend). */
export const PET_RARITY_ORDER:Record<PetRarity,number>={common:1,uncommon:2,rare:3,epic:4,legendary:5,mythic:6,ancestral:7,exclusive:8,nft_exclusive:9};
export const PET_RARITY_MULTIPLIER:Record<PetRarity,number>={common:1,uncommon:1.25,rare:1.6,epic:2.1,legendary:2.8,mythic:3.2,ancestral:3.6,exclusive:3.9,nft_exclusive:4.2};
/** Official base power per rarity: a superior rarity is ALWAYS stronger at the same level/stage. */
export const PET_RARITY_POWER:Record<PetRarity,number>={common:10000,uncommon:11500,rare:13500,epic:16000,legendary:19000,mythic:22500,ancestral:27000,exclusive:31000,nft_exclusive:35000};
export const PET_EVOLUTION_RARITY_MULTIPLIER:Record<PetRarity,number>={common:1,uncommon:1.25,rare:1.6,epic:2.2,legendary:3.2,mythic:3.8,ancestral:4.5,exclusive:4.9,nft_exclusive:5.2};
export const PET_BONUS_CAPS:Partial<Record<PetBonusKey,number>>={boss_damage_percent:60,boss_damage_reduction_percent:45,team_hp_percent:60,pvp_attack_percent:60,pvp_defense_percent:60,pvp_speed_percent:30,defense_percent:60,critical_chance_percent:30,reward_percent:40,mission_reward_percent:30,random_reward_percent:30,drop_chance_percent:30,egg_luck_percent:30,farm_fc_percent:45,offline_production_percent:45,hero_xp_percent:45,account_xp_percent:45,revive_speed_percent:80,mission_progress_percent:30};
export const PET_MAX_LEVEL=50;
export function normalizePetRarity(rarity?:string|null):PetRarity{const value=String(rarity??'common').trim().toLowerCase();return ({common:'common',comum:'common',uncommon:'uncommon',incomum:'uncommon',rare:'rare',raro:'rare',rara:'rare',epic:'epic',epico:'epic','épico':'epic',epica:'epic','épica':'epic',legendary:'legendary',mythic:'mythic',mitico:'mythic','mítico':'mythic',lendario:'legendary','lendário':'legendary',lendaria:'legendary','lendária':'legendary',ancestral:'ancestral',exclusive:'exclusive',exclusivo:'exclusive',exclusiva:'exclusive',nft_exclusive:'nft_exclusive','nft-exclusive':'nft_exclusive','nft exclusive':'nft_exclusive',nft:'nft_exclusive',nft_exclusivo:'nft_exclusive','nft exclusivo':'nft_exclusive'} as Record<string,PetRarity>)[value]??'common'}
const clampLevel=(level:number)=>Math.min(PET_MAX_LEVEL,Math.max(1,Math.floor(Number.isFinite(level)?level:1)));
/** Visual form: one new form every 10 levels (0 = base form … 5 = final form). */
export function petVisualStage(level:number){return Math.min(5,Math.max(0,Math.floor(clampLevel(level)/10)))}
/**
 * Growth points = level milestones (every 10 levels) PLUS evolution tiers. Both ALWAYS add up,
 * so crossing level 10/20/30/40/50 raises the stats even for an already evolved pet.
 */
export function petStageIndex(level:number,tier=0){return Math.min(10,petVisualStage(level)+Math.min(5,Math.max(0,Math.floor(Number.isFinite(tier)?tier:0))))}
export function petStagePowerMultiplier(stage:number){return 1+.08*Math.min(10,Math.max(0,Math.floor(stage)))}
export function petStageBuffMultiplier(stage:number){return 1+.10*Math.min(10,Math.max(0,Math.floor(stage)))}
export function petLevelMultiplier(level:number){return 1+(clampLevel(level)-1)*.02}
/**
 * Official buff formula — mirrors public.pet_effective_buff: rarity multiplier applied to the
 * original base, base limitada ao teto normal (nível 1 nunca perde valor) e o crescimento pode ir até 1.5x o teto.
 */
export const PET_MAX_BUFF_GROWTH=petStageBuffMultiplier(10)*(1+(PET_MAX_LEVEL-1)*.005);
export function calculatePetBonus(base:number,rarity:string,level:number,key?:PetBonusKey,stage=0){if(!Number.isFinite(base)||base<=0)return 0;const growth=petStageBuffMultiplier(stage)*(1+(clampLevel(level)-1)*.005);const cap=key?PET_BONUS_CAPS[key]:undefined;let scaled=base*PET_RARITY_MULTIPLIER[normalizePetRarity(rarity)];if(cap&&cap>0){scaled=Math.min(scaled,cap);return Number(Math.min(scaled*growth,cap*1.5,150).toFixed(2))}return Number(Math.min(scaled*growth,150).toFixed(2))}

/** Official power formula, mirroring public.pet_instance_power. */
export function petPower(rarity:string,level:number,passives:Record<string,number>,tier=0){const lvl=clampLevel(level),stage=petStageIndex(lvl,tier),total=Object.values(passives).filter(Number.isFinite).reduce((a,b)=>a+b,0);return Math.round(PET_RARITY_POWER[normalizePetRarity(rarity)]*(1+(lvl-1)*.05)*petStagePowerMultiplier(stage)+Math.min(total,200)*2)}
export function levelCostFc(level:number){return Math.round(1000*Math.pow(Math.max(1,level),1.45))}
export function calculatePetEvolutionCostFc(currentLevel:number,rarity:string){const level=Math.max(1,Math.floor(Number.isFinite(currentLevel)?currentLevel:1)),multiplier=PET_EVOLUTION_RARITY_MULTIPLIER[normalizePetRarity(rarity)];return Math.ceil(2500*Math.pow(level,1.45)*multiplier/100)*100}
export function canPetEvolve(level:number,currentXp:number){return level<PET_MAX_LEVEL&&Number.isFinite(currentXp)&&currentXp>=xpRequired(level)}
export function foodCost(level:number){return Math.ceil(Math.max(1,level)/3)}
export function fragmentCost(level:number){return level>=10?Math.ceil(level/5):0}
export function xpRequired(level:number){return Math.round(250*Math.pow(Math.max(1,level),1.35))}
export function applyEligibleBonus(base:number,percent:number,eligible=true){if(!Number.isFinite(base)||base<0||!Number.isFinite(percent))return 0;return eligible?Math.floor(base*(1+Math.max(0,percent)/100)):Math.floor(base)}
export function evolutionStage(level:number){return level>=30?'ancestral':level>=20?'adult':level>=10?'young':'baby'}
export function activateOnlyPet<T extends{id:string;isActive:boolean}>(pets:T[],id:string){return pets.map(p=>({...p,isActive:p.id===id}))}
export function canTriggerPetSkill(turn:number,cooldown:number,lastTriggeredTurn:number){return Number.isInteger(turn)&&cooldown>0&&turn-lastTriggeredTurn>=cooldown}
export function canPhoenixRevive(alreadyUsed:boolean,defeatedHeroes:number){return!alreadyUsed&&defeatedHeroes>0}
export function deterministicPercent(seed:string){let hash=2166136261;for(let i=0;i<seed.length;i++){hash^=seed.charCodeAt(i);hash=Math.imul(hash,16777619)}return(hash>>>0)/4294967296*100}
