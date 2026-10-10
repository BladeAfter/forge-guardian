import { describe, expect, it } from 'vitest';
import { confirmedTelegramMember, verifyOfficialChannel } from '../supabase/functions/game-api/channelMembership';
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