import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { welcomeReply } from './format.ts';
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
    return json(welcomeReply(JSON.parse(body)) ?? { ok: true });
  } catch { return json({ error: 'invalid_update' }, 400); }
});