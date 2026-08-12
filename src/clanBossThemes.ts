/**
 * Visual identity for the 10 Clan Boss cycles.
 *
 * Pure presentation: art + themed arena/background/glow per boss key. The
 * backend decides which boss is active (cycle -> template); this map only
 * decides how it looks, so swapping an individual image later is a one-line
 * change.
 */
import abyssalWarlord from './assets/clan-boss/abyssal-warlord.webp';
import frostTyrant from './assets/clan-boss/frost-tyrant.png';
import shadowDevourer from './assets/clan-boss/shadow-devourer.png';
import moltenColossus from './assets/clan-boss/molten-colossus.png';
import plagueMonarch from './assets/clan-boss/plague-monarch.png';
import stormReaper from './assets/clan-boss/storm-reaper.png';
import voidExecutioner from './assets/clan-boss/void-executioner.png';
import crimsonBehemoth from './assets/clan-boss/crimson-behemoth.png';
import soulbreakerKing from './assets/clan-boss/soulbreaker-king.png';
import eternalOverlord from './assets/clan-boss/eternal-overlord.png';

/** Ambient particle layer rendered over the arena art. */
export type ClanBossFx = 'ember' | 'snow' | 'mist' | 'spore' | 'spark' | 'gold';

export type ClanBossTheme = {
  art: string;
  /** Themed arena artwork rendered behind the boss (distant + mid + floor). */
  arena: string;
  /** Deep, layered stage background (radial + linear, with floor haze). */
  stage: string;
  /** Page-level backdrop behind the whole screen. */
  page: string;
  /** Soft aura painted behind the creature. */
  aura: string;
  /** Ground platform glow under the boss so it never looks floating. */
  base: string;
  /** Ambient particle style. */
  fx: ClanBossFx;
  /** Boss art drop-shadow glow. */
  glow: string;
  /** Border tint for the stage / cards. */
  border: string;
  /** HP bar gradient. */
  bar: string;
  /** Accent text colour class. */
  accent: string;
};

const arena = (file: string) => `/assets/game/clan-boss/arena-${file}.jpg`;
const aura = (rgb: string, alpha = 0.42) =>
  `radial-gradient(circle, rgba(${rgb},${alpha}) 0%, rgba(${rgb},0) 68%)`;
const base = (rgb: string) =>
  `radial-gradient(ellipse at 50% 50%, rgba(${rgb},.55) 0%, rgba(${rgb},.18) 45%, rgba(0,0,0,0) 72%)`;

const THEMES: Record<string, ClanBossTheme> = {
  abyssal_warlord: {
    art: abyssalWarlord,
    arena: arena('abyssal-warlord'),
    stage: 'radial-gradient(circle at 50% 8%, rgba(190,24,93,.45), rgba(76,5,25,.65) 45%, rgba(6,4,10,.96) 78%)',
    page: 'radial-gradient(circle at 50% 0%, rgba(120,20,60,.55), #0a0409 70%)',
    aura: aura('244,63,94'),
    base: base('244,63,94'),
    fx: 'ember',
    glow: 'drop-shadow(0 0 34px rgba(244,63,94,.55))',
    border: 'border-rose-400/30',
    bar: 'linear-gradient(90deg,#7f1d1d,#f43f5e,#fb7185)',
    accent: 'text-rose-200',
  },
  frost_tyrant: {
    art: frostTyrant,
    arena: arena('frost-tyrant'),
    stage: 'radial-gradient(circle at 50% 8%, rgba(56,189,248,.42), rgba(12,74,110,.6) 45%, rgba(4,8,16,.96) 78%)',
    page: 'radial-gradient(circle at 50% 0%, rgba(14,80,120,.55), #030812 70%)',
    aura: aura('103,232,249'),
    base: base('103,232,249'),
    fx: 'snow',
    glow: 'drop-shadow(0 0 34px rgba(103,232,249,.6))',
    border: 'border-cyan-300/30',
    bar: 'linear-gradient(90deg,#0e7490,#22d3ee,#a5f3fc)',
    accent: 'text-cyan-200',
  },
  shadow_devourer: {
    art: shadowDevourer,
    arena: arena('shadow-devourer'),
    stage: 'radial-gradient(circle at 50% 8%, rgba(139,92,246,.4), rgba(46,16,101,.6) 45%, rgba(5,3,10,.97) 78%)',
    page: 'radial-gradient(circle at 50% 0%, rgba(76,29,149,.55), #060410 70%)',
    aura: aura('167,139,250'),
    base: base('167,139,250'),
    fx: 'mist',
    glow: 'drop-shadow(0 0 34px rgba(167,139,250,.6))',
    border: 'border-violet-400/30',
    bar: 'linear-gradient(90deg,#4c1d95,#8b5cf6,#c4b5fd)',
    accent: 'text-violet-200',
  },
  molten_colossus: {
    art: moltenColossus,
    arena: arena('molten-colossus'),
    stage: 'radial-gradient(circle at 50% 8%, rgba(249,115,22,.45), rgba(120,53,15,.6) 45%, rgba(10,5,3,.96) 78%)',
    page: 'radial-gradient(circle at 50% 0%, rgba(154,52,18,.55), #0c0603 70%)',
    aura: aura('251,146,60'),
    base: base('251,146,60'),
    fx: 'ember',
    glow: 'drop-shadow(0 0 34px rgba(251,146,60,.6))',
    border: 'border-orange-400/30',
    bar: 'linear-gradient(90deg,#7c2d12,#f97316,#fbbf24)',
    accent: 'text-orange-200',
  },
  plague_monarch: {
    art: plagueMonarch,
    arena: arena('plague-monarch'),
    stage: 'radial-gradient(circle at 50% 8%, rgba(74,222,128,.35), rgba(20,83,45,.6) 45%, rgba(4,10,7,.96) 78%)',
    page: 'radial-gradient(circle at 50% 0%, rgba(21,94,60,.55), #040b07 70%)',
    aura: aura('134,239,172'),
    base: base('134,239,172'),
    fx: 'spore',
    glow: 'drop-shadow(0 0 34px rgba(134,239,172,.55))',
    border: 'border-emerald-400/30',
    bar: 'linear-gradient(90deg,#14532d,#22c55e,#bef264)',
    accent: 'text-emerald-200',
  },
  storm_reaper: {
    art: stormReaper,
    arena: arena('storm-reaper'),
    stage: 'radial-gradient(circle at 50% 8%, rgba(96,165,250,.4), rgba(30,41,59,.7) 45%, rgba(3,6,12,.96) 78%)',
    page: 'radial-gradient(circle at 50% 0%, rgba(30,58,138,.55), #030711 70%)',
    aura: aura('147,197,253'),
    base: base('147,197,253'),
    fx: 'spark',
    glow: 'drop-shadow(0 0 34px rgba(147,197,253,.65))',
    border: 'border-sky-300/30',
    bar: 'linear-gradient(90deg,#1e3a8a,#3b82f6,#93c5fd)',
    accent: 'text-sky-200',
  },
  void_executioner: {
    art: voidExecutioner,
    arena: arena('void-executioner'),
    stage: 'radial-gradient(circle at 50% 8%, rgba(147,51,234,.4), rgba(24,8,44,.75) 45%, rgba(2,2,6,.98) 78%)',
    page: 'radial-gradient(circle at 50% 0%, rgba(59,7,100,.6), #030206 70%)',
    aura: aura('192,132,252'),
    base: base('192,132,252'),
    fx: 'spark',
    glow: 'drop-shadow(0 0 36px rgba(192,132,252,.6))',
    border: 'border-fuchsia-400/30',
    bar: 'linear-gradient(90deg,#3b0764,#a855f7,#e879f9)',
    accent: 'text-fuchsia-200',
  },
  crimson_behemoth: {
    art: crimsonBehemoth,
    arena: arena('crimson-behemoth'),
    stage: 'radial-gradient(circle at 50% 8%, rgba(239,68,68,.45), rgba(69,10,10,.7) 45%, rgba(8,3,3,.97) 78%)',
    page: 'radial-gradient(circle at 50% 0%, rgba(127,29,29,.6), #0a0303 70%)',
    aura: aura('248,113,113'),
    base: base('248,113,113'),
    fx: 'ember',
    glow: 'drop-shadow(0 0 34px rgba(248,113,113,.6))',
    border: 'border-red-400/30',
    bar: 'linear-gradient(90deg,#450a0a,#dc2626,#f87171)',
    accent: 'text-red-200',
  },
  soulbreaker_king: {
    art: soulbreakerKing,
    arena: arena('soulbreaker-king'),
    stage: 'radial-gradient(circle at 50% 8%, rgba(45,212,191,.38), rgba(15,60,66,.68) 45%, rgba(3,8,10,.96) 78%)',
    page: 'radial-gradient(circle at 50% 0%, rgba(13,90,95,.55), #03090b 70%)',
    aura: aura('94,234,212'),
    base: base('94,234,212'),
    fx: 'mist',
    glow: 'drop-shadow(0 0 34px rgba(94,234,212,.6))',
    border: 'border-teal-300/30',
    bar: 'linear-gradient(90deg,#134e4a,#14b8a6,#99f6e4)',
    accent: 'text-teal-200',
  },
  eternal_overlord: {
    art: eternalOverlord,
    arena: arena('eternal-overlord'),
    stage: 'radial-gradient(circle at 50% 8%, rgba(250,204,21,.35), rgba(63,45,8,.7) 45%, rgba(6,5,3,.97) 78%)',
    page: 'radial-gradient(circle at 50% 0%, rgba(120,80,10,.55), #080603 70%)',
    aura: aura('253,224,71'),
    base: base('253,224,71'),
    fx: 'gold',
    glow: 'drop-shadow(0 0 40px rgba(253,224,71,.6))',
    border: 'border-amber-300/40',
    bar: 'linear-gradient(90deg,#78350f,#f59e0b,#fde68a)',
    accent: 'text-amber-200',
  },
};

export const DEFAULT_CLAN_BOSS_THEME = THEMES.abyssal_warlord;

/** Resolves the visual theme for a boss key, with a safe fallback. */
export function clanBossTheme(key: string | null | undefined): ClanBossTheme {
  return THEMES[String(key || '')] ?? DEFAULT_CLAN_BOSS_THEME;
}

/** Art override coming from the backend (admin-uploaded) wins over the bundled asset. */
export function clanBossArt(key: string | null | undefined, imageUrl?: string | null): string {
  return imageUrl && imageUrl.length > 4 ? imageUrl : clanBossTheme(key).art;
}

/** Arena override coming from the backend wins over the bundled scene. */
export function clanBossArena(key: string | null | undefined, imageUrl?: string | null): string {
  return imageUrl && imageUrl.length > 4 ? imageUrl : clanBossTheme(key).arena;
}
