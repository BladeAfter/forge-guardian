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