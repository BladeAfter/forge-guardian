import { describe, expect, it } from 'vitest';
import { languageFromUpdate, tutorialLanguage, tutorialForLanguage } from '../supabase/functions/game-bot/tutorialLanguages';
import { deliverFirstTutorial } from '../supabase/functions/game-bot/tutorial';
import { welcomeReply } from '../supabase/functions/game-bot/format';
describe('Telegram tutorial language', () => {
  it('detects Russian from Telegram sender', () => {
    expect(languageFromUpdate({ message: { from: { language_code: 'ru-RU' } } })).toBe('ru');
  });
  it('normalizes regional codes and aliases', () => {
    expect(tutorialLanguage('pt-BR')).toBe('pt');
    expect(tutorialLanguage('zh_CN')).toBe('zh');
    expect(tutorialLanguage('iw')).toBe('he');
  });
  it('defaults missing Telegram language to English', () => {
    expect(languageFromUpdate({ message: { from: {} } })).toBe('en');
  });
  it('never substitutes Portuguese or claims a missing-language delivery', async () => {
    const reply = welcomeReply({ update_id: 1, message: { text: '/start', chat: { id: 42, type: 'private' }, from: { id: 42 } } });
    if (!reply) throw new Error('Expected start');
    let claims = 0, sends = 0;
    expect(tutorialForLanguage('zz')).toBeNull();
    expect(await deliverFirstTutorial(reply, 1, { claim: async () => { claims++; return true; }, finish: async () => {} }, async () => { sends++; return { ok: true }; }, 'zz')).toBe(false);
    expect(claims).toBe(0);
    expect(sends).toBe(0);
  });
});