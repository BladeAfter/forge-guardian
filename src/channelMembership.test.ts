import { describe, expect, it } from 'vitest';
import { checkOfficialMembership, confirmedTelegramMember, verifyOfficialChannel } from '../supabase/functions/game-api/channelMembership';
describe('official channel membership', () => {
  it('rejects left, kicked, unknown and restricted non-members', () => {
    for (const result of [null, {}, { status: 'left' }, { status: 'kicked' }, { status: 'restricted', is_member: false }, { status: 'restricted' }]) expect(confirmedTelegramMember(result)).toBe(false);
  });
  it('accepts current members and restricted members only with is_member true', () => {
    for (const status of ['creator', 'administrator', 'member']) expect(confirmedTelegramMember({ status })).toBe(true);
    expect(confirmedTelegramMember({ status: 'restricted', is_member: true })).toBe(true);
  });
  it('never claims when Telegram does not confirm membership', async () => {
    let paid = 0;
    await expect(verifyOfficialChannel('@MythicSeasNews', 42, async () => false, async () => { paid++; })).rejects.toThrow('CHANNEL_MEMBERSHIP_REQUIRED');
    expect(paid).toBe(0);
  });
  it('checks the authenticated player before claiming', async () => {
    const steps: string[] = [];
    await verifyOfficialChannel('@MythicSeasChat', 42, async (chat, id) => { expect(chat).toBe('@MythicSeasChat'); expect(id).toBe(42); steps.push('verified'); return true; }, async () => { steps.push('claimed'); });
    expect(steps).toEqual(['verified', 'claimed']);
  });
});
 describe('strict official-channel checks', () => {
  const token = '99:isolated-test';
  function api(status = 'member', options: { wrongUser?: boolean; botStatus?: string; fail?: boolean } = {}) {
    const calls: Array<{ chat_id: string; user_id: number }> = [];
    const request = (async (_url: unknown, init?: RequestInit) => {
      const input = JSON.parse(String(init?.body)); calls.push(input);
      if (options.fail) throw new Error('network unavailable');
      return new Response(JSON.stringify({ ok: true, result: {
        status: input.user_id === 99 ? options.botStatus ?? 'administrator' : status,
        user: { id: options.wrongUser && input.user_id !== 99 ? 123 : input.user_id },
      } }), { status: 200 });
    }) as typeof fetch;
    return { request, calls };
  }
  it('checks bot permission and signed player in the fixed official chat', async () => {
    const mock = api();
    expect(await checkOfficialMembership('news', '@MythicSeasNews', 42, token, mock.request)).toBe(true);
    expect(mock.calls).toEqual([{ chat_id: '-1004294416879', user_id: 99 }, { chat_id: '-1004294416879', user_id: 42 }]);
  });
  it('never pays for a different identity, non-member or failed verification', async () => {
    for (const mock of [api('left'), api('kicked'), api('restricted'), api('member', { wrongUser: true }),
      api('member', { botStatus: 'member' }), api('member', { fail: true })]) {
      let paid = 0;
      await expect(verifyOfficialChannel('@MythicSeasNews', 42,
        (chat, id) => checkOfficialMembership('news', chat, id, token, mock.request),
        async () => { paid++; })).rejects.toThrow('CHANNEL_MEMBERSHIP_REQUIRED');
      expect(paid).toBe(0);
    }
    const mock = api();
    expect(await checkOfficialMembership('news', '@MythicSeasChat', 42, token, mock.request)).toBe(false);
    expect(await checkOfficialMembership('unknown', '@MythicSeasNews', 42, token, mock.request)).toBe(false);
    expect(mock.calls).toHaveLength(0);
  });
  it('checks again after leaving rather than reusing a prior success', async () => {
    expect(await checkOfficialMembership('news', '@MythicSeasNews', 42, token, api().request)).toBe(true);
    expect(await checkOfficialMembership('news', '@MythicSeasNews', 42, token, api('left').request)).toBe(false);
  });
});
