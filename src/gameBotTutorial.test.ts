import { describe, expect, it } from 'vitest';
import { deliverFirstTutorial } from '../supabase/functions/game-bot/tutorial';
import { welcomeReply } from '../supabase/functions/game-bot/format';
describe('first-start tutorial', () => {
  const reply = () => {
    const value = welcomeReply({ update_id: 1, message: { text: '/start', chat: { id: 42, type: 'private' }, from: { id: 42 } } });
    if (!value) throw new Error('Expected private start');
    return value;
  };
  it('sends once per player across repeated starts and duplicate updates', async () => {
    const claimed = new Set<number>(); const sent: Record<string, unknown>[] = [];
    const store = { claim: async (id: number) => { if (claimed.has(id)) return false; claimed.add(id); return true; }, finish: async () => {} };
    for (const updateId of [1, 1, 2]) await deliverFirstTutorial(reply(), updateId, store, async payload => { sent.push(payload); return { ok: true, result: { message_id: 99 } }; });
    expect(sent).toHaveLength(1);
    expect(sent[0].chat_id).toBe(42);
    expect(sent[0].video).toBeTruthy();
  });
  it('holds uncertain delivery for review', async () => {
    const statuses: string[] = [];
    await deliverFirstTutorial(reply(), 3, { claim: async () => true, finish: async (_id, status) => { statuses.push(status); } }, async () => { throw new Error('Timeout'); });
    expect(statuses).toEqual(['review']);
  });
});
