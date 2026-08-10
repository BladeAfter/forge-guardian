import { useMemo, useState } from 'react';
import { CalendarDays, Check, ChevronRight, Copy, Crown, Gift, MessageCircle, Megaphone, Wallet as WalletIcon } from 'lucide-react';
import { useRewardHistory, useSeasonPass } from '../hooks';
import type { RewardHistoryItem } from '../services';
import { getDisplayName, getInitials, type TelegramPlayerProfile } from '../playerProfile';
import type { GameState } from '../types';

type ProfilePageProps = {
  game: GameState;
  profile: TelegramPlayerProfile | null;
  telegramInitData: string | null;
  backendEnabled: boolean;
  onOpenBattlePass: () => void;
};

const CHANNELS = [
  { key: 'news', title: 'NEWS CHANNEL', subtitle: 'Stay updated with the latest news', url: 'https://t.me/+h5n08oLrHIlmOWQx', Icon: Megaphone },
  { key: 'community', title: 'COMMUNITY CHAT', subtitle: 'Chat with other players', url: 'https://t.me/+7a9XTXSObkw4ODc5', Icon: MessageCircle },
  { key: 'payments', title: 'PAYMENTS CHANNEL', subtitle: 'Deposits, withdrawals and payments', url: 'https://t.me/+M_ZLb9QUod0zZjcx', Icon: WalletIcon },
] as const;

const RARITY_COLOR: Record<string, string> = { common: '#cbd5f5', uncommon: '#4ade80', rare: '#38bdf8', epic: '#c084fc', legendary: '#fbbf24', mythic: '#fb7185', adventurer: '#38bdf8' };

const openTelegramLink = (url: string) => {
  const webApp = (window as any)?.Telegram?.WebApp;
  if (webApp?.openTelegramLink) webApp.openTelegramLink(url);
  else window.open(url, '_blank', 'noopener,noreferrer');
};

function relativeTime(iso: string): string {
  const then = new Date(iso).getTime();
  if (!Number.isFinite(then)) return '';
  const diff = Math.max(0, Date.now() - then);
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days === 1) return 'Yesterday';
  if (days < 7) return `${days}d ago`;
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

const TYPE_LABEL: Record<string, string> = { hero: 'Hero', pet: 'Pet', egg: 'Egg', food: 'Pet Food', fragment: 'Fragments', chest: 'Chest', hero_chest: 'Hero Chest', pet_egg: 'Pet Egg', fc: 'Forge Coins', pass_reward: 'Battle Pass', item: 'Item' };

/** Falls back to a readable label for any reward type the game adds later. */
const typeLabel = (type: string) => TYPE_LABEL[type] ?? type.replace(/_/g, ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());

function itemTitle(item: RewardHistoryItem): string {
  const quantity = Number(item.quantity ?? 1);
  const base = item.reward_name || typeLabel(item.reward_type) || 'Reward';
  if (quantity > 1) return `${base} x${quantity}`;
  return base;
}

function RewardRow({ item }: { item: RewardHistoryItem }) {
  const rarity = item.rarity?.toLowerCase() ?? null;
  const color = rarity ? RARITY_COLOR[rarity] ?? '#cbd5f5' : '#cbd5f5';
  return (
    <li className="flex items-center gap-2.5 rounded-2xl border border-amber-300/10 bg-black/35 px-2.5 py-2">
      <div className="grid h-10 w-10 shrink-0 place-items-center overflow-hidden rounded-xl border border-amber-300/20 bg-[#0b1120]">
        {item.image_url
          ? <img src={item.image_url} alt={item.reward_name} loading="lazy" className="h-full w-full object-cover" />
          : <Gift className="h-4 w-4 text-amber-300" />}
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-[12px] font-bold text-white">{itemTitle(item)}</p>
        <p className="truncate text-[9px] font-semibold uppercase tracking-[0.12em]" style={{ color }}>
          {rarity ? rarity : typeLabel(item.reward_type)}
        </p>
      </div>
      <span className="shrink-0 text-[9px] font-semibold uppercase tracking-wide text-slate-400">{relativeTime(item.created_at)}</span>
    </li>
  );
}

export function ProfilePage({ game, profile, telegramInitData, backendEnabled, onOpenBattlePass }: ProfilePageProps) {
  const [copied, setCopied] = useState(false);
  const [showAll, setShowAll] = useState(false);
  const enabled = Boolean(telegramInitData) && backendEnabled;
  const history = useRewardHistory(telegramInitData, enabled, showAll ? 50 : 5);
  const seasonPass = useSeasonPass(telegramInitData, enabled);

  const name = profile ? getDisplayName(profile) : 'Player';
  const tier = seasonPass.data?.player.tier ?? 'none';
  const passActive = tier === 'adventurer' || tier === 'legendary';
  const passLabel = tier === 'legendary' ? 'Legendary' : tier === 'adventurer' ? 'Adventurer' : 'No Battle Pass';

  const items = useMemo(() => history.data?.items ?? [], [history.data]);

  const copyId = async () => {
    if (!profile?.telegramId) return;
    try {
      await navigator.clipboard.writeText(String(profile.telegramId));
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  };

  return (
    <section className="space-y-3 pb-2">
      <p className="px-1 text-[10px] font-bold uppercase tracking-[0.3em] text-amber-300">Profile</p>

      {/* Single identity block — the app header is hidden on this tab to avoid duplication. */}
      <div className="relative overflow-hidden rounded-3xl border border-amber-300/25 bg-[#080d17]/90 p-3 shadow-[0_12px_35px_rgba(0,0,0,.55)]">
        <div className="absolute -right-14 -top-14 h-40 w-40 rounded-full bg-amber-500/10 blur-3xl" />
        <div className="relative flex items-center gap-3">
          {profile?.photoUrl
            ? <img src={profile.photoUrl} alt={name} className="h-14 w-14 shrink-0 rounded-full border-2 border-amber-400/60 object-cover" />
            : <div className="grid h-14 w-14 shrink-0 place-items-center rounded-full border-2 border-amber-400/60 bg-[#0b1120] text-sm font-black text-amber-200">{getInitials(name)}</div>}
          <div className="min-w-0 flex-1">
            <p className="truncate text-[15px] font-black leading-tight text-white">{name}</p>
            <p className="truncate text-[11px] font-semibold text-sky-300">{profile?.username ? `@${profile.username}` : 'No username'}</p>
            <div className="mt-1 flex items-center gap-1.5">
              <span className="truncate text-[10px] text-slate-400">ID: {profile?.telegramId ?? '--'}</span>
              <button
                type="button"
                onClick={copyId}
                aria-label="Copy Telegram ID"
                className="grid h-6 w-6 shrink-0 place-items-center rounded-lg border border-amber-300/25 bg-black/40 text-amber-200 active:scale-95"
              >
                {copied ? <Check className="h-3 w-3 text-emerald-300" /> : <Copy className="h-3 w-3" />}
              </button>
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <div className="rounded-2xl border border-amber-300/15 bg-[#080d17]/85 p-3">
          <div className="flex items-center gap-1.5">
            <CalendarDays className="h-3.5 w-3.5 shrink-0 text-amber-300" />
            <p className="truncate text-[9px] font-bold uppercase tracking-[0.16em] text-slate-400">Login Streak</p>
          </div>
          <p className="mt-1.5 text-lg font-black text-white">{game.loginStreak}d</p>
        </div>
        <button type="button" onClick={onOpenBattlePass} className="rounded-2xl border border-amber-300/15 bg-[#080d17]/85 p-3 text-left active:scale-[0.98]">
          <div className="flex items-center gap-1.5">
            <Crown className="h-3.5 w-3.5 shrink-0 text-amber-300" />
            <p className="truncate text-[9px] font-bold uppercase tracking-[0.16em] text-slate-400">Battle Pass</p>
          </div>
          <p className={`mt-1.5 text-[11px] font-black uppercase ${passActive ? 'text-emerald-300' : 'text-slate-500'}`}>{passActive ? 'Active' : 'Inactive'}</p>
          <p className="truncate text-[10px] font-semibold text-amber-200">{seasonPass.isLoading ? '...' : passLabel}</p>
        </button>
      </div>

      <div className="rounded-3xl border border-amber-300/15 bg-[#080d17]/85 p-3">
        <div className="flex items-center justify-between gap-2">
          <p className="truncate text-[10px] font-bold uppercase tracking-[0.2em] text-amber-300">Recently Unlocked</p>
          {items.length ? (
            <button type="button" onClick={() => setShowAll((value) => !value)} className="flex shrink-0 items-center gap-0.5 text-[10px] font-bold text-sky-300">
              {showAll ? 'Show less' : 'View All'} <ChevronRight className="h-3 w-3" />
            </button>
          ) : null}
        </div>
        {history.isLoading ? (
          <p className="mt-3 text-[11px] text-slate-400">Loading rewards...</p>
        ) : items.length ? (
          <ul className={`mt-2.5 space-y-1.5 ${showAll ? 'max-h-[52vh] overflow-y-auto pr-0.5' : ''}`}>
            {items.map((item, index) => <RewardRow key={`${item.reward_type}-${item.reward_key}-${item.created_at}-${index}`} item={item} />)}
          </ul>
        ) : (
          <div className="mt-2.5 rounded-2xl border border-white/5 bg-black/30 px-3 py-4 text-center">
            <p className="text-[12px] font-bold text-white">No rewards unlocked yet.</p>
            <p className="mt-1 text-[10px] text-slate-400">Play missions, PvP and Boss battles to earn rewards.</p>
          </div>
        )}
      </div>

      <div className="rounded-3xl border border-amber-300/15 bg-[#080d17]/85 p-3">
        <p className="text-[10px] font-bold uppercase tracking-[0.2em] text-amber-300">Official Channels</p>
        <div className="mt-2.5 space-y-1.5">
          {CHANNELS.map(({ key, title, subtitle, url, Icon }) => (
            <button
              key={key}
              type="button"
              onClick={() => openTelegramLink(url)}
              className="flex w-full items-center gap-2.5 rounded-2xl border border-amber-300/10 bg-black/35 px-2.5 py-2.5 text-left active:scale-[0.99]"
            >
              <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl border border-amber-300/20 bg-[#0b1120] text-amber-300"><Icon className="h-4 w-4" /></span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[11px] font-black uppercase tracking-wide text-white">{title}</span>
                <span className="block truncate text-[9px] text-slate-400">{subtitle}</span>
              </span>
              <ChevronRight className="h-4 w-4 shrink-0 text-amber-300/70" />
            </button>
          ))}
        </div>
      </div>
    </section>
  );
}
