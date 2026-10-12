import npc00 from './assets/island-pirates/npc-0-0.png';
import npc01 from './assets/island-pirates/npc-0-1.png';
import npc02 from './assets/island-pirates/npc-0-2.png';
import npc03 from './assets/island-pirates/npc-0-3.png';
import npc10 from './assets/island-pirates/npc-1-0.png';
import npc11 from './assets/island-pirates/npc-1-1.png';
import npc12 from './assets/island-pirates/npc-1-2.png';
import npc13 from './assets/island-pirates/npc-1-3.png';
import npc20 from './assets/island-pirates/npc-2-0.png';
import npc21 from './assets/island-pirates/npc-2-1.png';
import npc22 from './assets/island-pirates/npc-2-2.png';
import npc23 from './assets/island-pirates/npc-2-3.png';
import npc30 from './assets/island-pirates/npc-3-0.png';
import npc31 from './assets/island-pirates/npc-3-1.png';
import npc32 from './assets/island-pirates/npc-3-2.png';
import npc33 from './assets/island-pirates/npc-3-3.png';
import npc40 from './assets/island-pirates/npc-4-0.png';
import npc41 from './assets/island-pirates/npc-4-1.png';
import npc42 from './assets/island-pirates/npc-4-2.png';
import npc43 from './assets/island-pirates/npc-4-3.png';

export const islandPirateArt: Record<string, { image: string; aspect: number }> = {
  'islandCombat.enemy.0.0': { image: npc00, aspect: 0.359743 },
  'islandCombat.enemy.0.1': { image: npc01, aspect: 0.458552 },
  'islandCombat.enemy.0.2': { image: npc02, aspect: 0.389691 },
  'islandCombat.enemy.0.3': { image: npc03, aspect: 0.385396 },
  'islandCombat.enemy.1.0': { image: npc10, aspect: 0.480601 },
  'islandCombat.enemy.1.1': { image: npc11, aspect: 0.397059 },
  'islandCombat.enemy.1.2': { image: npc12, aspect: 0.481076 },
  'islandCombat.enemy.1.3': { image: npc13, aspect: 0.425868 },
  'islandCombat.enemy.2.0': { image: npc20, aspect: 0.351613 },
  'islandCombat.enemy.2.1': { image: npc21, aspect: 0.420668 },
  'islandCombat.enemy.2.2': { image: npc22, aspect: 0.387029 },
  'islandCombat.enemy.2.3': { image: npc23, aspect: 0.487206 },
  'islandCombat.enemy.3.0': { image: npc30, aspect: 0.450122 },
  'islandCombat.enemy.3.1': { image: npc31, aspect: 0.395492 },
  'islandCombat.enemy.3.2': { image: npc32, aspect: 0.498455 },
  'islandCombat.enemy.3.3': { image: npc33, aspect: 0.440083 },
  'islandCombat.enemy.4.0': { image: npc40, aspect: 0.353645 },
  'islandCombat.enemy.4.1': { image: npc41, aspect: 0.428721 },
  'islandCombat.enemy.4.2': { image: npc42, aspect: 0.493258 },
  'islandCombat.enemy.4.3': { image: npc43, aspect: 0.460474 },
};

/** Unknown identities never reuse another NPC’s image. */
export const pirateEncounterArt = (key: string) => islandPirateArt[key] ?? null;
