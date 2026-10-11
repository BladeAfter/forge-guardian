import { describe, expect, it } from 'vitest';
import { languageFromUpdate, tutorialLanguage, tutorialForLanguage, tutorialCaption } from '../supabase/functions/game-bot/tutorialLanguages';
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
  it('uses the Portuguese video for Brazilian and Portuguese Telegram locales', () => {
    const original = tutorialForLanguage('pt');
    expect(original?.video).toMatch(/tutorial-v3-combate-naval\.mp4$/);
    expect(tutorialForLanguage('pt-BR')).toEqual(original);
    expect(tutorialForLanguage('pt-PT')).toEqual(original);
  });
  it('provides distinct public HTTPS Russian and English video URLs for Telegram', () => {
    expect(tutorialForLanguage('ru')?.video).toMatch(/^https:\/\/mythicseas\.lovable\.app\/.*tutorial-ru-v2-batalha-naval\.mp4$/);
    expect(tutorialForLanguage('en')?.video).toMatch(/^https:\/\/mythicseas\.lovable\.app\/.*tutorial-en-v2-batalha-naval\.mp4$/);
    expect(tutorialForLanguage('ru')?.video).not.toBe(tutorialForLanguage('en')?.video);
  });
  it('uses the naval tutorial revision for every existing supported language', () => {
    for (const language of ['pt', 'am', 'ar', 'az', 'be', 'bg', 'bn', 'ca', 'cs', 'de', 'el', 'en', 'es', 'fa', 'fi', 'fil', 'fr', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'kk', 'ko', 'ms', 'nl', 'no', 'pl', 'ro', 'ru', 'sk', 'sr', 'sw', 'ta', 'th', 'tr', 'uk', 'ur', 'uz', 'vi', 'zh']) {
      expect(tutorialForLanguage(language)?.video).toMatch(language === 'pt' ? /tutorial-v3-combate-naval\.mp4$/ : /-v2-batalha-naval\.mp4$/);
    }
  });
  it('labels the Portuguese battle demonstration as simulated without real asset transfers', () => {
    expect(tutorialCaption('pt')).toContain('batalha naval simulada');
    expect(tutorialCaption('pt')).toContain('não movimenta bens reais');
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