/**
 * 🐾⚔️ FAMILIAR HUNT — ABILITY BOOK.
 * Each familiar gets a deterministic kit of 3 abilities (damage / support / special)
 * derived from its name, so the same pet always fights with the same skills.
 * Abilities are PRESENTATION only: the fight outcome and rewards stay server-side.
 */
export type AbilityKind = 'damage' | 'support' | 'special';

export type Ability = {
  name: string;
  kind: AbilityKind;
  icon: string;
  blurb: string;
  /** tailwind tone key used by the skill card */
  tone: 'ember' | 'frost' | 'nature' | 'arcane' | 'storm' | 'shadow';
};

type Kit = { tone: Ability['tone']; abilities: [Ability, Ability, Ability] };

const kit = (tone: Ability['tone'], rows: [string, string][], support: [string, string], special: [string, string]): Kit => ({
  tone,
  abilities: [
    { name: rows[0][0], kind: 'damage', icon: rows[0][1], blurb: 'Dano direto', tone },
    { name: support[0], kind: 'support', icon: support[1], blurb: 'Cura e escudo', tone },
    { name: special[0], kind: 'special', icon: special[1], blurb: 'Golpe devastador', tone },
  ],
});

const KITS: Kit[] = [
  kit('ember', [['Garra Flamejante', 'flame']], ['Rugido de Guerra', 'shield'], ['Impacto Infernal', 'swords']),
  kit('frost', [['Raio Congelante', 'snowflake']], ['Guarda de Cristal', 'shield'], ['Explosão Lunar', 'moon']),
  kit('nature', [['Semente Selvagem', 'leaf']], ['Floração Curativa', 'heart'], ['Tiro de Espinhos', 'zap']),
  kit('arcane', [['Lâmina Arcana', 'sparkles']], ['Véu Etéreo', 'shield'], ['Colapso Astral', 'orbit']),
  kit('storm', [['Presa Trovejante', 'zap']], ['Vento Restaurador', 'wind'], ['Fúria da Tempestade', 'cloud']),
  kit('shadow', [['Corte Sombrio', 'skull']], ['Manto Umbral', 'shield'], ['Devorar Almas', 'flame']),
];

const hash = (value: string) => {
  let total = 0;
  for (let index = 0; index < value.length; index += 1) total = (total * 31 + value.charCodeAt(index)) % 100000;
  return total;
};

export const abilityKitFor = (name: string, slot: number): Kit => KITS[(hash(name || '') + slot) % KITS.length];

export const TONE_STYLE: Record<Ability['tone'], { border: string; bg: string; text: string; glow: string; flash: string }> = {
  ember: { border: 'border-orange-300/60', bg: 'from-orange-500/25 to-rose-900/20', text: 'text-orange-100', glow: 'shadow-[0_0_22px_-6px_rgba(251,146,60,.75)]', flash: 'bg-orange-300/40' },
  frost: { border: 'border-sky-300/60', bg: 'from-sky-400/25 to-indigo-900/20', text: 'text-sky-100', glow: 'shadow-[0_0_22px_-6px_rgba(56,189,248,.75)]', flash: 'bg-sky-200/40' },
  nature: { border: 'border-emerald-300/60', bg: 'from-emerald-400/25 to-teal-900/20', text: 'text-emerald-100', glow: 'shadow-[0_0_22px_-6px_rgba(52,211,153,.75)]', flash: 'bg-emerald-200/40' },
  arcane: { border: 'border-fuchsia-300/60', bg: 'from-fuchsia-400/25 to-purple-900/20', text: 'text-fuchsia-100', glow: 'shadow-[0_0_22px_-6px_rgba(232,121,249,.75)]', flash: 'bg-fuchsia-200/40' },
  storm: { border: 'border-amber-300/60', bg: 'from-amber-300/25 to-yellow-900/20', text: 'text-amber-100', glow: 'shadow-[0_0_22px_-6px_rgba(251,191,36,.75)]', flash: 'bg-amber-200/45' },
  shadow: { border: 'border-violet-300/60', bg: 'from-violet-500/25 to-slate-900/30', text: 'text-violet-100', glow: 'shadow-[0_0_22px_-6px_rgba(167,139,250,.75)]', flash: 'bg-violet-200/40' },
};
