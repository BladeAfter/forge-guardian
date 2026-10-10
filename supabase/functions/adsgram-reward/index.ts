import { createClient } from 'npm:@supabase/supabase-js@2';
import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { launchStatus } from '../_shared/launch.ts';

/**
 * AdsGram server-side Reward URL.
 *
 * Configure in the AdsGram dashboard (rewarded block 42560):
 *   https://<project>.functions.supabase.co/adsgram-reward?userId=[userId]&secret=<ADSGRAM_REWARD_SECRET>
 *
 * `[userId]` is the Telegram id the Mini App passed to AdsGram. The reward itself is
 * settled by `pvp_ad_view_reward`, which only credits a PENDING ad view opened by the
 * player a few minutes earlier — so the client callback and this URL can never pay the
 * same view twice (whichever arrives first wins, the other gets ALREADY_REWARDED).
 */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  try {
    if (!launchStatus().released) return json({ ok: false, error: 'GAME_NOT_LAUNCHED' }, 423);
    const url = new URL(req.url);
    // Fail closed: without a configured secret nobody can trigger a payout.
    const expected = String(Deno.env.get('ADSGRAM_REWARD_SECRET') || '').trim();
    const provided = String(url.searchParams.get('secret') || '');
    if (!expected || provided.length !== expected.length) return json({ ok: false, error: 'FORBIDDEN' }, 403);
    let diff = 0;
    for (let i = 0; i < provided.length; i++) diff |= provided.charCodeAt(i) ^ expected.charCodeAt(i);
    if (diff !== 0) return json({ ok: false, error: 'FORBIDDEN' }, 403);

    const telegramId = Number(url.searchParams.get('userId') || url.searchParams.get('user_id') || '');
    if (!Number.isFinite(telegramId) || telegramId <= 0) return json({ ok: false, error: 'INVALID_USER' }, 400);

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceKey) return json({ ok: false, error: 'NOT_CONFIGURED' }, 503);

    const db = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error } = await db.rpc('pvp_ad_view_reward', {
      p_telegram_id: telegramId,
      p_view_id: null,
      p_source: 'reward_url',
    });
    if (error) {
      console.error('[adsgram-reward] rpc failed', error.message);
      return json({ ok: false, error: error.message }, 400);
    }
    return json({ ok: true, ...(data as Record<string, unknown>) });
  } catch (error) {
    console.error('[adsgram-reward] failed', error);
    return json({ ok: false, error: 'REWARD_FAILED' }, 500);
  }
});
