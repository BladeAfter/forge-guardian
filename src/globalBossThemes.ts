/**
 * Global Boss progression themes (10 bosses).
 *
 * Purely presentational: art, background gradients, glow and HP bar colors are
 * mapped by boss key/number. Attack logic, damage and ranking stay server-side.
 */
export type GlobalBossTheme = {
  key: string;
  art: string;
  /** Full-card stage background (behind the boss). */
  stage: string;
  /** Themed arena artwork rendered behind the boss. */
  arena: string;
  /** Soft aura painted behind the creature. */
  aura: string;
  /** CSS filter used as the boss glow. */
  glow: string;
  /** HP bar gradient. */
  bar: string;
  border: string;
  accent: string;
};

const art = (file: string) => `/assets/game/global-boss/${file}`;
const arena = (file: string) => `/assets/game/global-boss/arena-${file}.jpg`;

export const GLOBAL_BOSS_THEMES: Record<string, GlobalBossTheme> = {
  ancestral_dragon: {
    key: 'ancestral_dragon', art: art('ancestral-dragon.png'),
    arena: arena('ancestral-dragon'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #4a1608 0%, #240a06 45%, #07090d 100%)',
    aura: 'radial-gradient(circle, rgba(251,146,60,.42) 0%, rgba(120,30,10,0) 68%)',
    glow: 'drop-shadow(0 0 28px rgba(251,146,60,.55))',
    bar: 'linear-gradient(90deg,#fb923c,#ef4444,#7f1d1d)',
    border: 'border-orange-300/25', accent: 'text-orange-200',
  },
  infernal_behemoth: {
    key: 'infernal_behemoth', art: art('infernal-behemoth.png'),
    arena: arena('infernal-behemoth'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #5c1206 0%, #26070a 48%, #07090d 100%)',
    aura: 'radial-gradient(circle, rgba(239,68,68,.45) 0%, rgba(90,10,10,0) 68%)',
    glow: 'drop-shadow(0 0 30px rgba(239,68,68,.6))',
    bar: 'linear-gradient(90deg,#f97316,#dc2626,#651616)',
    border: 'border-red-400/25', accent: 'text-red-200',
  },
  void_harbinger: {
    key: 'void_harbinger', art: art('void-harbinger.png'),
    arena: arena('void-harbinger'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #2c1150 0%, #150a2b 48%, #06070d 100%)',
    aura: 'radial-gradient(circle, rgba(168,85,247,.42) 0%, rgba(60,20,110,0) 68%)',
    glow: 'drop-shadow(0 0 32px rgba(168,85,247,.6))',
    bar: 'linear-gradient(90deg,#c084fc,#7c3aed,#3b0764)',
    border: 'border-violet-300/25', accent: 'text-violet-200',
  },
  frozen_leviathan: {
    key: 'frozen_leviathan', art: art('frozen-leviathan.png'),
    arena: arena('frozen-leviathan'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #0d3450 0%, #0a1e32 48%, #05080d 100%)',
    aura: 'radial-gradient(circle, rgba(56,189,248,.4) 0%, rgba(10,60,90,0) 68%)',
    glow: 'drop-shadow(0 0 30px rgba(56,189,248,.6))',
    bar: 'linear-gradient(90deg,#67e8f9,#0ea5e9,#0c4a6e)',
    border: 'border-cyan-300/25', accent: 'text-cyan-200',
  },
  storm_colossus: {
    key: 'storm_colossus', art: art('storm-colossus.png'),
    arena: arena('storm-colossus'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #1b2b52 0%, #111a33 48%, #06080e 100%)',
    aura: 'radial-gradient(circle, rgba(96,165,250,.42) 0%, rgba(20,40,90,0) 68%)',
    glow: 'drop-shadow(0 0 30px rgba(96,165,250,.62))',
    bar: 'linear-gradient(90deg,#93c5fd,#3b82f6,#1e3a8a)',
    border: 'border-sky-300/25', accent: 'text-sky-200',
  },
  plague_sovereign: {
    key: 'plague_sovereign', art: art('plague-sovereign.png'),
    arena: arena('plague-sovereign'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #16351f 0%, #0d1f14 48%, #05090a 100%)',
    aura: 'radial-gradient(circle, rgba(132,204,22,.4) 0%, rgba(20,60,25,0) 68%)',
    glow: 'drop-shadow(0 0 28px rgba(163,230,53,.55))',
    bar: 'linear-gradient(90deg,#bef264,#65a30d,#1a2e05)',
    border: 'border-lime-300/25', accent: 'text-lime-200',
  },
  molten_tyrant: {
    key: 'molten_tyrant', art: art('molten-tyrant.png'),
    arena: arena('molten-tyrant'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #55190a 0%, #2a0c07 48%, #08080b 100%)',
    aura: 'radial-gradient(circle, rgba(249,115,22,.48) 0%, rgba(100,30,5,0) 68%)',
    glow: 'drop-shadow(0 0 32px rgba(249,115,22,.62))',
    bar: 'linear-gradient(90deg,#fdba74,#ea580c,#7c2d12)',
    border: 'border-amber-300/25', accent: 'text-amber-200',
  },
  soul_reaper_king: {
    key: 'soul_reaper_king', art: art('soul-reaper-king.png'),
    arena: arena('soul-reaper-king'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #0b3a3a 0%, #08222a 48%, #04070a 100%)',
    aura: 'radial-gradient(circle, rgba(45,212,191,.42) 0%, rgba(5,60,60,0) 68%)',
    glow: 'drop-shadow(0 0 30px rgba(45,212,191,.6))',
    bar: 'linear-gradient(90deg,#5eead4,#14b8a6,#134e4a)',
    border: 'border-teal-300/25', accent: 'text-teal-200',
  },
  abyss_lord: {
    key: 'abyss_lord', art: art('abyss-lord.png'),
    arena: arena('abyss-lord'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #111f52 0%, #0a1230 48%, #04050c 100%)',
    aura: 'radial-gradient(circle, rgba(99,102,241,.45) 0%, rgba(15,25,80,0) 68%)',
    glow: 'drop-shadow(0 0 32px rgba(99,102,241,.62))',
    bar: 'linear-gradient(90deg,#818cf8,#4338ca,#1e1b4b)',
    border: 'border-indigo-300/25', accent: 'text-indigo-200',
  },
  eternal_worldbreaker: {
    key: 'eternal_worldbreaker', art: art('eternal-worldbreaker.png'),
    arena: arena('eternal-worldbreaker'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #4a3a10 0%, #241d09 48%, #08080b 100%)',
    aura: 'radial-gradient(circle, rgba(250,204,21,.45) 0%, rgba(90,70,10,0) 68%)',
    glow: 'drop-shadow(0 0 34px rgba(250,204,21,.62))',
    bar: 'linear-gradient(90deg,#fde68a,#f59e0b,#78350f)',
    border: 'border-yellow-300/25', accent: 'text-yellow-200',
  },
};

const ORDER = [
  'ancestral_dragon', 'infernal_behemoth', 'void_harbinger', 'frozen_leviathan', 'storm_colossus',
  'plague_sovereign', 'molten_tyrant', 'soul_reaper_king', 'abyss_lord', 'eternal_worldbreaker',
];

export const DEFAULT_GLOBAL_BOSS_THEME = GLOBAL_BOSS_THEMES.ancestral_dragon;

/** Resolves the theme by boss key first, then by boss number (1-10). */
export function globalBossTheme(key?: string | null, bossNumber?: number | null): GlobalBossTheme {
  const normalized = String(key ?? '').trim().toLowerCase().replace(/[\s-]+/g, '_');
  if (GLOBAL_BOSS_THEMES[normalized]) return GLOBAL_BOSS_THEMES[normalized];
  const index = Math.min(ORDER.length, Math.max(1, Number(bossNumber) || 1)) - 1;
  return GLOBAL_BOSS_THEMES[ORDER[index]] ?? DEFAULT_GLOBAL_BOSS_THEME;
}

/** Boss art with a safe fallback for cycles created before the progression. */
export const globalBossArt = (key?: string | null, bossNumber?: number | null, image?: string | null) =>
  image && image.startsWith('/assets/game/global-boss/') ? image : globalBossTheme(key, bossNumber).art;
