import { tutorialForLanguage, tutorialCaption } from './tutorialLanguages.ts';
import { welcomeReply } from './format.ts';
type Reply = NonNullable<ReturnType<typeof welcomeReply>>;
type Store = {
  claim: (chatId: number, updateId: number) => Promise<boolean>;
  finish: (chatId: number, status: 'sent' | 'failed' | 'review', messageId?: number) => Promise<void>;
};
export async function deliverFirstTutorial(reply: Reply, updateId: number, store: Store,
  send: (payload: Record<string, unknown>) => Promise<{ ok: boolean; result?: { message_id?: number } }>, language: unknown = 'pt') {
  const tutorial = tutorialForLanguage(language);
  if (!tutorial) return false;
  const chatId = reply.chat_id as number;
  if (!await store.claim(chatId, updateId)) return false;
  try {
    const result = await send({ chat_id: chatId, video: tutorial.video, supports_streaming: true,
      caption: tutorialCaption(tutorial.language), reply_markup: { inline_keyboard: [[{
        text: '▶ Mythic Seas', web_app: reply.reply_markup.inline_keyboard[0][0].web_app,
      }]] } });
    await store.finish(chatId, result.ok ? 'sent' : 'failed', result.result?.message_id);
  } catch { await store.finish(chatId, 'review'); }
  return true;
}
