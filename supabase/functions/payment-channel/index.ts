import { createClient } from 'npm:@supabase/supabase-js@2';
import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { PAYMENT_CHANNEL, paymentCaption, type PaymentNotice } from './format.ts';

const ART = {
  deposit: 'https://mythicseas.lovable.app/__l5e/assets-v1/42205ff9-eb71-4826-8441-17a7de94d613/mythic-seas-deposit.jpg',
  withdrawal: 'https://mythicseas.lovable.app/__l5e/assets-v1/4d48f23c-6d83-413a-ba36-0e81a2236593/mythic-seas-withdrawal.jpg',
};
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
});
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const secret = Deno.env.get('TON_AUTO_WITHDRAW_SECRET');
  if (!secret || req.headers.get('x-payment-channel-secret') !== secret) return json({ error: 'unauthorized' }, 401);
  const token = Deno.env.get('TELEGRAM_BOT_TOKEN_GAME') || Deno.env.get('TELEGRAM_BOT_TOKEN');
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!token || !url || !key) return json({ error: 'configuration_missing' }, 503);
  const db = createClient(url, key, { auth: { persistSession: false } });
  // Do not log request URLs: Telegram URLs contain the bot credential.
  const telegram = async (method: string, body: Record<string, unknown>) => {
    const response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
      signal: AbortSignal.timeout(25000),
    });
    const result = await response.json();
    return { status: response.status, ...result };
  };
  const saveHealth = async (value: Record<string, unknown>) => {
    const result = await db.from('payment_channel_health').upsert({ id: true, ...value, checked_at: new Date().toISOString() });
    if (result.error) throw new Error('health_write_failed');
  };
  try {
    const reset = await db.from('game_settings').select('value').eq('key', 'game_reset_in_progress').maybeSingle();
    if (reset.error) return json({ error: 'reset_check_failed' }, 503);
    if (reset.data?.value === true) return json({ skipped: 'game_reset' });
    const me = await telegram('getMe', {});
    if (!me.ok) { await saveHealth({ ready: false, detail: me.description || 'bot_unavailable' }); return json({ error: 'bot_unavailable' }, 503); }
    const member = await telegram('getChatMember', { chat_id: PAYMENT_CHANNEL, user_id: me.result.id });
    const ready = member.ok && (member.result.status === 'creator' ||
      (member.result.status === 'administrator' && member.result.can_post_messages === true));
    await saveHealth({ ready, bot_username: me.result.username, detail: ready ? 'ready' : member.description || 'O bot precisa ser administrador com permissão para publicar.' });
    if (!ready) return json({ error: 'channel_permission_required' }, 403);
    const claimed = await db.rpc('payment_channel_claim');
    if (claimed.error) return json({ error: 'claim_failed' }, 500);
    let sent = 0;
    for (const notice of (claimed.data ?? []) as PaymentNotice[]) {
      let result;
      try {
        result = await telegram('sendPhoto', {
          chat_id: PAYMENT_CHANNEL, photo: ART[notice.kind], caption: paymentCaption(notice), parse_mode: 'HTML',
          reply_markup: { inline_keyboard: [[{ text: '🏴‍☠️ Jogar Mythic Seas', url: `https://t.me/${me.result.username}` }]] },
        });
      } catch {
        // A timeout may mean Telegram accepted the message. Never blindly resend it.
        await db.from('payment_channel_outbox').update({ status: 'uncertain', last_error: 'Resposta de envio não recebida; conferir o canal antes de reenviar.' }).eq('id', notice.id);
        continue;
      }
      const update = result.ok
        ? { status: 'sent', message_id: result.result.message_id, sent_at: new Date().toISOString(), last_error: null }
        : { status: 'pending', last_error: String(result.description || 'Telegram rejected message').slice(0, 500),
            next_attempt_at: new Date(Date.now() + Math.max(60, Number(result.parameters?.retry_after || 60)) * 1000).toISOString() };
      const saved = await db.from('payment_channel_outbox').update(update).eq('id', notice.id);
      if (saved.error) return json({ error: 'delivery_record_failed' }, 500);
      if (result.ok) sent++;
    }
    return json({ ok: true, sent });
  } catch {
    return json({ error: 'payment_channel_unavailable' }, 503);
  }
});