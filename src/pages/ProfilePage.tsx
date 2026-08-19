import { useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { CalendarDays, Check, ChevronRight, Copy, Crown, Gift, Loader2, MessageCircle, Megaphone, Wallet as WalletIcon } from 'lucide-react';
import { useChannelRewards, useRewardHistory, useSeasonPass } from '../hooks';
import { channelsRequest, type ChannelReward, type RewardHistoryItem } from '../services';
import { getDisplayName, getInitials, type TelegramPlayerProfile } from '../playerProfile';
import type { GameState } from '../types';
import { useT } from '../LanguageContext';
import{PlayerTag}from'../premiumTitles';
import { AvatarWithBorder } from '../components/AvatarWithBorder';

/** Reward icons come from mixed sources: only real URLs can be rendered as images. */
const isImageUrl = (value?: string | null) => Boolean(value && (/^https?:\/\//.test(value) || value.startsWith('/') || value.startsWith('data:')));

type ProfilePageProps = {
  game: GameState;
  profile: TelegramPlayerProfile | null;
  telegramInitData: string | null;
  backendEnabled: boolean;
  onOpenBattlePass: () => void;
};

const CHANNEL_ICON: Record<string, typeof Megaphone> = { news: Megaphone, community: MessageCircle, payments: WalletIcon };

const RARITY_COLOR: Record<string, string> = { common: '#cbd5f5', uncommon: '#4ade80', rare: '#38bdf8', epic: '#c084fc', legendary: '#fbbf24', mythic: '#fb7185', ancestral: '#f472b6', adventurer: '#38bdf8' };

const formatFc = (value: number) => new Intl.NumberFormat('en-US').format(Math.round(value));

const openTelegramLink = (url: string) => {
  const webApp = (window as any)?.Telegram?.WebApp;
  if (webApp?.openTelegramLink) webApp.openTelegramLink(url);
  else window.open(url, '_blank', 'noopener,noreferrer');
};

function relativeTime(iso: string, t: (key: string, params?: Record<string, string | number>) => string): string {
  const then = new Date(iso).getTime();
  if (!Number.isFinite(then)) return '';
  const diff = Math.max(0, Date.now() - then);
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return t('profile.time.justNow');
  if (minutes < 60) return t('profile.time.minutesAgo', { count: minutes });
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return t('profile.time.hoursAgo', { count: hours });
  const days = Math.floor(hours / 24);
  if (days < 7) return t('profile.time.daysAgo', { count: days });
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

/** Falls back to a readable label for any reward type the game adds later. */
const typeLabel = (type: string, t: (key: string) => string) => {
  const key = `profile.type.${type}`;
  const translated = t(key);
  return translated !== key ? translated : type.replace(/_/g, ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
};

function itemTitle(item: RewardHistoryItem, t: (key: string) => string): string {
  const quantity = Number(item.quantity ?? 1);
  const base = item.reward_name || typeLabel(item.reward_type, t) || 'Reward';
  if (quantity > 1) return `${base} x${quantity}`;
  return base;
}

function RewardRow({ item }: { item: RewardHistoryItem }) {
  const t = useT();
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
        <p className="truncate text-[12px] font-bold text-white">{itemTitle(item, t)}</p>
        <p className="truncate text-[9px] font-semibold uppercase tracking-[0.12em]" style={{ color }}>
          {rarity ? rarity : typeLabel(item.reward_type, t)}
        </p>
      </div>
      <span className="shrink-0 text-[9px] font-semibold uppercase tracking-wide text-slate-400">{relativeTime(item.created_at, t)}</span>
    </li>
  );
}

export function ProfilePage({ game, profile, telegramInitData, backendEnabled, onOpenBattlePass }: ProfilePageProps) {
  const t = useT();
  const [copied, setCopied] = useState(false);
  const [showAll, setShowAll] = useState(false);
  const enabled = Boolean(telegramInitData) && backendEnabled;
  const history = useRewardHistory(telegramInitData, enabled, showAll ? 50 : 5);
  const seasonPass = useSeasonPass(telegramInitData, enabled);
  const channels = useChannelRewards(telegramInitData, enabled);
  const queryClient = useQueryClient();
  const [channelError, setChannelError] = useState<{ key: string; message: string } | null>(null);
  const [joined, setJoined] = useState<Record<string, boolean>>({});

  /** JOIN never pays: only this verify call (server-side getChatMember) can credit FC. */
  const verify = useMutation({
    mutationFn: (channelKey: string) => channelsRequest(telegramInitData ?? '', { action: 'verify', channelKey }),
    onSuccess: () => {
      setChannelError(null);
      queryClient.invalidateQueries({ queryKey: ['channel-rewards'] });
      queryClient.invalidateQueries({ queryKey: ['wallet-summary'] });
      queryClient.invalidateQueries({ queryKey: ['game-state'] });
      queryClient.invalidateQueries({ queryKey: ['reward-history'] });
    },
    onError: (error: unknown, channelKey: string) =>
      setChannelError({ key: channelKey, message: error instanceof Error ? error.message : t('profile.verificationFailed') }),
  });



  const name = profile ? getDisplayName(profile) : t('profile.player');
  const tier = seasonPass.data?.player.tier ?? 'none';
  const passActive = tier === 'adventurer' || tier === 'legendary';
  const passLabel = tier === 'legendary' ? t('profile.tier.legendary') : tier === 'adventurer' ? t('profile.tier.adventurer') : t('profile.tier.none');

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
      <p className="px-1 text-[10px] font-bold uppercase tracking-[0.3em] text-amber-300">{t('profile.title')}</p>

      {/* Single identity block — the app header is hidden on this tab to avoid duplication. */}
      <div className="relative overflow-hidden rounded-3xl border border-amber-300/25 bg-[#080d17]/90 p-3 shadow-[0_12px_35px_rgba(0,0,0,.55)]">
        <div className="absolute -right-14 -top-14 h-40 w-40 rounded-full bg-amber-500/10 blur-3xl" />
        <div className="relative flex items-center gap-3">
          <AvatarWithBorder photoUrl={profile?.photoUrl} border={profile?.avatarBorder} fallback={getInitials(name)} size={profile?.avatarBorder ? 78 : 56} />
          <div className="min-w-0 flex-1">
            <p className="truncate text-[15px] font-black leading-tight text-white">{name}</p>
            <p className="truncate text-[11px] font-semibold text-sky-300"><PlayerTag telegramId={profile?.telegramId} username={profile?.username} fallback={t('profile.noUsername')}/></p>
            <div className="mt-1 flex items-center gap-1.5">
              <span className="truncate text-[10px] text-slate-400">ID: {profile?.telegramId ?? '--'}</span>
              <button
                type="button"
                onClick={copyId}
                aria-label={t('profile.copyIdAria')}
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
            <p className="truncate text-[9px] font-bold uppercase tracking-[0.16em] text-slate-400">{t('profile.loginStreak')}</p>
          </div>
          <p className="mt-1.5 text-lg font-black text-white">{game.loginStreak}d</p>
        </div>
        <button type="button" onClick={onOpenBattlePass} className="rounded-2xl border border-amber-300/15 bg-[#080d17]/85 p-3 text-left active:scale-[0.98]">
          <div className="flex items-center gap-1.5">
            <Crown className="h-3.5 w-3.5 shrink-0 text-amber-300" />
            <p className="truncate text-[9px] font-bold uppercase tracking-[0.16em] text-slate-400">{t('profile.battlePass')}</p>
          </div>
          <p className={`mt-1.5 text-[11px] font-black uppercase ${passActive ? 'text-emerald-300' : 'text-slate-500'}`}>{passActive ? t('profile.active') : t('profile.inactive')}</p>
          <p className="truncate text-[10px] font-semibold text-amber-200">{seasonPass.isLoading ? '...' : passLabel}</p>
        </button>
      </div>

      <div className="rounded-3xl border border-amber-300/15 bg-[#080d17]/85 p-3">
        <div className="flex items-center justify-between gap-2">
          <p className="truncate text-[10px] font-bold uppercase tracking-[0.2em] text-amber-300">{t('profile.recentlyUnlocked')}</p>
          {items.length ? (
            <button type="button" onClick={() => setShowAll((value) => !value)} className="flex shrink-0 items-center gap-0.5 text-[10px] font-bold text-sky-300">
              {showAll ? t('profile.showLess') : t('profile.viewAll')} <ChevronRight className="h-3 w-3" />
            </button>
          ) : null}
        </div>
        {history.isLoading ? (
          <p className="mt-3 text-[11px] text-slate-400">{t('profile.loadingRewards')}</p>
        ) : items.length ? (
          <ul className={`mt-2.5 space-y-1.5 ${showAll ? 'max-h-[52vh] overflow-y-auto pr-0.5' : ''}`}>
            {items.map((item, index) => <RewardRow key={`${item.reward_type}-${item.reward_key}-${item.created_at}-${index}`} item={item} />)}
          </ul>
        ) : (
          <div className="mt-2.5 rounded-2xl border border-white/5 bg-black/30 px-3 py-4 text-center">
            <p className="text-[12px] font-bold text-white">{t('profile.noRewardsYet')}</p>
            <p className="mt-1 text-[10px] text-slate-400">{t('profile.playToEarn')}</p>
          </div>
        )}
      </div>

      <div className="rounded-3xl border border-amber-300/15 bg-[#080d17]/85 p-3">
        <div className="flex items-center justify-between gap-2">
          <p className="truncate text-[10px] font-bold uppercase tracking-[0.2em] text-amber-300">{t('profile.officialChannels')}</p>
          <span className="shrink-0 text-[9px] font-bold uppercase tracking-wide text-emerald-300">{t('profile.rewardPerChannel', { amount: '5,000' })}</span>
        </div>
        {channels.isLoading ? (
          <p className="mt-3 text-[11px] text-slate-400">{t('profile.loadingChannels')}</p>
        ) : (
          <div className="mt-2.5 space-y-1.5">
            {(channels.data?.channels ?? []).filter((channel) => channel.enabled).map((channel: ChannelReward) => {
              const Icon = CHANNEL_ICON[channel.key] ?? Megaphone;
              const pending = verify.isPending && verify.variables === channel.key;
              const failed = channelError?.key === channel.key;
              return (
                <div key={channel.key} className="rounded-2xl border border-amber-300/10 bg-black/35 p-2.5">
                  <div className="flex items-center gap-2.5">
                    <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl border border-amber-300/20 bg-[#0b1120] text-amber-300"><Icon className="h-4 w-4" /></span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[11px] font-black uppercase tracking-wide text-white">{channel.title}</p>
                      <p className="truncate text-[9px] text-slate-400">{channel.subtitle}</p>
                    </div>
                    {channel.claimed ? (
                      <span className="flex shrink-0 items-center gap-1 rounded-lg border border-emerald-400/30 bg-emerald-500/10 px-2 py-1 text-[9px] font-black uppercase text-emerald-300">
                        <Check className="h-3 w-3" /> {t('profile.claimed')}
                      </span>
                    ) : (
                      <span className="shrink-0 text-[10px] font-black text-amber-300">+{formatFc(channel.rewardFc)} FC</span>
                    )}
                  </div>
                  {channel.claimed ? (
                    <div className="mt-2 flex items-center gap-1.5">
                      <p className="min-w-0 flex-1 truncate text-[9px] font-black uppercase tracking-wide text-emerald-300">
                        {t('profile.rewardClaimed', { amount: formatFc(channel.rewardReceived || channel.rewardFc) })}
                      </p>
                      <button
                        type="button"
                        onClick={() => openTelegramLink(channel.url)}
                        className="flex h-9 shrink-0 items-center justify-center gap-1 rounded-xl border border-amber-300/25 bg-black/50 px-3 text-[10px] font-black uppercase tracking-wide text-amber-200 active:scale-[0.98]"
                      >
                        {t('profile.openChannel')} <ChevronRight className="h-3 w-3" />
                      </button>
                    </div>
                  ) : (
                    <div className="mt-2 flex items-center gap-1.5">
                      <button
                        type="button"
                        onClick={() => { setJoined((state) => ({ ...state, [channel.key]: true })); openTelegramLink(channel.url); }}
                        className="flex h-10 flex-1 items-center justify-center gap-1 rounded-xl border border-amber-300/25 bg-black/50 text-[10px] font-black uppercase tracking-wide text-amber-200 active:scale-[0.98]"
                      >
                        {t('profile.join')} <ChevronRight className="h-3 w-3" />
                      </button>
                      <button
                        type="button"
                        disabled={pending}
                        onClick={() => verify.mutate(channel.key)}
                        className={`flex h-10 flex-1 items-center justify-center gap-1 rounded-xl border text-[10px] font-black uppercase tracking-wide active:scale-[0.98] ${joined[channel.key] ? 'border-emerald-400/40 bg-emerald-500/15 text-emerald-200' : 'border-amber-300/25 bg-amber-500/10 text-amber-200'} disabled:opacity-50`}
                      >
                        {pending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : null}
                        {pending ? t('profile.verifying') : t('profile.verify')}
                      </button>
                    </div>
                  )}
                  {failed ? <p className="mt-1.5 text-[9px] font-semibold text-rose-300">{channelError?.message}</p> : null}

                </div>
              );
            })}
          </div>
        )}
      </div>

    </section>
  );
}
