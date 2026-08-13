/**
 * Visual identity of the 10 Tower of Eternity bosses.
 *
 * Pure presentation: the backend decides which boss guards each floor and how
 * strong it is; this map only decides how it looks.
 */
import abyssalWarden from './assets/clan-boss/abyssal-warlord.webp';
import frostTyrant from './assets/clan-boss/frost-tyrant.png';
import shadowQueen from './assets/clan-boss/shadow-devourer.png';
import ironJuggernaut from './assets/clan-boss/molten-colossus.png';
import venomHydra from './assets/clan-boss/plague-monarch.png';
import celestialReaper from './assets/clan-boss/void-executioner.png';
import ancientTreant from './assets/tower-boss/ancient-treant.png';

const globalArt = (file: string) => `/assets/game/global-boss/${file}`;
const arena = (file: string) => `/assets/game/global-boss/arena-${file}.jpg`;

export type TowerBossTheme = {
  art: string;
  arena: string;
  stage: string;
  aura: string;
  glow: string;
  bar: string;
  border: string;
  accent: string;
};

export const TOWER_BOSS_THEMES: Record<string, TowerBossTheme> = {
  abyssal_warden: {
    art: abyssalWarden, arena: arena('abyss-lord'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #2a1147 0%, #150c26 48%, #06070d 100%)',
    aura: 'radial-gradient(circle, rgba(167,139,250,.4) 0%, rgba(60,20,110,0) 68%)',
    glow: 'drop-shadow(0 0 26px rgba(167,139,250,.55))',
    bar: 'linear-gradient(90deg,#a78bfa,#7c3aed,#3b0764)',
    border: 'border-violet-300/30', accent: 'text-violet-200',
  },
  infernal_behemoth: {
    art: globalArt('infernal-behemoth.png'), arena: arena('infernal-behemoth'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #5c1206 0%, #26070a 48%, #07090d 100%)',
    aura: 'radial-gradient(circle, rgba(239,68,68,.45) 0%, rgba(90,10,10,0) 68%)',
    glow: 'drop-shadow(0 0 28px rgba(249,115,22,.6))',
    bar: 'linear-gradient(90deg,#f97316,#dc2626,#651616)',
    border: 'border-orange-300/30', accent: 'text-orange-200',
  },
  frost_tyrant: {
    art: frostTyrant, arena: arena('frozen-leviathan'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #0d3450 0%, #0a1e32 48%, #05080d 100%)',
    aura: 'radial-gradient(circle, rgba(56,189,248,.42) 0%, rgba(10,60,90,0) 68%)',
    glow: 'drop-shadow(0 0 28px rgba(56,189,248,.6))',
    bar: 'linear-gradient(90deg,#67e8f9,#0ea5e9,#0c4a6e)',
    border: 'border-sky-300/30', accent: 'text-sky-200',
  },
  venom_hydra: {
    art: venomHydra, arena: arena('plague-sovereign'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #16351a 0%, #0d1f14 48%, #05080a 100%)',
    aura: 'radial-gradient(circle, rgba(74,222,128,.4) 0%, rgba(15,70,35,0) 68%)',
    glow: 'drop-shadow(0 0 26px rgba(74,222,128,.55))',
    bar: 'linear-gradient(90deg,#a3e635,#16a34a,#14532d)',
    border: 'border-lime-300/30', accent: 'text-lime-200',
  },
  storm_colossus: {
    art: globalArt('storm-colossus.png'), arena: arena('storm-colossus'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #1b2a55 0%, #101833 48%, #05070d 100%)',
    aura: 'radial-gradient(circle, rgba(96,165,250,.42) 0%, rgba(20,40,110,0) 68%)',
    glow: 'drop-shadow(0 0 30px rgba(96,165,250,.6))',
    bar: 'linear-gradient(90deg,#93c5fd,#2563eb,#1e3a8a)',
    border: 'border-blue-300/30', accent: 'text-blue-200',
  },
  shadow_queen: {
    art: shadowQueen, arena: arena('void-harbinger'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #35104a 0%, #1a0b26 48%, #06060c 100%)',
    aura: 'radial-gradient(circle, rgba(217,70,239,.4) 0%, rgba(70,10,90,0) 68%)',
    glow: 'drop-shadow(0 0 28px rgba(217,70,239,.55))',
    bar: 'linear-gradient(90deg,#e879f9,#a21caf,#4a044e)',
    border: 'border-fuchsia-300/30', accent: 'text-fuchsia-200',
  },
  iron_juggernaut: {
    art: ironJuggernaut, arena: arena('molten-tyrant'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #3a3a42 0%, #1c1c22 48%, #08080b 100%)',
    aura: 'radial-gradient(circle, rgba(203,213,225,.38) 0%, rgba(60,60,70,0) 68%)',
    glow: 'drop-shadow(0 0 26px rgba(203,213,225,.5))',
    bar: 'linear-gradient(90deg,#e2e8f0,#94a3b8,#334155)',
    border: 'border-slate-300/30', accent: 'text-slate-200',
  },
  ancient_treant: {
    art: ancientTreant, arena: arena('plague-sovereign'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #14401f 0%, #0c2415 48%, #04080a 100%)',
    aura: 'radial-gradient(circle, rgba(34,197,94,.42) 0%, rgba(10,70,30,0) 68%)',
    glow: 'drop-shadow(0 0 28px rgba(34,197,94,.55))',
    bar: 'linear-gradient(90deg,#4ade80,#15803d,#052e16)',
    border: 'border-emerald-300/30', accent: 'text-emerald-200',
  },
  celestial_reaper: {
    art: celestialReaper, arena: arena('soul-reaper-king'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #3d2a10 0%, #21142a 48%, #07070d 100%)',
    aura: 'radial-gradient(circle, rgba(251,191,36,.4) 0%, rgba(90,40,120,0) 68%)',
    glow: 'drop-shadow(0 0 30px rgba(251,191,36,.55))',
    bar: 'linear-gradient(90deg,#fde68a,#f59e0b,#7c2d12)',
    border: 'border-amber-300/30', accent: 'text-amber-200',
  },
  eternal_dragon: {
    art: globalArt('ancestral-dragon.png'), arena: arena('eternal-worldbreaker'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #4a1608 0%, #240a06 45%, #07090d 100%)',
    aura: 'radial-gradient(circle, rgba(251,146,60,.45) 0%, rgba(120,30,10,0) 68%)',
    glow: 'drop-shadow(0 0 32px rgba(251,146,60,.6))',
    bar: 'linear-gradient(90deg,#fb923c,#ef4444,#7f1d1d)',
    border: 'border-orange-300/30', accent: 'text-orange-200',
  },
};

export const towerBossTheme = (bossKey?: string | null): TowerBossTheme =>
  TOWER_BOSS_THEMES[String(bossKey ?? '').toLowerCase()] ?? TOWER_BOSS_THEMES.abyssal_warden;
