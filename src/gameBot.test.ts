import { describe, expect, it } from 'vitest';
import { welcomeReply } from '../supabase/functions/game-bot/format';
describe('game bot welcome', () => {
  const update = (text: string, type = 'private') => ({ update_id: 1, message: { text, chat: { id: 42, type }, from: { id: 42 } } });
  it('welcomes private starts with image and launch button', () => {
    const reply = welcomeReply(update('/start referral_12'));
    expect(reply?.method).toBe('sendPhoto');
    expect(reply?.photo).toContain('mythic-seas-welcome.jpg');
    expect(reply?.reply_markup.inline_keyboard[0][0].web_app.url).toBe('https://mythicseas.lovable.app');
  });
  it('ignores unrelated, group and invalid updates', () => {
    for (const value of [null, {}, update('hello'), update('/start', 'group'), update('/startother')]) expect(welcomeReply(value)).toBeNull();
  });
});