import type {PetRarity} from './petRules';
export type PetPassives=Record<string,number>;
export type PetCatalogItem={id:string;name:string;slug:string;species:string;category:string;description:string;basePassives:PetPassives;activeSkill:Record<string,unknown>|null;images:Record<'baby'|'young'|'adult'|'ancestral',string>;discovered:boolean;bestRarity:PetRarity|null;bestLevel:number|null};
export type PlayerPet={id:string;petId:string;name:string;slug:string;species:string;category:string;rarity:PetRarity;level:number;xp:number;xpRequired:number;canEvolve:boolean;evolutionCostFc:number;isMaxLevel:boolean;evolutionStage:string;fragments:number;isActive:boolean;image:string;passives:PetPassives;power:number;activeSkill:Record<string,unknown>|null};
export type PetEgg={id:string;name:string;slug:string;image:string;priceFc:number|null;priceTon:number|null;quantity:number;rarityRates:Record<string,number>;isPurchasable?:boolean;premiumOnly?:boolean;dailyQuantity?:number|null;perPlayerLimit?:number|null;availabilityLabel?:string|null};
export type PetInventory={food:number;universalFragments:number};
export type PetHistory={id:string;eggName:string;petName:string|null;rarity:PetRarity|null;duplicateFragments:number;createdAt:string};
export type PetDashboard={activePet:PlayerPet|null;playerPets:PlayerPet[];catalog:PetCatalogItem[];eggs:PetEgg[];inventory:PetInventory;history:PetHistory[];bonuses:PetPassives;balance:number};

export type MythicPetDefinition={slug:string;name:string;species:string;image:string;rarity:'legendary';eggTier:'mythic';weight:number};
export const MYTHIC_PET_CATALOG:readonly MythicPetDefinition[]=[
  {slug:'mythic-aetherion',name:'Aetherion',species:'Leão-Dragão Celestial',image:'/assets/game/pets/mythic/aetherion.png',rarity:'legendary',eggTier:'mythic',weight:20},
  {slug:'mythic-nymbrak',name:'Nymbrak',species:'Urso Rúnico de Obsidiana',image:'/assets/game/pets/mythic/nymbrak.png',rarity:'legendary',eggTier:'mythic',weight:20},
  {slug:'mythic-sylvaris',name:'Sylvaris',species:'Serpe-Cervo Ancestral',image:'/assets/game/pets/mythic/sylvaris.png',rarity:'legendary',eggTier:'mythic',weight:20},
  {slug:'mythic-zephyrax',name:'Zephyrax',species:'Grifo da Tempestade',image:'/assets/game/pets/mythic/zephyrax.png',rarity:'legendary',eggTier:'mythic',weight:20},
  {slug:'mythic-morvanna',name:'Morvanna',species:'Fênix-Serpe Carmesim',image:'/assets/game/pets/mythic/morvanna.png',rarity:'legendary',eggTier:'mythic',weight:20},
] as const;

export function selectMythicPetByRoll(roll:number):MythicPetDefinition{
  const safe=Number.isFinite(roll)?Math.min(.999999999,Math.max(0,roll)):0;
  const total=MYTHIC_PET_CATALOG.reduce((sum,pet)=>sum+pet.weight,0);
  let cursor=0;
  for(const pet of MYTHIC_PET_CATALOG){cursor+=pet.weight/total;if(safe<cursor)return pet}
  return MYTHIC_PET_CATALOG[MYTHIC_PET_CATALOG.length-1];
}

export function buildPetDashboardPreview():PetDashboard{
  const definitions:Array<{id:string;name:string;species:string;category:string;rarity:PetRarity;image:string;bonus:PetPassives}>=[
    {id:'pyron',name:'Pyron',species:'Dragão de Fogo',category:'dragon',rarity:'epic' as PetRarity,image:'/assets/game/pets/pyron.webp',bonus:{boss_damage_percent:8}},
    {id:'glacius',name:'Glacius',species:'Lobo de Gelo',category:'beast',rarity:'rare' as PetRarity,image:'/assets/game/pets/glacius.webp',bonus:{team_hp_percent:5}},
    {id:'noctis',name:'Noctis',species:'Corvo Sombrio',category:'bird',rarity:'uncommon' as PetRarity,image:'/assets/game/pets/noctis.webp',bonus:{drop_chance_percent:3}},
  ];
  const playerPets:PlayerPet[]=definitions.map((pet,index)=>({id:`preview-pet-${index+1}`,petId:pet.id,name:pet.name,slug:pet.id,species:pet.species,category:pet.category,rarity:pet.rarity,level:[12,7,4][index],xp:[620,180,75][index],xpRequired:[7168,3496,1625][index],canEvolve:false,evolutionCostFc:[201200,59400,23400][index],isMaxLevel:false,evolutionStage:index===0?'young':'baby',fragments:[18,7,3][index],isActive:index===0,image:pet.image,passives:pet.bonus,power:[6420,3180,1740][index],activeSkill:index===0?{name:'Chama Ancestral'}:null}));
  const catalog:PetCatalogItem[]=definitions.map((pet,index)=>({id:pet.id,name:pet.name,slug:pet.id,species:pet.species,category:pet.category,description:`Companheiro ${pet.species.toLowerCase()} das forjas.`,basePassives:pet.bonus,activeSkill:index===0?{name:'Chama Ancestral'}:null,images:{baby:pet.image,young:pet.image,adult:pet.image,ancestral:pet.image},discovered:true,bestRarity:pet.rarity,bestLevel:playerPets[index].level}));
  const eggs:PetEgg[]=[
    {id:'preview-common-egg',name:'Ovo Comum',slug:'common',image:'/assets/game/pet-eggs/common-egg.webp',priceFc:25000,priceTon:null,quantity:2,rarityRates:{common:75,uncommon:20,rare:5}},
    {id:'preview-rare-egg',name:'Ovo Raro',slug:'rare',image:'/assets/game/pet-eggs/rare-egg.webp',priceFc:100000,priceTon:null,quantity:1,rarityRates:{common:35,uncommon:40,rare:20,epic:5}},
    {id:'preview-epic-egg',name:'Ovo Épico',slug:'epic',image:'/assets/game/pet-eggs/epic-egg.webp',priceFc:null,priceTon:3,quantity:0,rarityRates:{rare:45,epic:45,legendary:10},premiumOnly:true},
    {id:'preview-dragon-egg',name:'Ovo de Dragão',slug:'dragon',image:'/assets/game/pet-eggs/dragon-egg.webp',priceFc:null,priceTon:10,quantity:0,rarityRates:{rare:50,epic:40,legendary:10},premiumOnly:true},
    {id:'preview-ancestral-egg',name:'Ovo Ancestral',slug:'ancestral',image:'/assets/game/pet-eggs/ancestral-egg.webp',priceFc:null,priceTon:null,quantity:0,rarityRates:{epic:70,legendary:30},isPurchasable:false,availabilityLabel:'Evento exclusivo'},
  ];
  return{activePet:playerPets[0],playerPets,catalog,eggs,inventory:{food:36,universalFragments:14},history:[{id:'preview-history-1',eggName:'Ovo Raro',petName:'Glacius',rarity:'rare',duplicateFragments:0,createdAt:new Date(Date.now()-86400000).toISOString()}],bonuses:{boss_damage_percent:8},balance:850000};
}
