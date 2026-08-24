// Clan Boss auto attack worker.
// Each attack runs in its OWN database transaction (one RPC call per player), so a
// failure/deadlock on a single player never aborts the rest of the batch.
import { createClient } from 'npm:@supabase/supabase-js@2';

const CONCURRENCY = 4;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok');

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  const { data: due, error } = await db.rpc('clan_boss_auto_due_users', { p_limit: 1000 });
  if (error) {
    console.error('[CLAN BOSS AUTO] due users error', error.message);
    return json({ ok: false, error: error.message }, 500);
  }

  const users: string[] = Array.isArray(due)
    ? due.map((row: any) => (typeof row === 'string' ? row : row?.clan_boss_auto_due_users ?? row)).filter(Boolean)
    : [];

  let attacked = 0;
  let paused = 0;
  let failed = 0;

  let cursor = 0;
  const worker = async () => {
    while (cursor < users.length) {
      const userId = users[cursor++];
      const { data, error: rpcError } = await db.rpc('clan_boss_auto_attack_one', { p_user: userId });
      if (rpcError) {
        failed++;
        console.error('[CLAN BOSS AUTO] attack error', userId, rpcError.message);
        continue;
      }
      if (data?.ok) attacked++;
      else if (data?.paused) paused++;
      else if (data?.error) failed++;
    }
  };

  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, Math.max(1, users.length)) }, worker));

  return json({ ok: true, due: users.length, attacked, paused, failed });
});
