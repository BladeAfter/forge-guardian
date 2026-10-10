import { describe, expect, it, vi } from 'vitest';
vi.mock('../supabase/functions/game-bot/tutorialLocalizedMedia', () => ({ LOCALIZED_TUTORIAL_VIDEOS: { ru: 'test-rendered-russian-video', en: 'test-rendered-english-video' } }));
import { deliverFirstTutorial } from '../supabase/functions/game-bot/tutorial';
import { welcomeReply } from '../supabase/functions/game-bot/format';
import { languageFromUpdate } from '../supabase/functions/game-bot/tutorialLanguages';
describe('language-specific tutorial delivery', () => {
  it('sends the Russian video to a Russian Telegram user, only once', async () => {
    const update = { update_id: 1, message: { text: '/start', chat: { id: 42, type: 'private' }, from: { id: 42, language_code: 'ru' } } };
    const reply = welcomeReply(update);
    if (!reply) throw new Error('Expected reply');
    let claimed = false; const videos: unknown[] = [];
    const store = { claim: async () => { if (claimed) return false; claimed = true; return true; }, finish: async () => {} };
    const send = async (payload: Record<string, unknown>) => { videos.push(payload.video); return { ok: true, result: { message_id: 1 } }; };
    await deliverFirstTutorial(reply, 1, store, send, languageFromUpdate(update));
    await deliverFirstTutorial(reply, 2, store, send, languageFromUpdate(update));
    expect(videos).toEqual(['test-rendered-russian-video']);
  });
});