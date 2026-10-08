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
  abyss_sovereign: {
    key: 'abyss_sovereign', art: art('abyss-sovereign.png'),
    arena: arena('abyss-sovereign'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #072f3c 0%, #051b26 48%, #03080c 100%)',
    aura: 'radial-gradient(circle, rgba(34,211,238,.45) 0%, rgba(5,50,70,0) 68%)',
    glow: 'drop-shadow(0 0 32px rgba(34,211,238,.6))',
    bar: 'linear-gradient(90deg,#67e8f9,#0891b2,#083344)',
    border: 'border-cyan-300/25', accent: 'text-cyan-200',
  },
  crimson_behemoth: {
    key: 'crimson_behemoth', art: art('crimson-behemoth.webp'),
    arena: arena('crimson-behemoth'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #4c0511 0%, #26060c 48%, #08060a 100%)',
    aura: 'radial-gradient(circle, rgba(244,63,94,.45) 0%, rgba(90,5,20,0) 68%)',
    glow: 'drop-shadow(0 0 32px rgba(244,63,94,.62))',
    bar: 'linear-gradient(90deg,#fda4af,#e11d48,#4c0519)',
    border: 'border-rose-400/25', accent: 'text-rose-200',
  },
  storm_devourer: {
    key: 'storm_devourer', art: art('storm-devourer.png'),
    arena: arena('storm-devourer'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #16304f 0%, #0d1c31 48%, #05070d 100%)',
    aura: 'radial-gradient(circle, rgba(125,211,252,.45) 0%, rgba(15,45,85,0) 68%)',
    glow: 'drop-shadow(0 0 34px rgba(125,211,252,.62))',
    bar: 'linear-gradient(90deg,#e0f2fe,#38bdf8,#075985)',
    border: 'border-sky-200/30', accent: 'text-sky-100',
  },
  infernal_colossus: {
    key: 'infernal_colossus', art: art('infernal-colossus.png'),
    arena: arena('infernal-colossus'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #5e1a05 0%, #2b0d05 48%, #08070a 100%)',
    aura: 'radial-gradient(circle, rgba(251,146,60,.5) 0%, rgba(100,30,5,0) 68%)',
    glow: 'drop-shadow(0 0 34px rgba(251,146,60,.65))',
    bar: 'linear-gradient(90deg,#fed7aa,#f97316,#7c2d12)',
    border: 'border-orange-300/25', accent: 'text-orange-100',
  },
  void_leviathan: {
    key: 'void_leviathan', art: art('void-leviathan.png'),
    arena: arena('void-leviathan'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #2a0f4d 0%, #150829 48%, #04040a 100%)',
    aura: 'radial-gradient(circle, rgba(192,132,252,.48) 0%, rgba(60,15,110,0) 68%)',
    glow: 'drop-shadow(0 0 34px rgba(192,132,252,.65))',
    bar: 'linear-gradient(90deg,#e9d5ff,#a855f7,#3b0764)',
    border: 'border-fuchsia-300/25', accent: 'text-fuchsia-200',
  },
  frostbound_tyrant: {
    key: 'frostbound_tyrant', art: art('frostbound-tyrant.png'),
    arena: arena('frostbound-tyrant'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #123c56 0%, #0b2234 48%, #04070c 100%)',
    aura: 'radial-gradient(circle, rgba(191,219,254,.45) 0%, rgba(15,60,90,0) 68%)',
    glow: 'drop-shadow(0 0 32px rgba(191,219,254,.6))',
    bar: 'linear-gradient(90deg,#f0f9ff,#60a5fa,#1e3a8a)',
    border: 'border-blue-200/30', accent: 'text-blue-100',
  },
  eclipse_warden: {
    key: 'eclipse_warden', art: art('eclipse-warden.png'),
    arena: arena('eclipse-warden'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #3b1d5c 0%, #1d1030 48%, #06050b 100%)',
    aura: 'radial-gradient(circle, rgba(253,186,116,.45) 0%, rgba(70,25,110,0) 68%)',
    glow: 'drop-shadow(0 0 34px rgba(253,224,71,.6))',
    bar: 'linear-gradient(90deg,#fde68a,#a855f7,#2e1065)',
    border: 'border-amber-200/25', accent: 'text-amber-100',
  },
  bone_emperor: {
    key: 'bone_emperor', art: art('bone-emperor.png'),
    arena: arena('bone-emperor'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #10352b 0%, #0a1f1a 48%, #04080a 100%)',
    aura: 'radial-gradient(circle, rgba(74,222,128,.42) 0%, rgba(10,60,45,0) 68%)',
    glow: 'drop-shadow(0 0 32px rgba(74,222,128,.6))',
    bar: 'linear-gradient(90deg,#d9f99d,#22c55e,#14532d)',
    border: 'border-emerald-300/25', accent: 'text-emerald-200',
  },
  chaos_paragon: {
    key: 'chaos_paragon', art: art('chaos-paragon.png'),
    arena: arena('chaos-paragon'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #451a52 0%, #1c1030 48%, #05050b 100%)',
    aura: 'radial-gradient(circle, rgba(236,72,153,.45) 0%, rgba(70,20,90,0) 68%)',
    glow: 'drop-shadow(0 0 36px rgba(236,72,153,.62))',
    bar: 'linear-gradient(90deg,#f9a8d4,#a855f7,#0ea5e9)',
    border: 'border-pink-300/25', accent: 'text-pink-200',
  },
  celestial_ruinbringer: {
    key: 'celestial_ruinbringer', art: art('celestial-ruinbringer.png'),
    arena: arena('celestial-ruinbringer'),
    stage: 'radial-gradient(120% 90% at 50% 12%, #4a4013 0%, #1c2033 48%, #05070c 100%)',
    aura: 'radial-gradient(circle, rgba(254,240,138,.5) 0%, rgba(80,70,15,0) 68%)',
    glow: 'drop-shadow(0 0 38px rgba(254,240,138,.68))',
    bar: 'linear-gradient(90deg,#fffbeb,#facc15,#92400e)',
    border: 'border-yellow-200/30', accent: 'text-yellow-100',
  },
};

const ORDER = [
  'ancestral_dragon', 'infernal_behemoth', 'void_harbinger', 'frozen_leviathan', 'storm_colossus',
  'plague_sovereign', 'molten_tyrant', 'soul_reaper_king', 'abyss_lord', 'eternal_worldbreaker',
  'abyss_sovereign', 'crimson_behemoth', 'storm_devourer', 'infernal_colossus', 'void_leviathan',
  'frostbound_tyrant', 'eclipse_warden', 'bone_emperor', 'chaos_paragon', 'celestial_ruinbringer',
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
