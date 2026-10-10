import type { ChannelReward } from './services';

const official = [
  { key: 'news', title: 'Notícias', subtitle: 'Novidades de Mythic Seas', url: 'https://t.me/MythicSeasNews' },
  { key: 'community', title: 'Comunidade', subtitle: 'Tripulação reunida no chat', url: 'https://t.me/MythicSeasChat' },
  { key: 'payments', title: 'Pagamentos', subtitle: 'Depósitos e saques confirmados', url: 'https://t.me/MythicSeasPayout' },
] as const;

export function officialChannelLinks(channels: ChannelReward[] = []): ChannelReward[] {
  return official.map(link => {
    const server = channels.find(channel => channel.key === link.key);
    return { rewardFc: 0, enabled: false, verifiable: false, joined: false, claimed: false,
      rewardReceived: 0, claimedAt: null, ...server, ...link };
  });
}