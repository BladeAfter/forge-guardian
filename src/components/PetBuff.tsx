import type { JSX, ReactNode } from 'react';
import { Coins, Flame, Heart, Shield, Star, Swords, Zap } from 'lucide-react';

const BUFF_ICONS: Record<string, JSX.Element> = {
  boss_damage_percent: <Flame />,
  team_hp_percent: <Heart />,
  farm_fc_percent: <Coins />,
  pvp_attack_percent: <Swords />,
  pvp_defense_percent: <Shield />,
  drop_chance_percent: <Star />,
};

export const petBuffIcon = (key?: string | null): JSX.Element => (key && BUFF_ICONS[key]) || <Zap />;

type Size = 'sm' | 'md';

const SIZES: Record<Size, { box: string; icon: number; label: string; value: string }> = {
  sm: { box: 'gap-1.5 px-2 py-1.5', icon: 20, label: 'text-[8px]', value: 'text-[13px]' },
  md: { box: 'gap-2 px-2.5 py-2', icon: 26, label: 'text-[9px]', value: 'text-lg' },
};


export function PetBuff({
  buffKey,
  label,
  value,
  size = 'sm',
  color,
  valueClassName,
  className,
  icon,
}: {
  buffKey?: string | null;
  label: string;
  value: string;
  size?: Size;
  color?: string;
  valueClassName?: string;
  className?: string;
  icon?: ReactNode;
}) {
  const s = SIZES[size];
  return (
    <div className={`flex items-center ${s.box} ${className ?? ''}`}>
      <span
        aria-hidden
        className="flex shrink-0 items-center justify-center [&>svg]:h-full [&>svg]:w-full"
        style={{ width: s.icon, height: s.icon, color }}
      >
        {icon ?? petBuffIcon(buffKey)}
      </span>
      <div className="flex min-w-0 flex-col justify-center">
        <p className={`m-0 truncate font-bold uppercase leading-[1.1] tracking-wide text-slate-300 ${s.label}`}>{label}</p>
        <b
          className={`mt-[3px] font-black leading-[1.1] ${s.value} ${valueClassName ?? 'text-emerald-300'}`}
          style={color ? { color } : undefined}
        >
          {value}
        </b>
      </div>
    </div>
  );
}
