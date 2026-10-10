import { TUTORIAL_VIDEO } from './tutorialMedia.ts';
import { welcomeReply } from './format.ts';
type Reply = NonNullable<ReturnType<typeof welcomeReply>>;
type Store = {
  claim: (chatId: number, updateId: number) => Promise<boolean>;
  finish: (chatId: number, status: 'sent' | 'failed' | 'review', messageId?: number) => Promise<void>;
};
export async function deliverFirstTutorial(reply: Reply, updateId: number, store: Store,
  send: (payload: Record<string, unknown>) => Promise<{ ok: boolean; result?: { message_id?: number } }>) {
  const chatId = reply.chat_id as number;
  if (!await store.claim(chatId, updateId)) return false;
  try {
    const result = await send({ chat_id: chatId, video: TUTORIAL_VIDEO, supports_streaming: true,
      caption: '🏴‍☠️ Bem-vindo a Mythic Seas, capitão!\n\nAssista ao tutorial da Grand Line e comece sua aventura.\n\n#MythicSeasbot', reply_markup: reply.reply_markup });
    await store.finish(chatId, result.ok ? 'sent' : 'failed', result.result?.message_id);
  } catch { await store.finish(chatId, 'review'); }
  return true;
}
