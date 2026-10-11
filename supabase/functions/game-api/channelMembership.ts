export function confirmedTelegramMember(result?: { status?: string; is_member?: boolean } | null): boolean {
  return Boolean(result && (['creator', 'administrator', 'member'].includes(result.status ?? '') ||
    (result.status === 'restricted' && result.is_member === true)));
}

export async function verifyOfficialChannel(chatRef: string | null, telegramId: number,
  check: (chat: string, id: number) => Promise<boolean>, claim: () => Promise<unknown>) {
  if (!chatRef) throw new Error('CHANNEL_NOT_AVAILABLE');
  if (!await check(chatRef, telegramId)) throw new Error('CHANNEL_MEMBERSHIP_REQUIRED');
  return claim();
}
const officialChats: Record<string, { id: string; handle: string }> = {
  news: { id: '-1004294416879', handle: '@MythicSeasNews' },
  community: { id: '-1004457596870', handle: '@MythicSeasChat' },
  payments: { id: '-1003882873432', handle: '@MythicSeasPayout' },
};

/** Fresh fixed-channel verification; never trust client identity or cached membership. */
export async function checkOfficialMembership(key: string, chatRef: string | null, telegramId: number,
  token: string, request: typeof fetch = fetch): Promise<boolean> {
  const target = officialChats[key];
  const botId = Number(token.split(':')[0]);
  if (!target || !token || !Number.isSafeInteger(botId) || botId <= 0 ||
    !Number.isSafeInteger(telegramId) || telegramId <= 0 ||
    (chatRef !== target.handle && chatRef !== target.id)) return false;
  const member = async (id: number) => {
    const response = await request(`https://api.telegram.org/bot${token}/getChatMember`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: target.id, user_id: id }),
      signal: AbortSignal.timeout(5000), cache: 'no-store',
    });
    if (!response.ok) return null;
    const payload = await response.json() as {
      ok?: boolean; result?: { status?: string; is_member?: boolean; user?: { id?: number } };
    };
    return payload?.ok === true && payload.result?.user?.id === id ? payload.result : null;
  };
  try {
    // Telegram guarantees other-user membership lookups only for administrator bots.
    const bot = await member(botId);
    if (!bot || !['creator', 'administrator'].includes(bot.status ?? '')) return false;
    return confirmedTelegramMember(await member(telegramId));
  } catch {
    return false;
  }
}
