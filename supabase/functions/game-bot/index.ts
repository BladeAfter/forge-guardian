import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { createClient } from 'npm:@supabase/supabase-js@2';
import { welcomeReply } from './format.ts';
import { deliverFirstTutorial } from './tutorial.ts';
import { launchInviter } from '../_shared/launch.ts';
import { languageFromUpdate, tutorialForLanguage } from './tutorialLanguages.ts';
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
async function webhookSecret(token: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`mythic-seas-game-webhook:${token}`));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}
function sameSecret(actual: string | null, expected: string) {
  if (!actual || actual.length !== expected.length) return false;
  let difference = 0;
  for (let i = 0; i < expected.length; i++) difference |= actual.charCodeAt(i) ^ expected.charCodeAt(i);
  return difference === 0;
}
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const token = Deno.env.get('TELEGRAM_BOT_TOKEN_GAME');
  if (!token) return json({ error: 'configuration_missing' }, 503);
  if (!sameSecret(req.headers.get('X-Telegram-Bot-Api-Secret-Token'), await webhookSecret(token))) return json({ error: 'unauthorized' }, 401);
  try {
    const body = await req.text();
    if (body.length > 65536) return json({ error: 'payload_too_large' }, 413);
    let update;
    try { update = JSON.parse(body); } catch { return json({ error: 'invalid_update' }, 400); }
    const reply = welcomeReply(update);
    if (!reply) return json({ ok: true });
    const language = languageFromUpdate(update);
    const url = Deno.env.get('SUPABASE_URL'), key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !key) return json({ error: 'configuration_missing' }, 503);
    const db = createClient(url, key);
    const inviter = launchInviter(update.message?.text?.trim().split(/\s+/)[1]);
    const registration = await db.rpc('register_launch_player', { p_telegram_id: reply.chat_id, p_name: update.message?.from?.first_name ?? 'Captain', p_inviter: inviter, p_verified: false });
    if (registration.error) throw new Error('launch_registration_failed');
    const handled = await deliverFirstTutorial(reply, update.update_id, {
      claim: async (chatId, updateId) => {
        const { error } = await db.from('game_bot_tutorial_deliveries').insert({ chat_id: chatId, update_id: updateId });
        if (error?.code === '23505') return false;
        if (error) throw new Error('tutorial_claim_failed');
        return true;
      },
      finish: async (chatId, status, messageId) => {
        const { error } = await db.from('game_bot_tutorial_deliveries').update({ status, message_id: messageId ?? null }).eq('chat_id', chatId);
        if (error) throw new Error('tutorial_status_failed');
      },
    }, async payload => {
      const response = await fetch(`https://api.telegram.org/bot${token}/sendVideo`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload), signal: AbortSignal.timeout(15000),
      });
      return await response.json();
    }, language);
    if (!tutorialForLanguage(language)) return json({ method: 'sendMessage', chat_id: reply.chat_id,
      text: '🏴‍☠️ Mythic Seas\n\nYour language’s tutorial is not available yet. No other-language video has been sent.', reply_markup: reply.reply_markup });
    return json(handled ? { ok: true } : reply);
  } catch { return json({ error: 'tutorial_unavailable' }, 503); }
});