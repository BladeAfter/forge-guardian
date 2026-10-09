import { useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Anchor, Compass, CalendarDays, Check, ChevronRight, Copy, Loader2, MessageCircle, Megaphone, Wallet as WalletIcon } from 'lucide-react';
import { useChannelRewards, useRewardHistory, useSeasonPass } from '../hooks';
import { channelsRequest, type ChannelReward, type RewardHistoryItem } from '../services';
import { getDisplayName, getInitials, type TelegramPlayerProfile } from '../playerProfile';
import type { GameState } from '../types';
import { useT } from '../LanguageContext';
import{PlayerTag}from'../premiumTitles';
import { AvatarWithBorder } from '../components/AvatarWithBorder';
import { profileArt } from '../gameAssets';
import { captainCharacters, readCaptainStyle, saveCaptainStyle, type CaptainStyle } from '../captainCharacter';
import { OceanControl } from '../components/OceanControl';

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
  return (
    <li className="captain-reward">
      <div className="captain-reward-art">
        {isImageUrl(item.image_url)
          ? <img src={item.image_url as string} alt={item.reward_name} loading="lazy" className="h-full w-full object-cover" />
          : <img src={profileArt.treasure} alt="" width={40} height={40} loading="lazy" />}
      </div>
      <div className="min-w-0 flex-1">
        <p className="captain-reward-name">{itemTitle(item, t)}</p>
        <p className={`captain-rarity captain-rarity--${rarity ?? 'common'}`}>
          {rarity ? rarity : typeLabel(item.reward_type, t)}
        </p>
      </div>
      <span className="captain-reward-time">{relativeTime(item.created_at, t)}</span>
    </li>
  );
}

export function ProfilePage({ game, profile, telegramInitData, backendEnabled, onOpenBattlePass }: ProfilePageProps) {
  const t = useT();
  const [copied, setCopied] = useState(false);
  const [captainStyle, setCaptainStyle] = useState<CaptainStyle>(() => readCaptainStyle(profile?.telegramId));
  const [showAll, setShowAll] = useState(false);
  const enabled = Boolean(telegramInitData) && backendEnabled;
  const history = useRewardHistory(telegramInitData, enabled, showAll ? 50 : 5);
  const seasonPass = useSeasonPass(telegramInitData, enabled);
  const channels = useChannelRewards(telegramInitData, enabled);
  const queryClient = useQueryClient();
  const [channelError, setChannelError] = useState<{ key: string; message: string } | null>(null);
  const [joined, setJoined] = useState<Record<string, boolean>>({});

  /** JOIN never pays: only this verify call (server-side getChatMember) can credit BERRIES. */
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
    <section className="captain-profile">
      <header className="captain-cover">
        <img className="captain-deck" src={profileArt.deck} alt="Convés de um navio nas águas de Mythic Seas" width={1280} height={768} />
        <div className="captain-cover-title"><span><Compass size={25} strokeWidth={1.3} />MYTHIC SEAS</span><h1>Ficha de <em>capitão</em></h1><i aria-hidden="true" /></div>
        <div className="captain-identity">
          <div className="captain-portrait">
            {profile?.photoUrl ? <AvatarWithBorder photoUrl={profile.photoUrl} border={profile.avatarBorder} fallback={getInitials(name)} size={80} /> : <img src={profileArt.captain} alt="" width={80} height={80} />}
          </div>
          <div className="captain-name"><h2>{name}</h2><p><PlayerTag telegramId={profile?.telegramId} username={profile?.username} fallback={t('profile.noUsername')} /></p></div>
        </div>
      </header>

      <div className="captain-content">
      <div className="captain-registry"><span>REGISTRO DE NAVEGANTE</span><div><span>ID {profile?.telegramId ?? '—'}</span><OceanControl onClick={copyId} disabled={!profile?.telegramId} title={t('profile.copyIdAria')} aria-label={t('profile.copyIdAria')} className="captain-copy">{copied ? <Check size={15} /> : <Copy size={15} />}</OceanControl></div></div>

      <div className="captain-log">
        <div className="captain-streak"><CalendarDays size={18} /><div><span>Dias a bordo</span><strong>{game.loginStreak}<small> {game.loginStreak === 1 ? 'dia seguido' : 'dias seguidos'}</small></strong></div></div>
        <OceanControl type="button" onClick={onOpenBattlePass} className="captain-pass"><img src={profileArt.pass} alt="" width={60} height={60} loading="lazy" /><div><span>{t('profile.battlePass')}</span><strong>{seasonPass.isLoading ? '…' : passLabel}</strong><small className={passActive ? 'captain-status-active' : ''}>{passActive ? t('profile.active') : t('profile.inactive')}</small></div><ChevronRight size={18} /></OceanControl>
      </div>

      <div className="captain-showcase">
      <section className="captain-character-section" aria-label="Personagem do perfil">
        <div className="captain-section-heading"><div><span><Compass size={13} />SEU PERSONAGEM</span><h2>Pirata de bordo</h2></div></div>
        <div className="captain-character-stage"><img className="captain-featured-character" src={captainCharacters[captainStyle].image} alt={captainStyle === 'male' ? 'Capitão pirata selecionado' : 'Capitã pirata selecionada'} width={512} height={512} /><div className="captain-character-options">{(['male', 'female'] as const).map(style => <OceanControl key={style} aria-label={style === 'male' ? 'Escolher pirata masculino' : 'Escolher pirata feminina'} aria-pressed={captainStyle === style} disabled={!profile?.telegramId} className={`captain-character-choice ${captainStyle === style ? 'is-selected' : ''}`} onClick={() => { if (!profile?.telegramId) return; saveCaptainStyle(profile.telegramId, style); setCaptainStyle(style); }}><img src={captainCharacters[style].image} alt={style === 'male' ? 'Pirata masculino' : 'Pirata feminina'} width={100} height={130} loading="lazy" />{captainStyle === style && <Check size={18} />}</OceanControl>)}</div></div>
      </section>

      <section className="captain-journal">
        <div className="captain-section-heading"><div><span>ESPÓLIOS DA JORNADA</span><h2>Diário de conquistas</h2></div>{items.length > 0 && <OceanControl type="button" onClick={() => setShowAll(value => !value)} className="captain-text-action">{showAll ? t('profile.showLess') : t('profile.viewAll')}<ChevronRight size={14} /></OceanControl>}</div>
        {history.isLoading ? <p className="captain-muted">{t('profile.loadingRewards')}</p> : items.length ? <ul className={`captain-rewards ${showAll ? 'captain-rewards-expanded' : ''}`}>{items.map((item, index) => <RewardRow key={`${item.reward_type}-${item.reward_key}-${item.created_at}-${index}`} item={item} />)}</ul> : <div className="captain-empty"><img src={profileArt.treasure} alt="" width={72} height={72} loading="lazy" /><div><p>Seu tesouro começa aqui</p><span>{t('profile.noRewardsYet')}</span></div></div>}
      </section>
      </div>

      <section className="captain-signals">
        <div className="captain-section-heading"><div><span><Anchor size={17} />RÁDIO DO NAVIO</span><h2>{t('profile.officialChannels')}</h2></div></div>
        {channels.isLoading ? <p className="captain-muted">{t('profile.loadingChannels')}</p> : <div className="captain-channel-list">{(channels.data?.channels ?? []).filter(channel => channel.enabled).map((channel: ChannelReward) => {
          const Icon = CHANNEL_ICON[channel.key] ?? Megaphone;
          const pending = verify.isPending && verify.variables === channel.key;
          const failed = channelError?.key === channel.key;
          return <article className="captain-channel" key={channel.key}>
            <div className="captain-channel-info"><Icon size={21} /><div><h3>{channel.title}</h3><p>{channel.subtitle}</p></div><span>{channel.claimed ? <Check size={18} aria-label={t('profile.claimed')} /> : `+${formatFc(channel.rewardFc)}`}</span></div>
            {channel.claimed ? <div className="captain-channel-actions"><span className="captain-status-active">{t('profile.rewardClaimed', { amount: formatFc(channel.rewardReceived || channel.rewardFc) })}</span><OceanControl type="button" className="captain-text-action" onClick={() => openTelegramLink(channel.url)}>{t('profile.openChannel')}<ChevronRight size={14} /></OceanControl></div> : <div className="captain-channel-actions"><OceanControl type="button" className="captain-channel-join" onClick={() => { setJoined(state => ({ ...state, [channel.key]: true })); openTelegramLink(channel.url); }}>{t('profile.join')}<ChevronRight size={14} /></OceanControl><OceanControl type="button" className={`captain-channel-verify ${joined[channel.key] ? 'is-joined' : ''}`} disabled={pending} onClick={() => verify.mutate(channel.key)}>{pending && <Loader2 size={14} className="animate-spin" />}{pending ? t('profile.verifying') : t('profile.verify')}</OceanControl></div>}
            {failed && <p className="captain-channel-error">{channelError?.message}</p>}
          </article>;
        })}</div>}
      </section>
      </div>
    </section>
  );
}
